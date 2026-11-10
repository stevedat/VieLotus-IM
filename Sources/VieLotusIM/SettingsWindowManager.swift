import Cocoa
import SwiftUI

final class SettingsWindowManager: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowManager()
    static let openFeedbackSheetNotification = Notification.Name("org.vielotus.inputmethod.openFeedbackSheet")

    private var window: NSWindow?

    func showFeedbackSheet() {
        showSettingsWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            NotificationCenter.default.post(name: Self.openFeedbackSheetNotification, object: nil)
        }
    }

    func showSettingsWindow() {
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            
            if let existingWindow = self.window {
                existingWindow.setContentSize(NSSize(width: 640, height: 420))
                existingWindow.makeKeyAndOrderFront(nil)
                self.activateApp()
                return
            }
            
            let settingsView = SettingsView()
            let hostingController = NSHostingController(rootView: settingsView)
            
            let newWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            
            newWindow.title = "Cài đặt Sen Việt"
            newWindow.titlebarAppearsTransparent = false
            newWindow.isMovableByWindowBackground = true
            newWindow.contentViewController = hostingController
            newWindow.setContentSize(NSSize(width: 640, height: 420))
            newWindow.contentMinSize = NSSize(width: 640, height: 420)
            newWindow.center()
            newWindow.isReleasedWhenClosed = false
            newWindow.delegate = self
            
            self.window = newWindow
            newWindow.makeKeyAndOrderFront(nil)
            self.activateApp()
        }
    }

    private func activateApp() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
