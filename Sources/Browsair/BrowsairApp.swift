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
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
