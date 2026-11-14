#if !VIELOTUS_OPEN_CORE_MACOS
import Foundation

/// Records the real-time sequence of text states inside an OS text input as a user types with an active keyboard/IME.
public struct LiveTypingTrace: Sendable, Equatable {
    public var currentText: String = ""
    public var snapshots: [String] = []

    public init(currentText: String = "", snapshots: [String] = []) {
        self.currentText = currentText
        self.snapshots = snapshots
    }

    public mutating func recordChange(_ newText: String) {
        if newText.isEmpty {
            currentText = ""
            snapshots.removeAll()
            return
        }
        guard newText != currentText else { return }
        currentText = newText
        if snapshots.last != newText {
            snapshots.append(newText)
        }
    }

    public mutating func clear() {
        currentText = ""
        snapshots.removeAll()
    }

    public var displayFinal: String {
        Self.formatVisibleSpaces(currentText)
    }

    public var formattedChain: String {
        guard !snapshots.isEmpty else { return "Chưa gõ" }
        return snapshots.map { Self.formatVisibleSpaces($0) }.joined(separator: " → ")
    }

    public static func formatVisibleSpaces(_ text: String) -> String {
        guard !text.isEmpty else { return "—" }
        return text.replacingOccurrences(of: " ", with: "␣")
    }
}

/// A single row in the empirical live-typing comparison worksheet between Apple Telex and Sen Việt.
public struct EmpiricalComparisonRow: Identifiable, Sendable, Equatable {
    public let id: Int
    public var scenarioTitle: String
    public var instructionHint: String
    public var appleTrace: LiveTypingTrace
    public var vieLotusTrace: LiveTypingTrace

    public init(
        id: Int,
        scenarioTitle: String,
        instructionHint: String,
        appleTrace: LiveTypingTrace = LiveTypingTrace(),
        vieLotusTrace: LiveTypingTrace = LiveTypingTrace()
    ) {
        self.id = id
        self.scenarioTitle = scenarioTitle
        self.instructionHint = instructionHint
        self.appleTrace = appleTrace
        self.vieLotusTrace = vieLotusTrace
    }

    public var hasBothInputs: Bool {
        !appleTrace.currentText.isEmpty && !vieLotusTrace.currentText.isEmpty
    }

    public var isFinalIdentical: Bool {
        hasBothInputs && appleTrace.currentText == vieLotusTrace.currentText
    }

    public var isChainIdentical: Bool {
        hasBothInputs && appleTrace.snapshots == vieLotusTrace.snapshots
    }

    public var statusText: String {
        guard hasBothInputs else {
            if appleTrace.currentText.isEmpty && vieLotusTrace.currentText.isEmpty {
                return "Chờ gõ thử ở 2 cột"
            } else if appleTrace.currentText.isEmpty {
                return "Chờ gõ cột Apple Telex"
            } else {
                return "Chờ gõ cột Sen Việt"
            }
        }
        if isFinalIdentical && isChainIdentical {
            return "Đồng nhất 100% (cả kết quả & chuỗi biến đổi)"
        } else if isFinalIdentical {
            return "Kết quả cuối giống nhau (khác bước trung gian)"
        } else {
            return "Khác kết quả: Apple [\(appleTrace.displayFinal)] ≠ Sen Việt [\(vieLotusTrace.displayFinal)]"
        }
    }

    public static func defaultRows() -> [EmpiricalComparisonRow] {
        [
            EmpiricalComparisonRow(
                id: 1,
                scenarioTitle: "1. Thêm ngay sau gõ",
                instructionHint: "Gõ từ gốc + phím thêm ngay lập tức (chưa bấm Cách)"
            ),
            EmpiricalComparisonRow(
                id: 2,
                scenarioTitle: "2. Thêm ngay sau gõ + Space",
                instructionHint: "Gõ từ gốc + phím thêm rồi bấm phím Cách (␣)"
            ),
            EmpiricalComparisonRow(
                id: 3,
                scenarioTitle: "3. Gõ xong + Space + ⌫ + Thêm",
                instructionHint: "Gõ từ gốc + Cách (␣) + Xoá lùi (⌫) + phím thêm"
            ),
            EmpiricalComparisonRow(
                id: 4,
                scenarioTitle: "4. Gõ xong + Space + ⌫ + Thêm + Space",
                instructionHint: "Gõ từ gốc + Cách (␣) + Xoá lùi (⌫) + phím thêm + Cách (␣)"
            )
        ]
    }

    public static func generateMarkdownReport(
        platformName: String,
        wordNote: String,
        autocorrectEnabled: Bool,
        rows: [EmpiricalComparisonRow],
        inputMethod: InputMethodType? = nil
    ) -> String {
        let inferredVNI = rows.contains { row in
            let allTexts = row.appleTrace.snapshots + row.vieLotusTrace.snapshots + [row.appleTrace.currentText, row.vieLotusTrace.currentText]
            return allTexts.contains { text in
                text.contains(where: \.isNumber) && text.contains(where: \.isLetter)
            }
        } || wordNote.localizedCaseInsensitiveContains("vni") || wordNote.contains(where: \.isNumber)
        let effectiveMethod = inputMethod ?? (inferredVNI ? .vni : .telex)
        let appleLabel = effectiveMethod == .vni ? "Apple VNI" : "Apple Telex"

        var resolvedWordNote = wordNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let isDefaultTelexNote = resolvedWordNote == "trưởng + w (truowngr + w)" || resolvedWordNote == "trưởng + w (Truowngr + w)"
        if isDefaultTelexNote,
           let firstRow = rows.first(where: { !$0.appleTrace.snapshots.isEmpty || !$0.vieLotusTrace.snapshots.isEmpty }) {
            let chain = !firstRow.appleTrace.snapshots.isEmpty ? firstRow.appleTrace.snapshots : firstRow.vieLotusTrace.snapshots
            let finalOut = !firstRow.appleTrace.currentText.isEmpty ? firstRow.appleTrace.currentText : firstRow.vieLotusTrace.currentText
            let cleanFinal = finalOut.trimmingCharacters(in: .whitespacesAndNewlines)
            if let baseComposed = chain.dropLast().last(where: { !$0.contains(where: \.isNumber) && !$0.allSatisfy(\.isASCII) }),
               !cleanFinal.isEmpty {
                let extraDigits = String(cleanFinal.reversed().prefix(while: \.isNumber).reversed())
                if !extraDigits.isEmpty {
                    let formattedExtra = extraDigits.map(String.init).joined(separator: ", ")
                    resolvedWordNote = "\(baseComposed) + \(formattedExtra) (\(effectiveMethod == .vni ? "VNI" : "Telex"))"
                } else {
                    resolvedWordNote = "\(baseComposed) → \(cleanFinal)"
                }
            } else if !cleanFinal.isEmpty && !cleanFinal.lowercased().hasPrefix("trưởng") && !cleanFinal.lowercased().hasPrefix("truỏng") {
                resolvedWordNote = cleanFinal
            }
        }

        var lines: [String] = []
        lines.append("### Bảng Đối Chiếu Gõ Thực Tế: \(appleLabel) vs. Sen Việt (\(platformName))")
        lines.append("- **Kiểu gõ**: `\(effectiveMethod == .vni ? "VNI" : "Telex")`")
        if !resolvedWordNote.isEmpty {
            lines.append("- **Từ / Tổ hợp đang test**: `\(resolvedWordNote)`")
        }
        lines.append("- **Autocorrect hệ thống trên ô nhập**: `\(autocorrectEnabled ? "BẬT" : "TẮT")`")
        lines.append("")
        lines.append("| Kịch bản | \(appleLabel) (Kết quả) | Sen Việt (Kết quả) | Chuỗi biến đổi \(appleLabel) | Chuỗi biến đổi Sen Việt | Đánh giá |")
        lines.append("| :--- | :--- | :--- | :--- | :--- | :--- |")
        for row in rows {
            lines.append(
                "| \(row.scenarioTitle) | `\(row.appleTrace.displayFinal)` | `\(row.vieLotusTrace.displayFinal)` | `\(row.appleTrace.formattedChain)` | `\(row.vieLotusTrace.formattedChain)` | \(row.statusText) |"
            )
        }
        return lines.joined(separator: "\n")
    }
}

/// Represents the relationship between Sen Việt (VieLotusIM) and Apple Telex at a given keystroke or scenario.
public enum ComparisonDeltaKind: String, Sendable, Equatable {
    case identical = "Khớp 100% Apple Telex"
    case vieLotusPreservesIntent = "Cải tiến: Giữ nguyên chữ vừa gõ (không tự sửa)"
    case vieLotusSmartBilingual = "Cải tiến: Bảo vệ từ tiếng Anh (Smart Bilingual)"
    case vieLotusPostCommitRefine = "Cải tiến: Bổ sung dấu sau khi xoá khoảng trắng"
    case vieLotusFlexibleOrder = "Cải tiến: Gõ dấu linh hoạt (SenFlex)"
}

/// A single keystroke step in a side-by-side comparison timeline between Apple Telex and Sen Việt.
public struct ComparisonStep: Identifiable, Sendable, Equatable {
    public let id: Int
    public let stepNumber: Int
    public let keyLabel: String
    public let rawBuffer: String
    public let appleTelexOutput: String
    public let appleAutocorrectNote: String?
    public let vieLotusOutput: String
    public let deltaKind: ComparisonDeltaKind
    public let explanation: String

    public init(
        stepNumber: Int,
        keyLabel: String,
        rawBuffer: String,
        appleTelexOutput: String,
        appleAutocorrectNote: String?,
        vieLotusOutput: String,
        deltaKind: ComparisonDeltaKind,
        explanation: String
    ) {
        self.id = stepNumber
        self.stepNumber = stepNumber
        self.keyLabel = keyLabel
        self.rawBuffer = rawBuffer
        self.appleTelexOutput = appleTelexOutput
        self.appleAutocorrectNote = appleAutocorrectNote
        self.vieLotusOutput = vieLotusOutput
        self.deltaKind = deltaKind
        self.explanation = explanation
    }
}

/// One of the 4 standard editing scenarios for comparing a base Telex word + extra keystroke.
public struct ComparisonScenarioRow: Identifiable, Sendable, Equatable {
    public let id: Int
    public let title: String
    public let subtitle: String
    public let keySequenceDisplay: String
    public let scriptTokens: [String]
    public let appleTelexOutput: String
    public let appleAutocorrectNote: String?
    public let vieLotusOutput: String
    public let deltaKind: ComparisonDeltaKind
    public let steps: [ComparisonStep]

    public init(
        id: Int,
        title: String,
        subtitle: String,
        keySequenceDisplay: String,
        scriptTokens: [String],
        appleTelexOutput: String,
        appleAutocorrectNote: String?,
        vieLotusOutput: String,
        deltaKind: ComparisonDeltaKind,
        steps: [ComparisonStep]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.keySequenceDisplay = keySequenceDisplay
        self.scriptTokens = scriptTokens
        self.appleTelexOutput = appleTelexOutput
        self.appleAutocorrectNote = appleAutocorrectNote
        self.vieLotusOutput = vieLotusOutput
        self.deltaKind = deltaKind
        self.steps = steps
    }
}

/// Built-in preset cases covering the Apple Telex vs. Sen Việt transformation matrix.
public struct ComparisonPreset: Identifiable, Sendable, Equatable {
    public let id: String
    public let label: String
    public let category: String
    public let baseRawWord: String
    public let extraKey: String
    public let inputMethod: InputMethodType

    public init(id: String, label: String, category: String, baseRawWord: String, extraKey: String, inputMethod: InputMethodType = .telex) {
        self.id = id
        self.label = label
        self.category = category
        self.baseRawWord = baseRawWord
        self.extraKey = extraKey
        self.inputMethod = inputMethod
    }

    public static let allPresets: [ComparisonPreset] = [
        ComparisonPreset(id: "vni_truong_72", label: "trường + 7, 2 (VNI)", category: "Bảng chuẩn Apple VNI", baseRawWord: "truong72", extraKey: "72", inputMethod: .vni),
        ComparisonPreset(id: "vni_khong_6", label: "không + 6 (VNI)", category: "Bảng chuẩn Apple VNI", baseRawWord: "khong6", extraKey: "6", inputMethod: .vni),
        ComparisonPreset(id: "vni_quyet_61", label: "quyết + 6, 1 (VNI)", category: "Bảng chuẩn Apple VNI", baseRawWord: "quyet61", extraKey: "61", inputMethod: .vni),
        ComparisonPreset(id: "truong_w", label: "trưởng + w", category: "Bảng chuẩn Apple", baseRawWord: "Truowngr", extraKey: "w"),
        ComparisonPreset(id: "kenh_e", label: "kênh + e", category: "Bảng chuẩn Apple", baseRawWord: "keenh", extraKey: "e"),
        ComparisonPreset(id: "hong_o", label: "hồng + o", category: "Bảng chuẩn Apple", baseRawWord: "hoongf", extraKey: "o"),
        ComparisonPreset(id: "kinh_i", label: "kính + i", category: "Bảng chuẩn Apple", baseRawWord: "kinhs", extraKey: "i"),
        ComparisonPreset(id: "tu_u", label: "tủ + u", category: "Bảng chuẩn Apple", baseRawWord: "tur", extraKey: "u"),
        ComparisonPreset(id: "mung_u", label: "mừng + u", category: "Bảng chuẩn Apple", baseRawWord: "muwngf", extraKey: "u"),
        ComparisonPreset(id: "duong_u", label: "đường + u", category: "Bảng chuẩn Apple", baseRawWord: "dduowngf", extraKey: "u"),
        ComparisonPreset(id: "duong_o", label: "đường + o", category: "Bảng chuẩn Apple", baseRawWord: "dduowngf", extraKey: "o"),
        ComparisonPreset(id: "truong_o", label: "trưởng + o", category: "Mở rộng vần", baseRawWord: "truowngr", extraKey: "o"),
        ComparisonPreset(id: "menh_e", label: "mệnh + e", category: "Mở rộng vần", baseRawWord: "meenhj", extraKey: "e"),
        ComparisonPreset(id: "mieng_e", label: "miệng + e", category: "Mở rộng vần", baseRawWord: "mieengj", extraKey: "e"),
        ComparisonPreset(id: "huong_o", label: "huống + o", category: "Mở rộng vần", baseRawWord: "huoongs", extraKey: "o"),
        ComparisonPreset(id: "nhan_a", label: "nhan + a (sửa dấu)", category: "Cải tiến Sen Việt", baseRawWord: "nhan", extraKey: "a"),
        ComparisonPreset(id: "window_s", label: "window + s (Song ngữ)", category: "Cải tiến Sen Việt", baseRawWord: "window", extraKey: "s"),
        ComparisonPreset(id: "service_s", label: "service + s (Song ngữ)", category: "Cải tiến Sen Việt", baseRawWord: "service", extraKey: "s")
    ]
}

/// Deterministic simulator comparing Apple Telex/VNI and Sen Việt (VieLotusIM) keystroke by keystroke.
public enum TelexComparisonSimulator {

    public static func buildFourScenarioMatrix(
        baseRawWord: String,
        extraKey: String,
        inputMethod: InputMethodType = .telex,
        grammarProfile: GrammarProfile = .senFlex,
        smartBilingual: Bool = true,
        simulateAppleAutocorrect: Bool = true
    ) -> [ComparisonScenarioRow] {
        let cleanBase = baseRawWord.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanExtra = extraKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let extraTokens = cleanExtra.isEmpty ? ["w"] : cleanExtra.map(String.init)
        let extraDisplay = extraTokens.joined()
        let baseTokens = cleanBase.map(String.init)

        let scenarios: [(id: Int, title: String, subtitle: String, display: String, tokens: [String])] = [
            (
                1,
                "1. Thêm ngay sau gõ",
                "Đang gõ âm tiết, bấm thêm phím '\(extraDisplay)' ngay trước khi cách",
                "\(cleanBase) + \(extraDisplay)",
                baseTokens + extraTokens
            ),
            (
                2,
                "2. Thêm ngay sau gõ + Space",
                "Gõ thêm phím '\(extraDisplay)' rồi bấm phím Cách (␣)",
                "\(cleanBase) + \(extraDisplay) + ␣",
                baseTokens + extraTokens + ["␣"]
            ),
            (
                3,
                "3. Gõ xong + Space + ⌫ + Thêm",
                "Chốt từ bằng ␣, bấm ⌫ xoá dấu cách rồi gõ thêm '\(extraDisplay)'",
                "\(cleanBase) + ␣ + ⌫ + \(extraDisplay)",
                baseTokens + ["␣", "⌫"] + extraTokens
            ),
            (
                4,
                "4. Gõ xong + Space + ⌫ + Thêm + Space",
                "Xoá dấu cách, gõ thêm '\(extraDisplay)' rồi bấm ␣ chốt lần nữa",
                "\(cleanBase) + ␣ + ⌫ + \(extraDisplay) + ␣",
                baseTokens + ["␣", "⌫"] + extraTokens + ["␣"]
            )
        ]

        return scenarios.map { item in
            let steps = simulateSteps(
                tokens: item.tokens,
                inputMethod: inputMethod,
                grammarProfile: grammarProfile,
                smartBilingual: smartBilingual,
                simulateAppleAutocorrect: simulateAppleAutocorrect
            )
            let lastStep = steps.last
            return ComparisonScenarioRow(
                id: item.id,
                title: item.title,
                subtitle: item.subtitle,
                keySequenceDisplay: item.display,
                scriptTokens: item.tokens,
                appleTelexOutput: lastStep?.appleTelexOutput ?? "",
                appleAutocorrectNote: lastStep?.appleAutocorrectNote,
                vieLotusOutput: lastStep?.vieLotusOutput ?? "",
                deltaKind: lastStep?.deltaKind ?? .identical,
                steps: steps
            )
        }
    }

    public static func parseScriptTokens(_ script: String) -> [String] {
        var tokens: [String] = []
        for ch in script {
            if ch == " " || ch == "␣" {
                tokens.append("␣")
            } else if ch == "⌫" || ch == "<" {
                tokens.append("⌫")
            } else {
                tokens.append(String(ch))
            }
        }
        return tokens
    }

    public static func simulateSteps(
        tokens: [String],
        inputMethod: InputMethodType = .telex,
        grammarProfile: GrammarProfile = .senFlex,
        smartBilingual: Bool = true,
        simulateAppleAutocorrect: Bool = true
    ) -> [ComparisonStep] {
        let vieSession = InputSessionManager()
        vieSession.setInputMethod(inputMethod)
        vieSession.setGrammarProfile(grammarProfile)
        vieSession.setModernOrthography(true)
        var vieBuffer = ""

        let appleEngine = VietnameseEngine()
        appleEngine.inputMethod = inputMethod
        appleEngine.grammarProfile = .classic
        appleEngine.modernOrthography = true
        appleEngine.simpleTelex = false
        var appleCommittedPrefix = ""
        var appleComposing = ""

        var results: [ComparisonStep] = []

        for (idx, token) in tokens.enumerated() {
            let prevVieBuffer = vieBuffer
            var autocorrectNote: String? = nil

            if token == "␣" {
                if vieSession.isComposing {
                    let action = vieSession.commitWord(smartBilingualEnabled: smartBilingual, boundaryChar: " ")
                    applySessionAction(action, to: &vieBuffer, fallbackAppend: " ", appendTrailingSpaceOnCommit: true)
                } else {
                    vieSession.reset()
                    vieBuffer.append(" ")
                }

                let fullAppleBeforeSpace = appleCommittedPrefix + appleComposing
                if !appleComposing.isEmpty {
                    let lastSpaceIdx = fullAppleBeforeSpace.lastIndex(of: " ")
                    let wordStartIdx = lastSpaceIdx.map { fullAppleBeforeSpace.index(after: $0) } ?? fullAppleBeforeSpace.startIndex
                    let currentFullWord = String(fullAppleBeforeSpace[wordStartIdx...])
                    let prefixBeforeWord = String(fullAppleBeforeSpace[..<wordStartIdx])

                    if simulateAppleAutocorrect,
                       let corrected = appleAutocorrectOnSpace(word: currentFullWord, raw: appleEngine.rawString()) {
                        appleCommittedPrefix = prefixBeforeWord + corrected + " "
                        autocorrectNote = "Autocorrect iOS đổi '\(currentFullWord)' → '\(corrected)'"
                    } else {
                        appleCommittedPrefix = fullAppleBeforeSpace + " "
                    }
                    appleComposing = ""
                    appleEngine.reset()
                } else {
                    appleCommittedPrefix.append(" ")
                    appleEngine.reset()
                }
            } else if token == "⌫" {
                let action = vieSession.handleBackspace()
                switch action {
                case .passThrough, .reset:
                    if !vieBuffer.isEmpty { vieBuffer.removeLast() }
                case .consumed:
                    break
                case let .replace(backspaces, text), let .commit(backspaces, text, _):
                    replaceUTF16Suffix(in: &vieBuffer, backspaces: backspaces, with: text)
                }

                if !appleComposing.isEmpty {
                    if let bs = appleEngine.backspace() {
                        replaceUTF16Suffix(in: &appleComposing, backspaces: bs.backspaces, with: bs.suffix)
                    } else if !appleComposing.isEmpty {
                        appleComposing.removeLast()
                    }
                    if appleEngine.rawString().isEmpty {
                        appleComposing = ""
                    }
                } else if !appleCommittedPrefix.isEmpty {
                    appleCommittedPrefix.removeLast()
                }
            } else if let ch = token.first {
                if vieSession.isWordBoundary(ch) {
                    if vieSession.isComposing {
                        let action = vieSession.commitWord(smartBilingualEnabled: smartBilingual, boundaryChar: ch)
                        applySessionAction(action, to: &vieBuffer, fallbackAppend: "", appendTrailingSpaceOnCommit: false)
                    } else {
                        vieSession.reset()
                    }
                    vieBuffer.append(ch)
                    appleCommittedPrefix += appleComposing + String(ch)
                    appleComposing = ""
                    appleEngine.reset()
                } else {
                    let action = vieSession.handleCharacter(ch)
                    applySessionAction(action, to: &vieBuffer, fallbackAppend: String(ch), appendTrailingSpaceOnCommit: false)

                    if let feed = appleEngine.feed(ch) {
                        replaceUTF16Suffix(in: &appleComposing, backspaces: feed.backspaces, with: feed.suffix)
                    } else {
                        appleComposing.append(ch)
                    }
                }
            }

            let currentAppleOutput = appleCommittedPrefix + appleComposing
            let delta = classifyDelta(
                token: token,
                appleOutput: currentAppleOutput,
                appleAutocorrectNote: autocorrectNote,
                vieOutput: vieBuffer,
                vieRaw: vieSession.rawWord
            )
            let explanation = buildStepExplanation(
                token: token,
                prevVie: prevVieBuffer,
                currVie: vieBuffer,
                currApple: currentAppleOutput,
                autocorrectNote: autocorrectNote,
                delta: delta
            )

            results.append(
                ComparisonStep(
                    stepNumber: idx + 1,
                    keyLabel: token,
                    rawBuffer: vieSession.rawWord,
                    appleTelexOutput: currentAppleOutput,
                    appleAutocorrectNote: autocorrectNote,
                    vieLotusOutput: vieBuffer,
                    deltaKind: delta,
                    explanation: explanation
                )
            )
        }

        return results
    }

    private static func applySessionAction(
        _ action: SessionAction,
        to buffer: inout String,
        fallbackAppend: String,
        appendTrailingSpaceOnCommit: Bool
    ) {
        switch action {
        case .passThrough, .reset:
            buffer.append(fallbackAppend)
        case .consumed:
            break
        case let .replace(backspaces, text):
            replaceUTF16Suffix(in: &buffer, backspaces: backspaces, with: text)
        case let .commit(backspaces, text, _):
            let replacement = appendTrailingSpaceOnCommit ? (text + " ") : text
            replaceUTF16Suffix(in: &buffer, backspaces: backspaces, with: replacement)
        }
    }

    private static func replaceUTF16Suffix(in buffer: inout String, backspaces: Int, with replacement: String) {
        if backspaces > 0 {
            let utf16 = buffer.utf16
            let dropCount = min(backspaces, utf16.count)
            let endIdx = utf16.index(utf16.endIndex, offsetBy: -dropCount)
            if let prefix = String(utf16[..<endIdx]) {
                buffer = prefix
            }
        }
        buffer.append(replacement)
    }

    private static func appleAutocorrectOnSpace(word: String, raw: String) -> String? {
        let lowerWord = word.lowercased()
        let explicitMap: [String: String] = [
            "truỏng": "trưởng",
            "truỏngw": "trưởng",
            "kenh": "kênh",
            "kenhe": "kênh",
            "hòng": "hông",
            "hòngo": "hông",
            "kínhi": "kính",
            "mừngu": "mừng",
            "đườngu": "đường",
            "đuồngo": "đuồng",
            "mẹnhe": "mệnh",
            "miẹnge": "miệng",
            "huóngo": "huống",
            "truổngo": "trưởng"
        ]
        if let mapped = explicitMap[lowerWord] {
            if let first = word.first, first.isUppercase, let mFirst = mapped.first {
                return String(mFirst).uppercased() + String(mapped.dropFirst())
            }
            return mapped
        }
        if lowerWord.hasSuffix("ư") {
            return nil
        }
        if lowerWord.count >= 4,
           !VietnameseSyllableDictionary.shared.isValidSyllable(lowerWord) {
            let stem = String(word.dropLast())
            if !stem.allSatisfy(\.isASCII),
               VietnameseSyllableDictionary.shared.isValidSyllable(stem.lowercased()) {
                return stem
            }
        }
        return nil
    }

    private static func classifyDelta(
        token: String,
        appleOutput: String,
        appleAutocorrectNote: String?,
        vieOutput: String,
        vieRaw: String
    ) -> ComparisonDeltaKind {
        if appleOutput.caseInsensitiveCompare(vieOutput) == .orderedSame && appleAutocorrectNote == nil {
            return .identical
        }
        if appleAutocorrectNote != nil {
            return .vieLotusPreservesIntent
        }
        let vieWords = vieOutput.split(separator: " ")
        let appleWords = appleOutput.split(separator: " ")
        if let lastVie = vieWords.last, let lastApple = appleWords.last,
           lastVie.allSatisfy(\.isASCII), !lastApple.allSatisfy(\.isASCII) {
            return .vieLotusSmartBilingual
        }
        if token != "␣" && token != "⌫" && VietnameseSyllableDictionary.shared.isValidSyllable(String(vieWords.last ?? "")) &&
           !VietnameseSyllableDictionary.shared.isValidSyllable(String(appleWords.last ?? "")) {
            return .vieLotusPostCommitRefine
        }
        return .vieLotusPreservesIntent
    }

    private static func buildStepExplanation(
        token: String,
        prevVie: String,
        currVie: String,
        currApple: String,
        autocorrectNote: String?,
        delta: ComparisonDeltaKind
    ) -> String {
        if token == "␣" {
            if let note = autocorrectNote {
                return "Chốt từ bằng dấu cách: Sen Việt giữ nguyên '\(currVie.trimmingCharacters(in: .whitespaces))', trong khi \(note)."
            }
            if delta == .vieLotusSmartBilingual {
                return "Chốt từ: Smart Bilingual giữ nguyên từ tiếng Anh '\(currVie.trimmingCharacters(in: .whitespaces))'."
            }
            return "Chốt âm tiết và thêm khoảng trắng."
        }
        if token == "⌫" {
            return "Xoá lùi 1 ký tự (từ '\(prevVie)' → '\(currVie)')."
        }
        switch delta {
        case .identical:
            if currVie.count == prevVie.count && currVie != prevVie {
                return "Biến đổi dấu/mũ tại chỗ: '\(prevVie)' → '\(currVie)'."
            }
            return "Nhịp phím '\(token)': '\(prevVie)' → '\(currVie)' (khớp 100% Apple Telex)."
        case .vieLotusSmartBilingual:
            return "Sen Việt phát hiện cấu trúc tiếng Anh nên giữ nguyên '\(currVie)', còn Apple Telex biến đổi thành '\(currApple)'."
        case .vieLotusPostCommitRefine:
            return "Sen Việt khôi phục âm tiết vừa chốt để ghép dấu thành '\(currVie)' (Apple Telex tách rời thành '\(currApple)')."
        case .vieLotusPreservesIntent, .vieLotusFlexibleOrder:
            return "Sen Việt xử lý thành '\(currVie)' (Apple Telex: '\(currApple)')."
        }
    }
}
#endif
