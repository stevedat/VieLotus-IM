#if os(macOS)
import XCTest
import AppKit
@testable import VieLotusCore

final class MarkedTextStylePolicyTests: XCTestCase {
    func testNearInvisibleDeviceRGBUsesStaticDeviceRGBColorWithAlphaByteOne() throws {
        let attr = MarkedTextStyleResolver.attributedMarkedText(
            "trường",
            userExplicitlyChoseMarkedText: false,
            stealthStyle: .nearInvisibleDeviceRGB
        )
        let inspection = MarkedTextStyleResolver.inspect(attr)

        XCTAssertTrue(inspection.isAttributedString)
        XCTAssertEqual(inspection.text, "trường")
        XCTAssertEqual(inspection.underlineStyleRawValue, NSUnderlineStyle.single.rawValue)
        XCTAssertEqual(inspection.markedClauseSegment, 0)
        XCTAssertEqual(inspection.underlineColorSpace, "NSDeviceRGBColorSpace")
        XCTAssertEqual(inspection.skiaAlphaByte, 1)

        // Unpatched Chromium + Blink:
        // - Light mode avoids UseTextColor() (alpha == 1 != 0), painting 1/255 stealth opacity.
        // - Dark mode forces WebkitTextFillColor via styleable_marker_painter.cc:192 (`|| in_dark_mode`).
        XCTAssertEqual(inspection.unpatchedChromiumLight.thickness, .thin)
        XCTAssertFalse(inspection.unpatchedChromiumLight.useTextColor)
        XCTAssertTrue(inspection.unpatchedChromiumLight.shouldPaintUnderline)
        XCTAssertFalse(inspection.unpatchedChromiumLight.paintsOpaqueTextColor)
        XCTAssertEqual(inspection.unpatchedChromiumLight.effectiveOpacityByte, 1)

        XCTAssertTrue(inspection.unpatchedChromiumDark.paintsOpaqueTextColor)
        XCTAssertEqual(inspection.unpatchedChromiumDark.effectiveOpacityByte, 255)
    }

    func testClearTransparentFallsBackToOpaqueTextColorInUnpatchedBlink() {
        let attr = MarkedTextStyleResolver.attributedMarkedText(
            "Việt",
            userExplicitlyChoseMarkedText: false,
            stealthStyle: .clearTransparent
        )
        let inspection = MarkedTextStyleResolver.inspect(attr)

        XCTAssertEqual(inspection.underlineStyleRawValue, NSUnderlineStyle.single.rawValue)
        XCTAssertEqual(inspection.skiaAlphaByte, 0)

        // Because Blink StyleableMarker::UseTextColor() returns `thickness != kNone && color == kTransparent`,
        // NSColor.clear with NSUnderlineStyle.single triggers UseTextColor() == true -> opaque underline!
        XCTAssertTrue(inspection.unpatchedChromiumLight.useTextColor)
        XCTAssertTrue(inspection.unpatchedChromiumLight.shouldPaintUnderline)
        XCTAssertTrue(inspection.unpatchedChromiumLight.paintsOpaqueTextColor)
        XCTAssertEqual(inspection.unpatchedChromiumLight.effectiveOpacityByte, 255)
    }

    func testUnderlineStyleNoneReproducesChromiumBugAndFixesBothLightAndDarkWhenPatched() {
        let attr = MarkedTextStyleResolver.attributedMarkedText(
            "Việt",
            userExplicitlyChoseMarkedText: false,
            stealthStyle: .underlineStyleNone
        )
        let inspection = MarkedTextStyleResolver.inspect(attr)

        XCTAssertEqual(inspection.underlineStyleRawValue, NSUnderlineStyle([]).rawValue)
        XCTAssertEqual(inspection.markedClauseSegment, 0)
        XCTAssertNil(inspection.underlineColorClass)

        // Unpatched Chromium: `0 > 1` is false -> kThin + SK_ColorBLACK -> opaque solid underline!
        XCTAssertEqual(inspection.unpatchedChromiumLight.thickness, .thin)
        XCTAssertEqual(inspection.unpatchedChromiumLight.underlineStyle, .solid)
        XCTAssertEqual(inspection.unpatchedChromiumLight.skiaAlphaByte, 255)
        XCTAssertTrue(inspection.unpatchedChromiumLight.shouldPaintUnderline)
        XCTAssertEqual(inspection.unpatchedChromiumLight.effectiveOpacityByte, 255)

        // Patched Chromium: maps NSUnderlineStyleNone -> Thickness::kNone + UnderlineStyle::kNone.
        // ShouldPaintUnderline() returns false in BOTH Light Mode AND Dark Mode!
        XCTAssertEqual(inspection.patchedChromiumLight.spanCount, 1)
        XCTAssertEqual(inspection.patchedChromiumLight.thickness, .none)
        XCTAssertEqual(inspection.patchedChromiumLight.underlineStyle, .none)
        XCTAssertFalse(inspection.patchedChromiumLight.useTextColor)
        XCTAssertFalse(inspection.patchedChromiumLight.shouldPaintUnderline)
        XCTAssertEqual(inspection.patchedChromiumLight.effectiveOpacityByte, 0)

        XCTAssertEqual(inspection.patchedChromiumDark.thickness, .none)
        XCTAssertFalse(inspection.patchedChromiumDark.shouldPaintUnderline)
        XCTAssertFalse(inspection.patchedChromiumDark.paintsOpaqueTextColor)
        XCTAssertEqual(inspection.patchedChromiumDark.effectiveOpacityByte, 0)
    }

    func testOmittingUnderlineStyleStillTriggersBlinkDefaultUnderlineFallback() {
        let attrWithoutUnderline = NSAttributedString(
            string: "trường",
            attributes: [.markedClauseSegment: 0]
        )
        let inspection = MarkedTextStyleResolver.inspect(attrWithoutUnderline)

        XCTAssertNil(inspection.underlineStyleRawValue)
        XCTAssertEqual(inspection.unpatchedChromiumLight.spanCount, 0)
        // Blink InputMethodController::SetComposition (line 1121) inserts a default kThin/kSolid/kTransparent marker.
        XCTAssertTrue(inspection.unpatchedChromiumLight.useTextColor)
        XCTAssertTrue(inspection.unpatchedChromiumLight.paintsOpaqueTextColor)
        XCTAssertEqual(inspection.unpatchedChromiumLight.effectiveOpacityByte, 255)
    }

    func testExplicitMarkedTextModeAlwaysUsesAppleStandardSingleUnderline() {
        let attr = MarkedTextStyleResolver.attributedMarkedText(
            "tiếng",
            userExplicitlyChoseMarkedText: true,
            stealthStyle: .nearInvisibleDeviceRGB
        )
        let inspection = MarkedTextStyleResolver.inspect(attr)

        XCTAssertEqual(inspection.underlineStyleRawValue, NSUnderlineStyle.single.rawValue)
        XCTAssertEqual(inspection.markedClauseSegment, 0)
        XCTAssertNil(inspection.underlineColorClass)
        XCTAssertEqual(inspection.patchedChromiumLight.thickness, .thin)
        XCTAssertTrue(inspection.patchedChromiumLight.shouldPaintUnderline)
        XCTAssertEqual(inspection.patchedChromiumLight.effectiveOpacityByte, 255)
    }

    func testAttributedStringSurvivesSecureKeyedArchivingRoundTrip() throws {
        let original = MarkedTextStyleResolver.attributedMarkedText(
            "tiếng",
            userExplicitlyChoseMarkedText: false,
            stealthStyle: .nearInvisibleDeviceRGB
        )
        let archived = try NSKeyedArchiver.archivedData(
            withRootObject: original,
            requiringSecureCoding: true
        )
        let decoded = try XCTUnwrap(
            NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: archived)
        )
        let inspection = MarkedTextStyleResolver.inspect(decoded)

        XCTAssertEqual(inspection.text, "tiếng")
        XCTAssertEqual(inspection.underlineStyleRawValue, NSUnderlineStyle.single.rawValue)
        XCTAssertEqual(inspection.markedClauseSegment, 0)
        XCTAssertEqual(inspection.underlineColorSpace, "NSDeviceRGBColorSpace")
        XCTAssertEqual(inspection.skiaAlphaByte, 1)
    }
}
#endif
