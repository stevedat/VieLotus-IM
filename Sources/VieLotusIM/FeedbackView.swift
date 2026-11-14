import AppKit
import Foundation
import SwiftUI
import VieLotusCore
import VieLotusTrace

enum VieLotusFeedbackKind: String, CaseIterable, Identifiable {
    case wordBug = "word_bug"
    case appCompat = "app_compat"
    case featureRequest = "feature_request"
    case general = "general_feedback"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .wordBug:
            return "character.cursor.ibeam"
        case .appCompat:
            return "macwindow.badge.plus"
        case .featureRequest:
            return "sparkles"
        case .general:
            return "bubble.left.and.text.bubble.right"
        }
    }

    var title: String {
        switch self {
        case .wordBug:
            return "Lỗi gõ từ / Song ngữ"
        case .appCompat:
            return "Tương thích App / Web"
        case .featureRequest:
            return "Đề xuất tính năng"
        case .general:
            return "Góp ý chung"
        }
    }

    var githubLabelPrefix: String {
        switch self {
        case .wordBug:
            return "[Word/Bilingual Bug]"
        case .appCompat:
            return "[App/Web Compat]"
        case .featureRequest:
            return "[Feature Request]"
        case .general:
            return "[Feedback]"
        }
    }
}

struct FeedbackSheetView: View {
    @ObservedObject var prefs: Preferences
    let onClose: () -> Void

    @State private var selectedKind: VieLotusFeedbackKind = .wordBug
    @State private var typedKeys: String = ""
    @State private var actualOutput: String = ""
    @State private var expectedOutput: String = ""
    @State private var appOrTopic: String = ""
    @State private var message: String = ""
    @State private var contactEmail: String = ""
    @State private var includeDiagnostics: Bool = true
    @State private var showDiagnosticPreview: Bool = false
    @State private var statusBanner: String? = nil

    static let githubIssuesNewURL = "https://github.com/stevedat/VieLotus-IM/issues/new"
    static let communityZaloURL = "https://zalo.me/g/6wwyvywyvhsb0n6rwkze"
    static let supportEmail = "eduflows.app@gmail.com"

    private var inputMethodTitle: String {
        prefs.inputMethod == .vni ? "VNI" : "Telex"
    }

    private var systemBadgeText: String {
        "Sen Việt v\(AppInfo.appVersion) (\(AppInfo.buildNumber)) • macOS \(AppInfo.osVersionString) • \(AppInfo.architecture) • \(inputMethodTitle)"
    }

    private var imeDiagnosticBlock: String {
        let tis = InputSourceDoctor.inspect()
        let overrides = prefs.appModeOverrides
        var lines: [String] = []
        lines.append("- **Kiểu gõ (Input Method):** `\(inputMethodTitle)` (`\(prefs.grammarProfile.rawValue)`)")
        lines.append("- **Song ngữ thông minh (Smart Bilingual):** `\(prefs.smartBilingual ? "Bật" : "Tắt")`")
        lines.append("- **Chính tả chuẩn mới (oà, uý):** `\(prefs.modernOrthography ? "Bật" : "Tắt")`")
        lines.append("- **Tối ưu Terminal Direct:** `\(prefs.terminalDirectMode ? "Bật" : "Tắt")`")
        lines.append("- **Chế độ hiển thị (Presentation Mode):** `\(prefs.presentationModePreference.rawValue)`")
        lines.append("- **Trạng thái TIS Input Source:** `\(tis.summaryTitle) (conflict=\(tis.hasAnyInputConflict))`")
        lines.append("- **Số lượng cụm gõ tắt (Macros):** `\(MacroEngine.shared.getMacroEntries().count)`")
        if overrides.isEmpty {
            lines.append("- **Tuỳ chỉnh theo ứng dụng (App Overrides):** `Mặc định tự động (0 overrides)`")
        } else {
            lines.append("- **Tuỳ chỉnh theo ứng dụng (\(overrides.count)):**")
            for (bundleID, mode) in overrides.sorted(by: { $0.key < $1.key }).prefix(15) {
                lines.append("  • `\(bundleID)` → `\(mode.rawValue)`")
            }
        }
        return lines.joined(separator: "\n")
    }

    private var compiledMarkdownReport: String {
        let trimmedKeys = typedKeys.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedActual = actualOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExpected = expectedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTopic = appOrTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMsg = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)

        let headerTopic: String
        if !trimmedKeys.isEmpty {
            headerTopic = "Gõ `\(trimmedKeys)` ra `\(trimmedActual.isEmpty ? "?" : trimmedActual)` (mong muốn `\(trimmedExpected.isEmpty ? "?" : trimmedExpected)`)"
        } else if !trimmedTopic.isEmpty {
            headerTopic = trimmedTopic
        } else {
            headerTopic = selectedKind.title
        }

        var lines: [String] = []
        lines.append("### \(selectedKind.githubLabelPrefix) \(headerTopic)")
        lines.append("")

        if !trimmedKeys.isEmpty || !trimmedActual.isEmpty || !trimmedExpected.isEmpty {
            lines.append("- **Chuỗi phím đã gõ (Typed Keys):** `\(trimmedKeys.isEmpty ? "—" : trimmedKeys)`")
            lines.append("- **Sen Việt hiện ra (Actual Output):** `\(trimmedActual.isEmpty ? "—" : trimmedActual)`")
            lines.append("- **Kết quả mong muốn (Expected Output):** `\(trimmedExpected.isEmpty ? "—" : trimmedExpected)`")
        }
        if !trimmedTopic.isEmpty {
            lines.append("- **Ứng dụng / Chủ đề (App / Topic):** `\(trimmedTopic)`")
        }
        if !trimmedEmail.isEmpty {
            lines.append("- **Email liên hệ (Contact):** `\(trimmedEmail)`")
        }
        if !trimmedMsg.isEmpty {
            lines.append("")
            lines.append("**Mô tả chi tiết / Description:**")
            lines.append(trimmedMsg)
            lines.append("")
        }

        if includeDiagnostics {
            lines.append("- **Phiên bản & Hệ điều hành (System):** `\(systemBadgeText)`")
            lines.append("")
            lines.append("<details>")
            lines.append("<summary><strong>Thông số Cấu hình & Chẩn đoán Bộ gõ (IME Diagnostics)</strong></summary>")
            lines.append("")
            lines.append(imeDiagnosticBlock)
            lines.append("")
            lines.append("</details>")
        }

        return lines.joined(separator: "\n")
    }

    private var compiledIssueTitle: String {
        let trimmedKeys = typedKeys.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedActual = actualOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExpected = expectedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTopic = appOrTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMsg = message.trimmingCharacters(in: .whitespacesAndNewlines)

        let summary: String
        if !trimmedKeys.isEmpty {
            summary = "Gõ \"\(trimmedKeys)\" ra \"\(trimmedActual.isEmpty ? "?" : trimmedActual)\" (mong muốn \"\(trimmedExpected.isEmpty ? "?" : trimmedExpected)\")"
        } else if !trimmedTopic.isEmpty {
            summary = trimmedTopic
        } else if !trimmedMsg.isEmpty {
            let firstLine = trimmedMsg.components(separatedBy: .newlines).first ?? trimmedMsg
            summary = String(firstLine.prefix(64))
        } else {
            summary = selectedKind.title
        }
        return "\(selectedKind.githubLabelPrefix) \(summary) (v\(AppInfo.appVersion))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.indigo)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Góp ý & Báo lỗi nhanh")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Báo lỗi gõ từ song ngữ, tương thích ứng dụng hoặc đề xuất tính năng mới.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // System Metadata Pill
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)
                Text(systemBadgeText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.05))
            )

            // Category Selector
            VStack(alignment: .leading, spacing: 6) {
                Text("Loại phản hồi")
                    .font(.system(size: 12, weight: .semibold))

                HStack(spacing: 6) {
                    ForEach(VieLotusFeedbackKind.allCases) { kind in
                        let isSelected = selectedKind == kind
                        Button {
                            selectedKind = kind
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: kind.iconName)
                                    .font(.system(size: 11))
                                Text(kind.title)
                                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(isSelected ? Color.indigo.opacity(0.16) : Color(NSColor.controlBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(isSelected ? Color.indigo.opacity(0.55) : Color.primary.opacity(0.08), lineWidth: 1)
                            )
                            .foregroundStyle(isSelected ? Color.indigo : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Structured Word Report Row (for Word / Bilingual or App Compat bugs)
            if selectedKind == .wordBug || selectedKind == .appCompat {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Phím đã gõ (Tuỳ chọn)")
                            .font(.system(size: 11, weight: .medium))
                        TextField("VD: just, cos...", text: $typedKeys)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sen Việt hiện ra")
                            .font(.system(size: 11, weight: .medium))
                        TextField("VD: jút...", text: $actualOutput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mong muốn đúng")
                            .font(.system(size: 11, weight: .medium))
                        TextField("VD: just...", text: $expectedOutput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }
                }
            }

            // App / Subject + Optional Email
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ứng dụng / Trang web hoặc Chủ đề (Tuỳ chọn)")
                        .font(.system(size: 11.5, weight: .medium))
                    TextField("VD: Safari, Zalo, Chrome, Ghostty, VS Code...", text: $appOrTopic)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Email liên hệ (Tuỳ chọn)")
                        .font(.system(size: 11.5, weight: .medium))
                    TextField("you@example.com", text: $contactEmail)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .frame(width: 205)
                }
            }

            // Description TextEditor
            VStack(alignment: .leading, spacing: 4) {
                Text("Nội dung chi tiết")
                    .font(.system(size: 11.5, weight: .medium))

                TextEditor(text: $message)
                    .font(.system(size: 12.5))
                    .frame(minHeight: 84, maxHeight: 115)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color(NSColor.textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.primary.opacity(0.14), lineWidth: 1)
                    )
            }

            // Auto-Diagnostics Toggle & Preview
            VStack(alignment: .leading, spacing: 6) {
                Text("Không gửi tự động. Khi chọn một nút bên dưới, báo cáo có thể gồm nội dung đã nhập và cấu hình chẩn đoán; GitHub hoặc email có thể nhận nội dung qua URL. Báo cáo cũng được sao chép vào Clipboard. Hãy xem trước và xóa dữ liệu nhạy cảm.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Toggle(
                        "Đính kèm cấu hình bộ gõ & trạng thái hệ thống",
                        isOn: $includeDiagnostics
                    )
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11.5))

                    Spacer()

                    Button(showDiagnosticPreview ? "Ẩn bản xem trước" : "Xem dữ liệu đính kèm") {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showDiagnosticPreview.toggle()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.indigo)
                }

                if showDiagnosticPreview {
                    ScrollView {
                        Text(compiledMarkdownReport)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(8)
                    }
                    .frame(height: 90)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.05))
                    )
                }
            }

            if let banner = statusBanner {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(banner)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.green.opacity(0.12))
                )
            }

            Divider()

            // Action Buttons (Copy, Zalo Community, Email, GitHub 1-Click)
            HStack(spacing: 8) {
                Button {
                    copyReportToClipboard()
                    statusBanner = "Đã sao chép báo cáo kèm thông số chẩn đoán vào Clipboard!"
                } label: {
                    Label("Sao chép", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button {
                    copyReportToClipboard()
                    statusBanner = "Đã chép báo cáo vào Clipboard! Hãy nhấn ⌘V (Dán) vào nhóm Zalo Hỗ trợ."
                    if let url = URL(string: Self.communityZaloURL) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Chép & Mở Zalo", systemImage: "bubble.left.and.bubble.right.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button {
                    copyReportToClipboard()
                    var comps = URLComponents()
                    comps.scheme = "mailto"
                    comps.path = Self.supportEmail
                    comps.queryItems = [
                        URLQueryItem(name: "subject", value: compiledIssueTitle),
                        URLQueryItem(name: "body", value: compiledMarkdownReport)
                    ]
                    if let url = comps.url {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Gửi Email", systemImage: "envelope.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Spacer()

                Button {
                    copyReportToClipboard()
                    var comps = URLComponents(string: Self.githubIssuesNewURL)
                    comps?.queryItems = [
                        URLQueryItem(name: "title", value: compiledIssueTitle),
                        URLQueryItem(name: "body", value: compiledMarkdownReport)
                    ]
                    if let url = comps?.url {
                        NSWorkspace.shared.open(url)
                    }
                    statusBanner = "Đã mở GitHub Issues (điền sẵn thông số) và sao chép dự phòng vào Clipboard!"
                } label: {
                    Label("Gửi lên GitHub Issues", systemImage: "paperplane.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .controlSize(.regular)
            }
        }
        .padding(18)
        .frame(width: 660)
    }

    private func copyReportToClipboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(compiledMarkdownReport, forType: .string)
    }
}
