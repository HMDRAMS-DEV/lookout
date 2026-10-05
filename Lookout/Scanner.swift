import Darwin
import Foundation
import SQLite3
import os

let log = Logger(subsystem: "dev.lookout.Lookout", category: "scan")

/// Reads what each agent leaves on disk and turns it into sessions. Every source is read
/// incrementally, so a scan every two seconds stays cheap.
///
/// - Claude Code writes `~/.claude/sessions/<pid>.json` with `status` busy, idle, or waiting.
/// - Codex keeps threads in `~/.codex/state_N.sqlite` and each turn's events in a rollout file.
/// - Cursor keeps nothing usable, so its hooks append to `~/.lookout/events.jsonl` (see Hooks).
actor Scanner {
    static let shared = Scanner()

    /// A running session with no activity for this long has probably died with its app.
    static let quietAfter: TimeInterval = 30 * 60

    private let home = FileManager.default.homeDirectoryForCurrentUser.path

    private var transcripts: [String: String] = [:]
    private var transcriptRead: [String: UInt64] = [:]
    private var aiTitles: [String: String] = [:]
    private var customTitles: [String: String] = [:]

    private var codexDB: OpaquePointer?
    private var rollouts: [String: Rollout] = [:]

    private var eventsRead: UInt64?
    private var chats: [String: Chat] = [:]

    /// Finished sessions older than `keep` seconds are left out.
    func scan(keep: TimeInterval) -> [Session] {
        let now = Date()
        var seen = Set<Session.ID>()
        return (claude() + codex(now: now, keep: keep) + cursor(now: now))
            .filter { $0.phase != .done || now.timeIntervalSince($0.since) < keep }
            .filter { seen.insert($0.id).inserted }
    }

    // MARK: Claude Code

    private struct Registry: Decodable {
        var pid: Int32
        var sessionId: String
        var cwd: String?
        var name: String?
        var status: String?
        var waitingFor: String?
        var statusUpdatedAt: Double?
        var updatedAt: Double?
        var startedAt: Double?
    }

    private func claude() -> [Session] {
        let dir = home + "/.claude/sessions"
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        var result: [Session] = []
        for file in files where file.hasSuffix(".json") {
            guard let data = FileManager.default.contents(atPath: "\(dir)/\(file)"),
                  let entry = try? JSONDecoder().decode(Registry.self, from: data),
                  Proc.alive(entry.pid, since: entry.startedAt.map { Date(timeIntervalSince1970: $0 / 1000) })
            else { continue }

            let phase: Phase = switch entry.status {
            case "waiting": .waiting
            case "busy": .running
            default: .done
            }
            let stamp = entry.statusUpdatedAt ?? entry.updatedAt ?? entry.startedAt ?? 0
            result.append(Session(
                id: "claude:\(entry.sessionId)",
                agent: .claude,
                title: claudeTitle(entry),
                cwd: entry.cwd ?? "",
                phase: phase,
                since: Date(timeIntervalSince1970: stamp / 1000),
                detail: phase == .waiting ? entry.waitingFor.map(Words.sentence) : nil,
                target: .process(entry.pid)
            ))
        }
        return result
    }

    /// The session's /rename title, else the title Claude Code generated, else its derived name.
    private func claudeTitle(_ entry: Registry) -> String {
        let id = entry.sessionId
        if transcripts[id] == nil { transcripts[id] = findTranscript(id, cwd: entry.cwd) }
        if let path = transcripts[id] {
            let start = transcriptRead[id] ?? 0
            transcriptRead[id] = Lines.read(path, from: start) { line in
                guard line.range(of: Data("-title\"".utf8)) != nil,
                      let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
                if let title = object["customTitle"] as? String { customTitles[id] = title }
                if let title = object["aiTitle"] as? String { aiTitles[id] = title }
            }
        }
        return customTitles[id] ?? aiTitles[id] ?? entry.name ?? "Claude Code session"
    }

    private func findTranscript(_ id: String, cwd: String?) -> String? {
        let projects = home + "/.claude/projects"
        if let cwd {
            let folder = String(cwd.map { $0.isLetter || $0.isNumber ? $0 : "-" })
            let path = "\(projects)/\(folder)/\(id).jsonl"
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: projects)) ?? []
        return folders.lazy.map { "\(projects)/\($0)/\(id).jsonl" }.first { FileManager.default.fileExists(atPath: $0) }
    }

    // MARK: Codex

    private struct Rollout {
        var read: UInt64 = 0
        var phase = Phase.done
        var since: Date?
        var detail: String?
    }

    private func codex(now: Date, keep: TimeInterval) -> [Session] {
        guard let db = openCodex() else { return [] }
        let sql = """
            select id, coalesce(name, ''), title, cwd, rollout_path from threads
            where archived = 0 and updated_at >= ? order by updated_at desc limit 50
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            log.error("codex query failed: \(String(cString: sqlite3_errmsg(db)), privacy: .public)")
            sqlite3_close(db)
            codexDB = nil
            return []
        }
        defer { sqlite3_finalize(statement) }
        // A long turn can go a while without touching the thread row, so look back at least a day.
        sqlite3_bind_int64(statement, 1, Int64(now.timeIntervalSince1970 - max(keep, 86400)))

        var result: [Session] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            func column(_ i: Int32) -> String { sqlite3_column_text(statement, i).map { String(cString: $0) } ?? "" }
            let (id, name, title, cwd, path) = (column(0), column(1), column(2), column(3), column(4))
            var state = rollout(path)
            let modified = Files.modified(path) ?? now
            if state.phase == .running, now.timeIntervalSince(modified) > Self.quietAfter {
                state = Rollout(read: state.read, phase: .done, since: modified, detail: "Went quiet")
            }
            result.append(Session(
                id: "codex:\(id)",
                agent: .codex,
                title: Words.headline(name.isEmpty ? title : name, fallback: "Codex thread"),
                cwd: cwd,
                phase: state.phase,
                since: state.since ?? modified,
                detail: state.detail,
                target: .url("codex://threads/\(id)")
            ))
        }
        return result
    }

    /// Opens the newest `state_N.sqlite` read-only. Codex bumps N when its schema changes.
    private func openCodex() -> OpaquePointer? {
        if let codexDB { return codexDB }
        let dir = home + "/.codex"
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        let newest = files
            .filter { $0.hasPrefix("state_") && $0.hasSuffix(".sqlite") }
            .max { Int($0.dropFirst(6).dropLast(7)) ?? 0 < Int($1.dropFirst(6).dropLast(7)) ?? 0 }
        guard let newest else { return nil }
        var db: OpaquePointer?
        guard sqlite3_open_v2("\(dir)/\(newest)", &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        sqlite3_busy_timeout(db, 250)
        codexDB = db
        return db
    }

    /// Follows a rollout file's turn events: started, waiting on an approval, complete, aborted.
    private func rollout(_ path: String) -> Rollout {
        var state = rollouts[path] ?? Rollout()
        if let size = Files.size(path), size < state.read { state = Rollout() }
        state.read = Lines.read(path, from: state.read) { line in
            guard line.range(of: Data("\"event_msg\"".utf8)) != nil,
                  let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let payload = object["payload"] as? [String: Any],
                  let type = payload["type"] as? String else { return }
            let at = (object["timestamp"] as? String).flatMap(Words.date) ?? state.since
            func set(_ phase: Phase, _ detail: String? = nil) {
                state.phase = phase
                state.since = at
                state.detail = detail
            }
            switch type {
            case "task_started": set(.running)
            case "task_complete": set(.done)
            case "turn_aborted": set(.done, "Stopped")
            case "exec_approval_request": set(.waiting, "Approve a command")
            case "apply_patch_approval_request": set(.waiting, "Approve an edit")
            case "request_permissions": set(.waiting, "Grant permissions")
            case "request_user_input", "elicitation_request": set(.waiting, "Answer a question")
            case "token_count": break
            default: if state.phase == .waiting { set(.running) }
            }
        }
        rollouts[path] = state
        return state
    }

    // MARK: Cursor

    private struct Chat {
        var title: String
        var cwd = ""
        var phase = Phase.running
        var since: Date
        var detail: String?
        var last: Date
    }

    private func cursor(now: Date) -> [Session] {
        let path = Hooks.events
        if eventsRead == nil { eventsRead = Hooks.trimEvents() }
        eventsRead = Lines.read(path, from: eventsRead ?? 0) { line in
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  object["src"] as? String == "cursor",
                  let data = object["data"] as? [String: Any],
                  let id = data["conversation_id"] as? String,
                  let ts = object["ts"] as? Double else { return }
            let at = Date(timeIntervalSince1970: ts)
            let event = (object["event"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? data["hook_event_name"] as? String
            let prompt = data["prompt"] as? String

            var chat = chats[id] ?? Chat(title: Words.headline(prompt ?? "", fallback: "Cursor chat"), since: at, last: at)
            if let root = (data["workspace_roots"] as? [String])?.first {
                chat.cwd = root.hasPrefix("file://") ? URL(string: root)?.path ?? root : root
            }
            chat.last = at
            switch event {
            case "beforeSubmitPrompt":
                chat.phase = .running
                chat.since = at
                chat.detail = nil
            case "stop":
                chat.phase = .done
                chat.since = at
                chat.detail = switch data["status"] as? String {
                case "aborted": "Stopped"
                case "error": "Error"
                default: nil
                }
            default: break
            }
            chats[id] = chat
        }

        chats = chats.filter { now.timeIntervalSince($0.value.last) < 2 * 86400 }
        return chats.map { id, chat in
            var phase = chat.phase, since = chat.since, detail = chat.detail
            if phase == .running, now.timeIntervalSince(chat.last) > Self.quietAfter {
                (phase, since, detail) = (.done, chat.last, "Went quiet")
            }
            return Session(id: "cursor:\(id)", agent: .cursor, title: chat.title, cwd: chat.cwd, phase: phase,
                           since: since, detail: detail, target: .app(bundleID: Agent.cursorBundleID))
        }
    }
}

// MARK: - Helpers

enum Lines {
    /// Calls `body` for each complete line after `offset` and returns the offset after the last one.
    /// A line still being written is left for the next read.
    static func read(_ path: String, from offset: UInt64, _ body: (Data) -> Void) -> UInt64 {
        guard let handle = FileHandle(forReadingAtPath: path) else { return offset }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size > offset else { return offset }
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), let end = data.lastIndex(of: 0x0A) else { return offset }
        let complete = data[data.startIndex...end]
        for line in complete.split(separator: 0x0A) where !line.isEmpty { body(Data(line)) }
        return offset + UInt64(complete.count)
    }
}

enum Files {
    static func modified(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    static func size(_ path: String) -> UInt64? {
        ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.uint64Value
    }
}

enum Words {
    private static let link = try! NSRegularExpression(pattern: #"\[([^\]]*)\]\([^)]*\)"#)

    /// The first line of a prompt, with Markdown links reduced to their text, cut to fit a row.
    static func headline(_ text: String, fallback: String) -> String {
        let plain = link.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1")
        guard let line = plain.split(whereSeparator: \.isNewline).lazy
            .map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: { !$0.isEmpty }) else { return fallback }
        return line.count > 90 ? line.prefix(89) + "…" : line
    }

    static func sentence(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    static func date(_ text: String) -> Date? {
        (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text))
            ?? (try? Date.ISO8601FormatStyle().parse(text))
    }
}

enum Proc {
    private static func info(_ pid: pid_t) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }

    /// True if `pid` is running and started no later than `since`. A recycled pid starts after.
    static func alive(_ pid: pid_t, since: Date?) -> Bool {
        guard let info = info(pid) else { return false }
        let start = info.kp_proc.p_starttime
        let started = Date(timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000)
        guard let since else { return true }
        return started <= since.addingTimeInterval(5)
    }

    static func parent(_ pid: pid_t) -> pid_t? {
        info(pid)?.kp_eproc.e_ppid
    }

    /// The controlling terminal, like "ttys003".
    static func tty(_ pid: pid_t) -> String? {
        guard let device = info(pid)?.kp_eproc.e_tdev, device != -1, let name = devname(device, S_IFCHR) else { return nil }
        return String(cString: name)
    }
}
