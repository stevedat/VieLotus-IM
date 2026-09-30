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

if let unmanaged = TISCreateInputSourceList(nil, true) {
    let list = unmanaged.takeRetainedValue() as? [TISInputSource] ?? []
    for src in list {
        guard let idPtr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else { continue }
        let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
        if id.lowercased().contains("vielotus") {
            let e = TISEnableInputSource(src)
            FileHandle.standardError.write(Data("enable \(id) -> \(e)\n".utf8))
        }
    }
}
exit(0)
