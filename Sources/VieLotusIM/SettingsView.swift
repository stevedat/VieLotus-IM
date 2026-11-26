import VieLotusCore
import VieLotusTrace
import SwiftUI
import AppKit

enum SettingsTab: String, CaseIterable, Identifiable {
    case settings = "settings"
    case about = "about"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .settings: return "slider.horizontal.3"
        case .about: return "info.circle"
        }
    }

    func title(isEnglish: Bool) -> String {
        switch self {
        case .settings: return isEnglish ? "Settings" : "Cài đặt"
        case .about: return isEnglish ? "About" : "Thông tin"
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
                            .help(prefs.tr("Phiên bản chi tiết: v\(AppInfo.appVersion)", "Detailed version: v\(AppInfo.appVersion)"))

                        headerUpdatePill
                    }
                    Text(prefs.tr(
                        "Thuần chuẩn Apple • 100% Offline • Không quyền Trợ năng",
                        "Pure Apple Native • 100% Offline • No Accessibility Needed"
                    ))
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
                                Text(tab.title(isEnglish: prefs.isEnglishUI))
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
                    Text(prefs.tr(
                        "Song ngữ Anh–Việt • Chính tả chuẩn mới tự động",
                        "Smart Bilingual EN–VI • Modern Orthography"
                    ))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 10)

                Menu {
                    Button {
                        prefs.uiLanguage = .auto
                    } label: {
                        if prefs.uiLanguage == .auto {
                            Label(prefs.tr("Tự động (Theo hệ thống)", "Auto (System)"), systemImage: "checkmark")
                        } else {
                            Text(prefs.tr("Tự động (Theo hệ thống)", "Auto (System)"))
                        }
                    }
                    Button {
                        prefs.uiLanguage = .vietnamese
                    } label: {
                        if prefs.uiLanguage == .vietnamese {
                            Label("Tiếng Việt", systemImage: "checkmark")
                        } else {
                            Text("Tiếng Việt")
                        }
                    }
                    Button {
                        prefs.uiLanguage = .english
                    } label: {
                        if prefs.uiLanguage == .english {
                            Label("English", systemImage: "checkmark")
                        } else {
                            Text("English")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                        Text(prefs.uiLanguage.shortBadge)
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .menuStyle(.borderedButton)
                .controlSize(.small)
                .fixedSize()
                .help(prefs.tr("Ngôn ngữ giao diện (VI / EN)", "Interface Language (VI / EN)"))

                Button {
                    showingFeedbackSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                        Text(prefs.tr("Góp ý & Báo lỗi", "Feedback & Bugs"))
                    }
                    .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(prefs.tr(
                    "Gửi góp ý, báo lỗi gõ từ hoặc đề xuất tính năng",
                    "Send feedback, report typing bugs, or suggest features"
                ))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(barSurfaceColor)
        }
        .background(windowCanvasColor)
        .frame(width: 640, height: 468)
        .sheet(isPresented: $showingMacroEditor) {
            MacroEditorView(prefs: prefs)
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
            if !prefs.terminalDirectMode { prefs.terminalDirectMode = true }
            if !prefs.passthroughRemoteApps { prefs.passthroughRemoteApps = true }
            if !prefs.enforceABCBaseLayout { prefs.enforceABCBaseLayout = true }
            macroCount = MacroEngine.shared.getMacroEntries().count
            tisStatus = InputSourceDoctor.inspect()
            if prefs.launchAtLogin {
                prefs.applyLaunchAtLoginRegistration(enabled: true)
            }
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
        .onReceive(
            DistributedNotificationCenter.default()
                .publisher(for: InputSourceDoctor.selectedInputSourceChangedNotification)
                .receive(on: DispatchQueue.main)
        ) { _ in
            tisStatus = InputSourceDoctor.inspect()
        }
        .onReceive(
            DistributedNotificationCenter.default()
                .publisher(for: InputSourceDoctor.enabledInputSourcesChangedNotification)
                .receive(on: DispatchQueue.main)
        ) { _ in
            tisStatus = InputSourceDoctor.inspect()
        }
    }

    // MARK: - Tab 1: Cài đặt (Bố cục ngang 3 hàng vừa khít khung chữ nhật 640x420)
    private var settingsTabView: some View {
        VStack(alignment: .leading, spacing: 11) {
            // Hàng 1: Kiểu gõ tiếng Việt (3 thẻ ngang trên cùng 1 hàng: Telex Tự Do | VNI | Dấu trước âm)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(prefs.tr("KIỂU GÕ TIẾNG VIỆT", "VIETNAMESE INPUT METHOD"))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(prefs.tr("Bỏ dấu tự do • Z xoá dấu", "Free-tone typing • Z removes tone"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.accentColor)
                }

                HStack(spacing: 10) {
                    inputMethodCard(
                        method: .telex,
                        title: prefs.tr("Telex Tự Do", "Telex"),
                        badge: "s f r x j w",
                        subtitle: "vieetj → việt",
                        icon: "command.square.fill"
                    )
                    inputMethodCard(
                        method: .vni,
                        title: prefs.tr("VNI (Số 1–9)", "VNI (1–9)"),
                        badge: "1–5 • 6–9",
                        subtitle: "viet65 → việt",
                        icon: "number.square.fill"
                    )
                    senFlexCard
                }
            }

            // Hàng 2: Tiện ích & Tương thích (Bento Grid 2x2 ngang rộng rãi)
            VStack(alignment: .leading, spacing: 6) {
                Text(prefs.tr("TIỆN ÍCH & TƯƠNG THÍCH", "UTILITIES & COMPATIBILITY"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)

                LazyVGrid(columns: bentoColumns, spacing: 9) {
                    // Tile 1: Bảng gõ tắt
                    bentoFeatureCard(
                        icon: "text.badge.plus",
                        accent: .indigo,
                        title: prefs.tr("Bảng gõ tắt", "Text Shortcuts"),
                        subtitle: prefs.macroEnabled
                            ? prefs.tr("Đang bật • \(macroCount) cụm từ", "On • \(macroCount) shortcuts")
                            : prefs.tr("Đang tắt • Bấm để bật", "Off • Click to enable"),
                        isActive: prefs.macroEnabled,
                        onToggle: { prefs.macroEnabled.toggle() }
                    ) {
                        Button(prefs.tr("Quản lý (\(macroCount))", "Manage (\(macroCount))")) {
                            showingMacroEditor = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }

                    // Tile 2: Chế độ Code
                    bentoFeatureCard(
                        icon: "chevron.left.forwardslash.chevron.right",
                        accent: .teal,
                        title: prefs.tr("Chế độ Code", "Code Mode"),
                        subtitle: prefs.developerMode
                            ? prefs.tr("Tự ngắt dấu trong `code`", "Auto-pause tones in `code`")
                            : prefs.tr("Gõ tiếng Việt bình thường", "Standard Vietnamese typing"),
                        isActive: prefs.developerMode,
                        onToggle: { prefs.developerMode.toggle() }
                    ) {
                        Text(prefs.developerMode ? prefs.tr("BẬT", "ON") : prefs.tr("TẮT", "OFF"))
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

            // Hàng 3: Trạng thái Bộ gõ Hệ thống & Khởi động cùng hệ thống (2 cột cân đối)
            HStack(spacing: 10) {
                systemStatusCompactCard
                launchAtLoginCard
            }

            // Hàng 4: Thanh Thử gõ nhanh
            quickTestBar

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
                Text(prefs.tr("Dấu trước âm", "Tone-First"))
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

                Text(isFlex ? prefs.tr("Đang bật", "On") : prefs.tr("Đang tắt", "Off"))
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
        let anyActive = prefs.quickTelex || prefs.relaxedCoda || prefs.genZMode
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
                Text(prefs.tr("Tốc gõ phụ âm", "Quick Consonants"))
                    .font(.system(size: 12.5, weight: .bold))
                    .lineLimit(1)
                Spacer()
            }

            HStack(spacing: 6) {
                chipToggleButton(
                    label: prefs.tr("Đầu (cc/gg/qq)", "Initial (cc/gg/qq)"),
                    isOn: prefs.quickTelex
                ) {
                    prefs.quickTelex.toggle()
                }
                chipToggleButton(
                    label: prefs.tr("Cuối (-g/-h/-k)", "Final (-g/-h/-k)"),
                    isOn: prefs.relaxedCoda
                ) {
                    prefs.relaxedCoda.toggle()
                }
                chipToggleButton(
                    label: "f/j/w/z",
                    isOn: prefs.genZMode
                ) {
                    prefs.genZMode.toggle()
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
                return prefs.tr("Đã ghim \(overrideCount) ứng dụng riêng", "Pinned \(overrideCount) custom apps")
            }
            switch prefs.presentationModePreference {
            case .automatic:
                return prefs.tr("Mặc định (Direct & Native Marked Text)", "Automatic (Direct & Native Marked Text)")
            case .directReplacement:
                return prefs.tr("Ưu tiên Direct (Thử nghiệm trên Web)", "Prefer Direct (Experimental on Web)")
            case .markedText:
                return "Native Marked Text"
            case .passthrough:
                return prefs.tr("Tạm ngắt bộ gõ", "Bypass IME (Passthrough)")
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
                Text(prefs.tr("Tương thích App", "App Compatibility"))
                    .font(.system(size: 12.5, weight: .bold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button(prefs.tr("Tuỳ chỉnh", "Configure")) {
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

    private var systemStatusCompactCard: some View {
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

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(tisStatusColor.opacity(0.16))
                        .frame(width: 22, height: 22)
                    Image(systemName: tisStatusIcon)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(tisStatusColor)
                }
                Text(tisStatus.localizedSummaryTitle(isEnglish: prefs.isEnglishUI))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button(prefs.tr("Bàn phím ↗", "Keyboards ↗")) {
                    openSystemKeyboardSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            Text(tisStatus.localizedSummarySubtitle(isEnglish: prefs.isEnglishUI))
                .font(.system(size: 10.5))
                .foregroundColor(tisStatus.hasAnyInputConflict ? .orange : .secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(cardSurfaceColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1.0)
        )
    }

    private var launchAtLoginCard: some View {
        let isAuto = prefs.launchAtLogin
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isAuto ? Color.green.opacity(0.16) : Color.secondary.opacity(0.12))
                        .frame(width: 22, height: 22)
                    Image(systemName: "power.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isAuto ? .green : .secondary)
                }
                Text(prefs.tr("Khởi động cùng hệ thống", "Launch at Login"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(isAuto ? "AUTO" : prefs.tr("TẮT", "OFF"))
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isAuto ? Color.green.opacity(0.16) : Color.secondary.opacity(0.12))
                    .foregroundColor(isAuto ? .green : .secondary)
                    .clipShape(Capsule())
                Toggle("", isOn: $prefs.launchAtLogin)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }

            Text(isAuto
                 ? prefs.tr("Tự động bật khi đăng nhập macOS", "Automatically enabled at macOS login")
                 : prefs.tr("Đang tắt • Bấm để bật tự động", "Off • Click switch to enable"))
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(cardSurfaceColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isAuto ? Color.green.opacity(isDark ? 0.55 : 0.40) : cardBorderColor, lineWidth: 1.0)
        )
    }

    private var quickTestBar: some View {
        let placeholder = prefs.inputMethod == .vni
            ? prefs.tr(
                "Gõ thử (VNI): tru7o7ng3 → trưởng • 12ha2 → 12hà • window user...",
                "Test typing (VNI): tru7o7ng3 → trưởng • 12ha2 → 12hà • window user..."
            )
            : prefs.tr(
                "Gõ thử (Telex): truowngr → trưởng • 12haf → 12hà • window user...",
                "Test typing (Telex): truowngr → trưởng • 12haf → 12hà • window user..."
            )
        return HStack(spacing: 8) {
            Text(prefs.tr("✦ Thử gõ:", "✦ Test:"))
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.indigo)
            TextField(placeholder, text: $quickTestText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity)
            if !quickTestText.isEmpty {
                Button(prefs.tr("Xoá thử", "Clear")) {
                    quickTestText = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(cardSurfaceColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.indigo.opacity(isDark ? 0.45 : 0.28), lineWidth: 1.0)
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
                    Label(prefs.tr("SỨ MỆNH SEN VIỆT", "SEN VIỆT MISSION"), systemImage: "sparkles")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(.indigo)
                    Spacer()
                    Text(prefs.tr(
                        "InputMethodKit Chuẩn Apple • Pure Swift 6 • 100% Offline",
                        "Apple InputMethodKit Native • Pure Swift 6 • 100% Offline"
                    ))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }

                Text(prefs.tr(
                    "\"Hãy để việc gõ là gõ — dù bạn gõ tiếng Việt hay tiếng Anh; nhanh hay chậm; gõ là Sen Việt.\"",
                    "\"Just type naturally — Vietnamese or English, fast or slow; Sen Việt handles the rest seamlessly.\""
                ))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(.primary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    aboutFeaturePill(icon: "bolt.fill", text: prefs.tr("Phản hồi tức thì (< 1ms)", "Instant response (< 1ms)"), color: .orange)
                    aboutFeaturePill(icon: "globe", text: prefs.tr("Song ngữ Anh–Việt tự động", "Auto EN–VI Bilingual"), color: .indigo)
                    aboutFeaturePill(icon: "lock.shield.fill", text: prefs.tr("Không cần quyền Trợ năng", "No Accessibility needed"), color: .green)
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

            // Hàng 2: 2 thẻ Thông tin kỹ thuật & Giấy phép (Cân đối, không quảng cáo)
            HStack(spacing: 12) {
                // Thẻ Trái: Quyền riêng tư & An toàn
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.green.opacity(0.14))
                                .frame(width: 28, height: 28)
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundColor(.green)
                        }

                        VStack(alignment: .leading, spacing: 1.5) {
                            HStack(spacing: 5) {
                                Text(prefs.tr("Quyền riêng tư & An toàn", "Privacy & Security"))
                                    .font(.system(size: 12.5, weight: .bold))
                                Text("100% OFFLINE")
                                    .font(.system(size: 8.5, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Color.green.opacity(0.14))
                                    .foregroundColor(.green)
                                    .clipShape(Capsule())
                            }
                            Text(prefs.tr("Không thu thập hay gửi dữ liệu phím gõ", "Never collects or uploads keystrokes"))
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                        }

                        Spacer(minLength: 0)
                    }

                    Text(prefs.tr(
                        "Xử lý toàn bộ phím gõ cục bộ trên thiết bị, không cần quyền Trợ năng và tự động bỏ qua ô mật khẩu.",
                        "All keystrokes are processed locally on-device with no Accessibility permissions, automatically bypassing password fields."
                    ))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(cardSurfaceColor)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.green.opacity(isDark ? 0.35 : 0.22), lineWidth: 0.9)
                )

                // Thẻ Phải: Giấy phép Mã nguồn mở MIT
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.indigo.opacity(0.14))
                                .frame(width: 28, height: 28)
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.indigo)
                        }

                        VStack(alignment: .leading, spacing: 1.5) {
                            HStack(spacing: 5) {
                                Text(prefs.tr("Mã nguồn mở", "Open Source"))
                                    .font(.system(size: 12.5, weight: .bold))
                                Text("MIT LICENSE")
                                    .font(.system(size: 8.5, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Color.indigo.opacity(0.14))
                                    .foregroundColor(.indigo)
                                    .clipShape(Capsule())
                            }
                            Text(prefs.tr("Đa nền tảng macOS • Windows • Linux", "Cross-platform: macOS • Windows • Linux"))
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                        }

                        Spacer(minLength: 0)
                    }

                    Text(prefs.tr(
                        "Sen Việt (VieLotusIM) phát hành miễn phí theo giấy phép MIT. Mã nguồn minh bạch, kiểm chứng công khai trên GitHub.",
                        "Sen Việt (VieLotusIM) is free and open-source under the MIT License, with verifiable source code on GitHub."
                    ))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(cardSurfaceColor)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.indigo.opacity(isDark ? 0.35 : 0.22), lineWidth: 0.9)
                )
            }
            .frame(height: 112)

            // Hàng 3: Thanh Hỗ trợ, Cộng đồng & Mã nguồn (Toàn chiều ngang)
            HStack(spacing: 12) {
                Button {
                    showingFeedbackSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "bubble.left.and.text.bubble.right.fill")
                            .foregroundColor(.indigo)
                        Text(prefs.tr("Gửi Góp ý & Báo lỗi", "Feedback & Bug Report"))
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
                    Link(prefs.tr("Cộng đồng Zalo ↗", "Zalo Community ↗"), destination: zaloURL)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.primary)
                }

                Text("•").foregroundColor(.secondary)

                if let ghURL = URL(string: "https://github.com/stevedat/VieLotus-IM") {
                    Link(prefs.tr("Mã nguồn GitHub ↗", "GitHub Source ↗"), destination: ghURL)
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
                    Text(prefs.tr("Kiểm tra cập nhật", "Check Updates"))
                        .font(.system(size: 10, weight: .medium))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 1.5)
                .background(isDark ? Color.white.opacity(0.08) : Color.secondary.opacity(0.10))
                .foregroundColor(.secondary)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(prefs.tr(
                "Kiểm tra phiên bản mới từ GitHub Releases (có xác thực SHA-256)",
                "Check for updates from GitHub Releases (SHA-256 verified)"
            ))

        case .checking:
            HStack(spacing: 4) {
                Image(systemName: "hourglass")
                    .font(.system(size: 9, weight: .semibold))
                Text(prefs.tr("Đang kiểm tra...", "Checking..."))
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
                    Text(prefs.tr("Bản mới nhất", "Up to date"))
                        .font(.system(size: 10, weight: .semibold))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 1.5)
                .background(Color.green.opacity(isDark ? 0.20 : 0.12))
                .foregroundColor(.green)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(prefs.tr("Đang dùng bản mới nhất • Bấm để kiểm tra lại", "You're up to date • Click to recheck"))

        case .updateAvailable(let manifest):
            Button {
                Task { await updater.downloadAndInstallUpdate() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 9.5, weight: .bold))
                    Text(prefs.tr("Cập nhật v\(manifest.version)", "Update v\(manifest.version)"))
                        .font(.system(size: 10, weight: .bold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.green)
                .foregroundColor(.white)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(prefs.tr(
                "Tải về VieLotusIM.pkg v\(manifest.version), đối chiếu SHA-256 và cài đặt tự động",
                "Download VieLotusIM.pkg v\(manifest.version), verify SHA-256 and install"
            ))

        case .downloading(let progress):
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 9.5, weight: .semibold))
                Text(prefs.tr("Đang tải \(Int(progress * 100))%...", "Downloading \(Int(progress * 100))%..."))
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
                Text(prefs.tr("Đang cài đặt...", "Installing..."))
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
                    Text(prefs.tr("Thử lại cập nhật", "Retry Update"))
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
                    Text(prefs.tr("Tương thích Ứng dụng", "App Compatibility"))
                        .font(.system(size: 14, weight: .bold))
                    Text(prefs.tr(
                        "Mặc định dùng Direct cho app native và Native Marked Text (ổn định nhất đã kiểm thử) cho Chromium/Electron",
                        "Defaults to Direct for native apps and tested Native Marked Text for Chromium/Electron"
                    ))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(prefs.tr("Đóng", "Close")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(prefs.tr("Chế độ toàn cục:", "Global Mode:"))
                        .font(.system(size: 11.5, weight: .semibold))
                    Picker("", selection: $prefs.presentationModePreference) {
                        Text(prefs.tr("Mặc định (Tự động theo ứng dụng)", "Automatic (Per-app smart default)")).tag(PresentationModePreference.automatic)
                        Text(prefs.tr("Ưu tiên Direct (Thử nghiệm trên Web)", "Prefer Direct (Experimental on Web)")).tag(PresentationModePreference.directReplacement)
                        Text("Native Marked Text").tag(PresentationModePreference.markedText)
                    }
                    .labelsHidden()
                    .frame(width: 265)

                    Spacer()

                    if !prefs.appModeOverrides.isEmpty ||
                        !ClientAdapter.forcedMarkedTextBundles().isEmpty ||
                        prefs.presentationModePreference != .automatic ||
                        prefs.experimentalVerifiedExplicitRange {
                        Button(prefs.tr("Khôi phục mặc định", "Restore Defaults")) {
                            prefs.presentationModePreference = .automatic
                            prefs.experimentalVerifiedExplicitRange = false
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
        .frame(width: 590, height: 370)
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
                Text(prefs.tr("Mặc định", "Automatic")).tag(PresentationModePreference.automatic)
                Text(app.category == .chromium
                     ? prefs.tr("Direct (Thử nghiệm)", "Direct (Experimental)")
                     : prefs.tr("Direct (Không gạch)", "Direct (No underline)")).tag(PresentationModePreference.directReplacement)
                Text("Native Marked Text").tag(PresentationModePreference.markedText)
                Text("Passthrough").tag(PresentationModePreference.passthrough)
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 155)
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
            case .directReplacement:
                if category == .chromium {
                    return (prefs.tr("Ghim • Direct (Thử nghiệm)", "Pinned • Direct (Experimental)"), .orange)
                }
                return (prefs.tr("Ghim • Không gạch chân", "Pinned • No underline"), .green)
            case .markedText: return (prefs.tr("Ghim • Native Marked Text", "Pinned • Native Marked Text"), .blue)
            case .terminalDirect: return (prefs.tr("Ghim • Terminal Direct", "Pinned • Terminal Direct"), .teal)
            case .passthrough: return (prefs.tr("Ghim • Tắt bộ gõ", "Pinned • Bypass IME"), .secondary)
            }
        default:
            switch mode {
            case .directReplacement:
                if category == .chromium {
                    return (prefs.tr("Direct • Thử nghiệm", "Direct • Experimental"), .orange)
                }
                return (prefs.tr("Direct • Không gạch chân", "Direct • No underline"), .green)
            case .markedText:
                if category == .chromium {
                    return (prefs.tr("Native Marked Text • Mặc định", "Native Marked Text • Default"), .indigo)
                }
                return (prefs.tr("Native Marked Text • Ổn định", "Native Marked Text • Stable"), .blue)
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
