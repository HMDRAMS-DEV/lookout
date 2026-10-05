import AppKit
import SwiftUI

// Lookout: watches your Claude Code, Codex, and Cursor sessions from the menu bar and tells you
// when one finishes or needs you.

@main
struct LookoutApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = Store.shared

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(store)
        } label: {
            MenuBarLabel()
                .environment(store)
        }
        .menuBarExtraStyle(.window)

        Window("Lookout Settings", id: WindowID.settings) {
            SettingsView()
                .environment(store)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            UserDefaults.registerLookoutDefaults()
            Notifier.setUp()
            Hooks.writeScript()
            Monitor.start()
        }
    }
}

/// Scans every two seconds and hands the result to the store.
@MainActor
enum Monitor {
    static let interval: Duration = .seconds(2)
    private static var task: Task<Void, Never>?

    static func start() {
        task?.cancel()
        task = Task {
            while !Task.isCancelled {
                let keep = Double(UserDefaults.standard.integer(forKey: Keys.keepHours)) * 3600
                let found = await Scanner.shared.scan(keep: keep)
                Store.shared.apply(found)
                try? await Task.sleep(for: interval)
            }
        }
    }
}
