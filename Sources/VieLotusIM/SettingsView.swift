import VieLotusCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var prefs = Preferences.shared
    @State private var newOverrideBundleID = ""

    private let overrideApps: [(name: String, bundleID: String)] = [
        ("Google Chrome", "com.google.chrome"),
        ("Safari", "com.apple.safari"),
        ("Microsoft Word", "com.microsoft.Word"),
        ("Visual Studio Code", "com.microsoft.vscode"),
        ("Slack", "com.tinyspeck.slackmacgap"),
        ("Discord", "com.hnc.Discord")
    ]

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Apple Minimalist Header
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.indigo.gradient)
                        .frame(width: 56, height: 56)
                    
                    Text("Ṽ")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .offset(y: -2)
                }
                .shadow(color: .indigo.opacity(0.25), radius: 8, x: 0, y: 4)

                VStack(spacing: 2) {
                    Text("Sen Việt")
                        .font(.system(size: 17, weight: .bold))
                    Text("Bộ gõ tiếng Việt thuần chuẩn InputMethodKit")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 12)

            // MARK: - Native Grouped Configuration Form
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("KIỂU GÕ")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        Picker("", selection: $prefs.inputMethod) {
                            Text("Telex").tag(InputMethodType.telex)
                            Text("VNI").tag(InputMethodType.vni)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    .padding(.vertical, 4)
                }

                Section("CÁCH HIỂN THỊ CHỮ ĐANG GÕ") {
                    Picker("Mặc định", selection: $prefs.presentationModePreference) {
                        Text("Tự động (Khuyên dùng)").tag(PresentationModePreference.automatic)
                        Text("Direct Replacement").tag(PresentationModePreference.directReplacement)
                        Text("Marked Text").tag(PresentationModePreference.markedText)
                        Text("Bỏ qua (Passthrough)").tag(PresentationModePreference.passthrough)
                    }

                    Text("Tự động tối ưu theo từng ứng dụng (Direct Replacement không gạch chân cho AppKit/Terminal; Marked Text chuẩn W3C cho Web/Electron chống lặp từ).")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    ForEach(overrideApps, id: \.bundleID) { app in
                        appOverrideRow(name: app.name, bundleID: app.bundleID)
                    }

                    ForEach(customOverrideBundleIDs, id: \.self) { bundleID in
                        appOverrideRow(name: bundleID, bundleID: bundleID)
                    }

                    HStack(spacing: 8) {
                        TextField("Bundle ID ứng dụng", text: $newOverrideBundleID)
                            .textFieldStyle(.roundedBorder)
                        Button("Thêm") { addAppOverride() }
                            .disabled(newOverrideBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section {
                    Toggle(isOn: $prefs.smartBilingual) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Nhận diện tiếng Anh thông minh")
                                .font(.system(size: 13, weight: .medium))
                            Text("Apple Neural Engine tự động gỡ dấu cho từ tiếng Anh")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    Toggle(isOn: $prefs.developerMode) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Chế độ Lập trình viên (Code & Markdown)")
                                .font(.system(size: 13, weight: .medium))
                            Text("Tự động bỏ qua dấu trong cặp backticks ` ` và cú pháp code")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    Toggle(isOn: $prefs.terminalDirectMode) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tối ưu dòng lệnh Terminal (Direct Input)")
                                .font(.system(size: 13, weight: .medium))
                            Text("Truyền ký tự trực tiếp cho auto-completion (Kitty, iTerm2, Alacritty...)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    Toggle(isOn: $prefs.modernOrthography) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dấu chuẩn mới (hoà, thuỷ)")
                                .font(.system(size: 13, weight: .medium))
                            Text("Đặt dấu thanh trên âm chính theo chuẩn hiện đại")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    Toggle(isOn: $prefs.wordSuggestions) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Gợi ý từ ghép thông minh (Quick Prediction)")
                                .font(.system(size: 13, weight: .medium))
                            Text("Hiển thị cửa sổ ứng viên gợi ý từ tiếp theo khi gõ")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    Toggle(isOn: $prefs.macroEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bật bảng gõ tắt (Macro / Shorthand)")
                                .font(.system(size: 13, weight: .medium))
                            Text("Tự động bung từ viết tắt (vn → Việt Nam, sg → Sài Gòn, dc → được)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    Toggle(isOn: $prefs.genZMode) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Chế độ gõ Gen-Z (Teen Code)")
                                .font(.system(size: 13, weight: .medium))
                            Text("Cho phép gõ tắt lóng (fải, bik, thix, mún, đc, ko...)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }


                    Toggle(isOn: $prefs.relaxedCoda) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Viết tắt phụ âm cuối")
                                .font(.system(size: 13, weight: .medium))
                            Text("Gõ nhanh g = ng, h = nh, k = ch")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    if prefs.inputMethod == .telex {
                        Toggle(isOn: $prefs.quickTelex) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Quick Telex")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Gõ cc = ch, gg = gi, qq = qu")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Toggle(isOn: $prefs.passthroughRemoteApps) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bỏ qua ứng dụng Remote / Máy ảo (Passthrough)")
                                .font(.system(size: 13, weight: .medium))
                            Text("Tự động ngắt can thiệp khi dùng RDP, VNC, RustDesk, Parallels để tránh gõ trùng dấu")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    Toggle(isOn: $prefs.enforceABCBaseLayout) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Khóa bàn phím cơ sở chuẩn ABC (QWERTY)")
                                .font(.system(size: 13, weight: .medium))
                            Text("Bảo đảm gõ chuẩn khi dùng bàn phím quốc tế (AZERTY, QWERTZ, Dvorak)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("CHẨN ĐOÁN & HỖ TRỢ")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(AppInfo.systemSummary)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        HStack(spacing: 8) {
                            Button {
                                copyDiagnostics()
                            } label: {
                                Label(copiedDiagnostics ? "Đã sao chép!" : "Sao chép cấu hình",
                                      systemImage: copiedDiagnostics ? "checkmark.circle.fill" : "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button {
                                openGitHubIssue()
                            } label: {
                                Label("Báo lỗi", systemImage: "ladybug")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button {
                                openGitHubDiscussions()
                            } label: {
                                Label("Thảo luận", systemImage: "bubble.left.and.bubble.right")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button {
                                openVieLotusLab()
                            } label: {
                                Label("Mở Lab", systemImage: "waveform.path.ecg")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        Text("🔒 Sen Việt áp dụng Zero-logging: Tuyệt đối không ghi phím gõ. Nhấn 'Sao chép cấu hình' để đính kèm thông số vào GitHub Issue.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .formStyle(.grouped)

            // MARK: - Apple Clean Minimalist Footer
            HStack {
                Text("v\(AppInfo.appVersion) (\(AppInfo.gitCommit)) • Không quyền Trợ năng")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Link("GitHub", destination: URL(string: "https://github.com/stevedat/VieLotus-IM")!)
                    .font(.system(size: 11, weight: .medium))
                
                Text("•")
                    .foregroundColor(.secondary)

                Link("Thảo luận", destination: URL(string: "https://github.com/stevedat/VieLotus-IM/discussions")!)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                
                Text("•")
                    .foregroundColor(.secondary)
                
                Link("YouPersona.com", destination: URL(string: "https://youpersona.com")!)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .frame(width: 460, height: 700)
    }

    @State private var copiedDiagnostics = false

    private var customOverrideBundleIDs: [String] {
        prefs.appModeOverrides.keys
            .filter { bundleID in !overrideApps.contains(where: { $0.bundleID == bundleID }) }
            .sorted()
    }

    private func appOverrideRow(name: String, bundleID: String) -> some View {
        HStack {
            Text(name)
                .lineLimit(1)
            Spacer(minLength: 8)
            Picker("", selection: Binding(
                get: { prefs.appModeOverrides[bundleID] ?? .automatic },
                set: { mode in
                    if mode == .automatic {
                        prefs.appModeOverrides.removeValue(forKey: bundleID)
                    } else {
                        prefs.appModeOverrides[bundleID] = mode
                    }
                }
            )) {
                Text("Tự động").tag(PresentationModePreference.automatic)
                Text("Direct").tag(PresentationModePreference.directReplacement)
                Text("Marked").tag(PresentationModePreference.markedText)
                Text("Passthrough").tag(PresentationModePreference.passthrough)
            }
            .labelsHidden()
            .frame(width: 130)
        }
    }

    private func addAppOverride() {
        let bundleID = newOverrideBundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !bundleID.isEmpty else { return }
        prefs.appModeOverrides[bundleID] = .markedText
        newOverrideBundleID = ""
    }

    private func copyDiagnostics() {
        var text = "### 📋 Thông số Cấu hình & Môi trường VieLotusIM\n\n"
        text += "- **Hệ điều hành:** macOS \(AppInfo.osVersionString) (\(AppInfo.architecture))\n"
        text += "- **Phiên bản:** v\(AppInfo.appVersion) (Build \(AppInfo.buildNumber) · `\(AppInfo.gitCommit)`)\n"
        text += AppInfo.formattedConfiguration(
            inputMethod: prefs.inputMethod == .telex ? "TELEX" : "VNI",
            smartBilingual: prefs.smartBilingual,
            modernOrthography: prefs.modernOrthography,
            developerMode: prefs.developerMode,
            terminalDirectMode: prefs.terminalDirectMode,
            quickTelex: prefs.quickTelex,
            relaxedCoda: prefs.relaxedCoda
        ) + "\n\n"
        text += "- **Chế độ hiển thị:** \(prefs.presentationModePreference.rawValue)\n"
        if !prefs.appModeOverrides.isEmpty {
            text += "- **Ghi đè ứng dụng:** " + prefs.appModeOverrides.keys.sorted().map { bundleID in
                "\(bundleID)=\(prefs.appModeOverrides[bundleID]?.rawValue ?? "automatic")"
            }.joined(separator: ", ") + "\n"
        }
        text += "\n"
        text += "> 🔒 Sen Việt áp dụng Zero-logging: Không ghi phím vào đĩa hay mạng.\n"

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedDiagnostics = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedDiagnostics = false
        }
    }

    private func openGitHubIssue() {
        if let url = URL(string: "https://github.com/stevedat/VieLotus-IM/issues/new?template=bug_report.md") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openGitHubDiscussions() {
        if let url = URL(string: "https://github.com/stevedat/VieLotus-IM/discussions") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openVieLotusLab() {
        let searchPaths = [
            "/Applications/VieLotus Lab.app",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/VieLotus Lab.app").path,
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("VieLotusLab.app").path
        ]
        for path in searchPaths {
            if FileManager.default.fileExists(atPath: path) {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
                return
            }
        }
        if let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.vielotus.inputmethod.VieLotusLab") {
            NSWorkspace.shared.open(appUrl)
        } else {
            if let url = URL(string: "https://github.com/stevedat/VieLotus-IM/releases") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
