import Foundation

/// Multi-order Vietnamese syllable intent parser.
internal final class InputGrammarParser: Sendable {
    internal static let shared = InputGrammarParser()

    internal init() {}

    /// Parses raw keystrokes according to the specified GrammarProfile.
    internal func parse(
        _ chars: [Character],
        profile: GrammarProfile,
        modernOrthography: Bool = true,
        relaxedCoda: Bool = false,
        genZMode: Bool = false,
        simpleTelex: Bool = true
    ) -> (intent: SyllableIntent, rendered: String) {
        guard !chars.isEmpty else {
            return (SyllableIntent(), "")
        }

        let lowerRaw = String(chars).lowercased()

        // Non-Vietnamese initials: 'f', 'j', 'z' cannot start a Vietnamese syllable unless genZMode
        if let first = lowerRaw.first, (first == "f" || first == "j" || first == "z") && !genZMode {
            return (SyllableIntent(rawChars: chars), String(chars))
        }

        // Simple Telex default: standalone 'w' or repeated 'w' ("w", "ww", "www", ...) remains literal 'w...' (not 'ư' or swallowed)
        if simpleTelex && chars.allSatisfy({ $0.lowercased() == "w" }) {
            return (SyllableIntent(rawChars: chars), String(chars))
        }

        // Gen-Z 'w'-initial syllables where 'w' stands for 'qu' (e.g. was/wsa -> wá, war/wra -> wả, waf/wfa -> wà, waayj/wayaj -> wậy)
        if genZMode, let wResolved = VietnameseEngine.transformGenZInitialWIfApplicable(
            chars,
            profile: profile,
            modernOrthography: modernOrthography,
            relaxedCoda: relaxedCoda,
            simpleTelex: simpleTelex
        ) {
            return wResolved
        }

        // Phonotactically impossible Vietnamese 'w'-initial words (e.g. "we", "wi", "wh", "wo", "wy", "wri", "wat", "wan")
        // resolve immediately to raw ASCII on the 2nd/3rd keystroke while preserving "ww" -> "w", "wa" -> "ưa", "wu" -> "ưu", "ws"/"wr" -> "ứ"/"ử".
        if VietnameseEngine.isEnglishWInitial(chars) || SmartBilingualDetector.isPostCodaCircumflexEnglishWord(lowerRaw) {
            return (SyllableIntent(rawChars: chars), String(chars))
        }

        // For Pre-vowel, Smart Hybrid, and SEN VIỆT Flex:
        let parsed = parsePreVowelOrHybrid(
            chars,
            profile: profile,
            modernOrthography: modernOrthography,
            relaxedCoda: relaxedCoda,
            genZMode: genZMode,
            simpleTelex: simpleTelex
        )

        if genZMode, let first = lowerRaw.first, (first == "f" || first == "j" || first == "z" || lowerRaw.hasPrefix("dz")),
           parsed.rendered.lowercased() != lowerRaw,
           !VietnameseEngine.isValidGenZInitialTransformation(rendered: parsed.rendered, raw: lowerRaw) {
            return (SyllableIntent(rawChars: chars), String(chars))
        }

        if profile != .classic {
            let candidate = SyllableCandidateResolver.shared.arbitrate(
                rawChars: chars,
                vnParsed: parsed,
                profile: profile
            )
            return (candidate.intent, candidate.rendered)
        }

        return parsed
    }

    internal func parsePreVowelOrHybrid(
        _ chars: [Character],
        profile: GrammarProfile,
        modernOrthography: Bool,
        relaxedCoda: Bool,
        genZMode: Bool = false,
        simpleTelex: Bool = true
    ) -> (intent: SyllableIntent, rendered: String) {
        if VietnameseEngine.isPostCodaEnglishDoubleVowelEscape(chars) {
            return (SyllableIntent(rawChars: chars), String(chars.dropLast()))
        }
        if SmartBilingualDetector.isPostCodaCircumflexEnglishWord(String(chars).lowercased()) {
            return (SyllableIntent(rawChars: chars), String(chars))
        }

        // Support transposed initial d-V-d / d-V-V-d (e.g. dodongf -> đồng, dadauf -> đầu, dedens -> đến, dudowcj / duodcwj -> được)
        if chars.count >= 4,
           Character(chars[0].lowercased()) == "d",
           VietnameseEngine.isVietnameseVowel(Character(chars[1].lowercased())),
           !SmartBilingualDetector.isKnownEnglishWord(String(chars).lowercased()) {
            var foundInfixDIdx: Int? = nil
            for k in 2..<min(5, chars.count - 1) {
                let cLower = Character(chars[k].lowercased())
                if cLower == "d" {
                    if Character(chars[k + 1].lowercased()) != "d" {
                        foundInfixDIdx = k
                    }
                    break
                } else if !VietnameseEngine.isVietnameseVowel(cLower) && cLower != "w" {
                    break
                }
            }
            if let dIdx = foundInfixDIdx {
                var reordered = chars
                let secondD = reordered.remove(at: dIdx)
                reordered.insert(secondD, at: 1)
                let candidate = parsePreVowelOrHybrid(
                    reordered,
                    profile: profile,
                    modernOrthography: modernOrthography,
                    relaxedCoda: relaxedCoda,
                    genZMode: genZMode,
                    simpleTelex: simpleTelex
                )
                if VietnameseSyllableDictionary.shared.isValidSyllable(candidate.rendered) ||
                   VietnameseSyllableDictionary.shared.isPlausibleInProgressVietnamese(candidate.rendered) ||
                   SyllableCandidateResolver.isPostCodaModifierUndoOrExtension(lowerRaw: String(reordered).lowercased(), rendered: candidate.rendered) {
                    var updatedIntent = candidate.intent
                    updatedIntent.rawChars = chars
                    return (updatedIntent, candidate.rendered)
                }
            }
        }

        let rawStr = String(chars)
        let lowerRaw = rawStr.lowercased()
        let lowerChars = Array(lowerRaw)
        let n = lowerChars.count

        var intent = SyllableIntent(rawChars: chars)
        var tone: VietnameseTone = .none
        var hasHorn = false
        var onset = ""
        var idx = 0

        // Special check: "www" at word start is web prefix, not horn/vowel
        if idx == 0 && n >= 3 && lowerChars[0] == "w" && lowerChars[1] == "w" && lowerChars[2] == "w" {
            let remainder = String(lowerChars[3...])
            return (SyllableIntent(rawChars: chars), applyCasing(original: chars, transformed: Array("www" + remainder)))
        }

        // Special check: "ww" at word start cancels "ư" -> literal "w"; any subsequent characters are literal ASCII
        if idx == 0 && n >= 2 && lowerChars[0] == "w" && lowerChars[1] == "w" {
            let transformedChars: [Character] = [chars[0]] + Array(chars.dropFirst(2))
            return (SyllableIntent(rawChars: chars), String(transformedChars))
        }

        // 1. Parse Onset with Maximal Munch and special Pre-vowel Onset rules
        // Check "ddd" -> "dd" (triple-d escape) and "dd" -> "đ"
        if idx + 2 < n && lowerChars[idx] == "d" && lowerChars[idx + 1] == "d" && lowerChars[idx + 2] == "d" {
            onset = "dd"
            idx += 3
        } else if idx + 1 < n && lowerChars[idx] == "d" && lowerChars[idx + 1] == "d" {
            onset = "đ"
            idx += 2
        }
        // Check "qu" vs "q" + tone + "u"
        else if lowerChars[idx] == "q" {
            if idx + 1 < n && lowerChars[idx + 1] == "u" {
                onset = "qu"
                idx += 2
            } else if idx + 2 < n && isToneKey(lowerChars[idx + 1]) && lowerChars[idx + 2] == "u" {
                // e.g. "qfua" -> onset is "qu", tone is "f", consumed q, f, u
                onset = "qu"
                tone = mapToneKey(lowerChars[idx + 1])
                intent.hasPreVowelTone = true
                idx += 3
            } else {
                onset = "q"
                idx += 1
            }
        }
        // Check initial "w" before vowel/consonant
        else if lowerChars[idx] == "w" {
            if idx + 1 < n && lowerChars[idx + 1] == "w" {
                // "ww" at start -> literal "w"
                onset = "w"
                idx += 2
            } else {
                // Initial single "w" -> "ư" (English w-initials like wo/wh/we/wi/wri are already filtered by isEnglishWInitial)
                onset = ""
                // Let 'w' be handled in vowel parsing below as 'ư'
            }
        }
        // Check multi-character standard Vietnamese onsets (Length 3, then Length 2, then Length 1)
        else {
            let prefixes3 = ["ngh"]
            let prefixes2 = genZMode
                ? ["ch", "dz", "gh", "gi", "kh", "nh", "ng", "ph", "th", "tr"]
                : ["ch", "gh", "gi", "kh", "nh", "ng", "ph", "th", "tr"]
            let prefixes1 = ["b", "c", "d", "f", "g", "h", "j", "k", "l", "m", "n", "p", "r", "s", "t", "v", "x", "z"]

            var matchedOnset = ""
            if idx + 3 <= n && prefixes3.contains(String(lowerChars[idx..<idx+3])) {
                matchedOnset = String(lowerChars[idx..<idx+3])
                idx += 3
            } else if idx + 2 <= n && prefixes2.contains(String(lowerChars[idx..<idx+2])) {
                let candidate = String(lowerChars[idx..<idx+2])
                if candidate == "gi" {
                    let tailVowels = lowerChars[(idx+2)...].filter { isVowelChar($0) }
                    if tailVowels.isEmpty || tailVowels.allSatisfy({ $0 == "i" }) {
                        matchedOnset = "g"
                        idx += 1
                    } else {
                        matchedOnset = candidate
                        idx += 2
                    }
                } else {
                    matchedOnset = candidate
                    idx += 2
                }
            } else if idx + 1 <= n && prefixes1.contains(String(lowerChars[idx..<idx+1])) {
                matchedOnset = String(lowerChars[idx..<idx+1])
                idx += 1
            }
            onset = matchedOnset
        }
        intent.onset = onset

        // 2. Parse Pre-Vowel Modifiers between Onset and Nucleus (e.g. "w", "s", "f", "r", "x", "j")
        // Pre-vowel modifiers can only appear AFTER a valid Vietnamese onset (or f/j/z/w in genZMode).
        let afterOnsetIdx = idx
        let remainingChars = lowerChars[idx...]
        let remainingHasVowel = remainingChars.contains { isVowelChar($0) }
        let isAllowedPreVowelOnset = !onset.isEmpty && onset != "dd" && onset != "q" && (genZMode || (onset != "f" && onset != "j" && onset != "z" && onset != "w"))
        if remainingHasVowel && isAllowedPreVowelOnset {
            while idx < n {
                let ch = lowerChars[idx]
                if ch == "w" {
                    if idx + 1 < n && lowerChars[idx + 1] == "w" {
                        // "ww" cancellation
                        idx += 2
                        break
                    }
                    let restAfterW = lowerChars[(idx + 1)...]
                    let hasHornCapableVowelAhead = restAfterW.contains { $0 == "a" || $0 == "o" || $0 == "u" }
                    let isEnglishClusterPrefix = (onset == "t" || onset == "s" || onset == "d") &&
                        (idx + 1 < n && (lowerChars[idx + 1] == "a" || lowerChars[idx + 1] == "o"))
                    if hasHornCapableVowelAhead && !isEnglishClusterPrefix {
                        hasHorn = true
                        intent.hasHornModifier = true
                        idx += 1
                    } else {
                        break
                    }
                } else if isToneKey(ch) && ch != "z" && tone == .none {
                    if onset == "f" && ch == "r" && lowerRaw != "fra" && lowerRaw != "frai" {
                        break
                    }
                    // Only recognize pre-vowel tone if followed by a vowel or 'w' (excluding <consonant != 's'> + 's' + 'w' like 'cswap', 'bswap', 'tswap')
                    let isEnglishSubwordSwapCluster = (idx + 1 < n && lowerChars[idx + 1] == "w" && ch == "s" && onset.count == 1 && onset != "s")
                    if idx + 1 < n && !isEnglishSubwordSwapCluster && (isVowelChar(lowerChars[idx + 1]) || lowerChars[idx + 1] == "w") {
                        tone = mapToneKey(ch)
                        intent.hasPreVowelTone = true
                        idx += 1
                    } else {
                        break
                    }
                } else {
                    break
                }
            }
        }
        let preVowelEndIdx = idx

        // 3. Parse Nucleus and Coda with Infix & Postfix modifier support
        var nucleusAndCodaChars: [Character] = []
        var trailingToneFound: VietnameseTone = .none
        var toneEscapeActive = (onset == "dd")
        var toneEscapeLocked = (onset == "dd")
        var cancelledToneKey: Character? = nil
        var hornCancelled = false
        var circumflexCancelledKey: Character? = nil
        var circumflexCancelled = false
        var strokeDCancelled = (onset == "dd")
        var postStrokeTail: [Character] = []

        while idx < n {
            let ch = lowerChars[idx]
            let isAdjacentDoubleVowelAfterToneEscape = toneEscapeActive &&
                (ch == "a" || ch == "e" || ch == "o") &&
                ((idx + 1 < n && lowerChars[idx + 1] == ch) ||
                 (nucleusAndCodaChars.last == ch))
            let hasValidVnCodaStemBeforeToneEscape: Bool = {
                guard toneEscapeActive, (onset.count + nucleusAndCodaChars.count) >= 3 else { return false }
                let stemBeforeEscape = onset + String(nucleusAndCodaChars.dropLast())
                guard let lastStemChar = stemBeforeEscape.last,
                      ["c", "m", "n", "p", "t", "g", "h"].contains(lastStemChar) else {
                    return false
                }
                return VietnameseSyllableDictionary.shared.isValidUntonedSyllable(stemBeforeEscape, genZMode: genZMode)
            }()
            if !ch.isLetter {
                toneEscapeActive = false
                toneEscapeLocked = false
                cancelledToneKey = nil
            } else if isVowelChar(ch) && !toneEscapeLocked && !(onset == "đ" || hasHorn || hornCancelled || circumflexCancelled || circumflexCancelledKey != nil || strokeDCancelled || nucleusAndCodaChars.contains(where: { "ăâêôơư".contains($0) }) || isAdjacentDoubleVowelAfterToneEscape || hasValidVnCodaStemBeforeToneEscape) {
                toneEscapeActive = false
                cancelledToneKey = nil
            }
            if circumflexCancelledKey != nil && ch != circumflexCancelledKey {
                circumflexCancelledKey = nil
            }

            // Post-coda / non-adjacent circumflex modifier (e.g. nhana -> nhân, nhanas -> nhấn, nhansa -> nhấn, theme -> thêm, trongo -> trông)
            if (ch == "a" || ch == "e" || ch == "o") && !nucleusAndCodaChars.isEmpty {
                if circumflexCancelledKey == ch {
                    let activeTone = trailingToneFound != .none ? trailingToneFound : tone
                    if let lockedStem = VietnameseEngine.shouldLockPostCodaOverflow(
                        stemChars: Array(onset) + nucleusAndCodaChars,
                        tone: activeTone,
                        hasHorn: hasHorn,
                        hornCancelled: hornCancelled,
                        circumflexCancelled: circumflexCancelled,
                        circumflexCancelledKey: circumflexCancelledKey,
                        strokeDCancelled: strokeDCancelled,
                        nextChar: ch,
                        remainingChars: lowerChars[idx...],
                        fullRawChars: chars,
                        modernOrthography: modernOrthography
                    ) {
                        nucleusAndCodaChars = Array(lockedStem.dropFirst(onset.count))
                        nucleusAndCodaChars.append(contentsOf: lowerChars[idx...])
                        intent.tone = activeTone
                        tone = .none
                        trailingToneFound = .none
                        hasHorn = false
                        hornCancelled = true
                        break
                    }
                    nucleusAndCodaChars.append(ch)
                    idx += 1
                    continue
                }
                let hasAnyToneKeyInChars = tone != .none || lowerChars.contains {
                    $0 == "s" || $0 == "f" || $0 == "r" || $0 == "x" || $0 == "j"
                }
                let hasCircumflexInNucleus = nucleusAndCodaChars.contains {
                    $0 == "â" || $0 == "ê" || $0 == "ô"
                }
                let allowOverflowModifiersAfterCancel =
                    (hasAnyToneKeyInChars || onset == "đ" || hasCircumflexInNucleus) &&
                    !SmartBilingualDetector.isKnownEnglishWord(lowerRaw)
                let remainingAllowCancel: Bool = {
                    for remIdx in (idx + 1)..<n {
                        let c = lowerChars[remIdx]
                        if c == ch {
                            // A subsequent identical vowel modifier saturates and locks the stem into literal overflow
                            return true
                        }
                        let isOverflowModifier = allowOverflowModifiersAfterCancel && ["a", "e", "o", "w"].contains(c)
                        let allowed = isOverflowModifier || (ch == "o" && c == "w") || c == "s" || c == "f" || c == "r" || c == "x" || c == "j" || (c == "z" && (hasAnyToneKeyInChars || hasCircumflexInNucleus))
                        if !allowed {
                            return false
                        }
                    }
                    return true
                }()
                let circumflexChar: Character = (ch == "a") ? "â" : ((ch == "e") ? "ê" : "ô")
                var postCodaHandled = false
                if !toneEscapeActive && postStrokeTail.isEmpty && nucleusAndCodaChars.count >= 2,
                   let lastResChar = nucleusAndCodaChars.last,
                   ["c", "m", "n", "p", "t", "g", "h"].contains(lastResChar) {
                    for vIdx in stride(from: nucleusAndCodaChars.count - 2, through: 0, by: -1) {
                        let vLower = nucleusAndCodaChars[vIdx]
                        if vLower == circumflexChar {
                            // Policy 3B+: Semantic Saturation — once the vowel already carries a circumflex
                            // before a coda, a duplicate modifier falls through as literal instead of stripping.
                            break
                        } else if ch == "o" && (vLower == "ơ" || vLower == "o") && vIdx >= 1 && nucleusAndCodaChars[vIdx - 1] == "ư" {
                            // Mutual-exclusion vowel reshape: ươ + o -> uô (e.g. trường + o -> truồng, thưởng + o -> thuổng, nước + o -> nuốc)
                            nucleusAndCodaChars[vIdx - 1] = "u"
                            nucleusAndCodaChars[vIdx] = "ô"
                            hasHorn = false
                            intent.hasHornModifier = false
                            hornCancelled = false
                            circumflexCancelled = false
                            circumflexCancelledKey = nil
                            idx += 1
                            postCodaHandled = true
                            break
                        } else if ch == "o" && vLower == "o" && vIdx >= 1 && nucleusAndCodaChars[vIdx - 1] == "u" && hasHorn {
                            // e.g. thrwuong + o -> thuổng, trwuongf + o -> truồng
                            hasHorn = false
                            intent.hasHornModifier = false
                            hornCancelled = false
                            circumflexCancelled = false
                            circumflexCancelledKey = nil
                            nucleusAndCodaChars[vIdx] = "ô"
                            idx += 1
                            postCodaHandled = true
                            break
                        } else if ch == "o" && vLower == "ơ" && remainingAllowCancel {
                            var candidateNucleusAndCoda = nucleusAndCodaChars
                            candidateNucleusAndCoda[vIdx] = "ô"
                            let candidateUntoned = onset + String(candidateNucleusAndCoda)
                            if VietnameseSyllableDictionary.shared.isValidUntonedSyllable(candidateUntoned, genZMode: genZMode) {
                                nucleusAndCodaChars[vIdx] = "ô"
                                hasHorn = false
                                intent.hasHornModifier = false
                                hornCancelled = false
                                circumflexCancelled = false
                                circumflexCancelledKey = nil
                                idx += 1
                                postCodaHandled = true
                                break
                            }
                        } else if ch == "a" && vLower == "ă" && remainingAllowCancel {
                            var candidateNucleusAndCoda = nucleusAndCodaChars
                            candidateNucleusAndCoda[vIdx] = "â"
                            let candidateUntoned = onset + String(candidateNucleusAndCoda)
                            if VietnameseSyllableDictionary.shared.isValidUntonedSyllable(candidateUntoned, genZMode: genZMode) {
                                nucleusAndCodaChars[vIdx] = "â"
                                hasHorn = false
                                intent.hasHornModifier = false
                                hornCancelled = false
                                circumflexCancelled = false
                                circumflexCancelledKey = nil
                                idx += 1
                                postCodaHandled = true
                                break
                            }
                        } else if vLower == ch {
                            var candidateNucleusAndCoda = nucleusAndCodaChars
                            candidateNucleusAndCoda[vIdx] = circumflexChar
                            let candidateUntoned = onset + String(candidateNucleusAndCoda)
                            if (VietnameseSyllableDictionary.shared.isValidUntonedSyllable(candidateUntoned, genZMode: genZMode) ||
                                VietnameseSyllableDictionary.shared.isValidRelaxedCodaVietnamese(candidateUntoned, raw: lowerRaw, genZMode: genZMode) ||
                                (!lowerRaw.hasPrefix("w") && VietnameseSyllableDictionary.shared.isValidUntonedRhyme(candidateUntoned))) {
                                let allowPostCodaEnglish = !SmartBilingualDetector.isPostCodaCircumflexEnglishWord(lowerRaw) &&
                                    (lowerRaw == "cana" || !SmartBilingualDetector.isKnownEnglishWord(lowerRaw))
                                if allowPostCodaEnglish && remainingAllowCancel {
                                    nucleusAndCodaChars[vIdx] = circumflexChar
                                    idx += 1
                                    postCodaHandled = true
                                    break
                                }
                            }
                        }
                    }
                } else if !toneEscapeActive && postStrokeTail.isEmpty && nucleusAndCodaChars.count >= 1 {
                    let lastIdx = nucleusAndCodaChars.count - 1
                    let lastRes = nucleusAndCodaChars[lastIdx]
                    let isCompoundUO = nucleusAndCodaChars.count >= 2 && (nucleusAndCodaChars[nucleusAndCodaChars.count - 2] == "ư" || (nucleusAndCodaChars[nucleusAndCodaChars.count - 2] == "u" && hasHorn))
                    if lastRes == circumflexChar {
                        // Policy 3B+: Non-contiguous post-tone duplicate vowel on an open circumflex syllable
                        // is saturated (contiguous aaa/eee/ooo is handled by the triple-vowel block below).
                    } else if remainingAllowCancel && ch == "o" && (lastRes == "ơ" || (lastRes == "o" && hasHorn)) && !isCompoundUO {
                        var candidateNucleus = nucleusAndCodaChars
                        candidateNucleus[lastIdx] = "ô"
                        let candidateUntoned = onset + String(candidateNucleus)
                        if VietnameseSyllableDictionary.shared.isValidUntonedSyllable(candidateUntoned, genZMode: genZMode) {
                            nucleusAndCodaChars[lastIdx] = "ô"
                            hasHorn = false
                            intent.hasHornModifier = false
                            hornCancelled = false
                            circumflexCancelled = false
                            circumflexCancelledKey = nil
                            idx += 1
                            postCodaHandled = true
                        }
                    } else if remainingAllowCancel && ch == "a" && (lastRes == "ă" || (lastRes == "a" && hasHorn && !isCompoundUO)) {
                        var candidateNucleus = nucleusAndCodaChars
                        candidateNucleus[lastIdx] = "â"
                        let candidateUntoned = onset + String(candidateNucleus)
                        if VietnameseSyllableDictionary.shared.isValidUntonedSyllable(candidateUntoned, genZMode: genZMode) ||
                           VietnameseSyllableDictionary.shared.isValidOpenCircumflexPrefix(candidateUntoned, genZMode: genZMode) {
                            nucleusAndCodaChars[lastIdx] = "â"
                            hasHorn = false
                            intent.hasHornModifier = false
                            hornCancelled = false
                            circumflexCancelled = false
                            circumflexCancelledKey = nil
                            idx += 1
                            postCodaHandled = true
                        }
                    } else if nucleusAndCodaChars.count >= 2 {
                        let midIdx = nucleusAndCodaChars.count - 2
                        let midRes = nucleusAndCodaChars[midIdx]
                        let isGenZInitial = genZMode && ["f", "j", "z", "w"].contains(onset)
                        if midRes == circumflexChar &&
                           ((ch == "a" && (lastRes == "u" || lastRes == "y")) ||
                            (ch == "e" && lastRes == "u") ||
                            (ch == "o" && lastRes == "i")) {
                            // Policy 3B+: Offglide-closed circumflex syllable (đầu, thấy, nếu, nhiều, tuổi, tối)
                            // is saturated; duplicate modifier falls through as literal.
                        } else if remainingAllowCancel && midRes == ch &&
                                  ((isGenZInitial &&
                                    ((ch == "a" && (lastRes == "u" || lastRes == "y")) ||
                                     (ch == "e" && lastRes == "u") ||
                                     (ch == "o" && lastRes == "i"))) ||
                                   (ch == "o" && lastRes == "i" && midIdx >= 1 && nucleusAndCodaChars[midIdx - 1] == "u" &&
                                    !SmartBilingualDetector.isKnownEnglishWord(lowerRaw))) {
                            var candidateNucleus = nucleusAndCodaChars
                            candidateNucleus[midIdx] = circumflexChar
                            let candidateUntoned = onset + String(candidateNucleus)
                            if VietnameseSyllableDictionary.shared.isValidUntonedSyllable(candidateUntoned, genZMode: genZMode || isGenZInitial) ||
                               (!lowerRaw.hasPrefix("w") && VietnameseSyllableDictionary.shared.isValidUntonedRhyme(candidateUntoned)) {
                                nucleusAndCodaChars[midIdx] = circumflexChar
                                idx += 1
                                postCodaHandled = true
                            }
                        } else if remainingAllowCancel && ch == "o" && nucleusAndCodaChars.count >= 3 {
                            let prevRes = nucleusAndCodaChars[nucleusAndCodaChars.count - 3]
                            if (lastRes == "i" || lastRes == "u") && (midRes == "ơ" || midRes == "o") && prevRes == "ư" {
                                nucleusAndCodaChars[nucleusAndCodaChars.count - 3] = "u"
                                nucleusAndCodaChars[midIdx] = "ô"
                                hasHorn = false
                                intent.hasHornModifier = false
                                hornCancelled = false
                                circumflexCancelled = false
                                circumflexCancelledKey = nil
                                idx += 1
                                postCodaHandled = true
                            } else if (lastRes == "i" || lastRes == "u") && midRes == "o" && prevRes == "u" && hasHorn {
                                hasHorn = false
                                intent.hasHornModifier = false
                                hornCancelled = false
                                circumflexCancelled = false
                                circumflexCancelledKey = nil
                                nucleusAndCodaChars[midIdx] = "ô"
                                idx += 1
                                postCodaHandled = true
                            }
                        } else if remainingAllowCancel && ch == "o" && ((lastRes == "ơ" && midRes == "ư") || (lastRes == "o" && midRes == "u" && hasHorn)) {
                            nucleusAndCodaChars[midIdx] = "u"
                            nucleusAndCodaChars[lastIdx] = "ô"
                            hasHorn = false
                            intent.hasHornModifier = false
                            hornCancelled = false
                            circumflexCancelled = false
                            circumflexCancelledKey = nil
                            idx += 1
                            postCodaHandled = true
                        }
                    }
                }
                let isCasedEnglishECollision = chars.contains(where: { $0.isUppercase }) &&
                    ["here", "there", "these", "refer", "refers", "reset", "mere", "verse"].contains(lowerRaw)
                let currentTone = trailingToneFound != .none ? trailingToneFound : tone
                if !postCodaHandled && currentTone != .none && !toneEscapeActive &&
                   nucleusAndCodaChars.last == ch && !isCasedEnglishECollision && lowerRaw != "there" {
                    let remSlice = Array(lowerChars[(idx + 1)...])
                    let isGenZInitial = genZMode && ["f", "j", "z", "w"].contains(onset)
                    let toneKeyChars: Set<Character> = ["s", "f", "r", "x", "j", "z"]
                    let modifierKeyChars: Set<Character> = ["a", "e", "o", "w"]
                    let stopKeyChars = toneKeyChars.union(modifierKeyChars)
                    let codaSlice = remSlice.prefix(while: { !stopKeyChars.contains($0) })
                    let afterCodaSlice = remSlice.dropFirst(codaSlice.count)
                    let coda = String(codaSlice)
                    let canOverflowAfterCoda = !coda.isEmpty && !SmartBilingualDetector.isKnownEnglishWord(lowerRaw)
                    let afterCodaAllToneKeys = !afterCodaSlice.isEmpty
                        ? (afterCodaSlice.allSatisfy({
                            toneKeyChars.contains($0) || $0 == ch || $0 == "w" || (canOverflowAfterCoda && modifierKeyChars.contains($0))
                        }) &&
                           !(afterCodaSlice.first != ch && afterCodaSlice.contains(ch) && afterCodaSlice.contains(where: { toneKeyChars.contains($0) })))
                        : true
                    let validLateCodas: Set<String> = (ch == "e")
                        ? ["", "c", "ch", "m", "n", "nh", "p", "t", "u"]
                        : ["", "c", "ch", "m", "n", "ng", "nh", "p", "t", "u", "y", "i", "o"]
                    let isStopCoda = ["c", "ch", "p", "t"].contains(coda)
                    let effectiveLastToneChar: Character? = afterCodaSlice.last(where: { toneKeyChars.contains($0) }) ?? {
                        switch currentTone {
                        case .acute: return "s"
                        case .grave: return "f"
                        case .hook: return "r"
                        case .tilde: return "x"
                        case .dot: return "j"
                        case .none: return nil
                        }
                    }()
                    let stopCodaToneValid = !isStopCoda || effectiveLastToneChar == "s" || effectiveLastToneChar == "j" || effectiveLastToneChar == "z"
                    if (afterCodaAllToneKeys && validLateCodas.contains(coda) && stopCodaToneValid) || isGenZInitial {
                        var candidateNucleus = nucleusAndCodaChars
                        candidateNucleus[candidateNucleus.count - 1] = circumflexChar
                        let nonToneTail = isGenZInitial
                            ? String(remSlice.filter({ !toneKeyChars.contains($0) }))
                            : coda
                        let checkUntoned = onset + String(candidateNucleus) + nonToneTail
                        let isValidLateCircumflex =
                            VietnameseSyllableDictionary.shared.isValidUntonedSyllable(checkUntoned, genZMode: genZMode || isGenZInitial) ||
                            (!lowerRaw.hasPrefix("w") && !SmartBilingualDetector.isKnownEnglishWord(lowerRaw) && VietnameseSyllableDictionary.shared.isValidUntonedRhyme(checkUntoned)) ||
                            (ch == "a" && nonToneTail.isEmpty && VietnameseSyllableDictionary.shared.isValidOpenCircumflexPrefix(checkUntoned, genZMode: genZMode || isGenZInitial))
                        if isValidLateCircumflex {
                            nucleusAndCodaChars[nucleusAndCodaChars.count - 1] = circumflexChar
                            idx += 1
                            postCodaHandled = true
                        }
                    }
                }
                if postCodaHandled {
                    continue
                }
                let activeToneForVowelOverflow = trailingToneFound != .none ? trailingToneFound : tone
                if let lockedStem = VietnameseEngine.shouldLockPostCodaOverflow(
                    stemChars: Array(onset) + nucleusAndCodaChars,
                    tone: activeToneForVowelOverflow,
                    hasHorn: hasHorn,
                    hornCancelled: hornCancelled,
                    circumflexCancelled: circumflexCancelled,
                    circumflexCancelledKey: circumflexCancelledKey,
                    strokeDCancelled: strokeDCancelled,
                    nextChar: ch,
                    remainingChars: lowerChars[idx...],
                    fullRawChars: chars,
                    modernOrthography: modernOrthography
                ) {
                    nucleusAndCodaChars = Array(lockedStem.dropFirst(onset.count))
                    nucleusAndCodaChars.append(contentsOf: lowerChars[idx...])
                    intent.tone = activeToneForVowelOverflow
                    tone = .none
                    trailingToneFound = .none
                    hasHorn = false
                    hornCancelled = true
                    break
                }
            }

            // Triple vowels: aaa -> aa, eee -> ee, ooo -> oo
            // Vietnamese orthography never contains double ASCII vowels (aa, ee, oo).
            // Once escaped via triple vowel, clear any pending tone and consume remaining characters literally.
            // Guard: if ư/ơ is already present in nucleus, 'a'/'e' is a diphthong offglide (e.g. uwfaaa -> ừaaa), not circumflex â/ê.
            let hornBlocksTripleCircumflex = (ch == "a" || ch == "e") && nucleusAndCodaChars.contains(where: {
                $0 == "ư" || $0 == "ơ" || (hasHorn && ($0 == "u" || $0 == "o"))
            })
            if !toneEscapeActive && !hornBlocksTripleCircumflex && (ch == "a" || ch == "e" || ch == "o") && idx + 2 < n && lowerChars[idx + 1] == ch && lowerChars[idx + 2] == ch {
                if preVowelEndIdx > afterOnsetIdx {
                    nucleusAndCodaChars.insert(contentsOf: lowerChars[afterOnsetIdx..<preVowelEndIdx], at: 0)
                }
                nucleusAndCodaChars.append(ch)
                nucleusAndCodaChars.append(ch)
                tone = .none
                trailingToneFound = .none
                hasHorn = false
                hornCancelled = true
                intent.hasPreVowelTone = false
                intent.hasHornModifier = false
                idx += 3
                while idx < n {
                    let remCh = lowerChars[idx]
                    if (remCh == "a" || remCh == "e" || remCh == "o") && idx + 2 < n && lowerChars[idx + 1] == remCh && lowerChars[idx + 2] == remCh {
                        nucleusAndCodaChars.append(remCh)
                        nucleusAndCodaChars.append(remCh)
                        idx += 3
                    } else {
                        nucleusAndCodaChars.append(remCh)
                        idx += 1
                    }
                }
                break
            }

            // Double vowels: aa -> â, ee -> ê, oo -> ô (never form an illegal second circumflex after â/ê/ô/ă, or â/ê after ư/ơ)
            if !toneEscapeActive && (ch == "a" || ch == "e" || ch == "o") && idx + 1 < n && lowerChars[idx + 1] == ch {
                let hasPriorCircumflexOrBreve = nucleusAndCodaChars.contains(where: {
                    $0 == "â" || $0 == "ê" || $0 == "ô" || $0 == "ă" || ((ch == "a" || ch == "e") && ($0 == "ư" || $0 == "ơ" || (hasHorn && ($0 == "u" || $0 == "o"))))
                })
                if !hasPriorCircumflexOrBreve {
                    switch ch {
                    case "a": nucleusAndCodaChars.append("â")
                    case "e": nucleusAndCodaChars.append("ê")
                    case "o": nucleusAndCodaChars.append("ô")
                    default: nucleusAndCodaChars.append(ch)
                    }
                    idx += 2
                    continue
                }
            }

            // Modifiers: aw -> ă, ow -> ơ, uw -> ư, uaw -> ưa, uow -> ươ
            if ch == "w" {
                if hornCancelled {
                    let activeTone = trailingToneFound != .none ? trailingToneFound : tone
                    if let lockedStem = VietnameseEngine.shouldLockPostCodaOverflow(
                        stemChars: Array(onset) + nucleusAndCodaChars,
                        tone: activeTone,
                        hasHorn: hasHorn,
                        hornCancelled: hornCancelled,
                        circumflexCancelled: circumflexCancelled,
                        circumflexCancelledKey: circumflexCancelledKey,
                        strokeDCancelled: strokeDCancelled,
                        nextChar: ch,
                        remainingChars: lowerChars[idx...],
                        fullRawChars: chars,
                        modernOrthography: modernOrthography
                    ) {
                        nucleusAndCodaChars = Array(lockedStem.dropFirst(onset.count))
                        nucleusAndCodaChars.append(contentsOf: lowerChars[idx...])
                        intent.tone = activeTone
                        tone = .none
                        trailingToneFound = .none
                        hasHorn = false
                        hornCancelled = true
                        break
                    }
                    nucleusAndCodaChars.append("w")
                    idx += 1
                    continue
                }
                // If pre-vowel horn was already active (e.g. trwuongrw), under Policy 3B+ the vowel is already
                // saturated by the pre-vowel horn; do not strip `hasHorn`, let it fall through to overflow lock / literal append.
                let hasCircumflexReshapable = nucleusAndCodaChars.contains(where: { $0 == "ô" || $0 == "â" })
                let hasAlreadyHornedVowel = hasHorn || nucleusAndCodaChars.contains(where: { $0 == "ă" || $0 == "ơ" || $0 == "ư" })
                let endsWithHornableVowel: Bool = {
                    guard let lastV = nucleusAndCodaChars.last else { return false }
                    return lastV == "a" || lastV == "o" || lastV == "u"
                }()
                if !toneEscapeActive && tone == .none && trailingToneFound == .none && endsWithHornableVowel && !hasCircumflexReshapable && !hasAlreadyHornedVowel && idx + 1 < n && lowerChars[idx + 1] == "w" {
                    nucleusAndCodaChars.append("w")
                    hornCancelled = true
                    toneEscapeActive = true
                    toneEscapeLocked = true
                    idx += 2
                    continue
                }

                let canModifyExistingVowel: Bool = {
                    guard !hasHorn && !toneEscapeActive && postStrokeTail.isEmpty, let lastResChar = nucleusAndCodaChars.last else {
                        return false
                    }
                    return VietnameseEngine.isVietnameseVowel(lastResChar) ||
                        ["c", "m", "n", "p", "t", "g", "h"].contains(lastResChar)
                }()
                var modified = false
                if canModifyExistingVowel {
                    let hasCodaBeforeW = nucleusAndCodaChars.last.map { ["c", "m", "n", "p", "t", "g", "h"].contains($0) } ?? false
                    let isValidAfterCodaW: ([Character]) -> Bool = { candidateNucleus in
                        guard hasCodaBeforeW else { return true }
                        let candidateStr = onset + String(candidateNucleus)
                        return VietnameseSyllableDictionary.shared.isValidUntonedSyllable(candidateStr, genZMode: genZMode) ||
                            VietnameseSyllableDictionary.shared.hasUntonedPrefix(candidateStr, preserveVowelShape: true, relaxedCoda: true, genZMode: genZMode) ||
                            (!SmartBilingualDetector.isKnownEnglishWord(lowerRaw) &&
                             (VietnameseSyllableDictionary.shared.isValidRelaxedCodaVietnamese(candidateStr, raw: lowerRaw, genZMode: genZMode) ||
                              (!lowerRaw.hasPrefix("w") && VietnameseSyllableDictionary.shared.isValidUntonedRhyme(candidateStr))))
                    }
                    for vIdx in stride(from: nucleusAndCodaChars.count - 1, through: 0, by: -1) {
                    let vLower = nucleusAndCodaChars[vIdx]
                    if vLower == "ă" || vLower == "ư" || vLower == "ơ" {
                        // Policy 3B+: Semantic Saturation — once the vowel already has breve/horn,
                        // a non-contiguous trailing 'w' does NOT strip the diacritic; it falls through as literal.
                        break
                    } else if vLower == "ô" {
                        var candidateNucleus = nucleusAndCodaChars
                        if vIdx >= 1 && (candidateNucleus[vIdx - 1] == "u" || candidateNucleus[vIdx - 1] == "ư") && onset != "qu" {
                            candidateNucleus[vIdx - 1] = "ư"
                        }
                        candidateNucleus[vIdx] = "ơ"
                        if isValidAfterCodaW(candidateNucleus) {
                            nucleusAndCodaChars = candidateNucleus
                            circumflexCancelled = false
                            circumflexCancelledKey = nil
                            modified = true
                        }
                        break
                    } else if vLower == "â" {
                        var candidateNucleus = nucleusAndCodaChars
                        candidateNucleus[vIdx] = "ă"
                        if isValidAfterCodaW(candidateNucleus) {
                            nucleusAndCodaChars = candidateNucleus
                            circumflexCancelled = false
                            circumflexCancelledKey = nil
                            modified = true
                        }
                        break
                    } else if vLower == "a" {
                        let isStandaloneLabializedBreveWithCoda =
                            onset.isEmpty &&
                            vIdx == 1 &&
                            (hasCodaBeforeW ||
                             (idx + 1 < n && ["c", "m", "n", "p", "t"].contains(lowerChars[idx + 1]))) &&
                            !SmartBilingualDetector.isKnownEnglishWord(lowerRaw)
                        if vIdx >= 1 && nucleusAndCodaChars[vIdx - 1] == "u" && !isStandaloneLabializedBreveWithCoda {
                            var candidateNucleus = nucleusAndCodaChars
                            candidateNucleus[vIdx - 1] = "ư"
                            if isValidAfterCodaW(candidateNucleus) {
                                nucleusAndCodaChars = candidateNucleus
                                modified = true
                            }
                            break
                        }
                        if vIdx >= 1 && nucleusAndCodaChars[vIdx - 1] == "ư" {
                            // Policy 3B+: 'ưa' (e.g. cưa, cửa, mưa) is already horned (saturated).
                            break
                        }
                        var candidateNucleus = nucleusAndCodaChars
                        candidateNucleus[vIdx] = "ă"
                        if isValidAfterCodaW(candidateNucleus) {
                            nucleusAndCodaChars = candidateNucleus
                            modified = true
                        }
                        break
                    } else if vLower == "o" {
                        if vIdx >= 1 && nucleusAndCodaChars[vIdx - 1] == "u" {
                            var candidateNucleus = nucleusAndCodaChars
                            candidateNucleus[vIdx - 1] = "ư"
                            candidateNucleus[vIdx] = "ơ"
                            if isValidAfterCodaW(candidateNucleus) {
                                nucleusAndCodaChars = candidateNucleus
                                modified = true
                            }
                            break
                        } else if vIdx >= 1 && nucleusAndCodaChars[vIdx - 1] == "ư" {
                            if vIdx == nucleusAndCodaChars.count - 1 {
                                nucleusAndCodaChars[vIdx] = "ơ"
                                modified = true
                            }
                            // Policy 3B+: When 'ưo' is followed by a coda/offglide (vIdx < count - 1),
                            // it is already saturated as 'ươ'; break without stripping so 'w' appends literally.
                            break
                        }
                        var candidateNucleus = nucleusAndCodaChars
                        candidateNucleus[vIdx] = "ơ"
                        if isValidAfterCodaW(candidateNucleus) {
                            nucleusAndCodaChars = candidateNucleus
                            modified = true
                        }
                        break
                    } else if vLower == "u" {
                        if vIdx >= 1 && (nucleusAndCodaChars[vIdx - 1] == "o" || nucleusAndCodaChars[vIdx - 1] == "ơ") {
                            continue
                        }
                        if vIdx >= 1 && nucleusAndCodaChars[vIdx - 1] == "u" {
                            var candidateNucleus = nucleusAndCodaChars
                            candidateNucleus[vIdx - 1] = "ư"
                            if isValidAfterCodaW(candidateNucleus) {
                                nucleusAndCodaChars = candidateNucleus
                                modified = true
                            }
                            break
                        }
                        if vIdx >= 1 && nucleusAndCodaChars[vIdx - 1] == "ư" {
                            // Policy 3B+: 'ưu' (e.g. lưu, cứu, hưu) is already horned (saturated).
                            break
                        }
                        var candidateNucleus = nucleusAndCodaChars
                        candidateNucleus[vIdx] = "ư"
                        if isValidAfterCodaW(candidateNucleus) {
                            nucleusAndCodaChars = candidateNucleus
                            modified = true
                        }
                        break
                    }
                    }
                }

                if !modified {
                    if nucleusAndCodaChars.isEmpty && onset.isEmpty {
                        if simpleTelex && n == 1 {
                            nucleusAndCodaChars.append("w")
                        } else if idx + 2 < n && lowerChars[idx + 1] == "u" && (lowerChars[idx + 2] == "a" || lowerChars[idx + 2] == "o") {
                            hasHorn = true
                            intent.hasHornModifier = true
                        } else {
                            nucleusAndCodaChars.append("ư")
                        }
                    } else {
                        let hasVowelsAlready = nucleusAndCodaChars.contains { isVowelChar($0) }
                        let restAfterW = lowerChars[(idx + 1)...]
                        let hasHornCapableVowelAhead = restAfterW.contains { $0 == "a" || $0 == "o" || $0 == "u" }
                        let isEnglishClusterPrefix = onset == "q" || ((onset == "t" || onset == "s" || onset == "d") &&
                            (idx + 1 < n && (lowerChars[idx + 1] == "a" || lowerChars[idx + 1] == "o")))
                        if !hasVowelsAlready && hasHornCapableVowelAhead && !isEnglishClusterPrefix {
                            hasHorn = true
                            intent.hasHornModifier = true
                        } else {
                            let activeTone = trailingToneFound != .none ? trailingToneFound : tone
                            if let lockedStem = VietnameseEngine.shouldLockPostCodaOverflow(
                                stemChars: Array(onset) + nucleusAndCodaChars,
                                tone: activeTone,
                                hasHorn: hasHorn,
                                hornCancelled: hornCancelled,
                                circumflexCancelled: circumflexCancelled,
                                circumflexCancelledKey: circumflexCancelledKey,
                                strokeDCancelled: strokeDCancelled,
                                nextChar: ch,
                                remainingChars: lowerChars[idx...],
                                fullRawChars: chars,
                                modernOrthography: modernOrthography
                            ) {
                                nucleusAndCodaChars = Array(lockedStem.dropFirst(onset.count))
                                nucleusAndCodaChars.append(contentsOf: lowerChars[idx...])
                                intent.tone = activeTone
                                tone = .none
                                trailingToneFound = .none
                                hasHorn = false
                                hornCancelled = true
                                break
                            }
                            nucleusAndCodaChars.append("w")
                        }
                    }
                }
                idx += 1
                continue
            }

            // Check if tone key appears after vowels (infix or postfix)
            if isToneKey(ch) {
                let hasVowels = !nucleusAndCodaChars.contains("w") && nucleusAndCodaChars.contains { VietnameseEngine.isVietnameseVowel($0) }
                if hasVowels {
                    if ch == "z" {
                        if tone != .none || trailingToneFound != .none {
                            tone = .none
                            trailingToneFound = .none
                            idx += 1
                            continue
                        }
                    } else {
                        let newTone = mapToneKey(ch)
                        let currentTone = trailingToneFound != .none ? trailingToneFound : tone
                        let hasModifiedChar = onset == "đ" || hasHorn || nucleusAndCodaChars.contains { "ăâêôơư".contains($0) }
                        let isIllegalStopCodaTone =
                            (newTone == .grave || newTone == .hook || newTone == .tilde) &&
                            currentTone != newTone &&
                            (currentTone != .none || hasModifiedChar) &&
                            VietnameseEngine.endsWithStopCodaAfterVowel(nucleusAndCodaChars)

                        if !isIllegalStopCodaTone {
                            if toneEscapeActive {
                                let hasVnStem = hasModifiedChar || hornCancelled || circumflexCancelled || circumflexCancelledKey != nil || strokeDCancelled
                                if hasVnStem || ch == cancelledToneKey {
                                    nucleusAndCodaChars.append(ch)
                                    idx += 1
                                    continue
                                } else if ch != cancelledToneKey {
                                    cancelledToneKey = ch
                                    nucleusAndCodaChars.append(ch)
                                    if idx + 1 < n && lowerChars[idx + 1] == ch {
                                        idx += 2
                                    } else {
                                        idx += 1
                                    }
                                    continue
                                }
                            } else {
                                if profile != .preVowel {
                                    // Tone key cancellation: double-tap escape (e.g. pass -> pas, mass -> mas, boss -> bos, turrus -> turus)
                                    if currentTone != newTone && idx + 1 < n && lowerChars[idx + 1] == ch {
                                        tone = .none
                                        trailingToneFound = .none
                                        toneEscapeActive = true
                                        toneEscapeLocked = true
                                        cancelledToneKey = ch
                                        nucleusAndCodaChars.append(ch)
                                        idx += 2
                                        continue
                                    }
                                }

                                if currentTone == .none {
                                    let prevIsVowel = nucleusAndCodaChars.last.map { VietnameseEngine.isVietnameseVowel($0) } ?? false
                                    let isOffglide = (idx + 1 < n) && (lowerChars[idx + 1] == "i" || lowerChars[idx + 1] == "y" || lowerChars[idx + 1] == "u" || lowerChars[idx + 1] == "o")
                                    let nextIsToneKey = (idx + 1 < n) && isToneKey(lowerChars[idx + 1])
                                    let nextIsCoda = (idx + 1 < n) && !nextIsToneKey && (!isVowelChar(lowerChars[idx + 1]) || (isOffglide && idx + 2 >= n))

                                    let isGeminate = (idx + 1 < n) && (lowerChars[idx + 1] == ch)
                                    if prevIsVowel && nextIsCoda && !isGeminate {
                                        // Infix tone (e.g. truowfng, teest, nguowfi)
                                        tone = newTone
                                        idx += 1
                                        continue
                                    } else if profile == .smartHybrid || profile == .senFlex {
                                        trailingToneFound = newTone
                                        idx += 1
                                        continue
                                    }
                                } else if profile != .preVowel {
                                    // Tone replacement or repeated tone cancellation
                                    if currentTone == newTone && newTone != .none {
                                        let isAdjacentDoubleTone = idx > 0 && lowerChars[idx - 1] == ch
                                        let hasModifiedVowel = hasHorn || hornCancelled || circumflexCancelled || circumflexCancelledKey != nil || nucleusAndCodaChars.contains { "ăâêôơư".contains($0) }
                                        let isCodaLast = nucleusAndCodaChars.last.map { ["c", "m", "n", "p", "t", "g", "h"].contains($0) } ?? false
                                        let isPostCodaToneThenVowelReshape = idx >= 2 &&
                                            ["a", "e", "o", "w"].contains(lowerChars[idx - 1]) &&
                                            lowerChars[idx - 2] == ch &&
                                            isCodaLast &&
                                            hasModifiedVowel
                                        if isAdjacentDoubleTone || !isPostCodaToneThenVowelReshape {
                                            // P0.2 & P0.6 CancelToneAndEmitLiteral: Repeated active tone key cancels the tone
                                            // and emits one literal tone character (tur + r -> tur -> turus, canhf + f -> canhf,
                                            // cafnh + f -> canhf, hoongf + f -> hôngf, hoonfg + f -> hôngf).
                                            let stemBeforeEscape = onset + String(nucleusAndCodaChars)
                                            tone = .none
                                            trailingToneFound = .none
                                            intent.hasPreVowelTone = false
                                            toneEscapeActive = true
                                            if isAdjacentDoubleTone ||
                                               hasModifiedChar ||
                                               hornCancelled ||
                                               circumflexCancelled ||
                                               circumflexCancelledKey != nil ||
                                               strokeDCancelled ||
                                               VietnameseSyllableDictionary.shared.isValidUntonedSyllable(stemBeforeEscape, genZMode: genZMode) ||
                                               VietnameseSyllableDictionary.shared.isValidUntonedRhyme(stemBeforeEscape) ||
                                               VietnameseSyllableDictionary.shared.isPlausibleInProgressVietnamese(stemBeforeEscape, relaxedCoda: relaxedCoda, genZMode: genZMode) {
                                                toneEscapeLocked = true
                                            }
                                            cancelledToneKey = ch
                                            nucleusAndCodaChars.append(ch)
                                        } else {
                                            // Post-coda tone-then-vowel-reshape followed by same tone key (e.g. congror) is idempotent
                                            if trailingToneFound != .none {
                                                trailingToneFound = newTone
                                            } else {
                                                tone = newTone
                                            }
                                        }
                                        idx += 1
                                        continue
                                    } else if newTone != .none {
                                        // Different tone key replaces existing tone
                                        if trailingToneFound != .none {
                                            trailingToneFound = newTone
                                        } else {
                                            tone = newTone
                                        }
                                        idx += 1
                                        continue
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Relaxed coda shortcut: 'g' at end of word (or before trailing modifiers) transforms to 'ng'
            if relaxedCoda && ch == "g",
               !nucleusAndCodaChars.contains("w"),
               let lastChar = nucleusAndCodaChars.last, VietnameseEngine.isVietnameseVowel(lastChar),
               ((idx + 1)..<n).allSatisfy({ ["s", "f", "r", "x", "j", "z", "w", "a", "e", "o", "d"].contains(lowerChars[$0]) }) {
                nucleusAndCodaChars.append("n")
                nucleusAndCodaChars.append("g")
                idx += 1
                continue
            }

            if ch == "d" && onset == "đ" && !toneEscapeActive && postStrokeTail.isEmpty &&
               nucleusAndCodaChars.contains(where: { VietnameseEngine.isVietnameseVowel($0) }),
               let lastChar = nucleusAndCodaChars.last,
               (VietnameseEngine.isVietnameseVowel(lastChar) || ["c", "m", "n", "p", "t", "g", "h"].contains(lastChar)) {
                var candidateNucleus = nucleusAndCodaChars
                if hasHorn {
                    applyHornModifier(&candidateNucleus)
                }
                if !hornCancelled && circumflexCancelledKey != "o" && candidateNucleus.count >= 2 {
                    for vIdx in 0..<(candidateNucleus.count - 1) {
                        if candidateNucleus[vIdx] == "ư" && candidateNucleus[vIdx + 1] == "o" {
                            candidateNucleus[vIdx + 1] = "ơ"
                        }
                    }
                }
                if VietnameseSyllableDictionary.shared.isValidUntonedSyllableIgnoringVowelShape("đ" + String(candidateNucleus)) {
                    var dCount = 0
                    while idx + dCount < n && lowerChars[idx + dCount] == "d" {
                        dCount += 1
                    }
                    let afterDIdx = idx + dCount
                    if dCount == 1 {
                        onset = "d"
                        intent.onset = "d"
                        strokeDCancelled = true
                        idx += 1
                        continue
                    } else {
                        onset = "d"
                        intent.onset = "d"
                        if dCount == 2 {
                            postStrokeTail.append("đ")
                        } else if dCount >= 3 {
                            for _ in 1..<dCount {
                                postStrokeTail.append("d")
                            }
                        }
                        if afterDIdx < n {
                            postStrokeTail.append(contentsOf: lowerChars[afterDIdx...])
                        }
                        idx = n
                        break
                    }
                }
            }
            if ch == "d" && onset == "d" && nucleusAndCodaChars.count >= 2 &&
               !toneEscapeActive && !hornCancelled && !circumflexCancelled && circumflexCancelledKey == nil && postStrokeTail.isEmpty,
               let lastChar = nucleusAndCodaChars.last,
               ["c", "m", "n", "p", "t", "g", "h"].contains(lastChar),
               !SmartBilingualDetector.isKnownEnglishWord(lowerRaw),
               !SmartBilingualDetector.isKnownEnglishWord(String(lowerChars[0...idx])) {
                var candidateNucleus = nucleusAndCodaChars
                if hasHorn {
                    applyHornModifier(&candidateNucleus)
                }
                if candidateNucleus.count >= 2 {
                    for vIdx in 0..<(candidateNucleus.count - 1) {
                        if candidateNucleus[vIdx] == "ư" && candidateNucleus[vIdx + 1] == "o" {
                            candidateNucleus[vIdx + 1] = "ơ"
                        }
                    }
                }
                let candidateUntoned = "đ" + String(candidateNucleus)
                let hasShapeModifierAhead = (idx + 1 == n) || ((idx + 1)..<n).contains {
                    let c = lowerChars[$0]
                    return c == "w" || c == "o"
                }
                if VietnameseSyllableDictionary.shared.isValidUntonedSyllable(candidateUntoned) ||
                   (candidateUntoned.hasPrefix("đuo") &&
                    hasShapeModifierAhead &&
                    VietnameseSyllableDictionary.shared.isValidUntonedSyllableIgnoringVowelShape(candidateUntoned)) {
                    onset = "đ"
                    intent.onset = "đ"
                    if nucleusAndCodaChars.count >= 2 {
                        for vIdx in 0..<(nucleusAndCodaChars.count - 1) {
                            if nucleusAndCodaChars[vIdx] == "ư" && nucleusAndCodaChars[vIdx + 1] == "o" {
                                nucleusAndCodaChars[vIdx + 1] = "ơ"
                            }
                        }
                    }
                    idx += 1
                    continue
                }
            }

            let activeTone = trailingToneFound != .none ? trailingToneFound : tone
            if let lockedStem = VietnameseEngine.shouldLockPostCodaOverflow(
                stemChars: Array(onset) + nucleusAndCodaChars,
                tone: activeTone,
                hasHorn: hasHorn,
                hornCancelled: hornCancelled,
                circumflexCancelled: circumflexCancelled,
                circumflexCancelledKey: circumflexCancelledKey,
                strokeDCancelled: strokeDCancelled,
                nextChar: ch,
                remainingChars: lowerChars[idx...],
                fullRawChars: chars,
                modernOrthography: modernOrthography
            ) {
                nucleusAndCodaChars = Array(lockedStem.dropFirst(onset.count))
                nucleusAndCodaChars.append(contentsOf: lowerChars[idx...])
                intent.tone = activeTone
                tone = .none
                trailingToneFound = .none
                hasHorn = false
                hornCancelled = true
                break
            }

            if ch == "d" && !nucleusAndCodaChars.contains(where: { VietnameseEngine.isVietnameseVowel($0) }) {
                if nucleusAndCodaChars.last == "d" {
                    nucleusAndCodaChars[nucleusAndCodaChars.count - 1] = "đ"
                    idx += 1
                    continue
                } else if nucleusAndCodaChars.last == "đ" {
                    nucleusAndCodaChars[nucleusAndCodaChars.count - 1] = "d"
                    nucleusAndCodaChars.append("d")
                    idx += 1
                    continue
                }
            }

            nucleusAndCodaChars.append(ch)
            idx += 1
        }

        // If trailing tone was found and allowed
        if tone == .none && trailingToneFound != .none {
            tone = trailingToneFound
        }

        // 4. If hasHorn is true, apply horn to "uo" -> "ươ", "u" -> "ư", "o" -> "ơ", "a" -> "ă"
        if hasHorn {
            applyHornModifier(&nucleusAndCodaChars)
        }

        // Harmonize 'ưo' -> 'ươ' when horn was applied to 'u' before 'o' (e.g. truwongr -> trưởng, dduwocj -> được, nguwoif -> người)
        if !hornCancelled && circumflexCancelledKey != "o" && nucleusAndCodaChars.count >= 2 {
            for vIdx in 0..<(nucleusAndCodaChars.count - 1) {
                if nucleusAndCodaChars[vIdx] == "ư" && nucleusAndCodaChars[vIdx + 1] == "o" {
                    nucleusAndCodaChars[vIdx + 1] = "ơ"
                }
            }
        }

        // 5. Relaxed coda shortcut: 'g' at end transforms to 'ng' if relaxedCoda is enabled
        if relaxedCoda && !hornCancelled && !toneEscapeActive && nucleusAndCodaChars.last == "g" {
            if nucleusAndCodaChars.count >= 2 && VietnameseEngine.isVietnameseVowel(nucleusAndCodaChars[nucleusAndCodaChars.count - 2]) {
                nucleusAndCodaChars.removeLast()
                nucleusAndCodaChars.append("n")
                nucleusAndCodaChars.append("g")
            }
        }

        // Separate nucleus from coda
        separateNucleusAndCoda(nucleusAndCodaChars, intent: &intent)

        // Build base rendered string
        var renderedChars: [Character] = Array(onset) + nucleusAndCodaChars

        // 7. Apply tone to vowel cluster
        if tone != .none {
            VietnameseEngine.applyTone(&renderedChars, tone: tone, modern: modernOrthography)
            intent.tone = tone
        }

        if !postStrokeTail.isEmpty {
            renderedChars.append(contentsOf: postStrokeTail)
        }

        // 8. Preserve casing
        let finalRendered = applyCasing(original: chars, transformed: renderedChars)

        // Check validity against dictionary
        intent.isValidVietnamese = VietnameseSyllableDictionary.shared.isPhonotacticallyValidSyllable(finalRendered) ||
            (!lowerRaw.hasPrefix("w") &&
             VietnameseSyllableDictionary.shared.isValidVietnameseRhyme(finalRendered) &&
             !SmartBilingualDetector.isKnownEnglishWord(rawStr))

        return (intent, finalRendered)
    }

    private func separateNucleusAndCoda(_ chars: [Character], intent: inout SyllableIntent) {
        var nucleusChars: [Character] = []
        var codaChars: [Character] = []
        var inCoda = false

        for ch in chars {
            if !inCoda {
                if VietnameseEngine.isVietnameseVowel(ch) {
                    nucleusChars.append(ch)
                } else {
                    inCoda = true
                    codaChars.append(ch)
                }
            } else {
                codaChars.append(ch)
            }
        }

        intent.nucleus = String(nucleusChars)
        intent.coda = String(codaChars)
    }

    private func applyHornModifier(_ chars: inout [Character]) {
        // Look for "uo" -> "ươ"
        for i in 0..<chars.count {
            if chars[i] == "u" && i + 1 < chars.count && chars[i + 1] == "o" {
                chars[i] = "ư"
                chars[i + 1] = "ơ"
                return
            }
        }
        // Otherwise single "u" -> "ư", "o" -> "ơ", "a" -> "ă"
        for i in 0..<chars.count {
            if chars[i] == "u" {
                chars[i] = "ư"
                return
            } else if chars[i] == "o" {
                chars[i] = "ơ"
                return
            } else if chars[i] == "a" {
                chars[i] = "ă"
                return
            }
        }
    }

    private static let vowelCharacters: Set<Character> = [
        "a", "e", "i", "o", "u", "y", "ă", "â", "ê", "ô", "ơ", "ư"
    ]

    private func isVowelChar(_ ch: Character) -> Bool {
        return Self.vowelCharacters.contains(ch)
    }

    private func isToneKey(_ ch: Character) -> Bool {
        return ch == "s" || ch == "f" || ch == "r" || ch == "x" || ch == "j" || ch == "z"
    }

    private func mapToneKey(_ ch: Character) -> VietnameseTone {
        switch ch {
        case "s": return .acute
        case "f": return .grave
        case "r": return .hook
        case "x": return .tilde
        case "j": return .dot
        default: return .none
        }
    }

    private static func baseAsciiKey(for ch: Character) -> Character {
        let stripped = VietnameseSyllableDictionary.stripToneMarks(String(ch).lowercased())
        guard let c = stripped.first else { return ch }
        switch c {
        case "đ": return "d"
        case "ă", "â": return "a"
        case "ê": return "e"
        case "ô", "ơ": return "o"
        case "ư": return "u"
        default: return c
        }
    }

    private func applyCasing(original: [Character], transformed: [Character]) -> String {
        guard !original.isEmpty, !transformed.isEmpty else { return String(transformed) }

        let allLetters = original.filter { $0.isLetter }
        let isAllUpper = !allLetters.isEmpty && allLetters.allSatisfy { $0.isUppercase }
        let hasInteriorUpper = original.dropFirst().contains { $0.isUppercase }
        let isFirstUpper = original[0].isUppercase

        if isAllUpper {
            return String(transformed).uppercased()
        } else if hasInteriorUpper {
            var out: [Character] = []
            out.reserveCapacity(transformed.count)
            var origIdx = 0
            for (tIdx, tChar) in transformed.enumerated() {
                let targetBase = Self.baseAsciiKey(for: tChar)
                var matchedIdx: Int? = nil
                var scan = origIdx
                while scan < original.count {
                    if Self.baseAsciiKey(for: original[scan]) == targetBase {
                        matchedIdx = scan
                        break
                    }
                    scan += 1
                }
                if let mIdx = matchedIdx {
                    var useUpper = original[mIdx].isUppercase
                    let nextTransformedSameBase = (tIdx + 1 < transformed.count) &&
                        (Self.baseAsciiKey(for: transformed[tIdx + 1]) == targetBase)
                    if !nextTransformedSameBase,
                       mIdx + 1 < original.count,
                       Self.baseAsciiKey(for: original[mIdx + 1]) == targetBase {
                        if tChar.isASCII {
                            useUpper = original[mIdx + 1].isUppercase
                        }
                        origIdx = mIdx + 2
                    } else {
                        origIdx = mIdx + 1
                    }
                    if useUpper, let upperChar = String(tChar).uppercased().first {
                        out.append(upperChar)
                    } else if let lowerChar = String(tChar).lowercased().first {
                        out.append(lowerChar)
                    } else {
                        out.append(tChar)
                    }
                } else {
                    out.append(tChar)
                }
            }
            return String(out)
        } else if isFirstUpper {
            let first = String(transformed[0]).uppercased()
            let rest = String(transformed.dropFirst())
            return first + rest
        } else {
            return String(transformed).lowercased()
        }
    }
}
