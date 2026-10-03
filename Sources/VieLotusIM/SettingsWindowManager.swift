import Cocoa
import SwiftUI

final class SettingsWindowManager: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowManager()
    
    private var window: NSWindow?
    
    func showSettingsWindow() {
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            
            if let existingWindow = self.window {
                existingWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
            
            let settingsView = SettingsView()
            let hostingController = NSHostingController(rootView: settingsView)
            
            let newWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 520),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            
            newWindow.title = "Cài đặt Sen Việt"
            newWindow.titlebarAppearsTransparent = false
            newWindow.isMovableByWindowBackground = true
            newWindow.contentViewController = hostingController
            newWindow.center()
            newWindow.isReleasedWhenClosed = false
            newWindow.delegate = self
            
            self.window = newWindow
            newWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}