import Foundation
import Carbon

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: register-source <app-path>\n".utf8))
    exit(2)
}

let appURL = URL(fileURLWithPath: args[1]) as CFURL
let regStatus = TISRegisterInputSource(appURL)
FileHandle.standardError.write(Data("TISRegisterInputSource -> \(regStatus)\n".utf8))

if regStatus != noErr {
    FileHandle.standardError.write(Data("Error: TISRegisterInputSource failed with code \(regStatus)\n".utf8))
    exit(3)
}

guard let unmanaged = TISCreateInputSourceList(nil, true) else {
    FileHandle.standardError.write(Data("Error: TISCreateInputSourceList returned nil\n".utf8))
    exit(4)
}

let list = unmanaged.takeRetainedValue() as? [TISInputSource] ?? []
var primaryEnabled = false
var lastError: OSStatus = noErr

for src in list {
    guard let idPtr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else { continue }
    let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
    if id.lowercased().contains("vielotus") {
        if !primaryEnabled {
            let e = TISEnableInputSource(src)
            FileHandle.standardError.write(Data("enable \(id) -> \(e)\n".utf8))
            if e == noErr {
                primaryEnabled = true
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

if !primaryEnabled {
    FileHandle.standardError.write(Data("Error: Could not find or enable VieLotusIM in TIS (last error: \(lastError))\n".utf8))
    exit(5)
}

exit(0)
