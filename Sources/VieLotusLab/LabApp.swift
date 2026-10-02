import AppKit
import ApplicationServices
import SwiftUI
import VieLotusCore
import UniformTypeIdentifiers
import VieLotusTrace

private enum TraceChannel: String, CaseIterable, Identifiable {
    case sandbox = "Ô thử nghiệm"
    case external = "Theo dõi ứng dụng"
    case replay = "Giả lập Engine"
    var id: String { rawValue }
}

private struct TraceEntry: Identifiable, Codable {
    var id = UUID()
    var time = Self.timestamp()
    var monotonic: UInt64 = DispatchTime.now().uptimeNanoseconds
    var source: String
    var action: String
    var key: String
    var raw: String
    var composing: String
    var committed: String
    var documentBefore = ""
    var documentText = ""
    var operationID = ""
    var selectionBeforeLocation = -1
    var selectionLocation = -1
    var insertedText = ""
    var issue = ""
    var mutationIssue = ""
    var correlationIssue = ""
    var compositionIssue = ""
    var detail: String

    fileprivate static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

private struct TraceTarget: Identifiable, Hashable {
    let name: String
    let bundleID: String
    let category: AppCategory
    var id: String { bundleID }
    var label: String {
        let tag: String
        switch category {
        case .standardAppKit: tag = "AppKit"
        case .chromium: tag = "Chromium"
        case .msOffice: tag = "Office"
        case .terminal: tag = "Terminal"
        case .overlay: tag = "Overlay"
        case .unknown: tag = "Khác"
        }
        return "\(name) [\(tag)] · \(bundleID)"
    }
    var categoryDescription: String {
        switch category {
        case .standardAppKit: return "Standard AppKit / Cocoa"
        case .chromium: return "Chromium / Electron / WebKit"
        case .msOffice: return "Microsoft Office"
        case .terminal: return "Terminal Emulator"
        case .overlay: return "Quick Search / Overlay"
        case .unknown: return "Khác"
        }
    }
}

@MainActor
private final class LabStore: ObservableObject {
    private static let externalTraceSamplingInterval: TimeInterval = 0.04
    @Published var channel: TraceChannel = .sandbox
    @Published var method: InputMethodType = .telex { didSet { session.setInputMethod(method); session.reset() } }
    @Published var modern = true { didSet { session.setModernOrthography(modern); session.reset() } }
    @Published var smartBilingual = true
    @Published var traceEnabled = false
    @Published var entries: [TraceEntry] = []
    @Published var committed = ""
    @Published var liveText = ""
    @Published var liveSelection = "0,0"
    @Published var status = "Sẵn sàng"
    @Published var issueCount = 0
    @Published var lastIssue = ""
    @Published var traceTargets: [TraceTarget] = []
    @Published var selectedTargetBundleID = ""
    @Published var accessibilityTrusted = AXIsProcessTrusted()
    @Published var externalMonitorNote = ""
    var activeExternalTarget: String? { externalTargetBundleID }

    func clearLog() {
        session.reset()
        committed = ""
        entries.removeAll()
        issueCount = 0
        lastIssue = ""
        status = traceEnabled ? (externalTargetBundleID != nil ? "Đang theo dõi ứng dụng" : "Đang ghi trực tiếp") : "Sẵn sàng"
    }

    func feedString(_ text: String) {
        for char in text {
            press(String(char))
        }
    }

    let session = InputSessionManager()
    private var traceID: String?
    private var traceHeartbeat: Timer?
    private var externalTraceTimer: Timer?
    private var externalTargetBundleID: String?
    private var previousExternalText: String?
    private var previousExternalSelection = NSRange(location: NSNotFound, length: 0)
    private var previousFocusedElementHash: CFHashCode?
    private var lastAXDiagnosticKey: String?
    private var traceSpoolOffset: UInt64 = 0
    private let center = DistributedNotificationCenter.default()
    private var activeObserver: NSObjectProtocol?
    private var accessibilityCheckTimer: Timer?

    init() {
        LabTraceSpool.cleanupStaleTraces()
        session.setModernOrthography(true)
        refreshTraceTargets()
        checkAccessibilityState(prompt: false)

        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.checkAccessibilityState(prompt: false)
            }
        }
    }

    deinit {
        center.removeObserver(self)
        accessibilityCheckTimer?.invalidate()
        if let activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
        }
    }

    var raw: String { session.rawWord }
    var composing: String { session.currentOutput() }

    func press(_ key: String) {
        switch key {
        case "⌫":
            let before = session.composingWord
            let action = session.handleBackspace()
            record("backspace", key, before: before, action: describe(action))
        case "Space", "↵":
            let before = session.composingWord
            let action = session.commitWord(smartBilingualEnabled: smartBilingual)
            let text: String
            if case let .commit(_, value, _) = action { text = value } else { text = "" }
            committed += text + (key == "Space" ? " " : "\n")
            record("commit", key, before: before, action: describe(action))
        case "Clear":
            session.reset()
            committed = ""
            entries.removeAll()
            issueCount = 0
            lastIssue = ""
            status = traceEnabled ? "Đang ghi trực tiếp ô thử nghiệm" : "Sẵn sàng"
        default:
            guard let character = key.first else { return }
            let before = session.composingWord
            let action = session.handleCharacter(character)
            record("key", key, before: before, action: describe(action))
        }
    }

    func startTrace() {
        beginTrace(targetBundleID: nil)
    }

    func refreshTraceTargets() {
        let ownBundleID = Bundle.main.bundleIdentifier
        let running = NSWorkspace.shared.runningApplications.compactMap { app -> TraceTarget? in
            guard app.activationPolicy == .regular,
                  let bundleID = app.bundleIdentifier,
                  bundleID != ownBundleID,
                  bundleID != "org.vielotus.inputmethod.VieLotusIM",
                  let name = app.localizedName else { return nil }
            return TraceTarget(name: name, bundleID: bundleID, category: ClientAdapter.classify(bundleIdentifier: bundleID))
        }
        traceTargets = Dictionary(running.map { ($0.bundleID, $0) }, uniquingKeysWith: { first, _ in first })
            .values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if !traceTargets.contains(where: { $0.bundleID == selectedTargetBundleID }) {
            selectedTargetBundleID = traceTargets.first?.bundleID ?? ""
        }
        checkAccessibilityState(prompt: false)
    }

    func checkAccessibilityState(prompt: Bool = false) {
        if prompt {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            accessibilityTrusted = AXIsProcessTrustedWithOptions(options)
        } else {
            accessibilityTrusted = AXIsProcessTrusted()
        }
        if accessibilityTrusted {
            stopAccessibilityPolling()
            if externalMonitorNote.contains("Chưa bật quyền") || externalMonitorNote.isEmpty {
                externalMonitorNote = "Đã kết nối Trợ năng. Hãy chọn app và nhấn 'Bắt đầu theo dõi'"
            }
        } else {
            startAccessibilityPolling()
            externalMonitorNote = "Chưa bật quyền Trợ năng cho VieLotus Lab trong Cài đặt hệ thống"
        }
    }

    func startAccessibilityPolling() {
        guard accessibilityCheckTimer == nil else { return }
        accessibilityCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                let trusted = AXIsProcessTrusted()
                if trusted != self.accessibilityTrusted {
                    self.accessibilityTrusted = trusted
                    if trusted {
                        self.stopAccessibilityPolling()
                        self.externalMonitorNote = "Đã kết nối Trợ năng. Hãy chọn app và nhấn 'Bắt đầu theo dõi'"
                    }
                }
            }
        }
    }

    func stopAccessibilityPolling() {
        accessibilityCheckTimer?.invalidate()
        accessibilityCheckTimer = nil
    }

    func requestAccessibilityAccess() {
        checkAccessibilityState(prompt: true)
    }

    func openSystemSettingsAccessibility() {
        checkAccessibilityState(prompt: true)
        startAccessibilityPolling()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func startExternalTrace() {
        checkAccessibilityState(prompt: false)
        guard accessibilityTrusted else {
            openSystemSettingsAccessibility()
            return
        }
        guard !selectedTargetBundleID.isEmpty else {
            status = "Vui lòng chọn một ứng dụng đang chạy trước"
            return
        }
        externalTargetBundleID = selectedTargetBundleID
        previousExternalText = nil
        previousExternalSelection = NSRange(location: NSNotFound, length: 0)
        previousFocusedElementHash = nil
        lastAXDiagnosticKey = nil
        guard beginTrace(targetBundleID: selectedTargetBundleID) else { return }
        status = "Đang theo dõi · \(selectedTargetBundleID)"
        externalMonitorNote = "Đã bắt đầu theo dõi. Hãy chuyển sang \(selectedTargetBundleID) và gõ thử vào ô nhập"
        append(TraceEntry(source: "Lab", action: "external trace started", key: "", raw: "",
                          composing: "", committed: "",
                          detail: "target=\(selectedTargetBundleID) accessibility=granted"))
        externalTraceTimer = Timer.scheduledTimer(withTimeInterval: Self.externalTraceSamplingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.captureExternalSnapshot() }
        }
        captureExternalSnapshot()
    }

    @discardableResult
    private func beginTrace(targetBundleID: String?) -> Bool {
        stopTrace()
        let newTraceID = UUID().uuidString
        if targetBundleID != nil {
            do {
                try LabTraceSpool.prepare(traceID: newTraceID)
                try LabTraceSpool.activate(traceID: newTraceID, targetBundleID: targetBundleID!)
            } catch {
                status = "Could not start local trace queue: \(error.localizedDescription)"
                return false
            }
        }
        traceID = newTraceID
        traceSpoolOffset = 0
        traceEnabled = true
        externalTargetBundleID = targetBundleID
        status = targetBundleID == nil ? "Trace active · Lab host" : "Trace active · \(targetBundleID!)"
        broadcastTraceStart()
        traceHeartbeat = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.broadcastTraceStart() }
        }
        return true
    }

    func stopTrace() {
        drainTraceEvents()
        traceHeartbeat?.invalidate()
        traceHeartbeat = nil
        externalTraceTimer?.invalidate()
        externalTraceTimer = nil
        if let traceID {
            center.post(name: Notification.Name("org.vielotus.inputmethod.vielotuslab.trace.stop"), object: nil,
                        userInfo: ["traceID": traceID])
            LabTraceSpool.deactivate(traceID: traceID)
            LabTraceSpool.remove(traceID: traceID)
        }
        traceID = nil
        traceEnabled = false
        externalTargetBundleID = nil
        previousExternalText = nil
        lastAXDiagnosticKey = nil
        externalMonitorNote = ""
        status = "Trace off"
    }

    private func broadcastTraceStart() {
        guard let traceID else { return }
        center.post(name: Notification.Name("org.vielotus.inputmethod.vielotuslab.trace.start"), object: nil,
                    userInfo: ["traceID": traceID, "targetBundleID": externalTargetBundleID ?? ""])
    }

    private func captureExternalSnapshot() {
        drainTraceEvents()
        guard let targetBundleID = externalTargetBundleID else { return }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == targetBundleID else {
            let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "chưa rõ"
            resetExternalBaseline()
            externalMonitorNote = "Đang đợi ứng dụng mục tiêu được đưa lên trước (hiện tại: \(frontmost))"
            return
        }
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == targetBundleID && !$0.isTerminated
        }) else {
            resetExternalBaseline()
            recordAXDiagnostic("target-not-running", target: targetBundleID,
                               message: "Tiến trình ứng dụng đã chọn không còn chạy")
            return
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let focusedElement = focusedTextElement(in: appElement)
        guard let focusedElementValue = focusedElement.element else {
            resetExternalBaseline()
            let message: String
            switch focusedElement.error {
            case .noValue:
                message = "Chưa tìm thấy ô nhập được focus; hãy nhấp chuột vào ô văn bản của app mục tiêu"
            case .apiDisabled:
                checkAccessibilityState(prompt: false)
                message = "Quyền Trợ năng (Accessibility) bị tắt đối với VieLotus Lab"
            default:
                message = "Không thể truy vấn ô nhập qua Trợ năng (lỗi \(focusedElement.error.rawValue))"
            }
            recordAXDiagnostic("focused-element-\(focusedElement.error.rawValue)", target: targetBundleID,
                               message: message)
            return
        }
        let element = focusedElementValue
        let focusedHash = CFHash(element)

        let role = stringAttribute(kAXRoleAttribute as CFString, from: element) ?? "unknown"
        let subrole = stringAttribute(kAXSubroleAttribute as CFString, from: element) ?? ""
        if subrole == (kAXSecureTextFieldSubrole as String) {
            resetExternalBaseline()
            captureSecureField(targetBundleID: targetBundleID, role: role, subrole: subrole)
            return
        }
        guard let text = stringAttribute(kAXValueAttribute as CFString, from: element) else {
            resetExternalBaseline()
            let role = stringAttribute(kAXRoleAttribute as CFString, from: element) ?? "unknown"
            recordAXDiagnostic("value-unavailable-\(focusedHash)", target: targetBundleID,
                               message: "Ô điều khiển (\(role)) không cung cấp thuộc tính AXValue")
            return
        }
        lastAXDiagnosticKey = nil
        externalMonitorNote = "Đang bắt nhịp con trỏ và nội dung văn bản"
        let selection = selectedRange(from: element)
        if previousFocusedElementHash != focusedHash || previousExternalText == nil {
            previousFocusedElementHash = focusedHash
            previousExternalText = text
            previousExternalSelection = selection
            externalMonitorNote = "Đã bắt được ô nhập (\(role)). Hãy gõ thử để theo dõi biến đổi"
            let initialSummary = text.isEmpty ? "ô trống" : "có sẵn \(text.count) ký tự (đã ẩn nội dung)"
            append(TraceEntry(source: "Host", action: "AX focused control snapshot", key: "", raw: "",
                              composing: "", committed: "", documentText: "",
                              selectionLocation: selection.location,
                              detail: "target=\(targetBundleID) role=\(role) subrole=\(subrole) initial=\(initialSummary)"))
            return
        }
        guard text != previousExternalText || selection != previousExternalSelection else { return }
        let before = previousExternalText ?? text
        let beforeSelection = previousExternalSelection
        previousExternalText = text
        previousExternalSelection = selection
        let delta = computeTextDelta(from: before, to: text)
        captureHost("AX value/selection changed", before: before, after: text,
                    selectionBefore: beforeSelection, selectionAfter: selection,
                    operationID: UUID().uuidString,
                    detail: "target=\(targetBundleID) role=\(role) subrole=\(subrole) \(delta.summary)",
                    insertedText: delta.inserted)
    }

    private func focusedTextElement(in appElement: AXUIElement) -> (element: AXUIElement?, error: AXError) {
        if let focused = copyElement(kAXFocusedUIElementAttribute as CFString, from: appElement) {
            if exposesTextValue(focused) { return (focused, .success) }

            // Some Electron/Chromium apps expose a focused wrapper while the editable node is below it.
            if let editable = descendantTextElement(of: focused, depth: 0) { return (editable, .success) }
        }

        guard let window = copyElement(kAXFocusedWindowAttribute as CFString, from: appElement) else {
            return (nil, .noValue)
        }
        if exposesTextValue(window) { return (window, .success) }
        guard let descendant = descendantTextElement(of: window, depth: 0) else {
            return (nil, .noValue)
        }
        return (descendant, .success)
    }

    private func resetExternalBaseline() {
        previousExternalText = nil
        previousExternalSelection = NSRange(location: NSNotFound, length: 0)
        previousFocusedElementHash = nil
    }

    private func copyElement(_ attribute: CFString, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func exposesTextValue(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success else {
            return false
        }
        return value is String
    }

    private func descendantTextElement(of element: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth < 5 else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else { return nil }
        for child in children {
            if exposesTextValue(child) { return child }
            if let match = descendantTextElement(of: child, depth: depth + 1) { return match }
        }
        return nil
    }

    private func captureSecureField(targetBundleID: String, role: String, subrole: String) {
        guard previousExternalText != "<secure>" else { return }
        previousExternalText = "<secure>"
        previousExternalSelection = NSRange(location: NSNotFound, length: 0)
        externalMonitorNote = "Secure field detected; content is not captured"
        captureHost("AX secure field skipped", before: "", after: "<secure text not captured>",
                    selectionBefore: NSRange(location: NSNotFound, length: 0),
                    selectionAfter: NSRange(location: NSNotFound, length: 0),
                    operationID: UUID().uuidString,
                    detail: "target=\(targetBundleID) role=\(role) subrole=\(subrole)")
    }

    private func recordAXDiagnostic(_ key: String, target: String, message: String) {
        externalMonitorNote = message
        guard lastAXDiagnosticKey != key else { return }
        lastAXDiagnosticKey = key
        append(TraceEntry(source: "Host", action: "AX unavailable", key: "", raw: "", composing: "",
                          committed: "", detail: "target=\(target) \(message)"))
    }

    private func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    private func selectedRange(from element: AXUIElement) -> NSRange {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString,
                                            &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return NSRange(location: NSNotFound, length: 0)
        }
        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else { return NSRange(location: NSNotFound, length: 0) }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return NSRange(location: NSNotFound, length: 0) }
        return NSRange(location: range.location, length: range.length)
    }

    private func computeTextDelta(from before: String, to after: String) -> (summary: String, removed: String, inserted: String) {
        let old = before as NSString
        let new = after as NSString
        var prefix = 0
        while prefix < min(old.length, new.length), old.character(at: prefix) == new.character(at: prefix) { prefix += 1 }
        var suffix = 0
        while suffix < old.length - prefix, suffix < new.length - prefix,
              old.character(at: old.length - suffix - 1) == new.character(at: new.length - suffix - 1) { suffix += 1 }
        let removed = old.substring(with: NSRange(location: prefix, length: old.length - prefix - suffix))
        let inserted = new.substring(with: NSRange(location: prefix, length: new.length - prefix - suffix))
        return ("deltaAt=\(prefix) removed=\(removed.debugDescription) inserted=\(inserted.debugDescription)", removed, inserted)
    }

    func captureHost(_ action: String, text: String, selection: NSRange) {
        liveText = text
        liveSelection = "\(selection.location),\(selection.length)"
        append(TraceEntry(source: "Host", action: action, key: "", raw: "", composing: "",
                          committed: text, detail: "selection=\(selection.location),\(selection.length)"))
    }

    func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "vielotus-diagnostic-\(Int(Date().timeIntervalSince1970)).json"
        panel.allowedContentTypes = [UTType.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let targetName: String
            let targetCat: String
            if let targetID = externalTargetBundleID {
                let matched = traceTargets.first(where: { $0.bundleID == targetID })
                targetName = matched?.name ?? targetID
                targetCat = matched?.categoryDescription ?? "Ứng dụng ngoài"
            } else {
                targetName = "VieLotus Lab Host"
                targetCat = "Môi trường giả lập"
            }

            var packet: [String: Any] = [
                "diagnostic_schema_version": "1.0",
                "created_at": TraceEntry.timestamp(),
                "environment": [
                    "os_version": AppInfo.osVersionString,
                    "architecture": AppInfo.architecture,
                    "app_version": AppInfo.appVersion,
                    "build_number": AppInfo.buildNumber,
                    "git_commit": AppInfo.gitCommit
                ],
                "ime_settings": [
                    "input_method": method == .telex ? "telex" : "vni",
                    "modern_orthography": modern,
                    "smart_bilingual": smartBilingual
                ],
                "target_application": [
                    "name": targetName,
                    "bundle_id": externalTargetBundleID ?? "org.vielotus.lab.internal",
                    "category": targetCat
                ],
                "reproduction": [
                    "raw_keys": session.rawWord,
                    "composing": session.currentOutput(),
                    "committed": committed,
                    "issue_count": issueCount,
                    "total_events": entries.count
                ]
            ]

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let eventData = try entries.map { entry -> [String: Any] in
                var dict = (try JSONSerialization.jsonObject(with: try encoder.encode(entry)) as? [String: Any]) ?? [:]
                dict.removeValue(forKey: "documentBefore")
                if entry.action == "AX focused control snapshot" {
                    dict["documentText"] = "[REDACTED]"
                }
                return dict
            }
            packet["events"] = eventData

            let finalData = try JSONSerialization.data(withJSONObject: packet, options: [.prettyPrinted, .sortedKeys])
            try finalData.write(to: url, options: .atomic)
            status = "Đã xuất gói chẩn đoán JSON (\(entries.count) sự kiện)"
        } catch {
            status = "Xuất thất bại: \(error.localizedDescription)"
        }
    }

    func generateReportMarkdown() -> String {
        let targetName: String
        let targetCat: String
        if let targetID = externalTargetBundleID {
            let matched = traceTargets.first(where: { $0.bundleID == targetID })
            targetName = matched?.name ?? targetID
            targetCat = matched?.categoryDescription ?? "Ứng dụng ngoài"
        } else {
            targetName = "Khung soạn thảo VieLotus Lab (Nội bộ)"
            targetCat = "Môi trường giả lập"
        }

        var report = "### 📋 Gói Chẩn Đoán Lỗi VieLotus (Diagnostic Packet)\n\n"
        report += "#### 1. Môi trường kiểm thử (Environment)\n"
        report += "- **macOS:** \(AppInfo.osVersionString) (\(AppInfo.architecture))\n"
        report += "- **VieLotus Lab:** v\(AppInfo.appVersion) (Build \(AppInfo.buildNumber) · `\(AppInfo.gitCommit)`)\n"
        report += "- **Thời gian:** \(TraceEntry.timestamp())\n\n"

        report += "#### 2. Cấu hình bộ gõ (IME Settings)\n"
        report += "- **Kiểu gõ:** \(method == .telex ? "TELEX" : "VNI")\n"
        report += "- **Dấu chuẩn mới (oà/uý):** \(modern ? "Bật" : "Tắt")\n"
        report += "- **Nhận diện tiếng Anh thông minh:** \(smartBilingual ? "Bật" : "Tắt")\n\n"

        report += "#### 3. Ứng dụng mục tiêu (Target Application)\n"
        report += "- **Tên ứng dụng:** \(targetName)\n"
        if let targetID = externalTargetBundleID {
            report += "- **Bundle ID:** `\(targetID)`\n"
        }
        report += "- **Phân loại môi trường:** `\(targetCat)`\n\n"

        report += "#### 4. Dữ liệu thử nghiệm (Reproduction Data)\n"
        if !session.rawWord.isEmpty {
            report += "- **Chuỗi phím thô (Raw keys):** `\(session.rawWord)`\n"
        }
        if !session.composingWord.isEmpty {
            report += "- **Đang hiển thị (Composing):** `\(session.currentOutput())`\n"
        }
        if !committed.isEmpty {
            report += "- **Văn bản đã chốt (Committed):** `\(committed)`\n"
        }
        report += "- **Tổng số sự kiện trace:** \(entries.count) (Cảnh báo bất thường: \(issueCount))\n\n"

        if !entries.isEmpty {
            report += "<details>\n<summary><b>Chi tiết chuỗi sự kiện Trace (Nhấp để mở)</b></summary>\n\n"
            report += "```text\n"
            report += entries.map(humanReadableLine).joined(separator: "\n")
            report += "\n```\n</details>\n\n"
        }

        report += "---\n"
        report += "> 🔒 **Bảo vệ quyền riêng tư:** Báo cáo chỉ chứa các thao tác và phím do tester chủ động nhập trong phiên thử nghiệm của VieLotus Lab. Không lưu nội dung tài liệu có sẵn. Vui lòng rà soát lại trước khi gửi công khai lên GitHub Issue.\n"
        return report
    }

    func copyReport() {
        let report = generateReportMarkdown()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        status = "Đã sao chép gói báo cáo Markdown (\(entries.count) sự kiện)"
    }

    private func humanReadableLine(_ entry: TraceEntry) -> String {
        let time = String(entry.time.suffix(12))
        if entry.source == "Engine" {
            let key = entry.key.isEmpty ? entry.action : entry.key == " " ? "Space" : entry.key
            var line = "\(time) IME: \(entry.action) [\(key)]"
            if !entry.raw.isEmpty { line += " · chuỗi phím: \(entry.raw)" }
            if !entry.composing.isEmpty { line += " · đang hiển thị: \(entry.composing)" }
            if !entry.committed.isEmpty { line += " · đã chốt: \(entry.committed)" }
            if !entry.detail.isEmpty { line += " · \(entry.detail)" }
            return line
        }
        if entry.action == "AX focused control snapshot" {
            return "\(time) Ô nhập được focus · \(entry.detail)"
        }
        if entry.action == "AX value/selection changed" {
            let change: String
            if !entry.insertedText.isEmpty {
                change = "gõ «\(entry.insertedText)»"
            } else {
                change = "thay đổi phím/văn bản"
            }
            let correlation = entry.correlationIssue.isEmpty ? "IMK đồng bộ sự kiện" : entry.correlationIssue
            return "\(time) Ô nhập đổi: \(change) · caret \(entry.selectionLocation) · \(correlation)\(entry.issue.isEmpty ? "" : " · CẦN KIỂM TRA: \(entry.issue)")"
        }
        if !entry.issue.isEmpty { return "\(time) CẦN KIỂM TRA · \(entry.action): \(entry.issue) · \(entry.detail)" }
        return "\(time) \(entry.source): \(entry.action) · \(entry.detail)"
    }

    func displayAction(_ entry: TraceEntry) -> String {
        switch entry.action {
        case "AX focused control snapshot": return "Focused text field"
        case "AX value/selection changed": return "Text changed"
        case "AX secure field skipped": return "Secure field skipped"
        case "AX unavailable": return "Text field unavailable"
        case "keyDown": return "Key received"
        case "feed": return "Composition updated"
        case "directReplace": return "Text replaced"
        case "commitVietnamese": return "Vietnamese word committed"
        case "commitEnglish": return "English word restored"
        case "backspace": return "Backspace"
        case "space": return "Space"
        default: return entry.action
        }
    }

    func displayDetail(_ entry: TraceEntry) -> String {
        if entry.action == "AX focused control snapshot" {
            return "Starting text: «\(entry.documentText.isEmpty ? "(empty)" : entry.documentText)» · \(entry.detail)"
        }
        if entry.action == "AX value/selection changed" {
            let delta = computeTextDelta(from: entry.documentBefore, to: entry.documentText)
            let change = delta.removed.isEmpty ? "Added «\(delta.inserted)»" :
                delta.inserted.isEmpty ? "Deleted «\(delta.removed)»" :
                "Replaced «\(delta.removed)» with «\(delta.inserted)»"
            return "\(change) · now «\(entry.documentText)» · caret \(entry.selectionLocation)"
        }
        return entry.detail
    }

    private func drainTraceEvents() {
        guard let traceID, externalTargetBundleID != nil else { return }
        do {
            let events = try LabTraceSpool.read(traceID: traceID, offset: &traceSpoolOffset)
            for event in events where event.traceID == traceID {
                append(TraceEntry(time: event.time, monotonic: event.monotonic, source: "Engine",
                                  action: event.event, key: event.key, raw: event.raw,
                                  composing: event.composing, committed: "", detail: event.detail))
            }
        } catch {
            recordAXDiagnostic("trace-spool-read", target: externalTargetBundleID ?? "unknown",
                               message: "Cannot read local Engine trace queue: \(error.localizedDescription)")
        }
    }

    private func record(_ event: String, _ key: String, before: String, action: String) {
        append(TraceEntry(source: "Core", action: event, key: key, raw: session.rawWord,
                          composing: session.currentOutput(), committed: committed,
                          detail: "before=\(before) result=\(action)"))
    }

    private func append(_ entry: TraceEntry) {
        entries.append(entry)
        entries.sort { $0.monotonic < $1.monotonic }
        if entries.count > 2000 { entries.removeFirst(entries.count - 2000) }
        refreshIssueSummary()
        guard entry.source == "Host",
              entry.action == "insertText" || entry.action.hasPrefix("doCommand delete") ||
                entry.action == "AX value/selection changed" ||
                (entry.action == "textDidChange" && entry.operationID.isEmpty) else { return }
        let entryID = entry.id
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            self?.reconcileHostEvent(entryID)
        }
    }

    private func reconcileHostEvent(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let host = entries[index]
        let window: UInt64 = 1_000_000_000
        func distance(_ entry: TraceEntry) -> UInt64 {
            entry.monotonic > host.monotonic ? entry.monotonic - host.monotonic : host.monotonic - entry.monotonic
        }
        let expectedClientID = host.detail.split(separator: " ").first(where: { $0.hasPrefix("target=") })
            .map { String($0.dropFirst("target=".count)).lowercased() }
        let nearbyEngine = entries.filter { entry in
            guard entry.source == "Engine", distance(entry) <= window else { return false }
            guard let expectedClientID else { return true }
            return entry.detail.lowercased().contains("client=\(expectedClientID)")
        }
        let engineEntries = entries.filter { $0.source == "Engine" }
        let hasEngineKey = nearbyEngine.contains { $0.action == "keyDown" }
        if engineEntries.isEmpty {
            entries[index].correlationIssue = "No Engine events received in this trace; IMK activity cannot be verified"
        } else if !hasEngineKey {
            entries[index].correlationIssue = "No IMK keyDown near host edit for this client; events may be incomplete or input method may have been bypassed"
        }
        let isHostBoundary = !host.insertedText.isEmpty &&
            host.insertedText.allSatisfy { $0.isWhitespace || $0.isPunctuation }
        if host.action == "insertText", !isHostBoundary,
           let latest = nearbyEngine.filter({ ["feed", "backspace", "commitVietnamese", "commitEnglish"].contains($0.action) })
                .min(by: { distance($0) < distance($1) }),
           latest.action != "commitEnglish", !latest.composing.isEmpty {
            let output = latest.composing as NSString
            let document = host.documentText as NSString
            let caret = host.selectionLocation
            if caret >= output.length, caret <= document.length {
                let visible = document.substring(with: NSRange(location: caret - output.length, length: output.length))
                if visible != latest.composing {
                    entries[index].compositionIssue = "visible text differs from IMK composition: expected \(latest.composing.debugDescription), found \(visible.debugDescription)"
                }
            }
        }
        entries[index].issue = [entries[index].mutationIssue, entries[index].compositionIssue]
            .filter { !$0.isEmpty }.joined(separator: "; ")
        refreshIssueSummary()
    }

    private func refreshIssueSummary() {
        issueCount = entries.reduce(into: 0) { if !$1.issue.isEmpty { $0 += 1 } }
        lastIssue = entries.last(where: { !$0.issue.isEmpty })?.issue ?? ""
        if issueCount > 0 { status = "\(issueCount) trace anomalies · \(lastIssue)" }
    }

    func captureHost(_ action: String, before: String, after: String, selectionBefore: NSRange,
                     selectionAfter: NSRange, operationID: String, detail: String,
                     insertedText: String = "", issue: String = "") {
        liveText = after
        liveSelection = "\(selectionAfter.location),\(selectionAfter.length)"
        let issueText = issue
        append(TraceEntry(source: "Host", action: action, key: "", raw: "", composing: "", committed: "",
                          documentBefore: "", documentText: insertedText, operationID: operationID,
                          selectionBeforeLocation: selectionBefore.location,
                          selectionLocation: selectionAfter.location,
                          insertedText: insertedText,
                          issue: issueText, mutationIssue: issueText,
                          detail: "op=\(operationID.prefix(8)) beforeSelection=\(selectionBefore.location),\(selectionBefore.length) afterSelection=\(selectionAfter.location),\(selectionAfter.length) \(detail)"))
    }

    func captureTextChange(before: String, after: String, selection: NSRange, operationID: String) {
        liveText = after
        liveSelection = "\(selection.location),\(selection.length)"
        let delta = textDelta(from: before, to: after)
        append(TraceEntry(source: "Host", action: "textDidChange", key: "", raw: "", composing: "", committed: "",
                          documentBefore: "", documentText: "", operationID: operationID,
                          selectionLocation: selection.location,
                          detail: "op=\(operationID.prefix(8)) selection=\(selection.location),\(selection.length) delta=\(delta)"))
    }

    private func textDelta(from before: String, to after: String) -> String {
        let old = before as NSString
        let new = after as NSString
        var prefix = 0
        while prefix < min(old.length, new.length), old.character(at: prefix) == new.character(at: prefix) { prefix += 1 }
        var suffix = 0
        while suffix < old.length - prefix, suffix < new.length - prefix,
              old.character(at: old.length - suffix - 1) == new.character(at: new.length - suffix - 1) { suffix += 1 }
        let removed = old.substring(with: NSRange(location: prefix, length: old.length - prefix - suffix))
        let inserted = new.substring(with: NSRange(location: prefix, length: new.length - prefix - suffix))
        return "at=\(prefix) removed=\(removed.debugDescription) inserted=\(inserted.debugDescription)"
    }

    private func describe(_ action: SessionAction) -> String {
        switch action {
        case .passThrough: return "passThrough"
        case .consumed: return "consumed"
        case let .replace(backspaces, text): return "replace(\(backspaces),\(text))"
        case let .commit(backspaces, text, override): return "commit(\(backspaces),\(text),override=\(override))"
        case .reset: return "reset"
        }
    }
}

@main
struct VieLotusLabApp: App {
    var body: some Scene {
        WindowGroup("VieLotus Lab") { LabView().frame(minWidth: 900, minHeight: 650) }
            .windowResizability(.contentSize)
    }
}

private struct LabView: View {
    @StateObject private var store = LabStore()
    @State private var showingReportPreview = false
    @State private var reportPreviewText = ""

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Top Minimalist Navigation & Control Bar
            HStack(spacing: 12) {
                Picker("", selection: $store.channel) {
                    ForEach(TraceChannel.allCases) { channel in
                        Text(channel.rawValue).tag(channel)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 360)

                Spacer()

                // Live Status Indicator Pill
                HStack(spacing: 6) {
                    Circle()
                        .fill(store.issueCount > 0 ? Color.red : (store.traceEnabled ? Color.green : Color.secondary.opacity(0.5)))
                        .frame(width: 7, height: 7)
                    Text(store.issueCount > 0 ? "\(store.issueCount) cảnh báo · \(store.lastIssue)" : store.status)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(store.issueCount > 0 ? .red : .secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.08), in: Capsule())

                // Quick Action Buttons
                Button {
                    reportPreviewText = store.generateReportMarkdown()
                    showingReportPreview = true
                } label: {
                    Label("Xem trước & Báo cáo", systemImage: "doc.text.magnifyingglass")
                }
                .disabled(store.entries.isEmpty)
                .help("Xem trước, biên tập và sao chép báo cáo Markdown để dán vào GitHub Issue")

                Button {
                    store.export()
                } label: {
                    Label("Xuất gói JSON", systemImage: "square.and.arrow.down")
                }
                .disabled(store.entries.isEmpty)
                .help("Xuất toàn bộ gói chẩn đoán JSON để đính kèm Issue hoặc gửi dev phân tích")

                Button {
                    store.clearLog()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(store.entries.isEmpty)
                .help("Xóa toàn bộ nhật ký sự kiện")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // MARK: - Active Workspace Area (3 Focused Modes)
            Group {
                switch store.channel {
                case .sandbox:
                    sandboxView
                case .external:
                    externalView
                case .replay:
                    replayView
                }
            }
            .frame(minHeight: 180, maxHeight: 220)

            Divider()

            // MARK: - Bottom Diagnostic Event Stream Table
            traceView

            Divider()

            // MARK: - Apple Clean Minimalist Footer
            HStack(spacing: 8) {
                Text("v1.1 (Universal) • 100% Cục bộ & Bảo mật")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Link("GitHub", destination: URL(string: "https://github.com/stevedat/VietLotus-IM")!)
                    .font(.system(size: 11, weight: .medium))
                
                Text("•")
                    .foregroundStyle(.tertiary)
                
                Link("YouPersona.com", destination: URL(string: "https://youpersona.com")!)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showingReportPreview) {
            ReportPreviewSheet(text: $reportPreviewText)
        }
    }

    // MARK: - 1. Local Sandbox View
    private var sandboxView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label("Ô soạn thảo thử nghiệm", systemImage: "pencil.line")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("Route: \(adapterName)")
                    .font(.system(size: 10, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                Text("Caret: \(store.liveSelection)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button(store.traceEnabled && store.activeExternalTarget == nil ? "Dừng ghi" : "Bắt đầu ghi",
                       systemImage: store.traceEnabled && store.activeExternalTarget == nil ? "stop.fill" : "record.circle") {
                    store.traceEnabled ? store.stopTrace() : store.startTrace()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(store.traceEnabled && store.activeExternalTarget == nil ? .red : .accentColor)
            }

            LiveTextEditor(store: store)
                .frame(maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )

            HStack {
                Text("💡 Gõ tiếng Việt tại đây với Sen Việt để kiểm tra phản hồi, caret drift và triệt tiêu dấu.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if !store.liveText.isEmpty {
                    Text("\(store.liveText.count) ký tự")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(14)
    }

    // MARK: - 2. External App Trace View
    private var externalView: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "app.connected.to.app.below.fill")
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Theo dõi ứng dụng đang chạy")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Phát hiện xung đột con trỏ, nuốt phím hoặc nhân bản chữ trên app khác.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if store.accessibilityTrusted {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.shield.fill")
                            Text("Quyền Trợ năng: Đã kết nối")
                        }
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.1), in: Capsule())
                    } else {
                        HStack(spacing: 6) {
                            Button("Cấp quyền...", systemImage: "lock.shield") {
                                store.requestAccessibilityAccess()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("Mở Cài đặt hệ thống", systemImage: "arrow.up.forward.app") {
                                store.openSystemSettingsAccessibility()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(.orange)
                        }
                    }
                }

                if !store.accessibilityTrusted {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Chưa bật quyền Trợ năng (Accessibility) cho VieLotus Lab. Nhấn 'Mở Cài đặt hệ thống' và gạt bật công tắc để theo dõi app khác.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }

                Divider().opacity(0.5)

                HStack(spacing: 8) {
                    Picker("Mục tiêu:", selection: $store.selectedTargetBundleID) {
                        ForEach(store.traceTargets) { target in
                            Text(target.label).tag(target.bundleID)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Button {
                        store.refreshTraceTargets()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .controlSize(.small)
                    .help("Làm mới danh sách ứng dụng")

                    Button(store.traceEnabled && store.activeExternalTarget != nil ? "Dừng theo dõi" : "Bắt đầu theo dõi",
                           systemImage: store.traceEnabled && store.activeExternalTarget != nil ? "stop.fill" : "record.circle") {
                        if store.traceEnabled && store.activeExternalTarget != nil {
                            store.stopTrace()
                        } else {
                            store.startExternalTrace()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(store.traceEnabled && store.activeExternalTarget != nil ? .red : .accentColor)
                    .disabled(store.selectedTargetBundleID.isEmpty)
                }

                if !store.externalMonitorNote.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                        Text(store.externalMonitorNote)
                    }
                    .font(.caption2)
                    .foregroundStyle(store.traceEnabled ? .orange : .secondary)
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "lock.shield.fill")
                    Text("Bảo vệ quyền riêng tư (Privacy-First):")
                        .fontWeight(.semibold)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                Text("• Lab chỉ ghi lại phần ký tự do bạn gõ thêm hoặc xóa trong phiên thử, không lưu tài liệu có sẵn.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("• Khuyên dùng: Mở một ô nhập trống hoặc tài liệu mới trong app mục tiêu khi gõ thử để tránh vô tình chụp lại nội dung nhạy cảm.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(14)
        .onAppear {
            store.checkAccessibilityState(prompt: false)
            if !store.accessibilityTrusted {
                store.startAccessibilityPolling()
            }
        }
        .onDisappear {
            store.stopAccessibilityPolling()
        }
    }

    // MARK: - 3. Core Engine Replay View
    private var replayView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Picker("", selection: $store.method) {
                    Text("Telex").tag(InputMethodType.telex)
                    Text("VNI").tag(InputMethodType.vni)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)

                Toggle("Dấu chuẩn mới (oà/uý)", isOn: $store.modern)
                    .toggleStyle(.checkbox)
                    .font(.caption)

                Toggle("Phục hồi tiếng Anh thông minh", isOn: $store.smartBilingual)
                    .toggleStyle(.checkbox)
                    .font(.caption)

                Spacer()

                Button("Đặt lại", systemImage: "arrow.counterclockwise") {
                    store.session.reset()
                    store.committed = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(spacing: 10) {
                stateCard("PHÍM THÔ (RAW)", store.raw.isEmpty ? "—" : store.raw, color: .secondary)
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                stateCard("KẾT XUẤT FSM", store.composing.isEmpty ? "—" : store.composing, color: .accentColor)
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                stateCard("TỪ ĐÃ CHỐT", store.committed.isEmpty ? "—" : store.committed, color: .green)
            }

            HStack(spacing: 6) {
                Text("Mẫu thử nhanh:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(["việt nam", "toán học", "superadmin", "MAX_SIZE", "user", "tuyển"], id: \.self) { sample in
                    Button(sample) {
                        store.feedString(sample + " ")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                Spacer()
                Button("⌫ Xóa lùi") { store.press("⌫") }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                Button("␣ Space") { store.press("Space") }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
        }
        .padding(14)
    }

    // MARK: - State Metric Card
    private func stateCard(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.8)
        )
    }

    // MARK: - Diagnostic Event Table
    private var traceView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Label("Nhật ký sự kiện thời gian thực", systemImage: "waveform.path.ecg")
                    .font(.system(size: 11, weight: .semibold))
                Text("\(store.entries.count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.12), in: Capsule())

                if store.issueCount > 0 {
                    Label("\(store.issueCount) phát hiện", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.red, in: Capsule())
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

            Divider()

            if store.entries.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("Chưa có sự kiện nào được ghi nhận")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Bắt đầu gõ hoặc kích hoạt theo dõi để xem nhịp phím và biến đổi văn bản.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
            } else {
                Table(store.entries.reversed()) {
                    TableColumn("Thời gian") { entry in
                        Text(String(entry.time.suffix(12))).monospaced().foregroundStyle(.secondary)
                    }.width(85)
                    TableColumn("Nguồn") { entry in
                        Text(entry.source)
                            .font(.system(size: 11, weight: .medium))
                    }.width(55)
                    TableColumn("Sự kiện") { entry in
                        Text(store.displayAction(entry))
                            .lineLimit(1)
                    }.width(130)
                    TableColumn("Phím") { entry in
                        Text(entry.key.isEmpty ? "—" : entry.key)
                            .font(.system(size: 11, design: .monospaced))
                    }.width(40)
                    TableColumn("Phím thô") { entry in
                        Text(entry.raw.isEmpty ? "—" : entry.raw)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }.width(75)
                    TableColumn("Hiển thị / Bộ đệm") { entry in
                        Text(!entry.composing.isEmpty ? entry.composing : (!entry.documentText.isEmpty ? entry.documentText : entry.committed))
                            .lineLimit(1)
                    }.width(min: 90, ideal: 140)
                    TableColumn("Chi tiết biến đổi") { entry in
                        Text(store.displayDetail(entry))
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }.width(min: 140, ideal: 240)
                    TableColumn("Đánh giá") { entry in
                        if !entry.issue.isEmpty {
                            Label(entry.issue, systemImage: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                                .lineLimit(1)
                        } else {
                            Text("—").foregroundStyle(.tertiary)
                        }
                    }.width(min: 70, ideal: 110)
                }
                .font(.system(size: 11))
            }
        }
    }

    private var adapterName: String {
        switch ClientAdapter.classify(bundleIdentifier: Bundle.main.bundleIdentifier) {
        case .standardAppKit: return "AppKit"
        case .chromium: return "Chromium route"
        case .msOffice: return "Office route"
        case .terminal: return "Terminal route"
        case .overlay: return "Overlay route"
        case .unknown: return "Unknown"
        }
    }
}

private struct LiveTextEditor: NSViewRepresentable {
    @ObservedObject var store: LabStore

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        let text = LabTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 220))
        text.isRichText = false
        text.isEditable = true
        text.isSelectable = true
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.minSize = NSSize(width: 0, height: 0)
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.autoresizingMask = [.width]
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.font = .monospacedSystemFont(ofSize: 17, weight: .regular)
        text.delegate = context.coordinator
        text.labStore = store
        scroll.documentView = text
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let text = nsView.documentView as? LabTextView else { return }
        text.labStore = store
    }
    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let store: LabStore
        init(store: LabStore) { self.store = store }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            store.captureTextChange(before: store.liveText, after: view.string,
                                    selection: view.selectedRange(), operationID: (view as? LabTextView)?.activeOperationID ?? "")
        }
    }
}

private final class LabTextView: NSTextView {
    weak var labStore: LabStore?
    fileprivate var activeOperationID = ""

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let before = string
        let selectionBefore = selectedRange()
        let operationID = UUID().uuidString
        let inserted = (insertString as? String) ?? (insertString as? NSAttributedString)?.string ?? ""
        let effectiveRange = replacementRange.location == NSNotFound ? selectionBefore : replacementRange
        let oldNSString = before as NSString
        let validRange = effectiveRange.location != NSNotFound && effectiveRange.location >= 0 &&
            effectiveRange.length >= 0 && NSMaxRange(effectiveRange) <= oldNSString.length
        let expected = validRange
            ? oldNSString.replacingCharacters(in: effectiveRange, with: inserted)
            : nil
        activeOperationID = operationID
        super.insertText(insertString, replacementRange: replacementRange)
        activeOperationID = ""
        let after = string
        let selectionAfter = selectedRange()
        var issues: [String] = []
        if !validRange { issues.append("replacement range outside document") }
        if let expected, expected != after { issues.append("insert result differs from expected text") }
        if validRange, expected != after { issues.append("possible lost or duplicated characters") }
        if validRange {
            let expectedCaret = effectiveRange.location + (inserted as NSString).length
            if selectionAfter.length == 0 && selectionAfter.location != expectedCaret {
                issues.append("caret jump: expected \(expectedCaret), got \(selectionAfter.location)")
            }
        }
        labStore?.captureHost("insertText", before: before, after: after, selectionBefore: selectionBefore,
                              selectionAfter: selectionAfter, operationID: operationID,
                              detail: "requestedRange=\(replacementRange.location),\(replacementRange.length) effectiveRange=\(effectiveRange.location),\(effectiveRange.length) inserted=\(inserted.debugDescription)",
                              insertedText: inserted,
                              issue: issues.joined(separator: "; "))
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let before = self.string
        let selectionBefore = self.selectedRange()
        let operationID = UUID().uuidString
        activeOperationID = operationID
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        activeOperationID = ""
        labStore?.captureHost("setMarkedText", before: before, after: self.string, selectionBefore: selectionBefore,
                              selectionAfter: self.selectedRange(), operationID: operationID,
                              detail: "replacementRange=\(replacementRange.location),\(replacementRange.length) selectedRange=\(selectedRange.location),\(selectedRange.length)")
    }

    override func doCommand(by selector: Selector) {
        let before = string
        let selectionBefore = selectedRange()
        let sourceBefore = NSString(string: before)
        let command = NSStringFromSelector(selector)
        let validSelectionBefore = selectionBefore.location != NSNotFound && selectionBefore.location >= 0 &&
            selectionBefore.length >= 0 && NSMaxRange(selectionBefore) <= sourceBefore.length
        let expectedDelete = command == "deleteBackward:" && validSelectionBefore
            ? deletingBackward(from: before, selection: selectionBefore) : nil
        let expectedCaretBefore = expectedCaret(after: command, text: sourceBefore, selection: selectionBefore)
        let operationID = UUID().uuidString
        activeOperationID = operationID
        super.doCommand(by: selector)
        activeOperationID = ""
        let after = string
        let selectionAfter = selectedRange()
        var issues: [String] = []
        if !validSelectionBefore { issues.append("selection outside document before \(command)") }
        if let expectedDelete, expectedDelete != after {
            issues.append("backspace result differs from expected text")
        }
        if let expectedCaret = expectedCaretBefore,
            before != after || command == "moveLeft:" || command == "moveRight:",
            selectionAfter.length == 0, selectionAfter.location != expectedCaret {
            issues.append("caret jump during \(command): expected \(expectedCaret), got \(selectionAfter.location)")
        }
        if selectionAfter.location < 0 || selectionAfter.location > (after as NSString).length ||
            selectionAfter.length < 0 || NSMaxRange(selectionAfter) > (after as NSString).length {
            issues.append("selection outside document after \(command)")
        }
        labStore?.captureHost("doCommand \(command)", before: before, after: after,
                              selectionBefore: selectionBefore, selectionAfter: selectionAfter,
                              operationID: operationID,
                              detail: "command=\(command) beforeSelection=\(selectionBefore.location),\(selectionBefore.length)",
                              issue: issues.joined(separator: "; "))
    }

    private func deletingBackward(from text: String, selection: NSRange) -> String? {
        let source = text as NSString
        guard selection.location != NSNotFound, selection.location >= 0,
              selection.length >= 0, NSMaxRange(selection) <= source.length else { return nil }
        let range: NSRange
        if selection.length > 0 {
            range = selection
        } else if selection.location > 0 {
            range = source.rangeOfComposedCharacterSequence(at: selection.location - 1)
        } else {
            range = NSRange(location: 0, length: 0)
        }
        return source.replacingCharacters(in: range, with: "")
    }

    private func expectedCaret(after command: String, text: NSString, selection: NSRange) -> Int? {
        guard selection.location != NSNotFound, selection.location >= 0,
              selection.length >= 0, NSMaxRange(selection) <= text.length else { return nil }
        switch command {
        case "deleteBackward:":
            if selection.length > 0 { return selection.location }
            guard selection.location > 0 else { return 0 }
            return text.rangeOfComposedCharacterSequence(at: selection.location - 1).location
        case "moveLeft:":
            if selection.length > 0 { return selection.location }
            guard selection.location > 0 else { return 0 }
            return text.rangeOfComposedCharacterSequence(at: selection.location - 1).location
        case "moveRight:":
            if selection.length > 0 { return NSMaxRange(selection) }
            guard selection.location < text.length else { return text.length }
            let range = text.rangeOfComposedCharacterSequence(at: selection.location)
            return NSMaxRange(range)
        default:
            return nil
        }
    }
}

// MARK: - Privacy-First Report Preview & Redaction Sheet
private struct ReportPreviewSheet: View {
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Xem trước & Biên tập Báo cáo Lỗi")
                        .font(.headline)
                    Text("Bạn có toàn quyền kiểm tra, chỉnh sửa hoặc xóa bớt thông tin trước khi sao chép.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Đóng", systemImage: "xmark") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .controlSize(.small)
            }

            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(.orange)
                Text("Bảo vệ quyền riêng tư: Hãy xóa bỏ bất kỳ mật khẩu, email hoặc dữ liệu cá nhân nào nếu vô tình xuất hiện bên dưới.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

            TextEditor(text: $text)
                .font(.system(.caption, design: .monospaced))
                .padding(4)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 1))

            HStack {
                Button {
                    saveMarkdownToFile()
                } label: {
                    Label("Lưu file .md...", systemImage: "square.and.arrow.down")
                }
                .controlSize(.small)

                Spacer()

                Button("Hủy") {
                    dismiss()
                }
                .controlSize(.small)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        dismiss()
                    }
                } label: {
                    Label(copied ? "Đã sao chép!" : "Sao chép vào Clipboard",
                          systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(minWidth: 640, minHeight: 480)
    }

    private func saveMarkdownToFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "vielotus-bug-report-\(Int(Date().timeIntervalSince1970)).md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}

