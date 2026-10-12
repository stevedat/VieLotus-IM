import VieLotusCore
import Foundation
import Combine

public enum EngineBackend: String, CaseIterable, Sendable {
    case pureSwift = "pureSwift" // LotusEngine (Pure Swift 6)
}

final class Preferences: ObservableObject {
    static let shared = Preferences()
    private let defaults = UserDefaults.standard
    
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
        static let wordSuggestions = "VieLotusIM.wordSuggestions"
        static let passthroughRemoteApps = "VieLotusIM.passthroughRemoteApps"
        static let enforceABCBaseLayout = "VieLotusIM.enforceABCBaseLayout"
        static let macroEnabled = "VieLotusIM.macroEnabled"
    }
    
    @Published var inputMethod: InputMethodType {
        didSet { defaults.set(Int(inputMethod.rawValue), forKey: Key.inputMethod) }
    }
    
    @Published var modernOrthography: Bool {
        didSet { defaults.set(modernOrthography, forKey: Key.modernOrthography) }
    }
    
    @Published var relaxedCoda: Bool {
        didSet { defaults.set(relaxedCoda, forKey: Key.relaxedCoda) }
    }
    
    @Published var quickTelex: Bool {
        didSet { defaults.set(quickTelex, forKey: Key.quickTelex) }
    }
    
    @Published var vietnameseEnabled: Bool {
        didSet { defaults.set(vietnameseEnabled, forKey: Key.vietnameseEnabled) }
    }
    
    @Published var smartBilingual: Bool {
        didSet { defaults.set(smartBilingual, forKey: Key.smartBilingual) }
    }

    @Published var wordSuggestions: Bool {
        didSet { defaults.set(wordSuggestions, forKey: Key.wordSuggestions) }
    }

    @Published var terminalDirectMode: Bool {
        didSet { defaults.set(terminalDirectMode, forKey: Key.terminalDirectMode) }
    }

    @Published var presentationModePreference: PresentationModePreference {
        didSet {
            defaults.set(presentationModePreference.rawValue, forKey: Key.presentationModePreference)
            ClientAdapter.resetDynamicMarkedText()
        }
    }

    @Published var appModeOverrides: [String: PresentationModePreference] {
        didSet {
            defaults.set(appModeOverrides.mapValues(\.rawValue), forKey: Key.appModeOverrides)
            ClientAdapter.resetDynamicMarkedText()
        }
    }
    
    @Published var genZMode: Bool {
        didSet { defaults.set(genZMode, forKey: Key.genZMode) }
    }
    
    @Published var passthroughRemoteApps: Bool {
        didSet { defaults.set(passthroughRemoteApps, forKey: Key.passthroughRemoteApps) }
    }

    @Published var enforceABCBaseLayout: Bool {
        didSet { defaults.set(enforceABCBaseLayout, forKey: Key.enforceABCBaseLayout) }
    }

    @Published var macroEnabled: Bool {
        didSet { defaults.set(macroEnabled, forKey: Key.macroEnabled) }
    }

    @Published var developerMode: Bool {
        didSet { defaults.set(developerMode, forKey: Key.developerMode) }
    }
    
    @Published var engineBackend: EngineBackend {
        didSet { defaults.set(engineBackend.rawValue, forKey: Key.engineBackend) }
    }
    
    private init() {
        let rawIM = defaults.integer(forKey: Key.inputMethod)
        self.inputMethod = InputMethodType(rawValue: Int32(rawIM)) ?? .telex
        
        self.modernOrthography = defaults.object(forKey: Key.modernOrthography) as? Bool ?? true
        self.relaxedCoda = defaults.bool(forKey: Key.relaxedCoda)
        self.quickTelex = defaults.bool(forKey: Key.quickTelex)
        self.vietnameseEnabled = defaults.object(forKey: Key.vietnameseEnabled) as? Bool ?? true
        self.smartBilingual = defaults.object(forKey: Key.smartBilingual) as? Bool ?? true
        self.wordSuggestions = defaults.object(forKey: Key.wordSuggestions) as? Bool ?? false
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
        self.genZMode = defaults.object(forKey: Key.genZMode) as? Bool ?? false
        self.developerMode = defaults.object(forKey: Key.developerMode) as? Bool ?? false
        
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
        let rawIM = defaults.integer(forKey: Key.inputMethod)
        self.inputMethod = InputMethodType(rawValue: Int32(rawIM)) ?? .telex

        self.modernOrthography = defaults.object(forKey: Key.modernOrthography) as? Bool ?? true
        self.relaxedCoda = defaults.bool(forKey: Key.relaxedCoda)
        self.quickTelex = defaults.bool(forKey: Key.quickTelex)
        self.vietnameseEnabled = defaults.object(forKey: Key.vietnameseEnabled) as? Bool ?? true
        self.smartBilingual = defaults.object(forKey: Key.smartBilingual) as? Bool ?? true
        self.wordSuggestions = defaults.object(forKey: Key.wordSuggestions) as? Bool ?? false
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
        self.genZMode = defaults.object(forKey: Key.genZMode) as? Bool ?? false
        self.developerMode = defaults.object(forKey: Key.developerMode) as? Bool ?? false

        let rawBackend = defaults.string(forKey: Key.engineBackend) ?? EngineBackend.pureSwift.rawValue
        self.engineBackend = EngineBackend(rawValue: rawBackend) ?? .pureSwift
        ClientAdapter.resetDynamicMarkedText()
    }
}
