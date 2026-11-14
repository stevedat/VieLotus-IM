#if !VIELOTUS_OPEN_CORE_MACOS && !os(Android) && (BUDDYKEY_MASCOT || !os(iOS))
import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#else
public typealias CGFloat = Double
#endif

/// Single Source of Truth for Chú Trâu Luti 3D Mascot, AI Face Cropping & Framing,
/// and 60/120fps Playground & Fishing Motion Rules across iOS, iPadOS, and Android.
public enum MascotSharedSpec {

    // MARK: - 1. Canonical AI Face Cropping & Medallion Framing Rules (`FaceFramingSpec`)

    /// Guarantees Face 1 and Face 2 preserve 100% of the forehead, hair crown, and head contour
    /// inside both Chibi Frame mode (`22.0×22.0 pt`) and Full-Bleed mode (`31.0×31.0 pt`).
    public enum FaceFraming {
        /// Output resolution of the circular pre-cropped face avatar PNG (`160×160 px`).
        public static let avatarOutputPx: Int = 160
        public static let avatarPixelSize: Int = 160

        /// Multiplier applied to Apple Vision `boundingBox` (chin-to-eyebrow) to include forehead & hair.
        public static let visionFaceBoxExpandMultiplier: Double = 1.54
        public static let visionBoxExpansionMultiplier: CGFloat = 1.54

        /// Center-Y ratio from top of Apple Vision `boundingBox` (`0.34` shifts crop box upward toward hair crown).
        public static let visionFaceCenterYRatio: Double = 0.34
        public static let visionCenterYFraction: CGFloat = 0.34

        /// Multiplier applied to inter-ocular `eyesDistance` (Android `FaceDetector`) to match `1.54x` full face box.
        public static let eyeDistanceExpandMultiplier: Double = 3.45

        /// Upward shift in `eyesDistance` units (`0.18 * eyesDistance`) so forehead & hair crown are never cut off.
        public static let eyeMidpointUpwardShiftRatio: Double = 0.18

        /// Maximum extra top inset ratio (`0.14`) when the subject's head is near the top edge of the source photo.
        public static let maxExtraTopInsetRatio: CGFloat = 0.14

        /// Canonical `34×34 pt` coordinate space rect for the face circle when `showChibiFrame == true`.
        /// Positioned strictly below `y = 8.2 pt` so hats, crowns, and bows (`y = 0.3..7.2 pt`) never cover the forehead.
        public static let chibiFaceRectPt = (x: 6.0, y: 8.2, width: 22.0, height: 22.0)
        public static let chibiFaceX: CGFloat = 6.0
        public static let chibiFaceY: CGFloat = 8.2
        public static let chibiFaceSize: CGFloat = 22.0

        /// Top breathing offset (`+0.8 pt` downward, `-0.4 pt` height) inside `chibiFaceRectPt` so the top rim never clips hair.
        public static let chibiFaceTopBreathingOffsetPt: Double = 0.8
        public static let chibiFaceHeightTrimPt: Double = 0.4
        public static let faceBackdropBleedInsetPt: CGFloat = 0.6
        public static let faceTopBreathingOffsetPt: CGFloat = 0.8
        public static let faceHeightTrimPt: CGFloat = 0.4

        /// Canonical `34×34 pt` coordinate space rect for the face circle when `showChibiFrame == false` (Full-Bleed).
        public static let fullBleedFaceRectPt = (x: 1.5, y: 1.6, width: 31.0, height: 31.0)
        public static let fullBleedFaceX: CGFloat = 1.5
        public static let fullBleedFaceY: CGFloat = 1.6
        public static let fullBleedFaceSize: CGFloat = 31.0

        /// Outer bezel radii (`12.8 pt` Chibi frame / `15.2 pt` Full-Bleed) for `MascotChibiBorderStyle` decorations.
        public static let chibiOuterBorderRadiusPt: CGFloat = 12.8
        public static let fullBleedOuterBorderRadiusPt: CGFloat = 15.2
    }

    // MARK: - 2. Canonical 60/120fps Motion & Timing Rules (`MascotMotionSpec`)

    public enum Motion {
        public static let baseSpriteSizePt: Double = 34.0
        /// Side-by-side center-to-center spacing (`31.5 pt`) so Face 1 and Face 2 (`26–31 pt` diameter)
        /// sit cleanly next to each other with 0% overlap on either face or Chibi frame.
        public static let coupleSnuggleGapPt: Double = 31.5

        public static let idleTriggerSeconds: Double = 5.0
        public static let postSequenceCooldownSeconds: Double = 14.0
        public static let typingResumeDelaySeconds: Double = 1.8

        public static let walkStepSpanPt: Double = 26.0
        public static let walkStepDurationSeconds: Double = 0.34
        public static let minWalkStepsPerWay: Int = 6
        public static let maxWalkStepsPerWay: Int = 14

        public static let playgroundTotalDurationSeconds: Double = 6.80
        public static let playgroundKeyTimes: [Double] = [0.00, 0.12, 0.25, 0.39, 0.55, 0.72, 0.87, 1.00]
        public static let playgroundZoomScales: [Double] = [1.00, 1.26, 1.44, 1.62, 1.62, 1.66, 1.30, 1.00]

        public static let playgroundStep1DelaySeconds: Double = 0.76
        public static let playgroundStep2DelaySeconds: Double = 1.64
        public static let playgroundStep3DelaySeconds: Double = 2.55
        public static let playgroundFadeOutDelaySeconds: Double = 5.35

        public static let fishingCastDurationSeconds: Double = 2.85
        public static let fishingStep1DelaySeconds: Double = 0.42
        public static let fishingStep2DelaySeconds: Double = 1.12
        public static let fishingStep3DelaySeconds: Double = 1.85
        public static let fishingFinishDelaySeconds: Double = 3.75
    }

    // MARK: - 3. Canonical Shared 3D Asset Manifest (`@5x` 170×170px CoreGraphics PNGs)

    public enum Assets {
        public static let spriteScale: Double = 5.0
        public static let spritePixelSize: Int = 170

        public static let fullBodyWalkLeft = "fullbody_walk_left.png"
        public static let fullBodyWalkRight = "fullbody_walk_right.png"
        public static let fullBodyPlayfulKick = "fullbody_playful_kick.png"
        public static let fullBodyFishingRod = "fullbody_fishing_rod.png"
        public static let fullBodyAirborneTakeoff = "fullbody_airborne_takeoff.png"
        public static let fullBodyAirborneApex = "fullbody_airborne_apex.png"
        public static let fullBodySittingThinking = "fullbody_sitting_thinking.png"
        public static let fullBodySittingThinkingBlink = "fullbody_sitting_thinking_blink.png"

        public static func chibiUnderlay(outfit: Int) -> String {
            "chibi_underlay_outfit\(outfit).png"
        }

        public static func chibiOverlay(outfit: Int, accessory: Int) -> String {
            "chibi_overlay_outfit\(outfit)_acc\(accessory).png"
        }

        public static let defaultFaceChibiOpen = "default_face_chibi_open.png"
        public static let defaultFaceChibiBlink = "default_face_chibi_blink.png"
        public static let defaultFaceFullBleedOpen = "default_face_fullbleed_open.png"
        public static let defaultFaceFullBleedBlink = "default_face_fullbleed_blink.png"
        public static let fullBleedRingOverlay = "fullbleed_ring_overlay.png"
        public static let faceFishingRodOverlay = "face_fishing_rod_overlay.png"

        public static let thoughtCloud = "thought_cloud.png"
        public static let fishingHook = "fishing_hook.png"
        public static let radialShadow = "radial_shadow.png"
    }
}
#endif
