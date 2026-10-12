import Foundation
import Combine

/// Configuration and persistent settings for the iOS VieLotus Keyboard Extension and Host App.
public final class KeyboardPreferences: ObservableObject, @unchecked Sendable {
    public static let shared = KeyboardPreferences()

    private let defaults: UserDefaults
    public static let defaultSuiteName = "group.com.vietlotus.keyboard"

    public init(defaults: UserDefaults? = nil) {
        if let custom = defaults {
            self.defaults = custom
        } else if let groupDefaults = UserDefaults(suiteName: Self.defaultSuiteName) {
            self.defaults = groupDefaults
        } else {
            self.defaults = .standard
        }
    }

    public var inputMethod: InputMethodType {
        get {
            let raw = defaults.string(forKey: "inputMethod") ?? "telex"
            return raw == "vni" ? .vni : .telex
        }
        set {
            objectWillChange.send()
            defaults.set(newValue == .vni ? "vni" : "telex", forKey: "inputMethod")
        }
    }

    public var smartBilingual: Bool {
        get {
            if defaults.object(forKey: "smartBilingual") == nil { return true }
            return defaults.bool(forKey: "smartBilingual")
        }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: "smartBilingual")
        }
    }

    public var modernOrthography: Bool {
        get {
            if defaults.object(forKey: "modernOrthography") == nil { return true }
            return defaults.bool(forKey: "modernOrthography")
        }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: "modernOrthography")
        }
    }

    public var hapticFeedbackEnabled: Bool {
        get {
            if defaults.object(forKey: "hapticFeedbackEnabled") == nil { return true }
            return defaults.bool(forKey: "hapticFeedbackEnabled")
        }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: "hapticFeedbackEnabled")
        }
    }

    public var soundFeedbackEnabled: Bool {
        get {
            if defaults.object(forKey: "soundFeedbackEnabled") == nil { return true }
            return defaults.bool(forKey: "soundFeedbackEnabled")
        }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: "soundFeedbackEnabled")
        }
    }

    public var macroEnabled: Bool {
        get {
            if defaults.object(forKey: "macroEnabled") == nil { return true }
            return defaults.bool(forKey: "macroEnabled")
        }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: "macroEnabled")
        }
    }

    public var showNumberRow: Bool {
        get {
            if let custom = defaults.object(forKey: "showNumberRow") as? Bool {
                return custom
            }
            return inputMethod == .vni
        }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: "showNumberRow")
        }
    }

    public var autoCapitalizationEnabled: Bool {
        get {
            if defaults.object(forKey: "autoCapitalizationEnabled") == nil { return true }
            return defaults.bool(forKey: "autoCapitalizationEnabled")
        }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: "autoCapitalizationEnabled")
        }
    }

    public var periodShortcutEnabled: Bool {
        get {
            if defaults.object(forKey: "periodShortcutEnabled") == nil { return true }
            return defaults.bool(forKey: "periodShortcutEnabled")
        }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: "periodShortcutEnabled")
        }
    }
}
