import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Controls how macOS marked text (`setMarkedText`) renders composition underlines
/// when VieLotusIM runs in automatic Stealth Marked Text mode (Chromium / Electron /
/// dynamic fallback) instead of explicit Apple-standard Marked Text mode.
///
/// Can be overridden at runtime for field A/B verification without rebuilding:
/// ```bash
/// defaults write org.vielotus.inputmethod.VieLotusIM VieLotusIM.stealthMarkedTextStyle nearInvisibleDeviceRGB
/// defaults write org.vielotus.inputmethod.VieLotusIM VieLotusIM.stealthMarkedTextStyle clearTransparent
/// defaults write org.vielotus.inputmethod.VieLotusIM VieLotusIM.stealthMarkedTextStyle underlineStyleNone
/// defaults write org.vielotus.inputmethod.VieLotusIM VieLotusIM.stealthMarkedTextStyle appleStandardSingle
/// ```
@frozen public enum StealthMarkedTextStyle: String, CaseIterable, Sendable {
    /// Static `NSDeviceRGBColorSpace` color with alpha `1/255` (`0x01000000`).
    ///
    /// Keeps `.underlineStyle = .single` and `.markedClauseSegment = 0` so W3C/AppKit hosts
    /// preserve composition boundaries, while supplying a non-zero alpha byte (`1`) that avoids
    /// Blink's `StyleableMarker::UseTextColor()` fallback (`alpha == 0` -> opaque text color)
    /// and avoids dynamic catalog color shifts (`NSColor.labelColor`) across Dark/Light Mode.
    case nearInvisibleDeviceRGB = "nearInvisibleDeviceRGB"

    /// Uses `.underlineStyle = .single` with `NSColor.clear` (`alpha == 0`).
    /// Useful for A/B verification across WebKit/Gecko/AppKit hosts (note: current Blink
    /// maps `alpha == 0` with `Thickness::kThin` to `UseTextColor() == true`).
    case clearTransparent = "clearTransparent"

    /// Sends `.underlineStyle = NSUnderlineStyle.none.rawValue` (`0`) with `.markedClauseSegment = 0`.
    /// Reproduces Chromium's `ExtractUnderlines()` bug on unpatched builds and activates true
    /// zero-paint (`Thickness::kNone` / `UnderlineStyle::kNone`) on patched Chromium builds.
    case underlineStyleNone = "underlineStyleNone"

    /// Apple-standard single underline with no custom `.underlineColor` override.
    case appleStandardSingle = "appleStandardSingle"
}

#if canImport(AppKit)

public enum ChromiumSpanThickness: String, Sendable, Equatable {
    case none = "kNone"
    case thin = "kThin"
    case thick = "kThick"
}

public enum ChromiumSpanUnderlineStyle: String, Sendable, Equatable {
    case none = "kNone"
    case solid = "kSolid"
}

/// Faithful model of Chromium's `RenderWidgetHostViewCocoa` (`ExtractUnderlines`) ->
/// Blink `InputMethodController::SetComposition` -> `StyleableMarker` ->
/// `StyleableMarkerPainter::ShouldPaintUnderline` / `PaintUnderline` pipeline.
public struct ChromiumPipelineResult: Sendable, Equatable {
    public let spanCount: Int
    public let thickness: ChromiumSpanThickness
    public let underlineStyle: ChromiumSpanUnderlineStyle
    /// `SkColor` alpha byte (0..255) produced by `skia::NSDeviceColorToSkColor`.
    public let skiaAlphaByte: UInt8
    public let useTextColor: Bool
    public let shouldPaintUnderline: Bool
    /// Whether Blink actually paints an opaque visible underline (e.g. `UseTextColor()` or
    /// `in_dark_mode` forcing `WebkitTextFillColor`).
    public let paintsOpaqueTextColor: Bool
    /// Effective opacity byte (0 = skipped/invisible, 1 = 1/255 stealth, 255 = opaque).
    public let effectiveOpacityByte: UInt8
}

/// Decoded snapshot of the `NSAttributedString` / `NSString` payload received by an
/// `NSTextInputClient` in `setMarkedText(_:selectedRange:replacementRange:)`.
public struct MarkedTextInspection: Sendable, Equatable {
    public let isAttributedString: Bool
    public let text: String
    public let underlineStyleRawValue: Int?
    public let markedClauseSegment: Int?
    public let underlineColorClass: String?
    public let underlineColorSpace: String?
    public let deviceRGBAlpha: Double?
    public let skiaAlphaByte: UInt8?
    public let unpatchedChromiumLight: ChromiumPipelineResult
    public let unpatchedChromiumDark: ChromiumPipelineResult
    public let patchedChromiumLight: ChromiumPipelineResult
    public let patchedChromiumDark: ChromiumPipelineResult

    public var diagnosticSummary: String {
        let kind = isAttributedString ? "NSAttributedString" : "NSString"
        let styleStr = underlineStyleRawValue.map(String.init) ?? "nil"
        let clauseStr = markedClauseSegment.map(String.init) ?? "nil"
        let colorStr: String
        if let cls = underlineColorClass {
            let cs = underlineColorSpace ?? "unknown"
            let alphaStr = skiaAlphaByte.map(String.init) ?? "nil"
            colorStr = "\(cls)@\(cs)(skAlpha=\(alphaStr))"
        } else {
            colorStr = "nil"
        }
        return "type=\(kind) ulStyle=\(styleStr) clause=\(clauseStr) ulColor=\(colorStr) " +
               "blinkLight=\(unpatchedChromiumLight.thickness.rawValue):op\(unpatchedChromiumLight.effectiveOpacityByte) " +
               "blinkDark=\(unpatchedChromiumDark.thickness.rawValue):op\(unpatchedChromiumDark.effectiveOpacityByte) " +
               "patchedDark=\(patchedChromiumDark.thickness.rawValue):op\(patchedChromiumDark.effectiveOpacityByte)"
    }
}

public enum MarkedTextStyleResolver {
    /// Exact static `NSDeviceRGBColorSpace` color with alpha `1/255`.
    /// Allocated once so the keystroke path avoids dynamic color lookups or appearance queries.
    public static let nearInvisibleDeviceRGBColor: NSColor = NSColor(
        deviceRed: 0,
        green: 0,
        blue: 0,
        alpha: 1.0 / 255.0
    )

    /// Standard Chromium / WebKit `validAttributesForMarkedText` key list.
    public static let standardValidMarkedTextAttributes: [NSAttributedString.Key] = [
        .underlineStyle,
        .underlineColor,
        .markedClauseSegment,
        .glyphInfo,
        NSAttributedString.Key("NSTextInputReplacementRangeAttributeName")
    ]

    /// Builds the `NSAttributedString` attribute dictionary for a composition call.
    ///
    /// Defaults to `.appleStandardSingle` (`ulStyle=1`, `clause=0`, no custom color) because
    /// empirical macOS 27.0.1 IMKit/TSM IPC measurements proved Apple's `IMKClient` strips
    /// custom `NSUnderlineColor` (substituting opaque `NSDynamicSystemColor`) and rewrites
    /// `NSUnderlineStyleNone` (`0`) into thick underline (`2`) while dropping `clause=0`.
    public static func compositionAttributes(
        userExplicitlyChoseMarkedText: Bool,
        stealthStyle: StealthMarkedTextStyle = .appleStandardSingle
    ) -> [NSAttributedString.Key: Any] {
        let effectiveStyle: StealthMarkedTextStyle = userExplicitlyChoseMarkedText
            ? .appleStandardSingle
            : stealthStyle

        switch effectiveStyle {
        case .nearInvisibleDeviceRGB:
            return [
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .markedClauseSegment: 0,
                .underlineColor: nearInvisibleDeviceRGBColor
            ]
        case .clearTransparent:
            return [
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .markedClauseSegment: 0,
                .underlineColor: NSColor.clear
            ]
        case .underlineStyleNone:
            return [
                .underlineStyle: NSUnderlineStyle([]).rawValue,
                .markedClauseSegment: 0
            ]
        case .appleStandardSingle:
            return [
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .markedClauseSegment: 0
            ]
        }
    }

    public static func attributedMarkedText(
        _ text: String,
        userExplicitlyChoseMarkedText: Bool,
        stealthStyle: StealthMarkedTextStyle = .appleStandardSingle
    ) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: compositionAttributes(
                userExplicitlyChoseMarkedText: userExplicitlyChoseMarkedText,
                stealthStyle: stealthStyle
            )
        )
    }

    /// Converts an `NSColor` using Chromium's exact `ExtractUnderlines` conversion:
    /// `skia::NSDeviceColorToSkColor([color colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace])`.
    public static func chromiumSkiaAlphaByte(for color: NSColor) -> (alpha: Double, byte: UInt8)? {
        guard let deviceColor = color.usingColorSpace(.deviceRGB) else {
            return nil
        }
        let alpha = Double(deviceColor.alphaComponent)
        let clamped = max(0.0, min(1.0, alpha))
        let byte = UInt8(clamping: Int((clamped * 255.0).rounded()))
        return (alpha, byte)
    }

    /// Inspects any `setMarkedText` payload (`NSAttributedString` or `NSString`) and simulates
    /// both current unpatched Chromium/Blink and patched Chromium (`NSUnderlineStyleNone` fix).
    public static func inspect(_ input: Any) -> MarkedTextInspection {
        let isAttributed: Bool
        let text: String
        var underlineStyleRaw: Int?
        var clauseSegment: Int?
        var colorClass: String?
        var colorSpaceName: String?
        var deviceRGBAlpha: Double?
        var skiaAlphaByte: UInt8?

        if let attr = input as? NSAttributedString {
            isAttributed = true
            text = attr.string
            if attr.length > 0 {
                let attrs = attr.attributes(at: 0, effectiveRange: nil)
                if let styleNum = attrs[.underlineStyle] as? NSNumber {
                    underlineStyleRaw = styleNum.intValue
                }
                if let clauseNum = attrs[.markedClauseSegment] as? NSNumber {
                    clauseSegment = clauseNum.intValue
                }
                if let color = attrs[.underlineColor] as? NSColor {
                    colorClass = String(describing: type(of: color))
                    if color.type == .componentBased {
                        colorSpaceName = color.colorSpace == .deviceRGB
                            ? "NSDeviceRGBColorSpace"
                            : (color.colorSpace.localizedName ?? String(describing: color.colorSpace))
                    } else {
                        colorSpaceName = "catalog(\(color.type.rawValue))"
                    }
                    if let converted = chromiumSkiaAlphaByte(for: color) {
                        deviceRGBAlpha = converted.alpha
                        skiaAlphaByte = converted.byte
                    }
                }
            }
        } else if let str = input as? String {
            isAttributed = false
            text = str
        } else {
            isAttributed = false
            text = ""
        }

        let unpatchedLight = simulateChromiumPipeline(
            isAttributed: isAttributed,
            textLength: (text as NSString).length,
            underlineStyleRaw: underlineStyleRaw,
            skiaAlphaByte: skiaAlphaByte,
            respectUnderlineStyleNone: false,
            inDarkMode: false
        )
        let unpatchedDark = simulateChromiumPipeline(
            isAttributed: isAttributed,
            textLength: (text as NSString).length,
            underlineStyleRaw: underlineStyleRaw,
            skiaAlphaByte: skiaAlphaByte,
            respectUnderlineStyleNone: false,
            inDarkMode: true
        )
        let patchedLight = simulateChromiumPipeline(
            isAttributed: isAttributed,
            textLength: (text as NSString).length,
            underlineStyleRaw: underlineStyleRaw,
            skiaAlphaByte: skiaAlphaByte,
            respectUnderlineStyleNone: true,
            inDarkMode: false
        )
        let patchedDark = simulateChromiumPipeline(
            isAttributed: isAttributed,
            textLength: (text as NSString).length,
            underlineStyleRaw: underlineStyleRaw,
            skiaAlphaByte: skiaAlphaByte,
            respectUnderlineStyleNone: true,
            inDarkMode: true
        )

        return MarkedTextInspection(
            isAttributedString: isAttributed,
            text: text,
            underlineStyleRawValue: underlineStyleRaw,
            markedClauseSegment: clauseSegment,
            underlineColorClass: colorClass,
            underlineColorSpace: colorSpaceName,
            deviceRGBAlpha: deviceRGBAlpha,
            skiaAlphaByte: skiaAlphaByte,
            unpatchedChromiumLight: unpatchedLight,
            unpatchedChromiumDark: unpatchedDark,
            patchedChromiumLight: patchedLight,
            patchedChromiumDark: patchedDark
        )
    }

    private static func simulateChromiumPipeline(
        isAttributed: Bool,
        textLength: Int,
        underlineStyleRaw: Int?,
        skiaAlphaByte: UInt8?,
        respectUnderlineStyleNone: Bool,
        inDarkMode: Bool
    ) -> ChromiumPipelineResult {
        guard textLength > 0 else {
            return ChromiumPipelineResult(
                spanCount: 0,
                thickness: .none,
                underlineStyle: .none,
                skiaAlphaByte: 0,
                useTextColor: false,
                shouldPaintUnderline: false,
                paintsOpaqueTextColor: false,
                effectiveOpacityByte: 0
            )
        }

        // Step 1: RenderWidgetHostViewCocoa::setMarkedText + ExtractUnderlines
        let spanCount: Int
        let thickness: ChromiumSpanThickness
        let underlineStyle: ChromiumSpanUnderlineStyle
        let resolvedAlpha: UInt8

        if !isAttributed {
            // render_widget_host_view_cocoa.mm:2940 — default kThin + kSolid, underline_color = SK_ColorTRANSPARENT
            spanCount = 1
            thickness = .thin
            underlineStyle = .solid
            resolvedAlpha = 0
        } else if let styleVal = underlineStyleRaw {
            spanCount = 1
            // render_widget_host_view_cocoa.mm:191 — default SK_ColorBLACK (alpha 255) when color_attr is nil
            resolvedAlpha = skiaAlphaByte ?? 255
            if respectUnderlineStyleNone && styleVal == NSUnderlineStyle([]).rawValue {
                thickness = .none
                underlineStyle = .none
            } else if styleVal > NSUnderlineStyle.single.rawValue {
                thickness = .thick
                underlineStyle = .solid
            } else {
                // Unpatched Chromium falls through here for styleVal == 0 (NSUnderlineStyleNone)
                thickness = .thin
                underlineStyle = .solid
            }
        } else {
            // ExtractUnderlines produces 0 spans -> Blink InputMethodController::SetComposition (line 1121)
            // inserts default CompositionMarker(Color::kTransparent, kThin, kSolid)
            spanCount = 0
            thickness = .thin
            underlineStyle = .solid
            resolvedAlpha = 0
        }

        // Step 2: Blink StyleableMarker::UseTextColor (styleable_marker.cc:50-53)
        let isTransparent = (resolvedAlpha == 0)
        let useTextColor = (thickness != .none) && isTransparent

        // Step 3: Blink StyleableMarkerPainter::ShouldPaintUnderline (styleable_marker_painter.cc:142-152)
        let shouldPaint: Bool
        if thickness == .none || (isTransparent && !useTextColor) || underlineStyle == .none {
            shouldPaint = false
        } else {
            shouldPaint = true
        }

        // Step 4: Blink StyleableMarkerPainter::PaintUnderline (styleable_marker_painter.cc:191-194)
        // Color marker_color = (marker.UseTextColor() || in_dark_mode) ? WebkitTextFillColor : marker.UnderlineColor();
        let paintsOpaqueTextColor = shouldPaint && (useTextColor || inDarkMode)
        let effectiveOpacityByte: UInt8
        if !shouldPaint {
            effectiveOpacityByte = 0
        } else if paintsOpaqueTextColor {
            effectiveOpacityByte = 255
        } else {
            effectiveOpacityByte = resolvedAlpha
        }

        return ChromiumPipelineResult(
            spanCount: spanCount,
            thickness: thickness,
            underlineStyle: underlineStyle,
            skiaAlphaByte: resolvedAlpha,
            useTextColor: useTextColor,
            shouldPaintUnderline: shouldPaint,
            paintsOpaqueTextColor: paintsOpaqueTextColor,
            effectiveOpacityByte: effectiveOpacityByte
        )
    }
}

#endif
