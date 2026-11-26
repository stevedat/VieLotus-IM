import Cocoa
import SwiftUI

final class SettingsWindowManager: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowManager()
    static let openFeedbackSheetNotification = Notification.Name("org.vielotus.inputmethod.openFeedbackSheet")

    private var window: NSWindow?
    private var languageObserver: NSObjectProtocol?

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
                self.bringWindowToFront(existingWindow)
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

            newWindow.title = L10n.tr("Cài đặt Sen Việt", "Sen Việt Settings")
            newWindow.titlebarAppearsTransparent = false
            newWindow.isMovableByWindowBackground = true
            newWindow.collectionBehavior.insert([.moveToActiveSpace, .fullScreenAuxiliary])
            newWindow.contentViewController = hostingController
            newWindow.setContentSize(NSSize(width: 640, height: 420))
            newWindow.contentMinSize = NSSize(width: 640, height: 420)
            self.centerWindowOnActiveScreen(newWindow)
            newWindow.isReleasedWhenClosed = false
            newWindow.delegate = self

            self.window = newWindow
            if self.languageObserver == nil {
                self.languageObserver = NotificationCenter.default.addObserver(
                    forName: .vieLotusUILanguageDidChange,
                    object: nil,
                    queue: .main
                ) { [weak newWindow] _ in
                    newWindow?.title = L10n.tr("Cài đặt Sen Việt", "Sen Việt Settings")
                }
            }
            self.bringWindowToFront(newWindow)
        }
    }

    private func centerWindowOnActiveScreen(_ targetWindow: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        if let activeScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main {
            let visible = activeScreen.visibleFrame
            let size = targetWindow.frame.size
            let origin = NSPoint(
                x: visible.midX - size.width / 2.0,
                y: visible.midY - size.height / 2.0
            )
            targetWindow.setFrameOrigin(origin)
        } else {
            targetWindow.center()
        }
    }

    private func bringWindowToFront(_ targetWindow: NSWindow) {
        targetWindow.collectionBehavior.insert([.moveToActiveSpace, .fullScreenAuxiliary])
        if targetWindow.isMiniaturized {
            targetWindow.deminiaturize(nil)
        }
        activateApp()
        targetWindow.orderFrontRegardless()
        targetWindow.makeKeyAndOrderFront(nil)

        // TextInputMenuAgent finishes dismissing the Input Menu dropdown ~20–60ms after
        // invoking openSettings() and can restore focus to the host app; the .accessory -> .regular
        // activation policy transform also settles asynchronously. Re-assert foreground once.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self, weak targetWindow] in
            guard let self, let targetWindow, self.window === targetWindow, targetWindow.isVisible else {
                return
            }
            self.activateApp()
            targetWindow.orderFrontRegardless()
            targetWindow.makeKeyAndOrderFront(nil)
        }
    }

    private func activateApp() {
        // Cooperative NSApp.activate() on macOS 14+ is silently ignored when an InputMethodKit
        // server is invoked from TextInputMenuAgent without cooperative yield from the active app.
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard let closedWindow = notification.object as? NSWindow,
              closedWindow === self.window else {
            return
        }
        closedWindow.delegate = nil
        if let observer = self.languageObserver {
            NotificationCenter.default.removeObserver(observer)
            self.languageObserver = nil
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window === closedWindow else { return }
            closedWindow.contentViewController = nil
            self.window = nil
        }
    }
}
