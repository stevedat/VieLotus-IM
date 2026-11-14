import Foundation

/// Resolves candidate interpretations between raw ASCII tokens and composed Vietnamese syllables.
internal final class SyllableCandidateResolver: Sendable {
    internal static let shared = SyllableCandidateResolver()

    internal init() {}

    private static let unambiguousPreVowelPrefixDigests: Set<UInt64> = [
        0x1fb67f9bc5f1de76, 0xbd9525765d0d82b1, 0x89a474ff2716c44c, 0x3ecb19e3bcfae1f4,
        0x0415af1968d408cb, 0x275bd37622a76f98, 0xebc3eebf31c85dde, 0x01ea8f934b0f8da4,
        0xc5f99eddace37ed6, 0x8d7bbe733f0ebd07, 0x3613fac524d092e9, 0xf527282754d6ceeb,
        0xb747554f77e8ad0d, 0xdbbc88d847be7c91, 0x530e7819b9f600b8, 0x71d437bc5b922d6e,
        0x2005ce088a35f4b5, 0xa4fa3bf0e9df5336, 0xb5f13ccc9c2a7040, 0x9c12e871dbb6faa6,
        0x50df898617f02fda, 0xe50775e767d90d45, 0xe30eb15a42215a33
    ]

    internal static let englishCollisionDigests: Set<UInt64> = [
        0x8135b6d21537f54f, 0x26184131b5e9db64, 0x81d704ef364ff140, 0x4682f2866e028cc8,
        0xdb1c0fe3177d937b, 0x54cb9527f7a6e17c
    ]

    /// Arbitrates between candidate interpretations for a raw keystroke sequence.
    internal func arbitrate(
        rawChars: [Character],
        vnParsed: (intent: SyllableIntent, rendered: String),
        profile: GrammarProfile
    ) -> SyllableCandidate {
        let rawStr = String(rawChars)
        let lowerRaw = rawStr.lowercased()

        let rawCandidate = SyllableCandidate(
            raw: rawStr,
            rendered: rawStr,
            priority: .p6_ambiguousOrEnglish,
            isVietnamese: false,
            intent: SyllableIntent(rawChars: rawChars)
        )

        if rawChars.isEmpty {
            return rawCandidate
        }

        if isProtectedToken(lowerRaw) {
            return SyllableCandidate(
                raw: rawStr,
                rendered: rawStr,
                priority: .p2_protectedToken,
                isVietnamese: false,
                intent: rawCandidate.intent
            )
        }

        if vnParsed.rendered == rawStr {
            return SyllableCandidate(
                raw: rawStr,
                rendered: rawStr,
                priority: .p6_ambiguousOrEnglish,
                isVietnamese: vnParsed.intent.isValidVietnamese,
                intent: vnParsed.intent
            )
        }

        let vnPriority = evaluateVnPriority(lowerRaw: lowerRaw, intent: vnParsed.intent, rendered: vnParsed.rendered)

        if vnPriority == .p6_ambiguousOrEnglish {
            return rawCandidate
        }

        let score = calculateIntentScore(lowerRaw: lowerRaw, intent: vnParsed.intent, rendered: vnParsed.rendered)
        return SyllableCandidate(
            raw: rawStr,
            rendered: vnParsed.rendered,
            priority: vnPriority,
            isVietnamese: true,
            intent: vnParsed.intent,
            score: score
        )
    }

    internal func calculateIntentScore(lowerRaw: String, intent: SyllableIntent, rendered: String) -> Int {
        var score = 0
        if VietnameseSyllableDictionary.shared.isValidSyllable(rendered) {
            score += 40
        }
        if intent.hasHornModifier && intent.tone != .none {
            score += 25
        }
        let hasCircumflex = rendered.contains(where: { "âăêôơư".contains($0) })
        if hasCircumflex && intent.tone != .none {
            score += 20
        }
        if intent.hasPreVowelTone {
            score += 20
        }
        if Self.isEnglishCollision(lowerRaw) {
            score -= 50
        }
        return score
    }

    internal static func isEnglishCollision(_ lowerRaw: String) -> Bool {
        if LexiconDigest.contains(englishCollisionDigests, lowerRaw) {
            return true
        }
        if lowerRaw.count >= 3 && lowerRaw.hasSuffix("sh") &&
           !lowerRaw.contains("dd") && !lowerRaw.contains("aa") && !lowerRaw.contains("ee") && !lowerRaw.contains("oo") &&
           !lowerRaw.dropFirst().contains("w") {
            return true
        }
        return false
    }

    /// Evaluates post-coda modifier cancellation or vowel extension state transitions.
    internal static func isPostCodaModifierUndoOrExtension(lowerRaw: String, rendered: String) -> Bool {
        let lowerRendered = rendered.lowercased()
        guard lowerRaw != lowerRendered else { return false }
        if isSingleCharPostCodaModifierUndoOrExtension(lowerRaw: lowerRaw, lowerRendered: lowerRendered) {
            return true
        }
        if !lowerRendered.hasSuffix("z") && VietnameseSyllableDictionary.shared.isValidSyllable(lowerRendered) {
            return false
        }
        guard !Self.isEnglishCollision(lowerRaw),
              !SmartBilingualDetector.isKnownEnglishWord(lowerRaw),
              lowerRendered.count >= 2 else {
            return isStickyPostCodaOverflow(lowerRaw: lowerRaw, lowerRendered: lowerRendered)
        }
        var rawPrefix = lowerRaw
        var renderedPrefix = lowerRendered
        while rawPrefix.count >= 3,
              renderedPrefix.count >= 1,
              let rLast = rawPrefix.last,
              let dLast = renderedPrefix.last,
              rLast == dLast,
              rLast.isASCII {
            rawPrefix.removeLast()
            renderedPrefix.removeLast()
            if isSingleCharPostCodaModifierUndoOrExtension(lowerRaw: rawPrefix, lowerRendered: renderedPrefix) {
                return true
            }
        }
        return isStickyPostCodaOverflow(lowerRaw: lowerRaw, lowerRendered: lowerRendered)
    }

    private static func isSingleCharPostCodaModifierUndoOrExtension(lowerRaw: String, lowerRendered: String) -> Bool {
        guard lowerRaw != lowerRendered, lowerRaw.count >= 3, !lowerRendered.isEmpty else { return false }
        if lowerRaw.hasPrefix("d"),
           (lowerRendered.hasPrefix("d") || lowerRendered.hasPrefix("đ")),
           lowerRaw.filter({ $0 == "d" }).count >= 3,
           !Self.isEnglishCollision(lowerRaw),
           !SmartBilingualDetector.isKnownEnglishWord(lowerRaw) {
            var baseRendered = lowerRendered
            while baseRendered.count > 1 && (baseRendered.last == "đ" || baseRendered.last == "d") {
                baseRendered.removeLast()
            }
            if !baseRendered.isEmpty {
                let restoredD = "đ" + baseRendered.dropFirst()
                let hasShapeUndo =
                    restoredD.hasPrefix("đuo") ||
                    lowerRaw.filter({ $0 == "w" }).count >= 2 ||
                    lowerRaw.filter({ $0 == "a" }).count >= 3 ||
                    lowerRaw.filter({ $0 == "e" }).count >= 3 ||
                    lowerRaw.filter({ $0 == "o" }).count >= 3
                if VietnameseSyllableDictionary.shared.isPhonotacticallyValidSyllable(restoredD) ||
                   (!VietnameseSyllableDictionary.hasToneMark(restoredD) &&
                    VietnameseSyllableDictionary.shared.isValidUntonedSyllable(restoredD)) ||
                   (hasShapeUndo &&
                    (VietnameseSyllableDictionary.shared.isValidSyllableIgnoringVowelShape(restoredD) ||
                     (!VietnameseSyllableDictionary.hasToneMark(restoredD) &&
                      VietnameseSyllableDictionary.shared.isValidUntonedSyllableIgnoringVowelShape(restoredD)))) {
                    return true
                }
            }
        }
        let untonedRendered = VietnameseSyllableDictionary.stripToneMarks(lowerRendered)
        if lowerRaw.last == "o",
           lowerRaw.contains("w"),
           (untonedRendered.contains("uô") || (untonedRendered.contains("ô") && lowerRendered.count >= 2)),
           !SmartBilingualDetector.isKnownEnglishWord(lowerRaw),
           VietnameseSyllableDictionary.shared.isValidSyllableIgnoringVowelShape(lowerRendered) {
            return true
        }
        if lowerRaw.last == "a",
           lowerRaw.contains("w"),
           untonedRendered.contains("â"),
           !SmartBilingualDetector.isKnownEnglishWord(lowerRaw),
           (VietnameseSyllableDictionary.shared.isValidSyllableIgnoringVowelShape(lowerRendered) ||
            VietnameseSyllableDictionary.shared.isPhonotacticallyValidSyllable(lowerRendered)) {
            return true
        }
        if let lastRaw = lowerRaw.last,
           ["a", "e", "o", "w", "s", "f", "r", "x", "j", "z", "d"].contains(lastRaw),
           !untonedRendered.contains(where: { "ăâêôơư".contains($0) }) {
            let counts = ModifierCharCounts(lowerRaw)
            let aCount = counts.a
            let eCount = counts.e
            let oCount = counts.o
            let wCount = counts.w
            let hasVowelShapeUndo =
                wCount >= 2 ||
                aCount >= 3 ||
                eCount >= 3 ||
                oCount >= 3 ||
                (wCount >= 1 && oCount >= 2) ||
                (wCount >= 1 && aCount >= 2)
            if hasVowelShapeUndo &&
               (lowerRendered.last != lastRaw || VietnameseSyllableDictionary.shared.isValidUntonedSyllableIgnoringVowelShape(lowerRendered)) &&
               !Self.isEnglishCollision(lowerRaw) &&
               !SmartBilingualDetector.isKnownEnglishWord(lowerRaw) &&
               (VietnameseSyllableDictionary.shared.isValidSyllableIgnoringVowelShape(lowerRendered) ||
                (!VietnameseSyllableDictionary.hasToneMark(lowerRendered) &&
                 VietnameseSyllableDictionary.shared.isValidUntonedSyllableIgnoringVowelShape(lowerRendered))) {
                return true
            }
        }
        guard let lastRendered = lowerRendered.last, let lastRaw = lowerRaw.last, lastRendered == lastRaw else {
            return false
        }
        let trailingAllowed: Set<Character> = ["a", "e", "o", "u", "i", "y", "w"]
        if trailingAllowed.contains(lastRendered) {
            let counts = ModifierCharCounts(lowerRaw)
            let aCount = counts.a
            let eCount = counts.e
            let oCount = counts.o
            let iCount = counts.i
            let uCount = counts.u
            let yCount = counts.y
            let wCount = counts.w
            let rawStem = String(lowerRaw.dropLast())
            let endsStemWithToneKey = rawStem.last.map { "sfrxj".contains($0) } ?? false
            let hasInfixToneOnVnStem =
                VietnameseSyllableDictionary.hasToneMark(String(lowerRendered.dropLast())) &&
                rawStem.contains(where: { "sfrxj".contains($0) }) &&
                !Self.isEnglishCollision(rawStem) &&
                !rawStem.contains("st")
            let hasModifierSignal =
                wCount >= 1 ||
                lowerRaw.contains("dd") ||
                lowerRendered.hasPrefix("đ") ||
                aCount >= 2 ||
                eCount >= 2 ||
                oCount >= 2 ||
                iCount >= 2 ||
                uCount >= 2 ||
                yCount >= 2 ||
                ((endsStemWithToneKey || hasInfixToneOnVnStem) && lastRendered != "y" && LexiconDigest.hash(lowerRaw) != 0x97db446ad8626fee)
            if hasModifierSignal {
                let stem = String(lowerRendered.dropLast())
                if let lastStemChar = stem.last {
                    let validCodaEndings: Set<Character> = ["c", "m", "n", "p", "t", "g", "h"]
                    let isCodaStem = validCodaEndings.contains(lastStemChar)
                    let stemIsASCII = stem.unicodeScalars.allSatisfy({ $0.isASCII })

                    if isCodaStem {
                        if !stemIsASCII {
                            let isValidOrUntonedVnStem =
                                VietnameseSyllableDictionary.shared.isPhonotacticallyValidSyllable(stem) ||
                                (!VietnameseSyllableDictionary.hasToneMark(stem) &&
                                 (stem.contains(where: { "đăâơư".contains($0) }) || stem.contains("uô")) &&
                                 VietnameseSyllableDictionary.shared.isValidUntonedSyllable(stem)) ||
                                VietnameseSyllableDictionary.shared.isValidRelaxedCodaVietnamese(
                                    stem,
                                    raw: String(lowerRaw.dropLast()),
                                    genZMode: true
                                )
                            if isValidOrUntonedVnStem && !SmartBilingualDetector.isKnownEnglishWord(lowerRaw) {
                                return true
                            }
                            let isVowelShapeUndoOrReshape =
                                (lastRendered == "w" && wCount >= 2) ||
                                (lastRendered == "o" && ((wCount >= 1 && oCount >= 2) || oCount >= 3)) ||
                                (lastRendered == "a" && (aCount >= 3 || wCount >= 1)) ||
                                (lastRendered == "e" && eCount >= 3)
                            if isVowelShapeUndoOrReshape,
                               (VietnameseSyllableDictionary.shared.isValidSyllableIgnoringVowelShape(stem) ||
                                (stem.contains("đ") &&
                                 !VietnameseSyllableDictionary.hasToneMark(stem) &&
                                 VietnameseSyllableDictionary.shared.isValidUntonedSyllableIgnoringVowelShape(stem))) {
                                return true
                            }
                        } else {
                            let isUndoSignal =
                                (lastRendered == "a" && aCount >= 3) ||
                                (lastRendered == "e" && eCount >= 3) ||
                                (lastRendered == "o" && oCount >= 3) ||
                                (lastRendered == "w" && wCount >= 2)
                            if isUndoSignal && VietnameseSyllableDictionary.shared.isValidSyllableIgnoringVowelShape(stem) {
                                return true
                            }
                        }
                    } else {
                        let untonedStem = VietnameseSyllableDictionary.stripToneMarks(stem)
                        if !untonedStem.unicodeScalars.allSatisfy({ $0.isASCII }),
                           (lastStemChar == "i" || lastStemChar == "u" || lastStemChar == "y"),
                           !lowerRaw.hasPrefix("w"),
                           VietnameseSyllableDictionary.shared.isPhonotacticallyValidSyllable(stem) {
                            return true
                        }
                        if !stemIsASCII,
                           !lowerRaw.hasPrefix("w"),
                           !Self.isEnglishCollision(lowerRaw),
                           !SmartBilingualDetector.isKnownEnglishWord(lowerRaw),
                           Self.asciiBaseVowel(of: lastStemChar) == lastRendered,
                           VietnameseSyllableDictionary.shared.isPhonotacticallyValidSyllable(stem) {
                            return true
                        }
                        let isOffglideStem = lastStemChar == "i" || lastStemChar == "u" || lastStemChar == "y"
                        let isOpenOrOffglideUndoOrReshape =
                            (lastRendered == "w" && wCount >= 2) ||
                            (lastRendered == "o" && wCount >= 1 && oCount >= 2 && (lastStemChar == "i" || lastStemChar == "u") && VietnameseSyllableDictionary.stripToneMarks(stem).contains("uô")) ||
                            (lastRendered == "a" && (aCount >= 3 || (aCount >= 2 && wCount >= 1)) && (isOffglideStem || !stem.unicodeScalars.allSatisfy({ $0.isASCII }))) ||
                            (lastRendered == "e" && eCount >= 3 && (isOffglideStem || !stem.unicodeScalars.allSatisfy({ $0.isASCII }))) ||
                            (lastRendered == "o" && (oCount >= 3 || (oCount >= 2 && wCount >= 1)) && (isOffglideStem || !stem.unicodeScalars.allSatisfy({ $0.isASCII })))
                        if isOpenOrOffglideUndoOrReshape,
                           !SmartBilingualDetector.isKnownEnglishWord(lowerRaw),
                           VietnameseEngine.isVietnameseVowel(lastStemChar),
                           (VietnameseSyllableDictionary.shared.isValidSyllableIgnoringVowelShape(stem) ||
                            (stem.count >= 2 &&
                             !VietnameseSyllableDictionary.hasToneMark(stem) &&
                             VietnameseSyllableDictionary.shared.isValidUntonedSyllableIgnoringVowelShape(stem))) {
                            return true
                        }
                    }
                }
            }
        }
        return false
    }

    private static func asciiBaseVowel(of char: Character) -> Character? {
        guard VietnameseEngine.isVietnameseVowel(char),
              let firstScalar = String(char).lowercased().decomposedStringWithCanonicalMapping.unicodeScalars.first,
              firstScalar.isASCII else {
            return nil
        }
        return Character(firstScalar)
    }

    private static func isStickyPostCodaOverflow(lowerRaw: String, lowerRendered: String) -> Bool {
        guard !Self.isEnglishCollision(lowerRaw),
              !SmartBilingualDetector.isKnownEnglishWord(lowerRaw) else {
            return false
        }
        let validCodaEndings: Set<Character> = ["c", "m", "n", "p", "t", "g", "h"]
        let renderedChars = Array(lowerRendered)
        // Literal 'z' suffix on any non-ASCII Vietnamese vowel/consonant stem (e.g. ôz, rônz, rônzz, chưz, đươcz, cânz):
        // Never require dictionary validity or strip vowel modifiers back to raw ASCII (e.g. roonz, ooz, chuwz).
        if lowerRendered.hasSuffix("z"), lowerRaw.hasSuffix("z") {
            var stemChars = renderedChars
            var zTailCount = 0
            while stemChars.last == "z" {
                stemChars.removeLast()
                zTailCount += 1
            }
            let zTail = String(repeating: "z", count: zTailCount)
            let stem = String(stemChars)
            if !stem.isEmpty,
               lowerRaw.count > zTailCount,
               lowerRaw.hasSuffix(zTail),
               !stem.unicodeScalars.allSatisfy({ $0.isASCII }),
               !stem.hasPrefix("br") {
                return true
            }
        }
        guard renderedChars.count >= 2 else { return false }
        let hasDoubleToneEscape = ["ss", "ff", "rr", "xx", "jj"].contains(where: { lowerRaw.contains($0) })
        let collapsedRaw = SmartBilingualDetector.collapsedTelexToneEscapes(lowerRaw) ?? lowerRaw
        let rawCounts = ModifierCharCounts(lowerRaw)
        let aCount = rawCounts.a
        let eCount = rawCounts.e
        let oCount = rawCounts.o
        let wCount = rawCounts.w
        let dCount = rawCounts.d
        let hasCancelledVowelShape =
            wCount >= 2 ||
            aCount >= 3 ||
            eCount >= 3 ||
            oCount >= 3 ||
            (wCount >= 1 && oCount >= 2) ||
            (wCount >= 1 && aCount >= 2)

        for stemLen in stride(from: renderedChars.count - 1, through: 1, by: -1) {
            let tail = String(renderedChars[stemLen...])
            let rawTail = tail.replacingOccurrences(of: "đ", with: "dd")
            let isToneEscapeTail = hasDoubleToneEscape && (
                rawTail.allSatisfy({ "sfrxjz".contains($0) }) ||
                collapsedRaw.hasSuffix(rawTail)
            )
            guard rawTail.unicodeScalars.allSatisfy({ $0.isASCII }),
                  lowerRaw.count > rawTail.count,
                  (lowerRaw.hasSuffix(rawTail) || isToneEscapeTail) else {
                continue
            }
            let stem = String(renderedChars[0..<stemLen])
            let untonedStem = VietnameseSyllableDictionary.stripToneMarks(stem)
            let isSingleModifiedVowelStem =
                stemLen == 1 &&
                !lowerRaw.hasPrefix("w") &&
                untonedStem.contains(where: { "ăâêôơư".contains($0) }) &&
                rawTail.allSatisfy({ "aeiouy".contains($0) })
            if stemLen == 1 && !isSingleModifiedVowelStem {
                continue
            }
            let hasTone = VietnameseSyllableDictionary.hasToneMark(stem)
            let restoredDStem = "đ" + stem.dropFirst()
            let hasCancelledStrokeD =
                dCount >= 3 &&
                stem.hasPrefix("d") &&
                (VietnameseSyllableDictionary.shared.isPhonotacticallyValidSyllable(restoredDStem) ||
                 (!hasTone && VietnameseSyllableDictionary.shared.isValidUntonedSyllable(restoredDStem)) ||
                 ((restoredDStem.hasPrefix("đuo") || hasCancelledVowelShape) &&
                  (VietnameseSyllableDictionary.shared.isValidSyllableIgnoringVowelShape(restoredDStem) ||
                   (!hasTone && VietnameseSyllableDictionary.shared.isValidUntonedSyllableIgnoringVowelShape(restoredDStem)))))
            let isRelaxedCodaModifierOverflow =
                !stem.unicodeScalars.allSatisfy({ $0.isASCII }) &&
                rawTail.allSatisfy({ "aeowzsfrxj".contains($0) }) &&
                VietnameseSyllableDictionary.shared.isValidRelaxedCodaVietnamese(
                    stem,
                    raw: String(lowerRaw.dropLast(rawTail.count)),
                    genZMode: true
                )
            let isValidOrUntonedVnStem =
                isSingleModifiedVowelStem ||
                VietnameseSyllableDictionary.shared.isPhonotacticallyValidSyllable(stem) ||
                (!hasTone &&
                 (stem.contains(where: { "đăâơư".contains($0) }) || stem.contains("uô") || stem.contains("iê") || stem.contains("yê")) &&
                 VietnameseSyllableDictionary.shared.isValidUntonedSyllable(stem)) ||
                ((hasCancelledVowelShape || untonedStem.hasPrefix("đuo")) &&
                 (VietnameseSyllableDictionary.shared.isValidSyllableIgnoringVowelShape(stem) ||
                  (!hasTone && VietnameseSyllableDictionary.shared.isValidUntonedSyllableIgnoringVowelShape(stem)))) ||
                hasCancelledStrokeD ||
                isRelaxedCodaModifierOverflow
            guard let lastStemChar = stem.last,
                  (!stem.unicodeScalars.allSatisfy({ $0.isASCII }) || hasCancelledStrokeD || hasCancelledVowelShape),
                  isValidOrUntonedVnStem else {
                continue
            }

            if isToneEscapeTail {
                return true
            }

            let isVowelOverflowStem: Bool = {
                guard VietnameseEngine.isVietnameseVowel(lastStemChar),
                      !VietnameseSyllableDictionary.shared.isPlausibleInProgressVietnamese(lowerRendered, relaxedCoda: true, genZMode: true) else {
                    return false
                }
                if isSingleModifiedVowelStem {
                    return true
                }
                let rawStem = String(lowerRaw.dropLast(rawTail.count))
                let stemCounts = ModifierCharCounts(rawStem)
                let stemACount = stemCounts.a
                let stemECount = stemCounts.e
                let stemOCount = stemCounts.o
                let stemWCount = stemCounts.w
                let hasStemCancelledVowelShape =
                    stemWCount >= 2 ||
                    stemACount >= 3 ||
                    stemECount >= 3 ||
                    stemOCount >= 3 ||
                    (stemWCount >= 1 && stemOCount >= 2) ||
                    (stemWCount >= 1 && stemACount >= 2)
                guard hasTone || untonedStem.hasPrefix("đ") || hasStemCancelledVowelShape || hasCancelledStrokeD || lastStemChar == "i" || lastStemChar == "u" || lastStemChar == "y" else {
                    return false
                }
                if hasTone {
                    guard rawStem.contains(where: { "sfrxj".contains($0) }) else { return false }
                }
                return true
            }()

            guard validCodaEndings.contains(lastStemChar) || isVowelOverflowStem else {
                continue
            }

            let hasVnSpecificShape = untonedStem.contains(where: { "đăâơư".contains($0) }) || untonedStem.contains("uô") || untonedStem.contains("iê") || untonedStem.contains("yê")
            let hasCircumflexEOrOWithTone = hasTone && untonedStem.contains(where: { "êô".contains($0) })
            let rawStemForOverflow = String(lowerRaw.dropLast(rawTail.count))
            let hasPlainTonedModifierOverflow =
                hasTone &&
                rawTail.allSatisfy({ "aeowzsfrxj".contains($0) }) &&
                rawStemForOverflow.contains(where: { "sfrxj".contains($0) }) &&
                !Self.isEnglishCollision(rawStemForOverflow) &&
                !rawStemForOverflow.contains("st")

            if isSingleModifiedVowelStem || hasVnSpecificShape || hasCircumflexEOrOWithTone || hasPlainTonedModifierOverflow || hasCancelledVowelShape || hasCancelledStrokeD {
                return true
            }
        }
        return false
    }

    private func evaluateVnPriority(lowerRaw: String, intent: SyllableIntent, rendered: String) -> CandidatePriority {
        if Self.isEnglishCollision(lowerRaw) {
            return .p6_ambiguousOrEnglish
        }

        let telexDoubleEscapes = ["ww", "ss", "ff", "rr", "xx", "jj"]
        let telexTripleEscapes = ["aaa", "eee", "ooo", "ddd"]
        let hasPostCodaDoubleVowelEscape =
            ((lowerRaw.hasSuffix("aa") && !lowerRaw.hasSuffix("aaa")) ||
             (lowerRaw.hasSuffix("ee") && !lowerRaw.hasSuffix("eee")) ||
             (lowerRaw.hasSuffix("oo") && !lowerRaw.hasSuffix("ooo"))) &&
            rendered.lowercased() == String(lowerRaw.dropLast())
        let hasPreVowelTrigger = VietnameseEngine.hasPreVowelModifierTrigger(Array(lowerRaw))
        let hasExplicitZToneClear = SmartBilingualDetector.hasExplicitZToneClear(lowerRaw: lowerRaw, rendered: rendered)
        if rendered.lowercased() != lowerRaw {
            if hasExplicitZToneClear || SmartBilingualDetector.isExplicitTelexEscape(raw: lowerRaw, rendered: rendered) {
                return .p1_manualOverride
            }
            if rendered.unicodeScalars.allSatisfy({ $0.isASCII }),
               (telexDoubleEscapes.contains(where: { lowerRaw.contains($0) }) || hasPostCodaDoubleVowelEscape || hasPreVowelTrigger) {
                return .p1_manualOverride
            }
            if telexTripleEscapes.contains(where: { lowerRaw.contains($0) }) {
                return .p1_manualOverride
            }
        }

        if Self.isPostCodaModifierUndoOrExtension(lowerRaw: lowerRaw, rendered: rendered) {
            return .p1_manualOverride
        }

        if !hasPreVowelTrigger &&
           !rendered.unicodeScalars.allSatisfy({ $0.isASCII }) &&
           !VietnameseSyllableDictionary.shared.isPlausibleInProgressVietnamese(rendered, relaxedCoda: true, genZMode: true) &&
           !(!lowerRaw.hasPrefix("w") &&
             VietnameseSyllableDictionary.shared.isPlausibleInProgressVietnameseRhyme(rendered) &&
             !SmartBilingualDetector.isKnownEnglishWord(lowerRaw)) {
            return .p6_ambiguousOrEnglish
        }

        if isUnambiguousPreVowel(lowerRaw: lowerRaw, intent: intent) {
            return .p3_unambiguousPreVowel
        }

        if intent.hasHornModifier && intent.tone != .none {
            return .p4_multipleModifiers
        }
        if lowerRaw.contains("w") && (intent.tone != .none || intent.hasHornModifier) {
            return .p4_multipleModifiers
        }
        if lowerRaw.contains("dd") && intent.tone != .none {
            return .p4_multipleModifiers
        }

        if intent.isValidVietnamese || intent.tone != .none || intent.hasHornModifier ||
           intent.onset.contains("đ") ||
           VietnameseSyllableDictionary.isVietnameseStrokeDConsonantAbbreviation(rendered) ||
           intent.nucleus.contains(where: { "âăêôơư".contains($0) }) {
            return .p5_classicTrailing
        }

        return .p6_ambiguousOrEnglish
    }

    private func isUnambiguousPreVowel(lowerRaw: String, intent: SyllableIntent) -> Bool {
        if lowerRaw.count >= 2 && LexiconDigest.contains(Self.unambiguousPreVowelPrefixDigests, String(lowerRaw.prefix(2))) {
            return true
        }
        if lowerRaw.count >= 3 && LexiconDigest.contains(Self.unambiguousPreVowelPrefixDigests, String(lowerRaw.prefix(3))) {
            return true
        }

        if (lowerRaw.hasPrefix("rr") || lowerRaw.hasPrefix("ss") || lowerRaw.hasPrefix("xx")) && lowerRaw.count >= 3 {
            let third = lowerRaw[lowerRaw.index(lowerRaw.startIndex, offsetBy: 2)]
            if isVowel(third) || third == "w" {
                return true
            }
        }

        if LexiconDigest.hash(lowerRaw) == 0x97ff6dff2c8dfa04 {
            return true
        }

        if lowerRaw.hasPrefix("dd") && lowerRaw.count >= 3 {
            let third = lowerRaw[lowerRaw.index(lowerRaw.startIndex, offsetBy: 2)]
            if isToneKey(third) {
                return true
            }
        }

        if intent.hasPreVowelTone {
            return true
        }

        return false
    }

    private struct ModifierCharCounts {
        var a = 0, e = 0, o = 0, i = 0, u = 0, y = 0, w = 0, d = 0
        init(_ s: String) {
            for ch in s {
                switch ch {
                case "a": a += 1
                case "e": e += 1
                case "o": o += 1
                case "i": i += 1
                case "u": u += 1
                case "y": y += 1
                case "w": w += 1
                case "d": d += 1
                default: break
                }
            }
        }
    }

    private static let codeCharacters: Set<Character> = [
        "_", "/", "\\", ".", "@", "$", ":", "=", "+", "%", "#", "&", "*", "~", "^", "<", ">", "|", "`", "[", "]", "{", "}", "(", ")"
    ]

    private static let vowelCharacters: Set<Character> = [
        "a", "e", "i", "o", "u", "y", "ă", "â", "ê", "ô", "ơ", "ư"
    ]

    private func isProtectedToken(_ lowerRaw: String) -> Bool {
        return lowerRaw.contains { Self.codeCharacters.contains($0) || $0.isNumber }
    }

    private func isVowel(_ ch: Character) -> Bool {
        return Self.vowelCharacters.contains(ch)
    }

    private func isToneKey(_ ch: Character) -> Bool {
        return ch == "s" || ch == "f" || ch == "r" || ch == "x" || ch == "j"
    }
}
