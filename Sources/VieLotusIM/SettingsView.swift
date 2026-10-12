import VieLotusCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var prefs = Preferences.shared
    @State private var showingMacroEditor = false
    @State private var macroCount: Int = MacroEngine.shared.getMacroEntries().count

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

                    if prefs.macroEnabled {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(macroCount) từ viết tắt trong bảng")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Lưu tự động vào macros.json")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button {
                                showingMacroEditor = true
                            } label: {
                                Label("Quản lý bảng gõ tắt...", systemImage: "list.bullet.rectangle")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.vertical, 2)
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

                Section("CHUYỂN ĐỔI NGÔN NGỮ CHUẨN APPLE") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "globe")
                                .font(.system(size: 18))
                                .foregroundColor(.accentColor)
                                .frame(width: 22)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Phím tắt chuyển đổi chuẩn macOS")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Nhấn phím Fn / 🌐 hoặc Control + Space để chuyển đổi tức thì giữa Tiếng Anh (ABC) và Tiếng Việt (Sen Việt) với độ trễ 0ms.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }

                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 16))
                                .foregroundColor(.orange)
                                .frame(width: 22)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Khuyến nghị xoá bộ gõ cũ của Apple")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Xoá bỏ bộ gõ tiếng Việt cũ của Apple trong Cài đặt hệ thống để triệt tiêu hoàn toàn lỗi nuốt chữ kinh niên và tránh xung đột xoay vòng.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }

                        Button {
                            openSystemKeyboardSettings()
                        } label: {
                            Label("Mở Cài đặt Bàn phím macOS...", systemImage: "gearshape")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(.top, 2)
                    }
                    .padding(.vertical, 4)
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
        .frame(width: 460, height: 580)
        .sheet(isPresented: $showingMacroEditor) {
            MacroEditorView()
        }
        .onAppear {
            macroCount = MacroEngine.shared.getMacroEntries().count
        }
        .onReceive(NotificationCenter.default.publisher(for: MacroEngine.macrosDidChangeNotification)) { _ in
            macroCount = MacroEngine.shared.getMacroEntries().count
        }
    }

    @State private var copiedDiagnostics = false

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

    private func openSystemKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
