import VieLotusCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var prefs = Preferences.shared

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
                }
            }
            .formStyle(.grouped)

            // MARK: - Apple Clean Minimalist Footer
            HStack {
                Text("v1.1 (Universal) • Không quyền Trợ năng")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Link("GitHub", destination: URL(string: "https://github.com/stevedat/VietLotus-IM")!)
                    .font(.system(size: 11, weight: .medium))
                
                Text("•")
                    .foregroundColor(.secondary)
                
                Link("YouPersona.com", destination: URL(string: "https://youpersona.com")!)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .frame(width: 420, height: 500)
    }
}
