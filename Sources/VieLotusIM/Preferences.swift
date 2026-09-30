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
        static let developerMode = "VieLotusIM.developerMode"
        static let engineBackend = "VieLotusIM.engineBackend"
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

    @Published var terminalDirectMode: Bool {
        didSet { defaults.set(terminalDirectMode, forKey: Key.terminalDirectMode) }
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
        self.terminalDirectMode = defaults.object(forKey: Key.terminalDirectMode) as? Bool ?? true
        self.developerMode = defaults.object(forKey: Key.developerMode) as? Bool ?? false
        
        let rawBackend = defaults.string(forKey: Key.engineBackend) ?? EngineBackend.pureSwift.rawValue
        self.engineBackend = EngineBackend(rawValue: rawBackend) ?? .pureSwift
    }
}
