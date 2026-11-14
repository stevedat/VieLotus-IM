#if !VIELOTUS_OPEN_CORE_MACOS && !os(Android)
import Foundation
#if os(iOS) || os(macOS)
import notify
#endif
#if canImport(Combine)
import Combine
public typealias PreferencesObservableBase = ObservableObject
#else
public protocol PreferencesObservableBase: AnyObject {}
#endif

/// Outfit color palette for Chú Trâu Luti (Mascot 1 & Mascot 2).
public enum MascotOutfitStyle: Int, CaseIterable, Sendable, Identifiable {
    case denimBlue = 0
    case lotusPink = 1
    case royalGold = 2
    case emeraldMint = 3

    public var id: Int { rawValue }

    public var displayName: String {
        #if os(iOS) && !BUDDYKEY_MASCOT
        return ""
        #else
        switch self {
        case .denimBlue: return "Xanh Denim"
        case .lotusPink: return "Hồng Sen"
        case .royalGold: return "Vàng Kim"
        case .emeraldMint: return "Xanh Ngọc"
        }
        #endif
    }
}

/// Headwear / accessory options for Chú Trâu Luti (Mascot 1 & Mascot 2).
public enum MascotAccessory: Int, CaseIterable, Sendable, Identifiable {
    case none = 0
    case nonLa = 1
    case sunglasses = 2
    case crown = 3
    case bowRibbon = 4

    public var id: Int { rawValue }

    public var displayName: String {
        #if os(iOS) && !BUDDYKEY_MASCOT
        return ""
        #else
        switch self {
        case .none: return "Mặc định"
        case .nonLa: return "Nón lá 🌾"
        case .sunglasses: return "Kính râm 😎"
        case .crown: return "Vương miện 👑"
        case .bowRibbon: return "Nơ hồng 🎀"
        }
        #endif
    }
}

/// Customizable ambient & interaction particle effects for Chú Trâu Luti & Couple Mode.
public enum MascotEffectStyle: Int, CaseIterable, Sendable, Identifiable {
    case floatingHearts = 0
    case sparkleStars = 1
    case lotusPetals = 2
    case musicNotes = 3
    case none = 4

    public var id: Int { rawValue }

    public var displayName: String {
        #if os(iOS) && !BUDDYKEY_MASCOT
        return ""
        #else
        switch self {
        case .floatingHearts: return "Tim bay 💕"
        case .sparkleStars: return "Sao lấp lánh ✨"
        case .lotusPetals: return "Hoa sen 🌸"
        case .musicNotes: return "Nốt nhạc 🎵"
        case .none: return "Tắt hiệu ứng"
        }
        #endif
    }

    public var shortIcon: String {
        #if os(iOS) && !BUDDYKEY_MASCOT
        return ""
        #else
        switch self {
        case .floatingHearts: return "💕"
        case .sparkleStars: return "✨"
        case .lotusPetals: return "🌸"
        case .musicNotes: return "🎵"
        case .none: return "🚫"
        }
        #endif
    }
}

/// Decorative outer border / aura style baked into the `34×34 pt` Chibi medallion ("Viền ngoài viên Chibi").
public enum MascotChibiBorderStyle: Int, CaseIterable, Sendable, Identifiable {
    case classic3D = 0
    case crystalPearl = 1
    case pastelRainbow = 2
    case lotusGarland = 3
    case neonGlow = 4

    public var id: Int { rawValue }

    public var displayName: String {
        #if os(iOS) && !BUDDYKEY_MASCOT
        return ""
        #else
        switch self {
        case .classic3D: return "Mặc định 3D 🔘"
        case .crystalPearl: return "Ngọc trai pha lê 💎"
        case .pastelRainbow: return "Cầu vồng Pastel 🌈"
        case .lotusGarland: return "Vòng hoa sen 🌸"
        case .neonGlow: return "Hào quang phát sáng 💫"
        }
        #endif
    }

    public var shortIcon: String {
        #if os(iOS) && !BUDDYKEY_MASCOT
        return ""
        #else
        switch self {
        case .classic3D: return "🔘"
        case .crystalPearl: return "💎"
        case .pastelRainbow: return "🌈"
        case .lotusGarland: return "🌸"
        case .neonGlow: return "💫"
        }
        #endif
    }
}

/// Zero-overhead system font descriptor styles for the floating reminder/greeting badge ("Font chữ lời nhắc").
public enum MascotReminderFontStyle: Int, CaseIterable, Sendable, Identifiable {
    case rounded = 0
    case handwritten = 1
    case classicSerif = 2
    case monospaced = 3

    public var id: Int { rawValue }

    public var displayName: String {
        #if os(iOS) && !BUDDYKEY_MASCOT
        return ""
        #else
        switch self {
        case .rounded: return "Bo tròn dễ thương 🔤"
        case .handwritten: return "Viết tay mềm mại ✍️"
        case .classicSerif: return "Báo chí thanh lịch 📖"
        case .monospaced: return "Code hiện đại ⌨️"
        }
        #endif
    }

    public var shortIcon: String {
        #if os(iOS) && !BUDDYKEY_MASCOT
        return ""
        #else
        switch self {
        case .rounded: return "🔤"
        case .handwritten: return "✍️"
        case .classicSerif: return "📖"
        case .monospaced: return "⌨️"
        }
        #endif
    }
}

/// Trending GPU-driven kinetic movement & dance styles ("Kiểu chuyển động").
public enum MascotMotionStyle: Int, CaseIterable, Sendable, Identifiable {
    case playfulStroll = 0
    case mochiBounce = 1
    case vibeBeat = 2
    case coupleBoop = 3
    case cloudFloat = 4

    public var id: Int { rawValue }

    public var displayName: String {
        #if os(iOS) && !BUDDYKEY_MASCOT
        return ""
        #else
        switch self {
        case .playfulStroll: return "Đi bộ tinh nghịch 🐾"
        case .mochiBounce: return "Nhún nhảy Mochi 🍮"
        case .vibeBeat: return "Lắc lư bắt Beat 💃"
        case .coupleBoop: return "Cụng má Boop 💞"
        case .cloudFloat: return "Lướt mây Zero-G ☁️"
        }
        #endif
    }

    public var shortIcon: String {
        #if os(iOS) && !BUDDYKEY_MASCOT
        return ""
        #else
        switch self {
        case .playfulStroll: return "🐾"
        case .mochiBounce: return "🍮"
        case .vibeBeat: return "💃"
        case .coupleBoop: return "💞"
        case .cloudFloat: return "☁️"
        }
        #endif
    }
}

/// 5-second idle reminder / sticky-note & greeting presets ("Lời nhắc & Nhắc nhau").
public enum MascotFishingPreset: Int, CaseIterable, Sendable, Identifiable {
    case iLoveYou = 0
    case missYou = 1
    case cheerUp = 2
    case milkTea = 3
    case happyDay = 4
    case customText = 5
    case drinkWater = 6
    case relaxEyes = 7

    public var id: Int { rawValue }

    public var displayName: String {
        #if os(iOS) && !BUDDYKEY_MASCOT
        return ""
        #else
        switch self {
        case .drinkWater: return "Nhớ uống nước nhé 💧"
        case .relaxEyes: return "Nghỉ mắt chút nha 👀"
        case .cheerUp: return "Cố lên nhé! 💪"
        case .iLoveYou: return "I love you ❤️"
        case .missYou: return "Nhớ thương nhiều 💕"
        case .milkTea: return "Uống trà sữa nha 🧋"
        case .happyDay: return "Ngày mới vui vẻ ✨"
        case .customText: return "Ghi chú / Lời nhắc riêng ✍️"
        }
        #endif
    }

    public var shortQuickLabel: String {
        #if os(iOS) && !BUDDYKEY_MASCOT
        return ""
        #else
        switch self {
        case .drinkWater: return "Uống nước 💧"
        case .relaxEyes: return "Nghỉ mắt 👀"
        case .cheerUp: return "Cố lên! 💪"
        case .iLoveYou: return "I love you ❤️"
        case .missYou: return "Nhớ thương 💕"
        case .milkTea: return "Trà sữa 🧋"
        case .happyDay: return "Vui vẻ ✨"
        case .customText: return "Ghi chú riêng ✍️"
        }
        #endif
    }

    public func steps(customText: String) -> (step1: String, step2: String, final: String) {
        #if os(iOS) && !BUDDYKEY_MASCOT
        return ("", "", "")
        #else
        switch self {
        case .drinkWater:
            return ("Nhớ...", "Uống nước...", "Nhớ uống nước nhé 💧")
        case .relaxEyes:
            return ("Nghỉ...", "Nghỉ mắt...", "Nghỉ mắt chút nha 👀")
        case .iLoveYou:
            return ("I...", "I love...", "I love you ❤️")
        case .missYou:
            return ("Nhớ...", "Nhớ thương...", "Nhớ thương nhiều 💕")
        case .cheerUp:
            return ("Cố...", "Cố lên...", "Cố lên nhé! 💪")
        case .milkTea:
            return ("Uống...", "Trà sữa...", "Uống trà sữa nha 🧋")
        case .happyDay:
            return ("Ngày...", "Ngày mới...", "Ngày mới vui vẻ ✨")
        case .customText:
            let trimmed = customText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return ("Nhớ...", "Uống nước...", "Nhớ uống nước nhé 💧")
            }
            let words = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            if words.count >= 3 {
                return ("\(words[0])...", "\(words[0]) \(words[1])...", trimmed)
            } else if words.count == 2 {
                return ("\(words[0])...", "\(words[0])...", trimmed)
            } else {
                let prefix = String(trimmed.prefix(min(3, trimmed.count)))
                return ("\(prefix)...", trimmed, trimmed)
            }
        }
        #endif
    }
}

/// Movement range for the mascot when the keyboard is idle vs. when typing.
public enum MascotRoamArea: Int, CaseIterable, Sendable, Identifiable {
    case barOnly = 0
    case fullKeyboard = 1

    public var id: Int { rawValue }

    public var displayName: String {
        #if os(iOS) && !BUDDYKEY_MASCOT
        return ""
        #else
        switch self {
        case .barOnly: return "Chỉ trên thanh"
        case .fullKeyboard: return "Toàn bàn phím ✨"
        }
        #endif
    }

    public var subtitle: String {
        #if os(iOS) && !BUDDYKEY_MASCOT
        return ""
        #else
        switch self {
        case .barOnly:
            return "Miễn phí — Khi nghỉ đi dạo toàn thanh gợi ý; khi gõ thu gọn trong khung góc trái"
        case .fullKeyboard:
            return "Gói Flex ✨ — Khi nghỉ 5s dạo chơi khắp toàn màn hình bàn phím & thả câu"
        }
        #endif
    }
}

/// Subscription / One-time purchase tier for Gói nâng cấp SenFlex (Mascot Couple, Face Avatar, Full-Keyboard Roaming & Custom Fishing Text).
public enum MascotFlexPlan: Int, CaseIterable, Sendable, Identifiable {
    case free = 0
    case yearly = 1
    case lifetime = 2

    public var id: Int { rawValue }

    public var productID: String {
        #if os(iOS) && !BUDDYKEY_MASCOT
        return ""
        #else
        switch self {
        case .free: return ""
        case .yearly: return "org.vielotus.flex.yearly"
        case .lifetime: return "org.vielotus.flex.lifetime"
        }
        #endif
    }

    public var displayName: String {
        #if os(iOS) && !BUDDYKEY_MASCOT
        return ""
        #else
        switch self {
        case .free: return "Miễn phí"
        case .yearly: return "Flex Theo Năm"
        case .lifetime: return "Flex Trọn Đời"
        }
        #endif
    }

    public var defaultPriceLabel: String {
        #if os(iOS) && !BUDDYKEY_MASCOT
        return ""
        #else
        switch self {
        case .free: return "0đ"
        case .yearly: return "49.000đ / năm"
        case .lifetime: return "99.000đ (Trọn đời)"
        }
        #endif
    }
}

/// Configuration and persistent settings for the iOS VieLotus Keyboard Extension and Host App.
public final class KeyboardPreferences: PreferencesObservableBase, @unchecked Sendable {
    public static let shared = KeyboardPreferences()

    private let defaults: UserDefaults
    private let localDefaults: UserDefaults?
    private let usesSharedChannel: Bool
    private var lastLocalMutationTime: TimeInterval = 0
    #if os(iOS) || os(macOS)
    private var notifyToken: Int32 = -1
    private var suggestionsNotifyToken: Int32 = -1
    private static let darwinSharedSyncRegistration: Void = {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(
            center,
            nil,
            { _, _, _, _, _ in
                DispatchQueue.main.async {
                    KeyboardPreferences.shared.syncFromSharedState()
                }
            },
            KeyboardPreferences.preferencesDidChangeDarwinNotification as CFString,
            nil,
            .deliverImmediately
        )
    }()
    #endif
    public static let defaultSuiteName = "group.com.vietlotus.keyboard"
    public static let preferencesDidChangeDarwinNotification = "org.vielotus.keyboard.preferencesChanged.v4"

    private static let syncedPreferenceKeys: [String] = [
        "inputMethodV2",
        "grammarProfile",
        "smartBilingual",
        "wordSuggestionsEnabledV1",
        "modernOrthography",
        "hapticFeedbackEnabled",
        "soundFeedbackEnabled",
        "macroEnabledV2",
        "showNumberRowV2",
        "showCommaKeyV1",
        "autoCapitalizationEnabled",
        "periodShortcutEnabled",
        "periodShortcutDecoupledV2",
        "glideTypingUserEnabledV2",
        "genZModeV2",
        "keyboardThemeV1",
        "mascotEnabledV1",
        "mascotCoupleEnabledV1",
        "mascot1OutfitV1",
        "mascot1AccessoryV1",
        "mascot2OutfitV1",
        "mascot2AccessoryV1",
        "mascotFishingPresetV1",
        "mascotFaceRevisionV1",
        "mascotAdvancedModeV1",
        "mascotChibiFrameV1",
        "mascotRoamAreaV1",
        "mascotFlexUnlockedV1",
        "mascotFlexPlanV1",
        "mascotReminderEnabledV1",
        "mascotEffectStyleV1",
        "mascotChibiBorderStyleV1",
        "mascotReminderFontStyleV1",
        "mascotMotionStyleV1"
    ]

    private func reconcileDiskStores() {
        guard let local = localDefaults, local !== defaults else { return }
        let groupUpdatedAt = defaults.double(forKey: "preferencesUpdatedAtV1")
        let localUpdatedAt = local.double(forKey: "preferencesUpdatedAtV1")
        if groupUpdatedAt > localUpdatedAt + 0.001 {
            for key in Self.syncedPreferenceKeys {
                if let val = defaults.object(forKey: key) {
                    local.set(val, forKey: key)
                }
            }
            local.set(groupUpdatedAt, forKey: "preferencesUpdatedAtV1")
            local.synchronize()
        } else if localUpdatedAt > groupUpdatedAt + 0.001 {
            for key in Self.syncedPreferenceKeys {
                if let val = local.object(forKey: key) {
                    defaults.set(val, forKey: key)
                }
            }
            defaults.set(localUpdatedAt, forKey: "preferencesUpdatedAtV1")
            defaults.synchronize()
        } else if defaults.object(forKey: "inputMethodV2") == nil,
                  let localMethod = local.string(forKey: "inputMethodV2") {
            defaults.set(localMethod, forKey: "inputMethodV2")
            defaults.synchronize()
        } else if local.object(forKey: "inputMethodV2") == nil,
                  let groupMethod = defaults.string(forKey: "inputMethodV2") {
            local.set(groupMethod, forKey: "inputMethodV2")
            local.synchronize()
        }
    }

    @inline(__always)
    private func persist(_ value: Any?, forKey key: String) {
        defaults.set(value, forKey: key)
        localDefaults?.set(value, forKey: key)
    }

    @inline(__always)
    private func persistedObject(forKey key: String) -> Any? {
        if let value = defaults.object(forKey: key) {
            return value
        }
        return localDefaults?.object(forKey: key)
    }

    @inline(__always)
    private func persistedString(forKey key: String) -> String? {
        if let value = defaults.string(forKey: key) {
            return value
        }
        return localDefaults?.string(forKey: key)
    }

    @inline(__always)
    private func persistedBool(forKey key: String, default defaultValue: Bool) -> Bool {
        if let value = persistedObject(forKey: key) as? Bool {
            return value
        }
        return defaultValue
    }

    @inline(__always)
    private func persistedInt(forKey key: String, default defaultValue: Int) -> Int {
        if let value = persistedObject(forKey: key) as? Int {
            return value
        }
        return defaultValue
    }

    @inline(__always)
    private func willChange() {
        #if canImport(Combine)
        objectWillChange.send()
        #endif
    }

    @inline(__always)
    private func didChange() {
        let now = Date().timeIntervalSince1970
        lastLocalMutationTime = now
        persist(now, forKey: "preferencesUpdatedAtV1")
        defaults.synchronize()
        localDefaults?.synchronize()
        #if os(iOS) || os(macOS)
        guard usesSharedChannel else { return }
        publishSharedState(mutationTimestamp: now)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(Self.preferencesDidChangeDarwinNotification as CFString),
            nil,
            nil,
            true
        )
        #endif
    }

    public init(defaults: UserDefaults? = nil, localDefaults: UserDefaults? = nil) {
        if let custom = defaults {
            self.defaults = custom
            self.localDefaults = localDefaults
            self.usesSharedChannel = false
        } else if let groupDefaults = UserDefaults(suiteName: Self.defaultSuiteName) {
            self.defaults = groupDefaults
            self.localDefaults = localDefaults ?? ((groupDefaults === UserDefaults.standard) ? nil : UserDefaults.standard)
            self.usesSharedChannel = true
        } else {
            self.defaults = .standard
            self.localDefaults = localDefaults
            self.usesSharedChannel = true
        }
        reconcileDiskStores()
        #if os(iOS) || os(macOS)
        if usesSharedChannel {
            _ = notify_register_check(Self.preferencesDidChangeDarwinNotification, &notifyToken)
            _ = notify_register_check("org.vielotus.keyboard.wordSuggestions.v1", &suggestionsNotifyToken)
            var suggestionsState: UInt64 = 0
            if suggestionsNotifyToken != -1,
               notify_get_state(suggestionsNotifyToken, &suggestionsState) == NOTIFY_STATUS_OK,
               suggestionsState & 1 == 0 {
                _ = notify_set_state(suggestionsNotifyToken,
                    persistedBool(forKey: "wordSuggestionsEnabledV1", default: false) ? 3 : 1)
            }
            _ = Self.darwinSharedSyncRegistration
            var state: UInt64 = 0
            if notifyToken != -1,
               notify_get_state(notifyToken, &state) == NOTIFY_STATUS_OK,
               (state & 1) == 1 {
                syncFromSharedState()
            } else if persistedObject(forKey: "inputMethodV2") != nil {
                // Fresh boot / reboot where notifyd state is 0, but disk defaults already
                // hold the user's persisted inputMethod: seed notifyd from disk immediately.
                publishSharedState()
            }
        }
        #endif
        migrateDecoupledPeriodShortcutIfNeeded()
    }

    private func migrateDecoupledPeriodShortcutIfNeeded() {
        let migrationKey = "autoCapitalizationDefaultOnV3"
        let groupMigrated = defaults.bool(forKey: migrationKey)
        let localMigrated = localDefaults?.bool(forKey: migrationKey) ?? false
        guard !groupMigrated && !localMigrated else { return }
        persist(true, forKey: migrationKey)
        persist(true, forKey: "periodShortcutDecoupledV2")
        var didMutate = false
        if persistedObject(forKey: "autoCapitalizationEnabled") as? Bool == false {
            persist(true, forKey: "autoCapitalizationEnabled")
            didMutate = true
        }
        if persistedObject(forKey: "periodShortcutEnabled") as? Bool == false {
            persist(true, forKey: "periodShortcutEnabled")
            didMutate = true
        }
        if didMutate {
            let now = Date().timeIntervalSince1970
            persist(now, forKey: "preferencesUpdatedAtV1")
            defaults.synchronize()
            localDefaults?.synchronize()
            #if os(iOS) || os(macOS)
            if usesSharedChannel && notifyToken != -1 {
                publishSharedState(mutationTimestamp: now)
            }
            #endif
        } else {
            defaults.synchronize()
            localDefaults?.synchronize()
        }
    }

    deinit {
        #if os(iOS) || os(macOS)
        if notifyToken != -1 {
            notify_cancel(notifyToken)
        }
        if suggestionsNotifyToken != -1 { notify_cancel(suggestionsNotifyToken) }
        #endif
    }

    public func publishSharedState(mutationTimestamp: TimeInterval? = nil) {
        #if os(iOS) || os(macOS)
        guard usesSharedChannel, notifyToken != -1 else { return }
        var state: UInt64 = 1 // bit 0: valid marker
        if inputMethod == .vni { state |= (1 << 1) }
        let grammarBits: UInt64
        switch grammarProfile {
        case .senFlex: grammarBits = 0
        case .classic: grammarBits = 1
        case .preVowel: grammarBits = 2
        case .smartHybrid: grammarBits = 3
        }
        state |= (grammarBits << 2)
        if smartBilingual { state |= (1 << 4) }
        if modernOrthography { state |= (1 << 5) }
        if hapticFeedbackEnabled { state |= (1 << 6) }
        if soundFeedbackEnabled { state |= (1 << 7) }
        if macroEnabled { state |= (1 << 8) }
        if let customNumRow = persistedObject(forKey: "showNumberRowV2") as? Bool {
            state |= (1 << 9)
            if customNumRow { state |= (1 << 10) }
        }
        if autoCapitalizationEnabled { state |= (1 << 11) }
        if periodShortcutEnabled { state |= (1 << 12) }
        if glideTypingEnabled { state |= (1 << 13) }
        if !genZMode { state |= (1 << 14) }
        let themeBits = UInt64(theme.rawValue & 0xF)
        state |= (themeBits << 15)
        if mascotEnabled { state |= (1 << 19) }
        if mascotCoupleEnabled { state |= (1 << 20) }
        state |= (UInt64(mascot1Outfit.rawValue & 0x3) << 21)
        state |= (UInt64(mascot1Accessory.rawValue & 0x7) << 23)
        state |= (UInt64(mascot2Outfit.rawValue & 0x3) << 26)
        state |= (UInt64(mascot2Accessory.rawValue & 0x7) << 28)
        state |= (UInt64(mascotFishingPreset.rawValue & 0x7) << 31)
        state |= (UInt64(mascotFaceRevision & 0xF) << 34)
        if mascotAdvancedModeEnabled { state |= (1 << 38) }
        if !mascotChibiFrameEnabled { state |= (1 << 39) }
        if mascotRoamArea == .barOnly { state |= (1 << 40) }
        if mascotFlexUnlocked { state |= (1 << 41) }
        state |= (UInt64(mascotFlexPlan.rawValue & 0x3) << 42)
        if !mascotReminderEnabled { state |= (1 << 44) }
        state |= (UInt64(mascotEffectStyle.rawValue & 0x7) << 45)
        state |= (UInt64(mascotChibiBorderStyle.rawValue & 0x7) << 48)
        state |= (UInt64(mascotReminderFontStyle.rawValue & 0x3) << 51)
        state |= (UInt64(mascotMotionStyle.rawValue & 0x7) << 53)
        if showCommaKey { state |= (1 << 56) }
        var priorNotifyState: UInt64 = 0
        _ = notify_get_state(notifyToken, &priorNotifyState)
        let priorPayload = priorNotifyState & 0x01FFFFFFFFFFFFFF
        let priorSeq = (priorNotifyState >> 57) & 0x7F
        let nextSeq: UInt64
        if (priorNotifyState & 1) == 1 && priorPayload == state {
            nextSeq = priorSeq == 0 ? 1 : priorSeq
        } else {
            let incremented = (priorSeq &+ 1) & 0x7F
            nextSeq = incremented == 0 ? 1 : incremented
        }
        state |= (nextSeq << 57)
        let setStatus = notify_set_state(notifyToken, state)
        let effectiveTs = mutationTimestamp ?? max(
            defaults.double(forKey: "preferencesUpdatedAtV1"),
            localDefaults?.double(forKey: "preferencesUpdatedAtV1") ?? 0
        )
        let stamp = effectiveTs > 0 ? effectiveTs : Date().timeIntervalSince1970
        persist(stamp, forKey: "notifyStateUpdatedAtV1")
        var observedState: UInt64 = 0
        if notify_get_state(notifyToken, &observedState) == NOTIFY_STATUS_OK, (observedState & 1) == 1 {
            persist(String(observedState), forKey: "lastSyncedNotifyStateV1")
        } else if setStatus == NOTIFY_STATUS_OK {
            persist(String(state), forKey: "lastSyncedNotifyStateV1")
        }
        defaults.synchronize()
        localDefaults?.synchronize()
        #endif
    }

    public func syncFromSharedState() {
        #if os(iOS) || os(macOS)
        guard usesSharedChannel, notifyToken != -1 else {
            reconcileDiskStores()
            return
        }
        if Date().timeIntervalSince1970 - lastLocalMutationTime < 0.45 {
            return
        }
        defaults.synchronize()
        localDefaults?.synchronize()
        reconcileDiskStores()
        let groupUpdatedAt = defaults.double(forKey: "preferencesUpdatedAtV1")
        let localUpdatedAt = localDefaults?.double(forKey: "preferencesUpdatedAtV1") ?? 0
        let effectiveUpdatedAt = max(groupUpdatedAt, localUpdatedAt)
        let notifyUpdatedAt = max(
            defaults.double(forKey: "notifyStateUpdatedAtV1"),
            localDefaults?.double(forKey: "notifyStateUpdatedAtV1") ?? 0
        )
        var state: UInt64 = 0
        guard notify_get_state(notifyToken, &state) == NOTIFY_STATUS_OK, (state & 1) == 1 else {
            if persistedObject(forKey: "inputMethodV2") != nil {
                publishSharedState(mutationTimestamp: effectiveUpdatedAt > 0 ? effectiveUpdatedAt : nil)
            }
            return
        }
        if effectiveUpdatedAt > 0 && effectiveUpdatedAt > notifyUpdatedAt + 0.001 {
            willChange()
            publishSharedState(mutationTimestamp: effectiveUpdatedAt)
            return
        }
        let lastSynced = localDefaults?.string(forKey: "lastSyncedNotifyStateV1") ?? defaults.string(forKey: "lastSyncedNotifyStateV1")
        if lastSynced == String(state) {
            migrateDecoupledPeriodShortcutIfNeeded()
            willChange()
            return
        }
        willChange()
        persist(((state >> 1) & 1) == 1 ? "vni" : "telex", forKey: "inputMethodV2")
        let grammarBits = (state >> 2) & 0x3
        let profile: GrammarProfile
        switch grammarBits {
        case 1: profile = .classic
        case 2: profile = .preVowel
        case 3: profile = .smartHybrid
        default: profile = .senFlex
        }
        persist(profile.rawValue, forKey: "grammarProfile")
        persist(((state >> 4) & 1) == 1, forKey: "smartBilingual")
        persist(((state >> 5) & 1) == 1, forKey: "modernOrthography")
        persist(((state >> 6) & 1) == 1, forKey: "hapticFeedbackEnabled")
        persist(((state >> 7) & 1) == 1, forKey: "soundFeedbackEnabled")
        persist(((state >> 8) & 1) == 1, forKey: "macroEnabledV2")
        if ((state >> 9) & 1) == 1 {
            persist(((state >> 10) & 1) == 1, forKey: "showNumberRowV2")
        }
        persist(((state >> 11) & 1) == 1, forKey: "autoCapitalizationEnabled")
        persist(((state >> 12) & 1) == 1, forKey: "periodShortcutEnabled")
        persist(((state >> 13) & 1) == 1, forKey: "glideTypingUserEnabledV2")
        persist(((state >> 14) & 1) == 0, forKey: "genZModeV2")
        let rawTheme = Int((state >> 15) & 0xF)
        let resolvedTheme = KeyboardThemeID(rawValue: rawTheme) ?? .systemAuto
        persist(resolvedTheme.rawValue, forKey: "keyboardThemeV1")
        persist(((state >> 19) & 1) == 1, forKey: "mascotEnabledV1")
        persist(((state >> 20) & 1) == 1, forKey: "mascotCoupleEnabledV1")
        persist(Int((state >> 21) & 0x3), forKey: "mascot1OutfitV1")
        persist(Int((state >> 23) & 0x7), forKey: "mascot1AccessoryV1")
        persist(Int((state >> 26) & 0x3), forKey: "mascot2OutfitV1")
        persist(Int((state >> 28) & 0x7), forKey: "mascot2AccessoryV1")
        persist(Int((state >> 31) & 0x7), forKey: "mascotFishingPresetV1")
        persist(Int((state >> 34) & 0xF), forKey: "mascotFaceRevisionV1")
        persist(((state >> 38) & 1) == 1, forKey: "mascotAdvancedModeV1")
        persist(((state >> 39) & 1) == 0, forKey: "mascotChibiFrameV1")
        persist(((state >> 40) & 1) == 1 ? MascotRoamArea.barOnly.rawValue : MascotRoamArea.fullKeyboard.rawValue, forKey: "mascotRoamAreaV1")
        persist(((state >> 41) & 1) == 1, forKey: "mascotFlexUnlockedV1")
        persist(Int((state >> 42) & 0x3), forKey: "mascotFlexPlanV1")
        persist(((state >> 44) & 1) == 0, forKey: "mascotReminderEnabledV1")
        persist(Int((state >> 45) & 0x7), forKey: "mascotEffectStyleV1")
        persist(Int((state >> 48) & 0x7), forKey: "mascotChibiBorderStyleV1")
        persist(Int((state >> 51) & 0x3), forKey: "mascotReminderFontStyleV1")
        persist(Int((state >> 53) & 0x7), forKey: "mascotMotionStyleV1")
        persist(((state >> 56) & 1) == 1, forKey: "showCommaKeyV1")
        let syncStamp = Date().timeIntervalSince1970
        persist(syncStamp, forKey: "preferencesUpdatedAtV1")
        persist(syncStamp, forKey: "notifyStateUpdatedAtV1")
        persist(String(state), forKey: "lastSyncedNotifyStateV1")
        defaults.synchronize()
        localDefaults?.synchronize()
        migrateDecoupledPeriodShortcutIfNeeded()
        #endif
    }

    public var inputMethod: InputMethodType {
        get {
            let raw = persistedString(forKey: "inputMethodV2") ?? "telex"
            return raw == "vni" ? .vni : .telex
        }
        set {
            willChange()
            persist(newValue == .vni ? "vni" : "telex", forKey: "inputMethodV2")
            didChange()
        }
    }

    public var grammarProfile: GrammarProfile {
        get {
            let raw = persistedString(forKey: "grammarProfile") ?? GrammarProfile.senFlex.rawValue
            return GrammarProfile(rawValue: raw) ?? .senFlex
        }
        set {
            willChange()
            persist(newValue.rawValue, forKey: "grammarProfile")
            didChange()
        }
    }

    /// Word completion, correction and next-word candidates are opt-in.
    public var wordSuggestionsEnabled: Bool {
        get {
            #if os(iOS) || os(macOS)
            var state: UInt64 = 0
            if usesSharedChannel, suggestionsNotifyToken != -1,
               notify_get_state(suggestionsNotifyToken, &state) == NOTIFY_STATUS_OK, state & 1 == 1 {
                return state & 2 != 0
            }
            #endif
            return persistedBool(forKey: "wordSuggestionsEnabledV1", default: false)
        }
        set {
            willChange()
            persist(newValue, forKey: "wordSuggestionsEnabledV1")
            #if os(iOS) || os(macOS)
            if usesSharedChannel, suggestionsNotifyToken != -1 {
                _ = notify_set_state(suggestionsNotifyToken, newValue ? 3 : 1)
            }
            #endif
            didChange()
        }
    }

    public var smartBilingual: Bool {
        get {
            persistedBool(forKey: "smartBilingual", default: true)
        }
        set {
            willChange()
            persist(newValue, forKey: "smartBilingual")
            didChange()
        }
    }

    public var modernOrthography: Bool {
        get {
            persistedBool(forKey: "modernOrthography", default: true)
        }
        set {
            willChange()
            persist(newValue, forKey: "modernOrthography")
            didChange()
        }
    }

    public var hapticFeedbackEnabled: Bool {
        get {
            persistedBool(forKey: "hapticFeedbackEnabled", default: true)
        }
        set {
            willChange()
            persist(newValue, forKey: "hapticFeedbackEnabled")
            didChange()
        }
    }

    public var soundFeedbackEnabled: Bool {
        get {
            persistedBool(forKey: "soundFeedbackEnabled", default: true)
        }
        set {
            willChange()
            persist(newValue, forKey: "soundFeedbackEnabled")
            didChange()
        }
    }

    public var macroEnabled: Bool {
        get {
            persistedBool(forKey: "macroEnabledV2", default: false)
        }
        set {
            willChange()
            persist(newValue, forKey: "macroEnabledV2")
            didChange()
        }
    }

    public var showNumberRow: Bool {
        get {
            persistedBool(forKey: "showNumberRowV2", default: false)
        }
        set {
            willChange()
            persist(newValue, forKey: "showNumberRowV2")
            didChange()
        }
    }

    /// Optional dedicated `,` punctuation key next to the Spacebar on Row 4.
    /// Defaults to `false` so Row 4 matches 100% Apple native iOS keyboard proportions (`[123] [Spacebar] [Return]`).
    public var showCommaKey: Bool {
        get {
            persistedBool(forKey: "showCommaKeyV1", default: false)
        }
        set {
            willChange()
            persist(newValue, forKey: "showCommaKeyV1")
            didChange()
        }
    }

    public var autoCapitalizationEnabled: Bool {
        get {
            persistedBool(forKey: "autoCapitalizationEnabled", default: true)
        }
        set {
            willChange()
            persist(newValue, forKey: "autoCapitalizationEnabled")
            didChange()
        }
    }

    public var periodShortcutEnabled: Bool {
        get {
            persistedBool(forKey: "periodShortcutEnabled", default: true)
        }
        set {
            willChange()
            persist(newValue, forKey: "periodShortcutEnabled")
            didChange()
        }
    }

    public var glideTypingEnabled: Bool {
        get {
            persistedBool(forKey: "glideTypingUserEnabledV2", default: false)
        }
        set {
            willChange()
            persist(newValue, forKey: "glideTypingUserEnabledV2")
            didChange()
        }
    }

    public var genZMode: Bool {
        get {
            persistedBool(forKey: "genZModeV2", default: true)
        }
        set {
            willChange()
            persist(newValue, forKey: "genZModeV2")
            didChange()
        }
    }

    public var theme: KeyboardThemeID {
        get {
            guard persistedObject(forKey: "keyboardThemeV1") != nil else {
                return .systemAuto
            }
            let raw = persistedInt(forKey: "keyboardThemeV1", default: KeyboardThemeID.systemAuto.rawValue)
            return KeyboardThemeID(rawValue: raw) ?? .systemAuto
        }
        set {
            willChange()
            persist(newValue.rawValue, forKey: "keyboardThemeV1")
            didChange()
        }
    }

    public var mascotEnabled: Bool {
        get {
            #if os(iOS) && !BUDDYKEY_MASCOT
            return false
            #else
            return persistedBool(forKey: "mascotEnabledV1", default: false)
            #endif
        }
        set {
            willChange()
            persist(newValue, forKey: "mascotEnabledV1")
            didChange()
        }
    }

    /// Indicates whether the user has unlocked the paid **Gói Flex** tier (`Flex Theo Năm` or `Flex Trọn Đời`).
    /// - When `false` (Free Tier): Chú Trâu Luti 3D mặc định roams across the horizontal candidate bar (`barOnly`) and casts the default `"I love you ❤️"` fishing message.
    /// - When `true` (Gói Flex): Unlocks Full-Keyboard 2D Roaming (`fullKeyboard`), Couple Mode (`mascotCoupleEnabled`), Custom Face Avatar & Chibi/Full-Bleed Frame (`mascotAdvancedModeEnabled`), and Custom Fishing Text (`mascotFishingPreset`).
    public var mascotFlexUnlocked: Bool {
        get {
            persistedBool(forKey: "mascotFlexUnlockedV1", default: false)
        }
        set {
            willChange()
            persist(newValue, forKey: "mascotFlexUnlockedV1")
            if !newValue {
                persist(MascotFlexPlan.free.rawValue, forKey: "mascotFlexPlanV1")
            }
            didChange()
        }
    }

    public var mascotFlexPlan: MascotFlexPlan {
        get {
            guard mascotFlexUnlocked else { return .free }
            let raw = persistedInt(forKey: "mascotFlexPlanV1", default: MascotFlexPlan.lifetime.rawValue)
            let plan = MascotFlexPlan(rawValue: raw) ?? .lifetime
            return plan == .free ? .lifetime : plan
        }
        set {
            willChange()
            persist(newValue.rawValue, forKey: "mascotFlexPlanV1")
            persist(newValue != .free, forKey: "mascotFlexUnlockedV1")
            didChange()
        }
    }

    /// Separates Simple Mode (`false`: default full-body 3D Chú Trâu Luti) from Advanced Customization (`true`: Face-Only Chibi Circular Frame, Custom Face Avatar, Accessories & Couple Mode).
    public var mascotAdvancedModeEnabled: Bool {
        get {
            if persistedObject(forKey: "mascotAdvancedModeV1") == nil {
                // Smooth migration: if the user already enabled Couple Mode or saved a custom face photo, default Advanced Mode to true
                if persistedBool(forKey: "mascotCoupleEnabledV1", default: false) || loadCustomMascotFaceData(slot: 1) != nil {
                    return true
                }
                return false
            }
            return persistedBool(forKey: "mascotAdvancedModeV1", default: false)
        }
        set {
            willChange()
            persist(newValue, forKey: "mascotAdvancedModeV1")
            didChange()
        }
    }

    /// Enables Mascot 2 alongside Mascot 1 ("Chế độ Cặp đôi Couple").
    public var mascotCoupleEnabled: Bool {
        get {
            persistedBool(forKey: "mascotCoupleEnabledV1", default: false)
        }
        set {
            willChange()
            persist(newValue, forKey: "mascotCoupleEnabledV1")
            didChange()
        }
    }

    /// Controls whether the Chibi Circular Frame, Horns, Ears & 3D Accessories are drawn (`true`, default)
    /// or completely hidden so the circular face photo fills the maximum possible diameter (`false` — Full-Bleed Face Mode).
    public var mascotChibiFrameEnabled: Bool {
        get {
            persistedBool(forKey: "mascotChibiFrameV1", default: true)
        }
        set {
            willChange()
            persist(newValue, forKey: "mascotChibiFrameV1")
            didChange()
        }
    }

    public var mascotRoamArea: MascotRoamArea {
        get {
            guard mascotFlexUnlocked else { return .barOnly }
            guard persistedObject(forKey: "mascotRoamAreaV1") != nil else { return .fullKeyboard }
            return MascotRoamArea(rawValue: persistedInt(forKey: "mascotRoamAreaV1", default: MascotRoamArea.fullKeyboard.rawValue)) ?? .fullKeyboard
        }
        set {
            willChange()
            persist(newValue.rawValue, forKey: "mascotRoamAreaV1")
            didChange()
        }
    }

    public var mascot1Outfit: MascotOutfitStyle {
        get {
            guard persistedObject(forKey: "mascot1OutfitV1") != nil else { return .denimBlue }
            return MascotOutfitStyle(rawValue: persistedInt(forKey: "mascot1OutfitV1", default: MascotOutfitStyle.denimBlue.rawValue)) ?? .denimBlue
        }
        set {
            willChange()
            persist(newValue.rawValue, forKey: "mascot1OutfitV1")
            didChange()
        }
    }

    public var mascot1Accessory: MascotAccessory {
        get {
            guard persistedObject(forKey: "mascot1AccessoryV1") != nil else { return .none }
            return MascotAccessory(rawValue: persistedInt(forKey: "mascot1AccessoryV1", default: MascotAccessory.none.rawValue)) ?? .none
        }
        set {
            willChange()
            persist(newValue.rawValue, forKey: "mascot1AccessoryV1")
            didChange()
        }
    }

    public var mascot2Outfit: MascotOutfitStyle {
        get {
            guard persistedObject(forKey: "mascot2OutfitV1") != nil else { return .lotusPink }
            return MascotOutfitStyle(rawValue: persistedInt(forKey: "mascot2OutfitV1", default: MascotOutfitStyle.lotusPink.rawValue)) ?? .lotusPink
        }
        set {
            willChange()
            persist(newValue.rawValue, forKey: "mascot2OutfitV1")
            didChange()
        }
    }

    public var mascot2Accessory: MascotAccessory {
        get {
            guard persistedObject(forKey: "mascot2AccessoryV1") != nil else { return .bowRibbon }
            return MascotAccessory(rawValue: persistedInt(forKey: "mascot2AccessoryV1", default: MascotAccessory.bowRibbon.rawValue)) ?? .bowRibbon
        }
        set {
            willChange()
            persist(newValue.rawValue, forKey: "mascot2AccessoryV1")
            didChange()
        }
    }

    /// Customizable ambient & couple particle effect ("Hiệu ứng biểu cảm").
    public var mascotEffectStyle: MascotEffectStyle {
        get {
            guard persistedObject(forKey: "mascotEffectStyleV1") != nil else { return .floatingHearts }
            return MascotEffectStyle(rawValue: persistedInt(forKey: "mascotEffectStyleV1", default: MascotEffectStyle.floatingHearts.rawValue)) ?? .floatingHearts
        }
        set {
            willChange()
            persist(newValue.rawValue, forKey: "mascotEffectStyleV1")
            didChange()
        }
    }

    /// Decorative outer border / aura style baked into the `34×34 pt` Chibi medallion ("Viền ngoài viên Chibi").
    public var mascotChibiBorderStyle: MascotChibiBorderStyle {
        get {
            guard persistedObject(forKey: "mascotChibiBorderStyleV1") != nil else { return .classic3D }
            return MascotChibiBorderStyle(rawValue: persistedInt(forKey: "mascotChibiBorderStyleV1", default: MascotChibiBorderStyle.classic3D.rawValue)) ?? .classic3D
        }
        set {
            willChange()
            persist(newValue.rawValue, forKey: "mascotChibiBorderStyleV1")
            didChange()
        }
    }

    /// Zero-overhead system font style for the floating reminder/greeting badge ("Font chữ lời nhắc").
    public var mascotReminderFontStyle: MascotReminderFontStyle {
        get {
            guard persistedObject(forKey: "mascotReminderFontStyleV1") != nil else { return .rounded }
            return MascotReminderFontStyle(rawValue: persistedInt(forKey: "mascotReminderFontStyleV1", default: MascotReminderFontStyle.rounded.rawValue)) ?? .rounded
        }
        set {
            willChange()
            persist(newValue.rawValue, forKey: "mascotReminderFontStyleV1")
            didChange()
        }
    }

    /// Trending GPU-driven kinetic movement & dance style ("Kiểu chuyển động").
    public var mascotMotionStyle: MascotMotionStyle {
        get {
            guard persistedObject(forKey: "mascotMotionStyleV1") != nil else { return .playfulStroll }
            return MascotMotionStyle(rawValue: persistedInt(forKey: "mascotMotionStyleV1", default: MascotMotionStyle.playfulStroll.rawValue)) ?? .playfulStroll
        }
        set {
            willChange()
            persist(newValue.rawValue, forKey: "mascotMotionStyleV1")
            didChange()
        }
    }

    /// Controls whether the 5-second idle reminder / greeting banner ("Lời nhắc & Nhắc nhau") is shown (`true`, default) or muted (`false`).
    public var mascotReminderEnabled: Bool {
        get {
            persistedBool(forKey: "mascotReminderEnabledV1", default: true)
        }
        set {
            willChange()
            persist(newValue, forKey: "mascotReminderEnabledV1")
            didChange()
        }
    }

    public var mascotFishingPreset: MascotFishingPreset {
        get {
            guard persistedObject(forKey: "mascotFishingPresetV1") != nil else { return .iLoveYou }
            return MascotFishingPreset(rawValue: persistedInt(forKey: "mascotFishingPresetV1", default: MascotFishingPreset.iLoveYou.rawValue)) ?? .iLoveYou
        }
        set {
            willChange()
            persist(newValue.rawValue, forKey: "mascotFishingPresetV1")
            didChange()
        }
    }

    /// Title displayed on the quick reminder button inside the keyboard's `⚙️` inline settings panel.
    public var quickReminderButtonTitle: String {
        guard mascotReminderEnabled else {
            return "🔕 Nhắc nhau: Tắt ↻"
        }
        if mascotFishingPreset == .customText {
            let trimmed = customMascotFishingText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let preview = trimmed.count > 12 ? String(trimmed.prefix(11)) + "…" : trimmed
                return "📌 \(preview) ↻"
            }
        }
        return "📌 \(mascotFishingPreset.shortQuickLabel) ↻"
    }

    /// Cycles through built-in reminder/greeting presets (plus custom note when set) and an OFF state (`mascotReminderEnabled = false`).
    public func cycleQuickReminder() {
        var cycleOrder: [MascotFishingPreset] = [
            .drinkWater,
            .relaxEyes,
            .cheerUp,
            .iLoveYou,
            .missYou,
            .milkTea,
            .happyDay
        ]
        let trimmedCustom = customMascotFishingText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasCustomNote = !trimmedCustom.isEmpty && (trimmedCustom != "I love you ❤️" || mascotFishingPreset == .customText)
        if hasCustomNote {
            cycleOrder.append(.customText)
        }
        if !mascotReminderEnabled {
            mascotReminderEnabled = true
            mascotFishingPreset = cycleOrder[0]
            return
        }
        let current = mascotFishingPreset
        if let idx = cycleOrder.firstIndex(of: current) {
            if idx + 1 < cycleOrder.count {
                mascotFishingPreset = cycleOrder[idx + 1]
            } else {
                // Reached end of presets -> turn off reminders ("🔕 Nhắc nhau: Tắt")
                mascotReminderEnabled = false
            }
        } else {
            mascotFishingPreset = cycleOrder[0]
        }
    }

    public var customMascotFishingText: String {
        get {
            persistedString(forKey: "customMascotFishingTextV1") ?? "I love you ❤️"
        }
        set {
            willChange()
            let limited = String(newValue.prefix(28))
            persist(limited, forKey: "customMascotFishingTextV1")
            didChange()
        }
    }

    public var mascotFaceRevision: Int {
        get {
            persistedInt(forKey: "mascotFaceRevisionV1", default: 0)
        }
        set {
            willChange()
            persist(newValue & 0xF, forKey: "mascotFaceRevisionV1")
            didChange()
        }
    }

    private func customFaceFileURL(slot: Int) -> URL? {
        #if os(iOS) || os(macOS)
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.defaultSuiteName) else {
            return nil
        }
        return dir.appendingPathComponent("custom_mascot_face_\(slot).png")
        #else
        return nil
        #endif
    }

    public func saveCustomMascotFaceData(_ pngData: Data?, slot: Int) {
        let key = "customMascotFaceDataV1_\(slot)"
        if let pngData {
            defaults.set(pngData, forKey: key)
            if let url = customFaceFileURL(slot: slot) {
                try? pngData.write(to: url, options: .atomic)
            }
        } else {
            defaults.removeObject(forKey: key)
            if let url = customFaceFileURL(slot: slot) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        mascotFaceRevision = (mascotFaceRevision + 1) & 0xF
    }

    public func loadCustomMascotFaceData(slot: Int) -> Data? {
        let key = "customMascotFaceDataV1_\(slot)"
        if let data = defaults.data(forKey: key), !data.isEmpty {
            return data
        }
        if let url = customFaceFileURL(slot: slot),
           let data = try? Data(contentsOf: url), !data.isEmpty {
            return data
        }
        return nil
    }

    public func hasCustomMascotFace(slot: Int) -> Bool {
        loadCustomMascotFaceData(slot: slot) != nil
    }
}
#endif
