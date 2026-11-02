import Foundation

public enum ClipboardCharsetMode: String, CaseIterable, Sendable {
    case nfdToNFC = "nfd_to_nfc"
    case tcvn3ToUnicode = "tcvn3_to_unicode"
    case vniWindowsToUnicode = "vni_windows_to_unicode"

    public var menuTitle: String {
        switch self {
        case .nfdToNFC:
            return "Unicode tổ hợp → dựng sẵn (NFD → NFC)"
        case .tcvn3ToUnicode:
            return "TCVN3 (ABC) → Unicode"
        case .vniWindowsToUnicode:
            return "VNI Windows → Unicode"
        }
    }
}

/// Pure-Swift, offline Vietnamese clipboard text normalizer and legacy encoding converter.
/// Operates strictly off the keystroke hot path when explicitly triggered by the user.
public enum ClipboardCharsetConverter {
    public static func convert(_ text: String, mode: ClipboardCharsetMode) -> String {
        guard !text.isEmpty else { return text }
        switch mode {
        case .nfdToNFC:
            return normalizeNFC(text)
        case .tcvn3ToUnicode:
            return tcvn3ToUnicode(text)
        case .vniWindowsToUnicode:
            return vniWindowsToUnicode(text)
        }
    }

    // MARK: - 1. Unicode NFD -> NFC

    /// Converts decomposed Vietnamese Unicode (commonly produced by macOS PDF Quartz/Preview
    /// or HFS+/APFS filenames) into canonical precomposed Unicode (NFC).
    public static func normalizeNFC(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        // Also fold rare decomposed d/D + combining short/long stroke overlays into đ/Đ
        let strokeNormalized = text
            .replacingOccurrences(of: "d\u{0335}", with: "đ")
            .replacingOccurrences(of: "d\u{0336}", with: "đ")
            .replacingOccurrences(of: "D\u{0335}", with: "Đ")
            .replacingOccurrences(of: "D\u{0336}", with: "Đ")
        return strokeNormalized.precomposedStringWithCanonicalMapping
    }

    // MARK: - 2. TCVN3 (TCVN 5712:1993 / ABC / .VnTime) -> Unicode NFC

    private struct TCVN3ScalarToken {
        let converted: UnicodeScalar
        let isTCVN3AccentedLowerVowel: Bool
        let isOriginalUpperLetter: Bool
        let isOriginalLowerLetter: Bool
        let isWordLetter: Bool
    }

    /// Converts TCVN3 (ABC / `.VnTime` / `.VnTimeH`) plain text to precomposed Unicode (NFC),
    /// preserving Title Case while restoring ALL-CAPS words whose accented vowels share
    /// single-byte TCVN3 lowercase slots.
    public static func tcvn3ToUnicode(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        let scalars = Array(text.unicodeScalars)
        var tokens: [TCVN3ScalarToken] = []
        tokens.reserveCapacity(scalars.count)

        for scalar in scalars {
            if let mapped = tcvn3ScalarMap[scalar.value] {
                let isDedicatedUpper = (scalar.value >= 0xA1 && scalar.value <= 0xA7)
                let isDedicatedUnaccentedLower = (scalar.value >= 0xA8 && scalar.value <= 0xAE)
                tokens.append(TCVN3ScalarToken(
                    converted: mapped,
                    isTCVN3AccentedLowerVowel: !isDedicatedUpper && !isDedicatedUnaccentedLower,
                    isOriginalUpperLetter: isDedicatedUpper,
                    isOriginalLowerLetter: isDedicatedUnaccentedLower,
                    isWordLetter: true
                ))
            } else {
                let isUpper = CharacterSet.uppercaseLetters.contains(scalar)
                let isLower = CharacterSet.lowercaseLetters.contains(scalar)
                tokens.append(TCVN3ScalarToken(
                    converted: scalar,
                    isTCVN3AccentedLowerVowel: false,
                    isOriginalUpperLetter: isUpper,
                    isOriginalLowerLetter: isLower,
                    isWordLetter: isUpper || isLower
                ))
            }
        }

        // Partition contiguous letter runs so ALL-CAPS words (e.g. `.VnTimeH` headings)
        // promote ambiguous TCVN3 accented vowels without disturbing Title Case words.
        struct WordSpan {
            let start: Int
            let end: Int
            let upperCount: Int
            let lowerCount: Int
            let hasUpperAfterAmbiguousVowel: Bool

            var isUnambiguouslyAllCaps: Bool {
                lowerCount == 0 && (upperCount >= 2 || hasUpperAfterAmbiguousVowel)
            }

            var hasOriginalLower: Bool {
                lowerCount > 0
            }
        }

        var wordSpans: [WordSpan] = []
        var idx = 0
        while idx < tokens.count {
            guard tokens[idx].isWordLetter else {
                idx += 1
                continue
            }
            let start = idx
            var upperCount = 0
            var lowerCount = 0
            var seenAmbiguousVowel = false
            var hasUpperAfterAmbiguous = false

            while idx < tokens.count && tokens[idx].isWordLetter {
                let tok = tokens[idx]
                if tok.isOriginalUpperLetter {
                    upperCount += 1
                    if seenAmbiguousVowel {
                        hasUpperAfterAmbiguous = true
                    }
                } else if tok.isOriginalLowerLetter {
                    lowerCount += 1
                } else if tok.isTCVN3AccentedLowerVowel {
                    seenAmbiguousVowel = true
                }
                idx += 1
            }

            wordSpans.append(WordSpan(
                start: start,
                end: idx,
                upperCount: upperCount,
                lowerCount: lowerCount,
                hasUpperAfterAmbiguousVowel: hasUpperAfterAmbiguous
            ))
        }

        var promoteSpan = Array(repeating: false, count: wordSpans.count)
        for i in wordSpans.indices {
            let span = wordSpans[i]
            if span.isUnambiguouslyAllCaps {
                promoteSpan[i] = true
            } else if span.lowerCount == 0 && span.upperCount == 1 {
                // Single-consonant + accented-vowel word (e.g. "X·" -> "XÃ" vs "Xã"):
                // Promote when followed by an unambiguously ALL-CAPS word, or when preceded
                // by an unambiguously ALL-CAPS word and not followed by a lowercase/Title-Case word.
                let nextIsAllCaps = (i + 1 < wordSpans.count) && wordSpans[i + 1].isUnambiguouslyAllCaps
                let nextHasLower = (i + 1 < wordSpans.count) && wordSpans[i + 1].hasOriginalLower
                let prevIsAllCaps = (i > 0) && wordSpans[i - 1].isUnambiguouslyAllCaps
                if nextIsAllCaps || (prevIsAllCaps && !nextHasLower) {
                    promoteSpan[i] = true
                }
            }
        }

        var promoteIndex = Array(repeating: false, count: tokens.count)
        for (i, span) in wordSpans.enumerated() where promoteSpan[i] {
            for pos in span.start..<span.end {
                promoteIndex[pos] = true
            }
        }

        var out = String()
        out.reserveCapacity(text.utf8.count)
        for (pos, tok) in tokens.enumerated() {
            if tok.isTCVN3AccentedLowerVowel && promoteIndex[pos] {
                out.append(String(tok.converted).uppercased())
            } else {
                out.unicodeScalars.append(tok.converted)
            }
        }

        return out.precomposedStringWithCanonicalMapping
    }

    // Complete 74-entry TCVN 5712:1993 (VN1 / ABC) table
    private static let tcvn3ScalarMap: [UInt32: UnicodeScalar] = [
        0xA1: "\u{0102}", // Ă
        0xA2: "\u{00C2}", // Â
        0xA3: "\u{00CA}", // Ê
        0xA4: "\u{00D4}", // Ô
        0xA5: "\u{01A0}", // Ơ
        0xA6: "\u{01AF}", // Ư
        0xA7: "\u{0110}", // Đ
        0xA8: "\u{0103}", // ă
        0xA9: "\u{00E2}", // â
        0xAA: "\u{00EA}", // ê
        0xAB: "\u{00F4}", // ô
        0xAC: "\u{01A1}", // ơ
        0xAD: "\u{01B0}", // ư
        0xAE: "\u{0111}", // đ

        0xB5: "\u{00E0}", // à
        0xB6: "\u{1EA3}", // ả
        0xB7: "\u{00E3}", // ã
        0xB8: "\u{00E1}", // á
        0xB9: "\u{1EA1}", // ạ

        0xBB: "\u{1EB1}", // ằ
        0xBC: "\u{1EB3}", // ẳ
        0xBD: "\u{1EB5}", // ẵ
        0xBE: "\u{1EAF}", // ắ
        0xC6: "\u{1EB7}", // ặ

        0xC7: "\u{1EA7}", // ầ
        0xC8: "\u{1EA9}", // ẩ
        0xC9: "\u{1EAB}", // ẫ
        0xCA: "\u{1EA5}", // ấ
        0xCB: "\u{1EAD}", // ậ

        0xCC: "\u{00E8}", // è
        0xCE: "\u{1EBB}", // ẻ
        0xCF: "\u{1EBD}", // ẽ
        0xD0: "\u{00E9}", // é
        0xD1: "\u{1EB9}", // ẹ

        0xD2: "\u{1EC1}", // ề
        0xD3: "\u{1EC3}", // ể
        0xD4: "\u{1EC5}", // ễ
        0xD5: "\u{1EBF}", // ế
        0xD6: "\u{1EC7}", // ệ

        0xD7: "\u{00EC}", // ì
        0xD8: "\u{1EC9}", // ỉ
        0xDC: "\u{0129}", // ĩ
        0xDD: "\u{00ED}", // í
        0xDE: "\u{1ECB}", // ị

        0xDF: "\u{00F2}", // ò
        0xE1: "\u{1ECF}", // ỏ
        0xE2: "\u{00F5}", // õ
        0xE3: "\u{00F3}", // ó
        0xE4: "\u{1ECD}", // ọ

        0xE5: "\u{1ED3}", // ồ
        0xE6: "\u{1ED5}", // ổ
        0xE7: "\u{1ED7}", // ỗ
        0xE8: "\u{1ED1}", // ố
        0xE9: "\u{1ED9}", // ộ

        0xEA: "\u{1EDD}", // ờ
        0xEB: "\u{1EDF}", // ở
        0xEC: "\u{1EE1}", // ỡ
        0xED: "\u{1EDB}", // ớ
        0xEE: "\u{1EE3}", // ợ

        0xEF: "\u{00F9}", // ù
        0xF1: "\u{1EE7}", // ủ
        0xF2: "\u{0169}", // ũ
        0xF3: "\u{00FA}", // ú
        0xF4: "\u{1EE5}", // ụ

        0xF5: "\u{1EEB}", // ừ
        0xF6: "\u{1EED}", // ử
        0xF7: "\u{1EEF}", // ữ
        0xF8: "\u{1EE9}", // ứ
        0xF9: "\u{1EF1}", // ự

        0xFA: "\u{1EF3}", // ỳ
        0xFB: "\u{1EF7}", // ỷ
        0xFC: "\u{1EF9}", // ỹ
        0xFD: "\u{00FD}", // ý
        0xFE: "\u{1EF5}"  // ỵ
    ]

    // MARK: - 3. VNI Windows -> Unicode NFC

    /// Converts 2-byte / 1-byte VNI-Windows (`VNI-Times`, `VNI-Helve`, etc.) text into
    /// precomposed Unicode (NFC), covering all 134 Vietnamese accented letters.
    public static func vniWindowsToUnicode(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        let scalars = Array(text.unicodeScalars)
        var out = String()
        out.reserveCapacity(text.utf8.count)

        var i = 0
        while i < scalars.count {
            let first = scalars[i].value
            if i + 1 < scalars.count {
                let second = scalars[i + 1].value
                if let pairMapped = lookupVNI2Byte(base: first, modifier: second) {
                    out.unicodeScalars.append(pairMapped)
                    i += 2
                    continue
                }
            }
            if let singleMapped = vni1ByteMap[first] {
                out.unicodeScalars.append(singleMapped)
            } else {
                out.unicodeScalars.append(scalars[i])
            }
            i += 1
        }

        return out.precomposedStringWithCanonicalMapping
    }

    private static func lookupVNI2Byte(base: UInt32, modifier: UInt32) -> UnicodeScalar? {
        let isUpperBase: Bool
        let canonicalLowerBase: UInt32

        switch base {
        case 0x61: isUpperBase = false; canonicalLowerBase = 0x61 // a
        case 0x41: isUpperBase = true;  canonicalLowerBase = 0x61 // A
        case 0x65: isUpperBase = false; canonicalLowerBase = 0x65 // e
        case 0x45: isUpperBase = true;  canonicalLowerBase = 0x65 // E
        case 0x6F: isUpperBase = false; canonicalLowerBase = 0x6F // o
        case 0x4F: isUpperBase = true;  canonicalLowerBase = 0x6F // O
        case 0xF4: isUpperBase = false; canonicalLowerBase = 0xF4 // ô -> ơ base
        case 0xD4: isUpperBase = true;  canonicalLowerBase = 0xF4 // Ô -> Ơ base
        case 0x75: isUpperBase = false; canonicalLowerBase = 0x75 // u
        case 0x55: isUpperBase = true;  canonicalLowerBase = 0x75 // U
        case 0xF6: isUpperBase = false; canonicalLowerBase = 0xF6 // ö -> ư base
        case 0xD6: isUpperBase = true;  canonicalLowerBase = 0xF6 // Ö -> Ư base
        case 0x79: isUpperBase = false; canonicalLowerBase = 0x79 // y
        case 0x59: isUpperBase = true;  canonicalLowerBase = 0x79 // Y
        default:
            return nil
        }

        // Normalize uppercase VNI modifier bytes (0xC0..0xDC) to lowercase modifier slots (0xE0..0xFC).
        // When `isUpperBase` is true, accept either uppercase or lowercase modifier bytes (handles
        // manually Title-Cased words like "Aùo" in addition to standard "AÙo").
        // When `isUpperBase` is false, require lowercase modifier bytes (0xE0..0xFC) so an adjacent
        // uppercase VNI 1-byte letter (e.g. "aÑ" = "aĐ") is never misread as a modifier.
        let normalizedMod: UInt32
        if modifier >= 0xE0 && modifier <= 0xFC {
            normalizedMod = modifier
        } else if isUpperBase && modifier >= 0xC0 && modifier <= 0xDC {
            normalizedMod = modifier + 0x20
        } else {
            return nil
        }

        let key = (canonicalLowerBase << 8) | normalizedMod
        guard let lowerScalar = vniLowerPairMap[key] else { return nil }
        if isUpperBase {
            return String(lowerScalar).uppercased().unicodeScalars.first ?? lowerScalar
        }
        return lowerScalar
    }

    private static let vniLowerPairMap: [UInt32: UnicodeScalar] = [
        // a + plain tones
        (0x61 << 8) | 0xF8: "\u{00E0}", // à
        (0x61 << 8) | 0xFB: "\u{1EA3}", // ả
        (0x61 << 8) | 0xF5: "\u{00E3}", // ã
        (0x61 << 8) | 0xF9: "\u{00E1}", // á
        (0x61 << 8) | 0xEF: "\u{1EA1}", // ạ
        // a + breve (ă..ặ)
        (0x61 << 8) | 0xEA: "\u{0103}", // ă
        (0x61 << 8) | 0xE8: "\u{1EB1}", // ằ
        (0x61 << 8) | 0xFA: "\u{1EB3}", // ẳ
        (0x61 << 8) | 0xFC: "\u{1EB5}", // ẵ
        (0x61 << 8) | 0xE9: "\u{1EAF}", // ắ
        (0x61 << 8) | 0xEB: "\u{1EB7}", // ặ
        // a + circumflex (â..ậ)
        (0x61 << 8) | 0xE2: "\u{00E2}", // â
        (0x61 << 8) | 0xE0: "\u{1EA7}", // ầ
        (0x61 << 8) | 0xE5: "\u{1EA9}", // ẩ
        (0x61 << 8) | 0xE3: "\u{1EAB}", // ẫ
        (0x61 << 8) | 0xE1: "\u{1EA5}", // ấ
        (0x61 << 8) | 0xE4: "\u{1EAD}", // ậ

        // e + plain tones
        (0x65 << 8) | 0xF8: "\u{00E8}", // è
        (0x65 << 8) | 0xFB: "\u{1EBB}", // ẻ
        (0x65 << 8) | 0xF5: "\u{1EBD}", // ẽ
        (0x65 << 8) | 0xF9: "\u{00E9}", // é
        (0x65 << 8) | 0xEF: "\u{1EB9}", // ẹ
        // e + circumflex (ê..ệ)
        (0x65 << 8) | 0xE2: "\u{00EA}", // ê
        (0x65 << 8) | 0xE0: "\u{1EC1}", // ề
        (0x65 << 8) | 0xE5: "\u{1EC3}", // ể
        (0x65 << 8) | 0xE3: "\u{1EC5}", // ễ
        (0x65 << 8) | 0xE1: "\u{1EBF}", // ế
        (0x65 << 8) | 0xE4: "\u{1EC7}", // ệ

        // o + plain tones
        (0x6F << 8) | 0xF8: "\u{00F2}", // ò
        (0x6F << 8) | 0xFB: "\u{1ECF}", // ỏ
        (0x6F << 8) | 0xF5: "\u{00F5}", // õ
        (0x6F << 8) | 0xF9: "\u{00F3}", // ó
        (0x6F << 8) | 0xEF: "\u{1ECD}", // ọ
        // o + circumflex (ô..ộ)
        (0x6F << 8) | 0xE2: "\u{00F4}", // ô
        (0x6F << 8) | 0xE0: "\u{1ED3}", // ồ
        (0x6F << 8) | 0xE5: "\u{1ED5}", // ổ
        (0x6F << 8) | 0xE3: "\u{1ED7}", // ỗ
        (0x6F << 8) | 0xE1: "\u{1ED1}", // ố
        (0x6F << 8) | 0xE4: "\u{1ED9}", // ộ
        // ô (0xF4 = ơ base) + tones (ờ..ợ)
        (0xF4 << 8) | 0xF8: "\u{1EDD}", // ờ
        (0xF4 << 8) | 0xFB: "\u{1EDF}", // ở
        (0xF4 << 8) | 0xF5: "\u{1EE1}", // ỡ
        (0xF4 << 8) | 0xF9: "\u{1EDB}", // ớ
        (0xF4 << 8) | 0xEF: "\u{1EE3}", // ợ

        // u + plain tones
        (0x75 << 8) | 0xF8: "\u{00F9}", // ù
        (0x75 << 8) | 0xFB: "\u{1EE7}", // ủ
        (0x75 << 8) | 0xF5: "\u{0169}", // ũ
        (0x75 << 8) | 0xF9: "\u{00FA}", // ú
        (0x75 << 8) | 0xEF: "\u{1EE5}", // ụ
        // ö (0xF6 = ư base) + tones (ừ..ự)
        (0xF6 << 8) | 0xF8: "\u{1EEB}", // ừ
        (0xF6 << 8) | 0xFB: "\u{1EED}", // ử
        (0xF6 << 8) | 0xF5: "\u{1EEF}", // ữ
        (0xF6 << 8) | 0xF9: "\u{1EE9}", // ứ
        (0xF6 << 8) | 0xEF: "\u{1EF1}", // ự

        // y + tones (ỳ, ỷ, ỹ, ý + fallback yï -> ỵ)
        (0x79 << 8) | 0xF8: "\u{1EF3}", // ỳ
        (0x79 << 8) | 0xFB: "\u{1EF7}", // ỷ
        (0x79 << 8) | 0xF5: "\u{1EF9}", // ỹ
        (0x79 << 8) | 0xF9: "\u{00FD}", // ý
        (0x79 << 8) | 0xEF: "\u{1EF5}"  // ỵ (2-byte fallback; primary 1-byte is 0xEE)
    ]

    private static let vni1ByteMap: [UInt32: UnicodeScalar] = [
        0xF1: "\u{0111}", // đ
        0xD1: "\u{0110}", // Đ

        0xEC: "\u{00EC}", // ì
        0xE6: "\u{1EC9}", // ỉ
        0xF3: "\u{0129}", // ĩ
        0xED: "\u{00ED}", // í
        0xF2: "\u{1ECB}", // ị

        0xCC: "\u{00CC}", // Ì
        0xC6: "\u{1EC8}", // Ỉ
        0xD3: "\u{0128}", // Ĩ
        0xCD: "\u{00CD}", // Í
        0xD2: "\u{1ECA}", // Ị

        0xF4: "\u{01A1}", // ơ
        0xD4: "\u{01A0}", // Ơ
        0xF6: "\u{01B0}", // ư
        0xD6: "\u{01AF}", // Ư

        0xEE: "\u{1EF5}", // ỵ
        0xCE: "\u{1EF4}"  // Ỵ
    ]
}
