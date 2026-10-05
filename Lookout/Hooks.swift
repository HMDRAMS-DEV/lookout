import Foundation

/// Cursor writes no session state to disk, so Lookout registers a hook in `~/.cursor/hooks.json`.
/// The hook appends each event to `~/.lookout/events.jsonl`, which the scanner follows.
enum Hooks {
    static let home = FileManager.default.homeDirectoryForCurrentUser.path
    static let dir = home + "/.lookout"
    static let script = dir + "/hook.sh"
    static let events = dir + "/events.jsonl"
    static let cursorConfig = home + "/.cursor/hooks.json"
    static let cursorEvents = ["beforeSubmitPrompt", "afterAgentResponse", "stop"]

    private static let scriptBody = """
        #!/bin/sh
        # Written by Lookout. Appends one agent event to ~/.lookout/events.jsonl.
        # $1 is the agent (default cursor), $2 the event (default: the payload's hook_event_name).
        # stdin is the hook's JSON payload.
        data=$(tr -d '\\n\\r')
        [ -n "$data" ] || data='{}'
        printf '{"ts":%s,"src":"%s","event":"%s","data":%s}\\n' "$(date +%s)" "${1:-cursor}" "${2:-}" "$data" >> "$HOME/.lookout/events.jsonl"
        case "$data" in *beforeSubmitPrompt*) printf '{"continue":true}\\n' ;; esac
        exit 0

        """

    /// Keeps the hook script current. Cheap enough to run at every launch.
    static func writeScript() {
        let manager = FileManager.default
        try? manager.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if manager.contents(atPath: script) != Data(scriptBody.utf8) {
            manager.createFile(atPath: script, contents: Data(scriptBody.utf8), attributes: [.posixPermissions: 0o755])
        }
    }

    /// Where the scanner should start reading the event log. Keeps the log from growing forever:
    /// past 5 MB it keeps only the last 1 MB.
    static func trimEvents() -> UInt64 {
        guard let size = Files.size(events), size > 5_000_000,
              let handle = FileHandle(forReadingAtPath: events) else { return 0 }
        try? handle.seek(toOffset: size - 1_000_000)
        let tail = (try? handle.readToEnd()) ?? Data()
        try? handle.close()
        let start = tail.firstIndex(of: 0x0A).map { tail.index(after: $0) } ?? tail.endIndex
        try? Data(tail[start...]).write(to: URL(fileURLWithPath: events), options: .atomic)
        return 0
    }

    static var cursorInstalled: Bool {
        guard let hooks = readCursor()["hooks"] as? [String: Any] else { return false }
        return cursorEvents.allSatisfy { event in
            (hooks[event] as? [[String: Any]])?.contains { $0["command"] as? String == script } == true
        }
    }

    static var cursorPresent: Bool {
        FileManager.default.fileExists(atPath: home + "/.cursor")
    }

    static func installCursor() throws {
        writeScript()
        var root = readCursor()
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in cursorEvents {
            var list = hooks[event] as? [[String: Any]] ?? []
            if !list.contains(where: { $0["command"] as? String == script }) {
                list.append(["command": script])
            }
            hooks[event] = list
        }
        root["hooks"] = hooks
        root["version"] = root["version"] ?? 1
        try writeCursor(root)
    }

    static func removeCursor() throws {
        var root = readCursor()
        guard var hooks = root["hooks"] as? [String: Any] else { return }
        for (event, value) in hooks {
            let list = (value as? [[String: Any]])?.filter { $0["command"] as? String != script }
            hooks[event] = list?.isEmpty == true ? nil : list ?? value
        }
        root["hooks"] = hooks
        try writeCursor(root)
    }

    private static func readCursor() -> [String: Any] {
        guard let data = FileManager.default.contents(atPath: cursorConfig),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    private static func writeCursor(_ root: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try FileManager.default.createDirectory(atPath: home + "/.cursor", withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: cursorConfig), options: .atomic)
    }
}
