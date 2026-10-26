import VieLotusCore
import SwiftUI
import AppKit

enum SettingsTab: String, CaseIterable, Identifiable {
    case settings = "Cài đặt"
    case about = "Về ứng dụng"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .settings: return "slider.horizontal.3"
        case .about: return "sparkles"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var prefs = Preferences.shared
    @State private var selectedTab: SettingsTab = .settings
    @State private var showingMacroEditor = false
    @State private var showingAdaptiveSheet = false
    @State private var macroCount: Int = MacroEngine.shared.getMacroEntries().count
    @State private var showVietQR: Bool = false
    @State private var copiedAccount: Bool = false

    private let bentoColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header: Minimalist Branding + 2-Tab Switcher (Cài đặt | Về ứng dụng)
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 38, height: 38)
                    .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 1)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("Sen Việt")
                            .font(.system(size: 15.5, weight: .bold))
                        Text("v\(AppInfo.appVersion)")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Color.accentColor.opacity(0.14))
                            .foregroundColor(.accentColor)
                            .clipShape(Capsule())
                    }
                    Text("Pure Swift 6 • Không quyền Trợ năng")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Picker("", selection: $selectedTab) {
                    ForEach(SettingsTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 210)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            Divider()

            // MARK: - Tab Content
            Group {
                switch selectedTab {
                case .settings:
                    settingsTabView
                case .about:
                    aboutTabView
                }
            }
            .frame(maxHeight: .infinity)

            Divider()

            // MARK: - Clean Footer
            HStack {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("Song ngữ • Gợi ý • Chuẩn mới • Gen Z tự động bật")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Link("YouPersona.com", destination: URL(string: "https://youpersona.com")!)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.accentColor)

                Text("•").font(.system(size: 10)).foregroundColor(.secondary)

                Link("Zalo", destination: URL(string: "https://zalo.me/g/6wwyvywyvhsb0n6rwkze")!)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)

                Text("•").font(.system(size: 10)).foregroundColor(.secondary)

                Link("GitHub", destination: URL(string: "https://github.com/stevedat/VieLotus-IM")!)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
        }
        .frame(width: 480, height: 470)
        .sheet(isPresented: $showingMacroEditor) {
            MacroEditorView()
        }
        .sheet(isPresented: $showingAdaptiveSheet) {
            AdaptiveCompatibilitySheet(prefs: prefs)
        }
        .onAppear {
            if !prefs.smartBilingual { prefs.smartBilingual = true }
            if !prefs.modernOrthography { prefs.modernOrthography = true }
            if !prefs.genZMode { prefs.genZMode = true }
            if !prefs.terminalDirectMode { prefs.terminalDirectMode = true }
            if !prefs.passthroughRemoteApps { prefs.passthroughRemoteApps = true }
            if !prefs.enforceABCBaseLayout { prefs.enforceABCBaseLayout = true }
            macroCount = MacroEngine.shared.getMacroEntries().count
        }
        .onReceive(NotificationCenter.default.publisher(for: MacroEngine.macrosDidChangeNotification)) { _ in
            macroCount = MacroEngine.shared.getMacroEntries().count
        }
    }

    // MARK: - Tab 1: Cài đặt (Phong cách Bento hiện đại, tinh gọn, phi truyền thống)
    private var settingsTabView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // 1. Hero Visual Selector: Telex vs VNI
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("KIỂU GÕ TIẾNG VIỆT")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Bỏ dấu tự do mọi vị trí")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.accentColor)
                    }

                    HStack(spacing: 10) {
                        inputMethodCard(
                            method: .telex,
                            title: "Telex Tự Do",
                            badge: "s f r x j w",
                            subtitle: "vieetj → việt • w → ư",
                            icon: "command.square.fill"
                        )
                        inputMethodCard(
                            method: .vni,
                            title: "VNI Chuẩn",
                            badge: "1–5 • 6–9",
                            subtitle: "vie65t → việt • 9 → đ",
                            icon: "number.square.fill"
                        )
                    }
                }

                // 2. Bento Grid 2x2: Tiện ích & Chế độ thông minh
                VStack(alignment: .leading, spacing: 7) {
                    Text("TIỆN ÍCH & KHÔNG GIAN LÀM VIỆC")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(.secondary)

                    LazyVGrid(columns: bentoColumns, spacing: 10) {
                        // Tile 1: Bảng gõ tắt (Macro)
                        bentoFeatureCard(
                            icon: "text.badge.plus",
                            accent: .indigo,
                            title: "Bảng gõ tắt",
                            subtitle: prefs.macroEnabled ? "Đang bật • \(macroCount) cụm từ" : "Đang tắt gõ tắt",
                            isActive: prefs.macroEnabled,
                            onToggle: { prefs.macroEnabled.toggle() }
                        ) {
                            Button("Quản lý (\(macroCount))") {
                                showingMacroEditor = true
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }

                        // Tile 2: Chế độ Lập trình viên (Code & Markdown)
                        bentoFeatureCard(
                            icon: "chevron.left.forwardslash.chevron.right",
                            accent: .teal,
                            title: "Chế độ Code & Dev",
                            subtitle: prefs.developerMode ? "Tự ngắt dấu trong `code`" : "Gõ tiếng Việt bình thường",
                            isActive: prefs.developerMode,
                            onToggle: { prefs.developerMode.toggle() }
                        ) {
                            Text(prefs.developerMode ? "ĐANG BẬT" : "TẮT")
                                .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(prefs.developerMode ? Color.teal.opacity(0.18) : Color.secondary.opacity(0.12))
                                .foregroundColor(prefs.developerMode ? .teal : .secondary)
                                .clipShape(Capsule())
                        }

                        // Tile 3: Tốc gõ phụ âm đầu & cuối
                        bentoConsonantCard

                        // Tile 4: Tương thích macOS & Phím tắt hệ thống
                        bentoSystemShortcutCard
                    }
                }

                // 3. Compact Smart Engine Status Strip (Always On + Adaptive Hybrid Inspector)
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.indigo)
                    Text("Trí tuệ Sen Việt tự động:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("Song ngữ • Gợi ý • Chuẩn mới • Adaptive Hybrid")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button("Tương thích App") {
                        showingAdaptiveSheet = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.indigo.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.indigo.opacity(0.18), lineWidth: 0.8)
                )
            }
            .padding(16)
        }
    }

    private func inputMethodCard(
        method: InputMethodType,
        title: String,
        badge: String,
        subtitle: String,
        icon: String
    ) -> some View {
        let isSelected = (prefs.inputMethod == method)
        return Button {
            prefs.inputMethod = method
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.45))
                }

                HStack(spacing: 6) {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.12))
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.primary.opacity(0.09),
                        lineWidth: isSelected ? 1.8 : 0.8
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func bentoFeatureCard<Trailing: View>(
        icon: String,
        accent: Color,
        title: String,
        subtitle: String,
        isActive: Bool,
        onToggle: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: onToggle) {
                    HStack(spacing: 6) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(isActive ? accent.opacity(0.16) : Color.secondary.opacity(0.12))
                                .frame(width: 26, height: 26)
                            Image(systemName: icon)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundColor(isActive ? accent : .secondary)
                        }
                        Text(title)
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundColor(.primary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()
                trailing()
            }

            Button(action: onToggle) {
                HStack {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isActive ? accent.opacity(0.45) : Color.primary.opacity(0.08), lineWidth: 1.0)
        )
    }

    private var bentoConsonantCard: some View {
        let anyActive = prefs.quickTelex || prefs.relaxedCoda
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(anyActive ? Color.orange.opacity(0.16) : Color.secondary.opacity(0.12))
                        .frame(width: 26, height: 26)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(anyActive ? .orange : .secondary)
                }
                Text("Tốc gõ phụ âm")
                    .font(.system(size: 12.5, weight: .bold))
                Spacer()
            }

            HStack(spacing: 6) {
                chipToggleButton(
                    label: "Đầu (cc/gg/qq)",
                    isOn: prefs.quickTelex
                ) {
                    prefs.quickTelex.toggle()
                }
                chipToggleButton(
                    label: "Cuối (-g/-h/-k)",
                    isOn: prefs.relaxedCoda
                ) {
                    prefs.relaxedCoda.toggle()
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(anyActive ? Color.orange.opacity(0.45) : Color.primary.opacity(0.08), lineWidth: 1.0)
        )
    }

    private var bentoSystemShortcutCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 26, height: 26)
                    Image(systemName: "globe")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.blue)
                }
                Text("Phím tắt Đổi bộ gõ")
                    .font(.system(size: 12.5, weight: .bold))
                Spacer()
                Button("Mở cài đặt ↗") {
                    openSystemKeyboardSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            Text("Fn / 🌐 hoặc Ctrl + Space để chuyển nhanh")
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1.0)
        )
    }

    private func chipToggleButton(label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 10, weight: .bold))
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isOn ? Color.orange.opacity(0.16) : Color.secondary.opacity(0.10))
            )
            .foregroundColor(isOn ? .orange : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab 3: Về ứng dụng (Đồng bộ với bản Phone + Sản phẩm khác của tác giả YouPersona.com)
    private var aboutTabView: some View {
        ScrollView {
            VStack(spacing: 12) {
                // 1. Sứ mệnh tối thượng
                VStack(alignment: .leading, spacing: 6) {
                    Label("SỨ MỆNH TỐI THƯỢNG", systemImage: "sparkles")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(.indigo)

                    Text("Sen Việt được phát triển theo kim chỉ nam \"Hãy để việc gõ là gõ, dù bạn gõ tiếng Việt hay tiếng Anh; nhanh hay chậm; gõ là Sen Việt\".")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(.primary)
                        .lineSpacing(2.5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
                )

                // 2. Mời tác giả ly cà phê nhỏ (Chỉ dùng VietQR, không dùng BuyMeACoffee)
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            showVietQR.toggle()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "cup.and.saucer.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.orange)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 1) {
                                Text("Mời tác giả ly cà phê nhỏ")
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundColor(.primary)
                                Text("Sen Việt hoàn toàn miễn phí. Nếu bộ gõ hữu ích, bạn có thể ủng hộ nhẹ qua VietQR.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Label(showVietQR ? "Thu gọn" : "Mã VietQR", systemImage: showVietQR ? "chevron.up" : "qrcode")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.orange)
                        }
                    }
                    .buttonStyle(.plain)

                    if showVietQR {
                        Divider()
                        HStack(spacing: 14) {
                            if let qrImg = loadVietQRImage() {
                                Image(nsImage: qrImg)
                                    .resizable()
                                    .interpolation(.high)
                                    .scaledToFit()
                                    .frame(width: 96, height: 96)
                                    .padding(4)
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }

                            VStack(alignment: .leading, spacing: 5) {
                                Text("Ngân hàng Quân đội (MB Bank)")
                                    .font(.system(size: 12, weight: .semibold))

                                HStack(spacing: 8) {
                                    Text("STK: 0979266045")
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundColor(.indigo)

                                    Button(copiedAccount ? "✓ Đã chép" : "Sao chép STK") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString("0979266045", forType: .string)
                                        copiedAccount = true
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                                            copiedAccount = false
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                }

                                Text("Chủ TK: Trần Phát Đạt • Nội dung: Ung ho Sen Viet")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
                )

                // 3. Sản phẩm khác của tác giả — YouPersona.com (Giới thiệu gọn + CTA)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "chart.pie.fill")
                            .font(.system(size: 15))
                            .foregroundColor(.teal)
                            .frame(width: 20)
                            .padding(.top, 1)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("YouPersona.com")
                                    .font(.system(size: 12.5, weight: .bold))
                                Text("SẢN PHẨM KHÁC CỦA TÁC GIẢ")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.teal.opacity(0.15))
                                    .foregroundColor(.teal)
                                    .clipShape(Capsule())
                            }
                            Text("Trợ lý Quản lý Thu Chi & Tài chính Cá nhân AI — ghi chép bằng giọng nói, quét hoá đơn tự động và quản lý ngân sách theo phương pháp 6 chiếc lọ.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineSpacing(1.5)
                        }

                        Spacer(minLength: 8)

                        Link(destination: URL(string: "https://youpersona.com")!) {
                            HStack(spacing: 4) {
                                Text("Khám phá")
                                Image(systemName: "arrow.up.right")
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.teal)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.teal.opacity(0.25), lineWidth: 0.9)
                )

                // 4. Cộng đồng & Tác giả
                VStack(spacing: 8) {
                    aboutLinkRow(
                        title: "Kênh Thảo luận Cộng đồng (Zalo)",
                        urlString: "https://zalo.me/g/6wwyvywyvhsb0n6rwkze",
                        icon: "bubble.left.and.bubble.right.fill"
                    )
                    Divider()
                    aboutLinkRow(
                        title: "Tác giả: Trần Phát Đạt (LinkedIn)",
                        urlString: "https://www.linkedin.com/in/stevedat/?isSelfProfile=true",
                        icon: "person.crop.circle.badge.checkmark"
                    )
                    Divider()
                    aboutLinkRow(
                        title: "Mã nguồn Mở & Báo lỗi (GitHub)",
                        urlString: "https://github.com/stevedat/VieLotus-IM",
                        icon: "chevron.left.forwardslash.chevron.right"
                    )
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
                )
            }
            .padding(16)
        }
    }

    private func aboutLinkRow(title: String, urlString: String, icon: String) -> some View {
        Link(destination: URL(string: urlString)!) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12.5))
                    .foregroundColor(.indigo)
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func loadVietQRImage() -> NSImage? {
        if let url = Bundle.main.url(forResource: "vietqr", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        let devPaths = [
            "Sources/VieLotusIM/Resources/vietqr.png",
            "docs/assets/vietqr.png"
        ]
        for path in devPaths where FileManager.default.fileExists(atPath: path) {
            if let img = NSImage(contentsOfFile: path) {
                return img
            }
        }
        return nil
    }

    private func toggleLabel(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Actions
    private func openSystemKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct RunningAppItem: Identifiable {
    let id: String
    let name: String
    let icon: NSImage?
    let category: AppCategory
}

private struct AdaptiveCompatibilitySheet: View {
    @ObservedObject var prefs: Preferences
    @Environment(\.dismiss) private var dismiss
    @State private var runningApps: [RunningAppItem] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Adaptive Hybrid • Tương thích Ứng dụng")
                        .font(.system(size: 14, weight: .bold))
                    Text("Ưu tiên không gạch chân (Direct), tự động bảo vệ dữ liệu & tàng hình gạch chân (Stealth α=0.004)")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Đóng") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Chế độ toàn cục:")
                        .font(.system(size: 11.5, weight: .semibold))
                    Picker("", selection: $prefs.presentationModePreference) {
                        Text("Tự động (Adaptive Hybrid)").tag(PresentationModePreference.automatic)
                        Text("Ưu tiên Không gạch chân (Direct)").tag(PresentationModePreference.directReplacement)
                        Text("Native Marked Text (Chuẩn Apple)").tag(PresentationModePreference.markedText)
                    }
                    .labelsHidden()
                    .frame(width: 240)

                    Spacer()

                    if !prefs.appModeOverrides.isEmpty || !ClientAdapter.forcedMarkedTextBundles().isEmpty {
                        Button("Đặt lại mặc định") {
                            prefs.appModeOverrides.removeAll()
                            ClientAdapter.resetDynamicMarkedText()
                            reloadRunningApps()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(runningApps) { app in
                            runningAppRow(app)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
        }
        .frame(width: 470, height: 410)
        .onAppear {
            reloadRunningApps()
        }
    }

    private func runningAppRow(_ app: RunningAppItem) -> some View {
        let resolution = ClientAdapter.resolvePresentationModeWithSource(
            for: app.category,
            bundleIdentifier: app.id,
            terminalDirectEnabled: prefs.terminalDirectMode,
            passthroughRemoteApps: prefs.passthroughRemoteApps,
            preference: prefs.presentationModePreference,
            appOverrides: prefs.appModeOverrides
        )
        let badge = badgeInfo(mode: resolution.mode, source: resolution.source, category: app.category)
        let currentOverride = prefs.appModeOverrides[app.id] ?? .automatic

        return HStack(spacing: 10) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "app.fill")
                    .frame(width: 24, height: 24)
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(app.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(badge.label)
                        .font(.system(size: 9.5, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(badge.color.opacity(0.14))
                        .foregroundColor(badge.color)
                        .clipShape(Capsule())
                }
                Text(app.id)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Picker("", selection: Binding(
                get: { currentOverride },
                set: { newValue in
                    if newValue == .automatic {
                        prefs.appModeOverrides.removeValue(forKey: app.id)
                    } else {
                        prefs.appModeOverrides[app.id] = newValue
                    }
                    ClientAdapter.clearForcedMarkedText(for: app.id)
                }
            )) {
                Text("Tự động").tag(PresentationModePreference.automatic)
                Text("Direct (Không gạch)").tag(PresentationModePreference.directReplacement)
                Text("Marked Text").tag(PresentationModePreference.markedText)
                Text("Passthrough").tag(PresentationModePreference.passthrough)
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 135)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.8)
        )
    }

    private func badgeInfo(mode: VieLotusCore.PresentationMode, source: PresentationModeSource, category: AppCategory) -> (label: String, color: Color) {
        switch source {
        case .dynamicFallback:
            return ("Auto-Fallback • Marked Text", .orange)
        case .appOverride:
            switch mode {
            case .directReplacement: return ("Ghim • Không gạch chân", .green)
            case .markedText: return ("Ghim • Marked Text", .blue)
            case .terminalDirect: return ("Ghim • Terminal Direct", .teal)
            case .passthrough: return ("Ghim • Tắt bộ gõ", .secondary)
            }
        default:
            switch mode {
            case .directReplacement:
                return ("Direct • Không gạch chân", .green)
            case .markedText:
                if category == .chromium {
                    return ("Stealth • Gạch chân tàng hình", .indigo)
                }
                return ("Marked Text • An toàn", .blue)
            case .terminalDirect:
                return ("Terminal Direct", .teal)
            case .passthrough:
                return ("Passthrough", .secondary)
            }
        }
    }

    private func reloadRunningApps() {
        var seen = Set<String>()
        var items: [RunningAppItem] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let rawID = app.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawID.isEmpty,
                  !rawID.lowercased().hasPrefix("org.vielotus.inputmethod") else { continue }
            let id = rawID.lowercased()
            guard seen.insert(id).inserted else { continue }
            let name = app.localizedName ?? rawID
            items.append(RunningAppItem(
                id: id,
                name: name,
                icon: app.icon,
                category: ClientAdapter.classify(bundleIdentifier: id)
            ))
        }
        items.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        runningApps = items
    }
}
