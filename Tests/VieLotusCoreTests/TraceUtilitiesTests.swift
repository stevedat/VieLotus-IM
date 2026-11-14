import XCTest
import VieLotusTrace

final class TraceUtilitiesTests: XCTestCase {

    // MARK: - 1. ClipboardCharsetConverter: NFD -> NFC

    func testNFDToNFCNormalizesDecomposedVietnameseAndStrokeOverlays() {
        // Decomposed NFD string as commonly copied from macOS Preview/PDF or APFS filenames
        let decomposed = "Tru\u{031B}o\u{031B}\u{0300}ng \u{0110}a\u{0323}i ho\u{0323}c Ba\u{0301}ch Khoa Ha\u{0300} No\u{0302}\u{0323}i"
        let converted = ClipboardCharsetConverter.convert(decomposed, mode: .nfdToNFC)

        let expected = "Trường Đại học Bách Khoa Hà Nội"
        XCTAssertEqual(converted, expected)
        // Verify exact UTF-16 code-unit normalization (not merely canonical String.== equivalence)
        XCTAssertFalse(decomposed.utf16.elementsEqual(expected.utf16))
        XCTAssertTrue(converted.utf16.elementsEqual(expected.utf16))

        // Rare PDF stroke-overlay decomposed d/D + U+0335/U+0336
        let strokeDecomposed = "d\u{0335}o\u{0302}ng D\u{0336}o\u{0302}\u{0300}ng"
        let strokeConverted = ClipboardCharsetConverter.convert(strokeDecomposed, mode: .nfdToNFC)
        XCTAssertTrue(strokeConverted.utf16.elementsEqual("đông Đồng".utf16))
    }

    // MARK: - 2. ClipboardCharsetConverter: TCVN3 (ABC) -> Unicode

    func testTCVN3ToUnicodeCoversAll74CodepointsAndPreservesTitleCase() {
        // "Trường Đại học Bách Khoa Hà Nội" encoded in TCVN 5712:1993 (.VnTime)
        // Tr + ư(0xAD) + ờ(0xEA) + ng + " " + Đ(0xA7) + ạ(0xB9) + i + " " + h + ọ(0xE4) + c
        // + " " + B + á(0xB8) + ch + " " + Khoa + " " + H + à(0xB5) + " " + N + ộ(0xE9) + i
        let tcvnTitleCase = "Tr\u{00AD}\u{00EA}ng \u{00A7}\u{00B9}i h\u{00E4}c B\u{00B8}ch Khoa H\u{00B5} N\u{00E9}i"
        XCTAssertEqual(
            ClipboardCharsetConverter.convert(tcvnTitleCase, mode: .tcvn3ToUnicode),
            "Trường Đại học Bách Khoa Hà Nội"
        )

        // Single-consonant + accented-vowel Title Case words must NOT be erroneously uppercased
        // "Bố mẹ đi Hà Nội" -> B + ố(0xE8) + " " + m + ẹ(0xD1) + " " + đ(0xAE) + i + " " + H + à(0xB5) + " " + N + ộ(0xE9) + i
        let singleConsonantTitle = "B\u{00E8} m\u{00D1} \u{00AE}i H\u{00B5} N\u{00E9}i"
        XCTAssertEqual(
            ClipboardCharsetConverter.convert(singleConsonantTitle, mode: .tcvn3ToUnicode),
            "Bố mẹ đi Hà Nội"
        )

        // Administrative acronym followed by Title-Case place name ("UBND Xã Tân Lập")
        // X + ã(0xB7), T + â(0xA9) + n, L + ậ(0xCB) + p
        let acronymFollowedByTitle = "UBND X\u{00B7} T\u{00A9}n L\u{00CB}p"
        XCTAssertEqual(
            ClipboardCharsetConverter.convert(acronymFollowedByTitle, mode: .tcvn3ToUnicode),
            "UBND Xã Tân Lập"
        )
    }

    func testTCVN3ToUnicodePromotesAllCapsVnTimeHHeadings() {
        // ".VnTimeH" ALL-CAPS heading where accented vowels occupy TCVN3's shared single-byte slots:
        // "CỘNG HÒA XÃ HỘI CHỦ NGHĨA VIỆT NAM"
        // C + ộ(0xE9) + NG, H + ò(0xDF) + A, X + ã(0xB7), H + ộ(0xE9) + I,
        // CH + ủ(0xF1), NGH + ĩ(0xDC) + A, VI + ệ(0xD6) + T, NAM
        let vnTimeHHeading = "C\u{00E9}NG H\u{00DF}A X\u{00B7} H\u{00E9}I CH\u{00F1} NGH\u{00DC}A VI\u{00D6}T NAM"
        XCTAssertEqual(
            ClipboardCharsetConverter.convert(vnTimeHHeading, mode: .tcvn3ToUnicode),
            "CỘNG HÒA XÃ HỘI CHỦ NGHĨA VIỆT NAM"
        )

        // Trailing single-consonant ALL-CAPS word ("CÔNG AN XÃ"): C + Ô(0xA4) + NG + " " + AN + " " + X + ã(0xB7)
        let trailingAllCaps = "C\u{00A4}NG AN X\u{00B7}"
        XCTAssertEqual(
            ClipboardCharsetConverter.convert(trailingAllCaps, mode: .tcvn3ToUnicode),
            "CÔNG AN XÃ"
        )

        // Dedicated TCVN3 uppercase letters 0xA1..0xA7 -> Ă Â Ê Ô Ơ Ư Đ
        let dedicatedUpper = "\u{00A1}\u{00A2}\u{00A3}\u{00A4}\u{00A5}\u{00A6}\u{00A7}"
        XCTAssertEqual(
            ClipboardCharsetConverter.convert(dedicatedUpper, mode: .tcvn3ToUnicode),
            "ĂÂÊÔƠƯĐ"
        )
    }

    // MARK: - 3. ClipboardCharsetConverter: VNI Windows -> Unicode

    func testVNIWindowsToUnicodeConvertsAllTwoByteAndOneByteForms() {
        // "Trường Đại học Bách Khoa Hà Nội - Việt Nam" in VNI-Windows:
        // Tr + ö(0xF6=ư) + ôø(0xF4,0xF8=ờ) + ng
        // Ñ(0xD1=Đ) + aï(0x61,0xEF=ạ) + i
        // hoïc (o + 0xEF = ọ)
        // Baùch (a + 0xF9 = á)
        // Khoa
        // Haø (a + 0xF8 = à)
        // Noäi (o + 0xE4 = ộ)
        // Vieät (e + 0xE4 = ệ)
        let vniSentence = "Tr\u{00F6}\u{00F4}\u{00F8}ng \u{00D1}a\u{00EF}i ho\u{00EF}c Ba\u{00F9}ch Khoa Ha\u{00F8} No\u{00E4}i - Vie\u{00E4}t Nam"
        XCTAssertEqual(
            ClipboardCharsetConverter.convert(vniSentence, mode: .vniWindowsToUnicode),
            "Trường Đại học Bách Khoa Hà Nội - Việt Nam"
        )

        // 1-byte VNI characters: đ/Đ, ì/ỉ/ĩ/í/ị, Ì/Ỉ/Ĩ/Í/Ị, ơ/Ơ, ư/Ư, ỵ/Ỵ
        let vniOneByte = "\u{00F1}\u{00D1} \u{00EC}\u{00E6}\u{00F3}\u{00ED}\u{00F2} \u{00CC}\u{00C6}\u{00D3}\u{00CD}\u{00D2} \u{00F4}\u{00D4} \u{00F6}\u{00D6} k\u{00EE} K\u{00CE}"
        XCTAssertEqual(
            ClipboardCharsetConverter.convert(vniOneByte, mode: .vniWindowsToUnicode),
            "đĐ ìỉĩíị ÌỈĨÍỊ ơƠ ưƯ kỵ KỴ"
        )

        // Uppercase 2-byte pairs (both standard uppercase modifier "AÙO" and Title-Case "Aùo")
        let vniUpperAndTitle = "A\u{00D9}O A\u{00F9}o \u{00D6}\u{00D9}NG \u{00D4}\u{00DB}NG MY\u{00D5}"
        XCTAssertEqual(
            ClipboardCharsetConverter.convert(vniUpperAndTitle, mode: .vniWindowsToUnicode),
            "ÁO Áo ỨNG ỞNG MỸ"
        )

        // Boundary safety: lowercase ASCII vowel followed by uppercase 1-byte VNI letter (e.g. "aÑ" = "aĐ")
        // must NOT misparse 0xD1 ('Ñ' = 'Đ') as an uppercase modifier on lowercase 'a'.
        XCTAssertEqual(
            ClipboardCharsetConverter.convert("a\u{00D1}a", mode: .vniWindowsToUnicode),
            "aĐa"
        )
    }

    // MARK: - 4. InputSourceStatus & InputSourceDoctor

    func testInputSourceStatusClassifiesAllFiveHealthStatesAndConflicts() {
        let active = InputSourceStatus(
            isInstalledOnDisk: true,
            installedPath: "/Library/Input Methods/VieLotusIM.app",
            isRegistered: true,
            isEnabled: true,
            isActive: true,
            matchedInputSourceIDs: ["org.vielotus.inputmethod.VieLotusIM"],
            activeInputSourceID: "org.vielotus.inputmethod.VieLotusIM",
            activeInputSourceName: "Sen Việt"
        )
        XCTAssertEqual(active.state, .active)
        XCTAssertFalse(active.isConflictingAppleVietnameseActive)
        XCTAssertEqual(active.summaryTitle, "Đang dùng Sen Việt")

        let appleConflict = InputSourceStatus(
            isInstalledOnDisk: true,
            installedPath: "/Library/Input Methods/VieLotusIM.app",
            isRegistered: true,
            isEnabled: true,
            isActive: false,
            matchedInputSourceIDs: ["org.vielotus.inputmethod.VieLotusIM"],
            activeInputSourceID: "com.apple.inputmethod.VietnameseIM.VietnameseSimpleTelex",
            activeInputSourceName: "Simple Telex"
        )
        XCTAssertEqual(appleConflict.state, .enabledAppleVietnameseActive)
        XCTAssertTrue(appleConflict.isConflictingAppleVietnameseActive)
        XCTAssertTrue(appleConflict.humanReadableReport().contains("Warning"))

        let enabledABC = InputSourceStatus(
            isInstalledOnDisk: true,
            installedPath: "/Library/Input Methods/VieLotusIM.app",
            isRegistered: true,
            isEnabled: true,
            isActive: false,
            matchedInputSourceIDs: ["org.vielotus.inputmethod.VieLotusIM"],
            activeInputSourceID: "com.apple.keylayout.ABC",
            activeInputSourceName: "ABC"
        )
        XCTAssertEqual(enabledABC.state, .enabledNotSelected)
        XCTAssertFalse(enabledABC.isConflictingAppleVietnameseActive)

        let registeredOnly = InputSourceStatus(
            isInstalledOnDisk: true,
            installedPath: "/Library/Input Methods/VieLotusIM.app",
            isRegistered: true,
            isEnabled: false,
            isActive: false,
            matchedInputSourceIDs: ["org.vielotus.inputmethod.VieLotusIM"],
            activeInputSourceID: "com.apple.keylayout.ABC",
            activeInputSourceName: "ABC"
        )
        XCTAssertEqual(registeredOnly.state, .registeredNotEnabled)

        let notRegistered = InputSourceStatus(
            isInstalledOnDisk: false,
            installedPath: nil,
            isRegistered: false,
            isEnabled: false,
            isActive: false,
            matchedInputSourceIDs: [],
            activeInputSourceID: "com.apple.keylayout.ABC",
            activeInputSourceName: "ABC"
        )
        XCTAssertEqual(notRegistered.state, .notRegistered)

        // JSON round-trip
        let jsonData = Data(appleConflict.jsonReport().utf8)
        let decoded = try? JSONDecoder().decode(InputSourceStatus.self, from: jsonData)
        XCTAssertEqual(decoded, appleConflict)

        // Dual-enabled Apple Vietnamese warning even when Sen Việt is currently active
        let activeWithAppleEnabled = InputSourceStatus(
            isInstalledOnDisk: true,
            installedPath: "/Library/Input Methods/VieLotusIM.app",
            isRegistered: true,
            isEnabled: true,
            isActive: true,
            matchedInputSourceIDs: ["org.vielotus.inputmethod.VieLotusIM"],
            activeInputSourceID: "org.vielotus.inputmethod.VieLotusIM",
            activeInputSourceName: "Sen Việt",
            enabledAppleVietnameseNames: ["Telex"]
        )
        XCTAssertEqual(activeWithAppleEnabled.state, .active)
        XCTAssertTrue(activeWithAppleEnabled.hasEnabledAppleVietnameseInputSource)
        XCTAssertTrue(activeWithAppleEnabled.hasAnyInputConflict)
        XCTAssertNotNil(activeWithAppleEnabled.conflictWarningText)

        // Third-party background IME detection
        XCTAssertEqual(
            InputSourceStatus.matchThirdPartyVietnameseIME(bundleID: "com.tuyenmai.openkey", processName: "OpenKey"),
            "OpenKey"
        )
        XCTAssertEqual(
            InputSourceStatus.matchThirdPartyVietnameseIME(bundleID: "com.lamquangminh.evkey", processName: "EVKey"),
            "EVKey"
        )
        XCTAssertNil(
            InputSourceStatus.matchThirdPartyVietnameseIME(bundleID: "org.vielotus.inputmethod.VieLotusIM", processName: "VieLotusIM")
        )
    }

    #if os(macOS)
    func testInputSourceDoctorInspectRunsReadOnlyOnMacOS() {
        let live = InputSourceDoctor.inspect()
        XCTAssertEqual(live.bundleID, InputSourceStatus.defaultBundleID)
        XCTAssertFalse(live.humanReadableReport().isEmpty)

        // Querying a guaranteed-nonexistent bundle ID must return .notRegistered cleanly
        let nonexistent = InputSourceDoctor.inspect(bundleID: "org.vielotus.nonexistent.unit-test-probe")
        XCTAssertFalse(nonexistent.isRegistered)
        XCTAssertFalse(nonexistent.isEnabled)
        XCTAssertFalse(nonexistent.isActive)
        XCTAssertEqual(nonexistent.state, .notRegistered)
    }
    #endif
}
