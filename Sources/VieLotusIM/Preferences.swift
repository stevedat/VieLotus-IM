import VieLotusCore
import Foundation
import Combine

public enum EngineBackend: String, CaseIterable, Sendable {
    case pureSwift = "pureSwift" // LotusEngine (Pure Swift 6)
}

final class Preferences: ObservableObject {
    static let shared = Preferences()
    private let defaults = UserDefaults.standard
    private var isReloading = false
    
    private enum Key {
        static let inputMethod = "VieLotusIM.inputMethod"
        static let modernOrthography = "VieLotusIM.modernOrthography"
        static let relaxedCoda = "VieLotusIM.relaxedCoda"
        static let quickTelex = "VieLotusIM.quickTelex"
        static let vietnameseEnabled = "VieLotusIM.vietnameseEnabled"
        static let smartBilingual = "VieLotusIM.smartBilingual"
        static let terminalDirectMode = "VieLotusIM.terminalDirectMode"
        static let presentationModePreference = "VieLotusIM.presentationModePreference"
        static let appModeOverrides = "VieLotusIM.appModeOverrides"
        static let developerMode = "VieLotusIM.developerMode"
        static let genZMode = "VieLotusIM.genZMode"
        static let engineBackend = "VieLotusIM.engineBackend"
        static let passthroughRemoteApps = "VieLotusIM.passthroughRemoteApps"
        static let enforceABCBaseLayout = "VieLotusIM.enforceABCBaseLayout"
        static let macroEnabled = "VieLotusIM.macroEnabled"
        static let grammarProfile = "VieLotusIM.grammarProfile"
    }
    
    private func flushDefaults() {
        defaults.synchronize()
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
    }

    @Published var inputMethod: InputMethodType {
        didSet {
            guard !isReloading else { return }
            defaults.set(Int(inputMethod.rawValue), forKey: Key.inputMethod)
            CFPreferencesSetAppValue(
                Key.inputMethod as CFString,
                NSNumber(value: inputMethod.rawValue),
                kCFPreferencesCurrentApplication
            )
            flushDefaults()
            DistributedNotificationCenter.default().postNotificationName(
                Self.preferencesChangedNotification,
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
        }
    }
    
    @Published var grammarProfile: GrammarProfile {
        didSet {
            defaults.set(grammarProfile.rawValue, forKey: Key.grammarProfile)
            flushDefaults()
        }
    }
    
    @Published var modernOrthography: Bool {
        didSet {
            defaults.set(modernOrthography, forKey: Key.modernOrthography)
            flushDefaults()
        }
    }
    
    @Published var relaxedCoda: Bool {
        didSet {
            defaults.set(relaxedCoda, forKey: Key.relaxedCoda)
            flushDefaults()
        }
    }
    
    @Published var quickTelex: Bool {
        didSet {
            defaults.set(quickTelex, forKey: Key.quickTelex)
            flushDefaults()
        }
    }
    
    @Published var vietnameseEnabled: Bool {
        didSet {
            defaults.set(vietnameseEnabled, forKey: Key.vietnameseEnabled)
            flushDefaults()
        }
    }
    
    @Published var smartBilingual: Bool {
        didSet {
            defaults.set(smartBilingual, forKey: Key.smartBilingual)
            flushDefaults()
        }
    }

    @Published var terminalDirectMode: Bool {
        didSet {
            defaults.set(terminalDirectMode, forKey: Key.terminalDirectMode)
            flushDefaults()
        }
    }

    @Published var presentationModePreference: PresentationModePreference {
        didSet {
            defaults.set(presentationModePreference.rawValue, forKey: Key.presentationModePreference)
            flushDefaults()
            ClientAdapter.resetDynamicMarkedText()
        }
    }

    @Published var appModeOverrides: [String: PresentationModePreference] {
        didSet {
            defaults.set(appModeOverrides.mapValues(\.rawValue), forKey: Key.appModeOverrides)
            flushDefaults()
            ClientAdapter.resetDynamicMarkedText()
        }
    }
    
    @Published var genZMode: Bool {
        didSet {
            defaults.set(genZMode, forKey: Key.genZMode)
            flushDefaults()
        }
    }
    
    @Published var passthroughRemoteApps: Bool {
        didSet {
            defaults.set(passthroughRemoteApps, forKey: Key.passthroughRemoteApps)
            flushDefaults()
        }
    }

    @Published var enforceABCBaseLayout: Bool {
        didSet {
            defaults.set(enforceABCBaseLayout, forKey: Key.enforceABCBaseLayout)
            flushDefaults()
        }
    }

    @Published var macroEnabled: Bool {
        didSet {
            defaults.set(macroEnabled, forKey: Key.macroEnabled)
            flushDefaults()
        }
    }

    @Published var developerMode: Bool {
        didSet {
            defaults.set(developerMode, forKey: Key.developerMode)
            flushDefaults()
        }
    }
    
    @Published var engineBackend: EngineBackend {
        didSet {
            defaults.set(engineBackend.rawValue, forKey: Key.engineBackend)
            flushDefaults()
        }
    }
    
    private init() {
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
        let rawMethod: Int
        if let cfNum = CFPreferencesCopyAppValue(Key.inputMethod as CFString, kCFPreferencesCurrentApplication) as? NSNumber {
            rawMethod = cfNum.intValue
        } else {
            rawMethod = defaults.integer(forKey: Key.inputMethod)
        }
        self.inputMethod = InputMethodType(rawValue: Int32(rawMethod)) ?? .telex
        
        self.modernOrthography = true
        self.relaxedCoda = defaults.bool(forKey: Key.relaxedCoda)
        self.quickTelex = defaults.bool(forKey: Key.quickTelex)
        self.vietnameseEnabled = defaults.object(forKey: Key.vietnameseEnabled) as? Bool ?? true
        self.smartBilingual = true
        self.terminalDirectMode = defaults.object(forKey: Key.terminalDirectMode) as? Bool ?? true
        self.passthroughRemoteApps = defaults.object(forKey: Key.passthroughRemoteApps) as? Bool ?? true
        self.enforceABCBaseLayout = defaults.object(forKey: Key.enforceABCBaseLayout) as? Bool ?? true
        self.macroEnabled = defaults.object(forKey: Key.macroEnabled) as? Bool ?? true
        let rawPresentationMode = defaults.string(forKey: Key.presentationModePreference) ?? PresentationModePreference.automatic.rawValue
        self.presentationModePreference = PresentationModePreference(rawValue: rawPresentationMode) ?? .automatic
        let storedOverrides = defaults.dictionary(forKey: Key.appModeOverrides) as? [String: String] ?? [:]
        self.appModeOverrides = storedOverrides.reduce(into: [:]) { result, entry in
            let bundleID = entry.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let preference = PresentationModePreference(rawValue: entry.value),
               preference != .automatic,
               !bundleID.isEmpty {
                result[bundleID] = preference
            }
        }
        self.genZMode = true
        self.developerMode = defaults.object(forKey: Key.developerMode) as? Bool ?? false
        
        self.grammarProfile = .senFlex
        defaults.set(GrammarProfile.senFlex.rawValue, forKey: Key.grammarProfile)
        defaults.set(true, forKey: Key.smartBilingual)
        defaults.set(true, forKey: Key.modernOrthography)
        defaults.set(true, forKey: Key.genZMode)
        
        let rawBackend = defaults.string(forKey: Key.engineBackend) ?? EngineBackend.pureSwift.rawValue
        self.engineBackend = EngineBackend(rawValue: rawBackend) ?? .pureSwift

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleExternalPreferencesChange),
            name: Self.preferencesChangedNotification,
            object: nil
        )
    }

    public static let preferencesChangedNotification = Notification.Name("org.vielotus.inputmethod.preferencesChanged")

    @objc private func handleExternalPreferencesChange() {
        reload()
    }

    public func reload() {
        isReloading = true
        defer { isReloading = false }
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
        let rawMethod: Int
        if let cfNum = CFPreferencesCopyAppValue(Key.inputMethod as CFString, kCFPreferencesCurrentApplication) as? NSNumber {
            rawMethod = cfNum.intValue
        } else {
            rawMethod = defaults.integer(forKey: Key.inputMethod)
        }
        let resolvedMethod = InputMethodType(rawValue: Int32(rawMethod)) ?? .telex
        if self.inputMethod != resolvedMethod {
            self.inputMethod = resolvedMethod
        }

        self.grammarProfile = .senFlex

        self.modernOrthography = true
        self.relaxedCoda = defaults.bool(forKey: Key.relaxedCoda)
        self.quickTelex = defaults.bool(forKey: Key.quickTelex)
        self.vietnameseEnabled = defaults.object(forKey: Key.vietnameseEnabled) as? Bool ?? true
        self.smartBilingual = true
        self.terminalDirectMode = defaults.object(forKey: Key.terminalDirectMode) as? Bool ?? true
        self.passthroughRemoteApps = defaults.object(forKey: Key.passthroughRemoteApps) as? Bool ?? true
        self.enforceABCBaseLayout = defaults.object(forKey: Key.enforceABCBaseLayout) as? Bool ?? true
        self.macroEnabled = defaults.object(forKey: Key.macroEnabled) as? Bool ?? true
        let rawPresentationMode = defaults.string(forKey: Key.presentationModePreference) ?? PresentationModePreference.automatic.rawValue
        self.presentationModePreference = PresentationModePreference(rawValue: rawPresentationMode) ?? .automatic
        let storedOverrides = defaults.dictionary(forKey: Key.appModeOverrides) as? [String: String] ?? [:]
        self.appModeOverrides = storedOverrides.reduce(into: [:]) { result, entry in
            let bundleID = entry.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let preference = PresentationModePreference(rawValue: entry.value),
               preference != .automatic,
               !bundleID.isEmpty {
                result[bundleID] = preference
            }
        }
        self.genZMode = true
        self.developerMode = defaults.object(forKey: Key.developerMode) as? Bool ?? false

        let rawBackend = defaults.string(forKey: Key.engineBackend) ?? EngineBackend.pureSwift.rawValue
        self.engineBackend = EngineBackend(rawValue: rawBackend) ?? .pureSwift
        ClientAdapter.resetDynamicMarkedText()
    }
}
