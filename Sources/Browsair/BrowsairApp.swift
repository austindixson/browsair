import AppKit
import SwiftUI

@main
struct BrowsairApp: App {
    @StateObject private var session = BrowserSession()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Browsair") {
            BrowserChromeView(session: session)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    Task { await session.openTab(navigateTo: nil) }
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Close Tab") {
                    if let tab = session.activeTab {
                        session.closeTab(tab)
                    }
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            CommandMenu("AI") {
                Button("AI Settings…") { NSApp.sendAction(#selector(AppDelegate.showAISettings), to: nil, from: nil) }
            }

            CommandMenu("Tabs") {
                ForEach(1...9, id: \.self) { n in
                    Button("Tab \(n)") { session.selectTab(number: n) }
                        .keyboardShortcut(KeyEquivalent(Character(String(n))), modifiers: .command)
                }
                Button("Last Tab") { session.selectLastTab() }
                    .keyboardShortcut("9", modifiers: [.command, .option])
                Divider()
                Button("Next Tab") { session.selectNextTab() }
                    .disabled(!session.canSwitchTabs)
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                Button("Previous Tab") { session.selectPreviousTab() }
                    .disabled(!session.canSwitchTabs)
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            }

            CommandMenu("Navigation") {
                Button("Reload") {
                    Task { await session.reload() }
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Back") {
                    Task { await session.goBack() }
                }
                .keyboardShortcut("[", modifiers: .command)

                Button("Forward") {
                    Task { await session.goForward() }
                }
                .keyboardShortcut("]", modifiers: .command)

                Button("Focus Address Bar") {
                    // Address field uses FocusState locally; ⌘L still useful as reload cue
                    NotificationCenter.default.post(name: .browsairFocusAddressBar, object: nil)
                }
                .keyboardShortcut("l", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let browsairFocusAddressBar = Notification.Name("browsairFocusAddressBar")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var aiSettingsWindow: NSWindow?

    @objc func showAISettings() {
        if let window = aiSettingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 430),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "AI Settings"
        window.contentViewController = NSHostingController(rootView: AISettingsView())
        window.minSize = NSSize(width: 520, height: 430)
        window.setContentSize(NSSize(width: 520, height: 430))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        aiSettingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        aiSettingsWindow?.close()
        aiSettingsWindow = nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        launchWarningIfNotPersistent()
    }

    /// Warn when the process has no bundle identifier for WebKit to key persistent website data
    /// on. A `swift run` binary is not an app bundle, so login cookies will not survive quit
    /// (audit F3). Log + alert: the alert surfaces the issue to a developer running the app
    /// directly, which is exactly when it would otherwise go unnoticed.
    private func launchWarningIfNotPersistent() {
        let bundleID = WebsiteDataStoreLocation.resolvedBundleIdentifier(
            environment: ProcessInfo.processInfo.environment
        )
        guard !WebsiteDataStoreLocation.hasPersistentIdentity(bundleID) else { return }
        let message = """
        Browsair is running without a bundle identifier, so login cookies and website data will \
        not be saved between launches. Run it from the built .app bundle \
        (scripts/build-app-bundle.sh) for persistent sessions.
        """
        NSLog("Browsair persistence warning: \(message)")
        let alert = NSAlert()
        alert.messageText = "Website data will not persist"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
