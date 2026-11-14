import VieLotusCore
import VieLotusTrace
import SwiftUI
import AppKit

enum SettingsTab: String, CaseIterable, Identifiable {
    case settings = "Cài đặt"
    case about = "Thông tin"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .settings: return "slider.horizontal.3"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var prefs = Preferences.shared
    @ObservedObject private var updater = UpdateManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab: SettingsTab = .settings
    @State private var showingMacroEditor = false
    @State private var showingAdaptiveSheet = false
    @State private var showingFeedbackSheet = false
    @State private var macroCount: Int = MacroEngine.shared.getMacroEntries().count
    @State private var tisStatus: InputSourceStatus = InputSourceDoctor.inspect()
    @State private var quickTestText: String = ""

    private let bentoColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    private var isDark: Bool {
        colorScheme == .dark
    }

    private var windowCanvasColor: Color {
        isDark ? Color(red: 0.08, green: 0.08, blue: 0.10) : Color(red: 0.96, green: 0.96, blue: 0.97)
    }

    private var barSurfaceColor: Color {
        isDark ? Color(red: 0.11, green: 0.11, blue: 0.14) : Color.white
    }

    private var cardSurfaceColor: Color {
        isDark ? Color(red: 0.14, green: 0.14, blue: 0.18) : Color.white
    }

    private var cardBorderColor: Color {
        isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.09)
    }

    private var selectedSegmentSurfaceColor: Color {
        isDark ? Color(red: 0.22, green: 0.22, blue: 0.28) : Color.white
    }

    private var cleanDisplayVersion: String {
        let raw = AppInfo.appVersion
        if let dashIdx = raw.firstIndex(of: "-") {
            return String(raw[..<dashIdx])
        }
        return raw
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header: Minimalist Landscape Header
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 36, height: 36)
                    .shadow(color: .black.opacity(0.12), radius: 2.5, x: 0, y: 1)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Sen Việt")
                            .font(.system(size: 15.5, weight: .bold))
                        Text("v\(cleanDisplayVersion)")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 1.5)
                            .background(Color.accentColor.opacity(0.14))
                            .foregroundColor(.accentColor)
                            .clipShape(Capsule())
                            .help("Phiên bản chi tiết: v\(AppInfo.appVersion)")

                        headerUpdatePill
                    }
                    Text("InputMethodKit • Cập nhật qua GitHub theo yêu cầu")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: true, vertical: false)
                }

                Spacer(minLength: 12)

                // Custom clean segmented switcher (tránh lỗi khoảng trắng nhãn ẩn của NSSegmentedControl)
                HStack(spacing: 2) {
                    ForEach(SettingsTab.allCases) { tab in
                        let isSelected = (selectedTab == tab)
                        Button {
                            selectedTab = tab
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(tab.rawValue)
                                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isSelected ? selectedSegmentSurfaceColor : Color.clear)
                                    .shadow(color: isSelected ? .black.opacity(isDark ? 0.35 : 0.08) : .clear, radius: 1.5, x: 0, y: 0.5)
                            )
                            .foregroundColor(isSelected ? .primary : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isDark ? Color.white.opacity(0.08) : Color.secondary.opacity(0.12))
                )
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(barSurfaceColor)

            Divider()

            // MARK: - Tab Content (Landscape Rectangle — Zero Scroll Needed)
            Group {
                switch selectedTab {
                case .settings:
                    settingsTabView
                case .about:
                    aboutTabView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(windowCanvasColor)

            Divider()

            // MARK: - Clean Footer (Hiển thị trọn vẹn 100%, không bị cắt đáy hay cắt chữ)
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(tisStatusColor)
                        .frame(width: 6.5, height: 6.5)
                    Text("Song ngữ Anh–Việt • Chính tả chuẩn mới tự động")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: true, vertical: false)
                }

                Spacer(minLength: 12)

                if let url = URL(string: "https://educenter.app") {
                    Link("NidoOffice", destination: url)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.indigo)
                }

                Text("•").font(.system(size: 10)).foregroundColor(.secondary)

                if let url = URL(string: "https://youpersona.com") {
                    Link("YouPersona.com", destination: url)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.accentColor)
                }

                Text("•").font(.system(size: 10)).foregroundColor(.secondary)

                Button {
                    showingFeedbackSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                        Text("Góp ý & Báo lỗi")
                    }
                    .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Gửi góp ý, báo lỗi gõ từ hoặc đề xuất tính năng")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(barSurfaceColor)
        }
        .background(windowCanvasColor)
        .frame(width: 640, height: 420)
        .sheet(isPresented: $showingMacroEditor) {
            MacroEditorView()
        }
        .sheet(isPresented: $showingAdaptiveSheet) {
            AdaptiveCompatibilitySheet(prefs: prefs)
        }
        .sheet(isPresented: $showingFeedbackSheet) {
            FeedbackSheetView(prefs: prefs) {
                showingFeedbackSheet = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: SettingsWindowManager.openFeedbackSheetNotification)) { _ in
            showingFeedbackSheet = true
        }
        .onAppear {
            if !prefs.smartBilingual { prefs.smartBilingual = true }
            if !prefs.modernOrthography { prefs.modernOrthography = true }
            if !prefs.genZMode { prefs.genZMode = true }
            if !prefs.terminalDirectMode { prefs.terminalDirectMode = true }
            if !prefs.passthroughRemoteApps { prefs.passthroughRemoteApps = true }
            if !prefs.enforceABCBaseLayout { prefs.enforceABCBaseLayout = true }
            macroCount = MacroEngine.shared.getMacroEntries().count
            tisStatus = InputSourceDoctor.inspect()
            Task {
                await updater.checkIfNeededOnSettingsOpen()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: MacroEngine.macrosDidChangeNotification)) { _ in
            macroCount = MacroEngine.shared.getMacroEntries().count
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            tisStatus = InputSourceDoctor.inspect()
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: InputSourceDoctor.selectedInputSourceChangedNotification)) { _ in
            tisStatus = InputSourceDoctor.inspect()
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: InputSourceDoctor.enabledInputSourcesChangedNotification)) { _ in
            tisStatus = InputSourceDoctor.inspect()
        }
    }

    // MARK: - Tab 1: Cài đặt (Bố cục ngang 3 hàng vừa khít khung chữ nhật 640x420)
    private var settingsTabView: some View {
        VStack(alignment: .leading, spacing: 11) {
            // Hàng 1: Kiểu gõ tiếng Việt (3 thẻ ngang trên cùng 1 hàng: Telex Tự Do | VNI | Dấu trước âm)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("KIỂU GÕ TIẾNG VIỆT")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Bỏ dấu tự do • Z xoá dấu")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.accentColor)
                }

                HStack(spacing: 10) {
                    inputMethodCard(
                        method: .telex,
                        title: "Telex Tự Do",
                        badge: "s f r x j w",
                        subtitle: "vieetj → việt",
                        icon: "command.square.fill"
                    )
                    inputMethodCard(
                        method: .vni,
                        title: "VNI (Số 1–9)",
                        badge: "1–5 • 6–9",
                        subtitle: "viet65 → việt",
                        icon: "number.square.fill"
                    )
                    senFlexCard
                }
            }

            // Hàng 2: Tiện ích & Tương thích (Bento Grid 2x2 ngang rộng rãi)
            VStack(alignment: .leading, spacing: 6) {
                Text("TIỆN ÍCH & TƯƠNG THÍCH")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)

                LazyVGrid(columns: bentoColumns, spacing: 9) {
                    // Tile 1: Bảng gõ tắt
                    bentoFeatureCard(
                        icon: "text.badge.plus",
                        accent: .indigo,
                        title: "Bảng gõ tắt",
                        subtitle: prefs.macroEnabled ? "Đang bật • \(macroCount) cụm từ" : "Đang tắt • Bấm để bật",
                        isActive: prefs.macroEnabled,
                        onToggle: { prefs.macroEnabled.toggle() }
                    ) {
                        Button("Quản lý (\(macroCount))") {
                            showingMacroEditor = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }

                    // Tile 2: Chế độ Code
                    bentoFeatureCard(
                        icon: "chevron.left.forwardslash.chevron.right",
                        accent: .teal,
                        title: "Chế độ Code",
                        subtitle: prefs.developerMode ? "Tự ngắt dấu trong `code`" : "Gõ tiếng Việt bình thường",
                        isActive: prefs.developerMode,
                        onToggle: { prefs.developerMode.toggle() }
                    ) {
                        Text(prefs.developerMode ? "BẬT" : "TẮT")
                            .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(prefs.developerMode ? Color.teal.opacity(0.18) : Color.secondary.opacity(0.12))
                            .foregroundColor(prefs.developerMode ? .teal : .secondary)
                            .clipShape(Capsule())
                    }

                    // Tile 3: Tốc gõ phụ âm
                    bentoConsonantCard

                    // Tile 4: Tương thích App
                    bentoAdaptiveCard
                }
            }

            // Hàng 3: Trạng thái Bộ gõ Hệ thống (Full-Width 1 dòng ngang, không bao giờ cắt chữ)
            systemStatusFullWidthCard

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 8)
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
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                    Text(title)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.45))
                }

                HStack(spacing: 5) {
                    Text(badge)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.12))
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(isDark ? 0.18 : 0.08) : cardSurfaceColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor : cardBorderColor,
                        lineWidth: isSelected ? 1.6 : 0.9
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var senFlexCard: some View {
        let isFlex = (prefs.grammarProfile == .senFlex)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "wand.and.rays")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isFlex ? .accentColor : .secondary)
                Text("Dấu trước âm")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Toggle(
                    "",
                    isOn: Binding(
                        get: { prefs.grammarProfile == .senFlex },
                        set: { prefs.grammarProfile = $0 ? .senFlex : .classic }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
            }

            HStack(spacing: 5) {
                Text("rrung → rủng")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(isFlex ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.12))
                    .foregroundColor(isFlex ? .accentColor : .secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                Text(isFlex ? "Đang bật" : "Đang tắt")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isFlex ? Color.accentColor.opacity(isDark ? 0.14 : 0.06) : cardSurfaceColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isFlex ? Color.accentColor.opacity(isDark ? 0.65 : 0.45) : cardBorderColor,
                    lineWidth: 1.0
                )
        )
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button(action: onToggle) {
                    HStack(spacing: 6) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isActive ? accent.opacity(0.16) : Color.secondary.opacity(0.12))
                                .frame(width: 22, height: 22)
                            Image(systemName: icon)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(isActive ? accent : .secondary)
                        }
                        Text(title)
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 4)
                trailing()
            }

            Button(action: onToggle) {
                HStack {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(cardSurfaceColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isActive ? accent.opacity(isDark ? 0.65 : 0.45) : cardBorderColor, lineWidth: 1.0)
        )
    }

    private var bentoConsonantCard: some View {
        let anyActive = prefs.quickTelex || prefs.relaxedCoda
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(anyActive ? Color.orange.opacity(0.16) : Color.secondary.opacity(0.12))
                        .frame(width: 22, height: 22)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(anyActive ? .orange : .secondary)
                }
                Text("Tốc gõ phụ âm")
                    .font(.system(size: 12.5, weight: .bold))
                    .lineLimit(1)
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
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(cardSurfaceColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(anyActive ? Color.orange.opacity(isDark ? 0.65 : 0.45) : cardBorderColor, lineWidth: 1.0)
        )
    }

    private var bentoAdaptiveCard: some View {
        let overrideCount = prefs.appModeOverrides.count
        let subtitleText: String = {
            if overrideCount > 0 {
                return "Đã ghim \(overrideCount) ứng dụng riêng"
            }
            switch prefs.presentationModePreference {
            case .automatic:
                return "Direct & Stealth tự động"
            case .directReplacement:
                return "Ưu tiên Direct (Không gạch)"
            case .markedText:
                return "Marked Text chuẩn Apple"
            case .passthrough:
                return "Tạm ngắt bộ gõ"
            }
        }()

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.indigo.opacity(0.15))
                        .frame(width: 22, height: 22)
                    Image(systemName: "sparkles")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.indigo)
                }
                Text("Tương thích App")
                    .font(.system(size: 12.5, weight: .bold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button("Tuỳ chỉnh") {
                    showingAdaptiveSheet = true
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            Text(subtitleText)
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(cardSurfaceColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.indigo.opacity(isDark ? 0.48 : 0.32), lineWidth: 1.0)
        )
    }

    private var tisStatusColor: Color {
        if tisStatus.hasAnyInputConflict {
            return .orange
        }
        switch tisStatus.state {
        case .active:
            return .green
        case .enabledAppleVietnameseActive:
            return .orange
        case .enabledNotSelected:
            return .blue
        case .registeredNotEnabled, .notRegistered:
            return .red
        }
    }

    private var tisStatusIcon: String {
        if tisStatus.hasAnyInputConflict {
            return "exclamationmark.triangle.fill"
        }
        switch tisStatus.state {
        case .active:
            return "checkmark.seal.fill"
        case .enabledAppleVietnameseActive:
            return "exclamationmark.triangle.fill"
        case .enabledNotSelected:
            return "globe"
        case .registeredNotEnabled, .notRegistered:
            return "xmark.octagon.fill"
        }
    }

    private var systemStatusFullWidthCard: some View {
        let borderColor: Color = {
            if tisStatus.hasAnyInputConflict {
                return Color.orange.opacity(0.55)
            }
            switch tisStatus.state {
            case .active:
                return Color.green.opacity(0.45)
            case .enabledAppleVietnameseActive:
                return Color.orange.opacity(0.55)
            case .registeredNotEnabled, .notRegistered:
                return Color.red.opacity(0.45)
            case .enabledNotSelected:
                return cardBorderColor
            }
        }()

        return HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tisStatusColor.opacity(0.16))
                    .frame(width: 26, height: 26)
                Image(systemName: tisStatusIcon)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(tisStatusColor)
            }

            VStack(alignment: .leading, spacing: 1.5) {
                Text(tisStatus.summaryTitle)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(tisStatus.summarySubtitle)
                    .font(.system(size: 10))
                    .foregroundColor(tisStatus.hasAnyInputConflict ? .orange : .secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            HStack(spacing: 5) {
                Text("✦ Thử gõ:")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(.indigo)
                TextField("Gõ thử: thuongw / viet65...", text: $quickTestText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(width: 156)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(windowCanvasColor)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.indigo.opacity(isDark ? 0.45 : 0.28), lineWidth: 0.9)
                    )
            }

            Button("Cài đặt Bàn phím ↗") {
                openSystemKeyboardSettings()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(cardSurfaceColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1.0)
        )
    }

    private func chipToggleButton(label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3.5) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 9.5, weight: .bold))
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isOn ? Color.orange.opacity(isDark ? 0.24 : 0.16) : (isDark ? Color.white.opacity(0.08) : Color.secondary.opacity(0.10)))
            )
            .foregroundColor(isOn ? .orange : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab 2: Thông tin (Bố cục ngang chữ nhật 3 tầng cân đối, không cần cuộn)
    private var aboutTabView: some View {
        VStack(spacing: 12) {
            // Hàng 1: Thẻ Sứ mệnh & Chuẩn mực Kỹ thuật Sen Việt (Toàn chiều ngang)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Label("SỨ MỆNH SEN VIỆT", systemImage: "sparkles")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(.indigo)
                    Spacer()
                    Text("InputMethodKit • Engine Swift • Mã nguồn MIT")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }

                Text("\"Hãy để việc gõ là gõ — dù bạn gõ tiếng Việt hay tiếng Anh; nhanh hay chậm; gõ là Sen Việt.\"")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(.primary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    aboutFeaturePill(icon: "bolt.fill", text: "Phản hồi tức thì (< 1ms)", color: .orange)
                    aboutFeaturePill(icon: "globe", text: "Song ngữ Anh–Việt tự động", color: .indigo)
                    aboutFeaturePill(icon: "lock.shield.fill", text: "Không cần quyền Trợ năng", color: .green)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardSurfaceColor)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(cardBorderColor, lineWidth: 0.9)
            )

            // Hàng 2: 2 thẻ Hệ sinh thái AI đặt song song cân đối (NidoOffice | YouPersona.com)
            HStack(spacing: 12) {
                // Thẻ Trái: NidoOffice
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.indigo.opacity(0.14))
                                .frame(width: 28, height: 28)
                            Image(systemName: "doc.text.image.fill")
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundColor(.indigo)
                        }

                        VStack(alignment: .leading, spacing: 1.5) {
                            HStack(spacing: 5) {
                                Text("NidoOffice")
                                    .font(.system(size: 13, weight: .bold))
                                Text("EDUCENTER.APP")
                                    .font(.system(size: 8.5, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Color.indigo.opacity(0.14))
                                    .foregroundColor(.indigo)
                                    .clipShape(Capsule())
                            }
                            Text("Bộ ứng dụng Văn phòng AI thế hệ mới")
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                        }

                        Spacer(minLength: 4)

                        if let url = URL(string: "https://educenter.app") {
                            Link("Mở ↗", destination: url)
                                .font(.system(size: 10.5, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4.5)
                                .background(Color.indigo)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                    }

                    Text("Soạn thảo Tài liệu, Thiết kế Trang trình bày & Bảng tính thông minh tích hợp AI.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(cardSurfaceColor)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.indigo.opacity(isDark ? 0.38 : 0.22), lineWidth: 0.9)
                )

                // Thẻ Phải: YouPersona.com
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.teal.opacity(0.14))
                                .frame(width: 28, height: 28)
                            Image(systemName: "chart.pie.fill")
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundColor(.teal)
                        }

                        VStack(alignment: .leading, spacing: 1.5) {
                            HStack(spacing: 5) {
                                Text("YouPersona.com")
                                    .font(.system(size: 13, weight: .bold))
                                Text("THU CHI AI")
                                    .font(.system(size: 8.5, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Color.teal.opacity(0.14))
                                    .foregroundColor(.teal)
                                    .clipShape(Capsule())
                            }
                            Text("Trợ lý Tài chính cá nhân thông minh")
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                        }

                        Spacer(minLength: 4)

                        if let url = URL(string: "https://youpersona.com") {
                            Link("Mở ↗", destination: url)
                                .font(.system(size: 10.5, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4.5)
                                .background(Color.teal)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                    }

                    Text("Quét hoá đơn tự động, phân bổ Ngân sách 6 chiếc lọ & dự báo dòng tiền bằng AI.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(cardSurfaceColor)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.teal.opacity(isDark ? 0.38 : 0.22), lineWidth: 0.9)
                )
            }
            .frame(height: 98)

            // Hàng 3: Thanh Hỗ trợ, Cộng đồng & Mã nguồn (Toàn chiều ngang)
            HStack(spacing: 12) {
                Button {
                    showingFeedbackSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "bubble.left.and.text.bubble.right.fill")
                            .foregroundColor(.indigo)
                        Text("Gửi Góp ý & Báo lỗi")
                            .fontWeight(.semibold)
                    }
                    .font(.system(size: 11.5))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.indigo.opacity(isDark ? 0.22 : 0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)

                Spacer()

                if let zaloURL = URL(string: "https://zalo.me/g/6wwyvywyvhsb0n6rwkze") {
                    Link("Cộng đồng Zalo ↗", destination: zaloURL)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.primary)
                }

                Text("•").foregroundColor(.secondary)

                if let authorURL = URL(string: "https://www.linkedin.com/in/stevedat/?isSelfProfile=true") {
                    Link("Tác giả: Trần Phát Đạt ↗", destination: authorURL)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.primary)
                }

                Text("•").foregroundColor(.secondary)

                if let ghURL = URL(string: "https://github.com/stevedat/VieLotus-IM") {
                    Link("Mã nguồn GitHub ↗", destination: ghURL)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.indigo)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(cardSurfaceColor)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(cardBorderColor, lineWidth: 0.9)
            )

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var headerUpdatePill: some View {
        switch updater.status {
        case .idle:
            Button {
                Task { await updater.checkForUpdates(userInitiated: true) }
            } label: {
                HStack(spacing: 3.5) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Kiểm tra cập nhật")
                        .font(.system(size: 10, weight: .medium))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 1.5)
                .background(isDark ? Color.white.opacity(0.08) : Color.secondary.opacity(0.10))
                .foregroundColor(.secondary)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Kiểm tra phiên bản mới từ GitHub Releases (có xác thực SHA-256)")

        case .checking:
            HStack(spacing: 4) {
                Image(systemName: "hourglass")
                    .font(.system(size: 9, weight: .semibold))
                Text("Đang kiểm tra...")
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 1.5)
            .background(isDark ? Color.white.opacity(0.08) : Color.secondary.opacity(0.10))
            .foregroundColor(.secondary)
            .clipShape(Capsule())

        case .upToDate:
            Button {
                Task { await updater.checkForUpdates(userInitiated: true) }
            } label: {
                HStack(spacing: 3.5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9.5, weight: .semibold))
                    Text("Bản mới nhất")
                        .font(.system(size: 10, weight: .semibold))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 1.5)
                .background(Color.green.opacity(isDark ? 0.20 : 0.12))
                .foregroundColor(.green)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Đang dùng bản mới nhất • Bấm để kiểm tra lại")

        case .updateAvailable(let manifest):
            Button {
                Task { await updater.downloadAndInstallUpdate() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 9.5, weight: .bold))
                    Text("Cập nhật v\(manifest.version)")
                        .font(.system(size: 10, weight: .bold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.green)
                .foregroundColor(.white)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Tải về VieLotusIM.pkg v\(manifest.version), đối chiếu SHA-256 và cài đặt tự động")

        case .downloading(let progress):
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 9.5, weight: .semibold))
                Text("Đang tải \(Int(progress * 100))%...")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 1.5)
            .background(Color.accentColor.opacity(0.16))
            .foregroundColor(.accentColor)
            .clipShape(Capsule())

        case .installing:
            HStack(spacing: 4) {
                Image(systemName: "gearshape.2.fill")
                    .font(.system(size: 9.5, weight: .semibold))
                Text("Đang cài đặt...")
                    .font(.system(size: 10, weight: .semibold))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 1.5)
            .background(Color.accentColor.opacity(0.16))
            .foregroundColor(.accentColor)
            .clipShape(Capsule())

        case .error(let message):
            Button {
                Task { await updater.checkForUpdates(userInitiated: true) }
            } label: {
                HStack(spacing: 3.5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Thử lại cập nhật")
                        .font(.system(size: 10, weight: .semibold))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 1.5)
                .background(Color.orange.opacity(isDark ? 0.22 : 0.14))
                .foregroundColor(.orange)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(message)
        }
    }

    private func aboutFeaturePill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundColor(color)
            Text(text)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(isDark ? Color.white.opacity(0.08) : Color.secondary.opacity(0.08))
        .clipShape(Capsule())
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
                    Text("Tương thích Ứng dụng (Adaptive Hybrid)")
                        .font(.system(size: 14, weight: .bold))
                    Text("Tự động chọn chế độ gõ tối ưu (Direct / Stealth Marked Text) cho từng ứng dụng")
                        .font(.system(size: 11))
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
                        Text("Marked Text (Chuẩn Apple)").tag(PresentationModePreference.markedText)
                    }
                    .labelsHidden()
                    .frame(width: 235)

                    Spacer()

                    if !prefs.appModeOverrides.isEmpty || !ClientAdapter.forcedMarkedTextBundles().isEmpty {
                        Button("Khôi phục mặc định") {
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
        .frame(width: 560, height: 360)
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
            .frame(width: 140)
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
                    return ("Stealth • Gạch chân ẩn", .indigo)
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
