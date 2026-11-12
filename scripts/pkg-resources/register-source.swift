import Foundation
import Carbon

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: register-source <app-path>\n".utf8))
    exit(2)
}

let bundleID = "org.vielotus.inputmethod.VieLotusIM"
let appURL = URL(fileURLWithPath: args[1]) as CFURL
let regStatus = TISRegisterInputSource(appURL)
FileHandle.standardError.write(Data("TISRegisterInputSource -> \(regStatus)\n".utf8))

if regStatus != noErr {
    FileHandle.standardError.write(Data("Error: TISRegisterInputSource failed with code \(regStatus)\n".utf8))
    exit(3)
}

// Sync com.apple.HIToolbox AppleEnabledInputSources & AppleSelectedInputSources so macOS 14/15/26
// adds Sen Việt to the Menu Bar Input Sources immediately without manual System Settings -> "+" steps,
// and removes conflicting legacy com.apple.inputmethod.VietnameseIM entries.
func syncHIToolboxPreferences(for host: CFString) {
    let domain = "com.apple.HIToolbox" as CFString
    let enabledKey = "AppleEnabledInputSources" as CFString
    let selectedKey = "AppleSelectedInputSources" as CFString

    let vieLotusEntry: [String: Any] = [
        "InputSourceKind": "Keyboard Input Method",
        "Bundle ID": bundleID
    ]

    if let rawEnabled = CFPreferencesCopyValue(enabledKey, domain, kCFPreferencesCurrentUser, host) as? [[String: Any]] {
        var updatedEnabled: [[String: Any]] = []
        var hasVieLotus = false

        for item in rawEnabled {
            let itemBundle = (item["Bundle ID"] as? String) ?? ""
            let layoutName = (item["KeyboardLayout Name"] as? String) ?? ""
            if itemBundle == "com.apple.inputmethod.VietnameseIM" || layoutName.hasPrefix("Vietnamese") {
                continue
            }
            if itemBundle.caseInsensitiveCompare(bundleID) == .orderedSame {
                if !hasVieLotus {
                    updatedEnabled.append(vieLotusEntry)
                    hasVieLotus = true
                }
                continue
            }
            updatedEnabled.append(item)
        }

        if !hasVieLotus {
            updatedEnabled.append(vieLotusEntry)
        }

        CFPreferencesSetValue(enabledKey, updatedEnabled as CFArray, domain, kCFPreferencesCurrentUser, host)
    } else if host == kCFPreferencesAnyHost {
        let defaultUS: [String: Any] = [
            "InputSourceKind": "Keyboard Layout",
            "KeyboardLayout ID": 0,
            "KeyboardLayout Name": "U.S."
        ]
        CFPreferencesSetValue(enabledKey, [defaultUS, vieLotusEntry] as CFArray, domain, kCFPreferencesCurrentUser, host)
    }

    if let rawSelected = CFPreferencesCopyValue(selectedKey, domain, kCFPreferencesCurrentUser, host) as? [[String: Any]] {
        var updatedSelected: [[String: Any]] = []
        for item in rawSelected {
            let kind = (item["InputSourceKind"] as? String) ?? ""
            if kind == "Non Keyboard Input Method" {
                updatedSelected.append(item)
            }
        }
        updatedSelected.append(vieLotusEntry)
        CFPreferencesSetValue(selectedKey, updatedSelected as CFArray, domain, kCFPreferencesCurrentUser, host)
    }

    _ = CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, host)
}

syncHIToolboxPreferences(for: kCFPreferencesAnyHost)
syncHIToolboxPreferences(for: kCFPreferencesCurrentHost)
CFPreferencesAppSynchronize("com.apple.HIToolbox" as CFString)

guard let unmanaged = TISCreateInputSourceList(nil, true) else {
    FileHandle.standardError.write(Data("Error: TISCreateInputSourceList returned nil\n".utf8))
    exit(4)
}

let list = unmanaged.takeRetainedValue() as? [TISInputSource] ?? []
var primaryEnabled = false
var lastError: OSStatus = noErr
var targetSource: TISInputSource?

for src in list {
    guard let idPtr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else { continue }
    let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
    let lower = id.lowercased()

    if lower.hasPrefix("com.apple.inputmethod.vietnameseim") || lower.hasPrefix("com.apple.keylayout.vietnamese") {
        let d = TISDisableInputSource(src)
        FileHandle.standardError.write(Data("disable conflicting Apple IME \(id) -> \(d)\n".utf8))
        continue
    }

    if lower.contains("vielotus") {
        if !primaryEnabled {
            let e = TISEnableInputSource(src)
            FileHandle.standardError.write(Data("enable \(id) -> \(e)\n".utf8))
            if e == noErr {
                primaryEnabled = true
                targetSource = src
                _ = TISSelectInputSource(src)
            } else {
                lastError = e
            }
        } else {
            let d = TISDisableInputSource(src)
            FileHandle.standardError.write(Data("disable duplicate \(id) -> \(d)\n".utf8))
        }
    }
}

// Re-assert HIToolbox preferences after TIS calls in case TIS overwrote with stale in-memory cache
syncHIToolboxPreferences(for: kCFPreferencesAnyHost)
syncHIToolboxPreferences(for: kCFPreferencesCurrentHost)
CFPreferencesAppSynchronize("com.apple.HIToolbox" as CFString)

if let src = targetSource {
    _ = TISEnableInputSource(src)
    _ = TISSelectInputSource(src)
}

DistributedNotificationCenter.default().postNotificationName(
    Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
    object: nil,
    userInfo: nil,
    deliverImmediately: true
)
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
    object: nil,
    userInfo: nil,
    deliverImmediately: true
)

if !primaryEnabled {
    FileHandle.standardError.write(Data("Error: Could not find or enable VieLotusIM in TIS (last error: \(lastError))\n".utf8))
    exit(5)
}

exit(0)
