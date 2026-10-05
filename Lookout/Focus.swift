import AppKit

/// Brings a session's window to the front.
@MainActor
enum Focus {
    static func show(_ target: Target) {
        switch target {
        case .url(let link):
            if let url = URL(string: link) { NSWorkspace.shared.open(url) }
        case .app(let bundleID):
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                app.activate()
            } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
            }
        case .process(let pid):
            showProcess(pid)
        }
    }

    /// Walks up from the agent's process to the app hosting it. In Terminal, also selects its tab.
    private static func showProcess(_ pid: pid_t) {
        var current = pid
        var host: NSRunningApplication?
        for _ in 0..<32 {
            guard let parent = Proc.parent(current), parent > 1 else { break }
            if let app = NSRunningApplication(processIdentifier: parent), app.activationPolicy == .regular {
                host = app
                break
            }
            current = parent
        }
        guard let host else { return }
        if host.bundleIdentifier == "com.apple.Terminal", let tty = Proc.tty(pid) {
            selectTerminalTab("/dev/\(tty)")
        }
        host.activate()
    }

    private static func selectTerminalTab(_ tty: String) {
        let source = """
            tell application "Terminal"
                repeat with w in windows
                    -- Terminal can list a window with no tabs. Reading them throws, so skip it.
                    try
                        repeat with t in tabs of w
                            if tty of t is "\(tty)" then
                                set miniaturized of w to false
                                set selected of t to true
                                set index of w to 1
                                return
                            end if
                        end repeat
                    end try
                end repeat
            end tell
            """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { log.error("terminal tab: \(error, privacy: .public)") }
    }
}
