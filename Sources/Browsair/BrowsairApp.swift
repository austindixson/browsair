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
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
