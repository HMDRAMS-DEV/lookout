import AppKit
import Observation

// MARK: - Sessions

enum Agent: String, Sendable, CaseIterable {
    case claude, codex, cursor

    var name: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        }
    }

    static let cursorBundleID = "com.todesktop.230313mzl4w4u92"
}

/// Ordered the way the popover lists them: what needs you first.
enum Phase: Int, Sendable, CaseIterable, Comparable {
    case waiting, running, done

    static func < (a: Phase, b: Phase) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .waiting: "Needs you"
        case .running: "Running"
        case .done: "Done"
        }
    }
}

/// Where clicking a session takes you.
enum Target: Sendable, Equatable {
    /// A Claude Code process. Lookout finds the app (and Terminal tab) that hosts it.
    case process(pid_t)
    case url(String)
    case app(bundleID: String)
}

struct Session: Identifiable, Sendable, Equatable {
    var id: String
    var agent: Agent
    var title: String
    var cwd: String
    var phase: Phase
    /// When the session entered its phase.
    var since: Date
    /// Why it is waiting, or how it ended.
    var detail: String?
    var target: Target

    var project: String {
        cwd.isEmpty ? "" : URL(fileURLWithPath: cwd).lastPathComponent
    }
}

// MARK: - Settings

enum Keys {
    static let notifyDone = "notifyDone"
    static let notifyWaiting = "notifyWaiting"
    static let sound = "sound"
    /// Turns shorter than this finish without a notification. Seconds.
    static let minTurn = "minTurn"
    /// Finished sessions leave the list after this many hours.
    static let keepHours = "keepHours"
}

enum WindowID {
    static let settings = "settings"
}

extension UserDefaults {
    static func registerLookoutDefaults() {
        standard.register(defaults: [
            Keys.notifyDone: true,
            Keys.notifyWaiting: true,
            Keys.sound: true,
            Keys.minTurn: 10,
            Keys.keepHours: 8,
        ])
    }
}

// MARK: - Store

@MainActor
@Observable
final class Store {
    static let shared = Store()

    /// Everything the scanner found, minus what you cleared.
    private(set) var sessions: [Session] = []
    /// Sessions that finished or started waiting since you last opened the popover.
    private(set) var unseen: Set<Session.ID> = []
    /// The first scan only fills the list. Notifications start with the second.
    private(set) var loaded = false
    private(set) var scannedAt: Date?
    /// False when macOS has notifications turned off for Lookout.
    var notificationsAllowed = true

    /// Cleared finished sessions, by the time they finished. A new turn brings them back.
    private var cleared: [Session.ID: Date] = [:]

    func apply(_ found: [Session]) {
        let old = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        let visible = found
            .filter { !($0.phase == .done && cleared[$0.id] == $0.since) }
            .sorted { ($0.phase, $1.since) < ($1.phase, $0.since) }

        if loaded {
            for session in visible {
                let before = old[session.id]
                if before?.phase != session.phase {
                    log.info("\(session.id, privacy: .public): \(before?.phase.title ?? "new", privacy: .public) -> \(session.phase.title, privacy: .public)")
                }
                if session.phase == .waiting, before?.phase != .waiting {
                    unseen.insert(session.id)
                    Notifier.waiting(session)
                } else if session.phase == .done, let before, before.phase != .done {
                    unseen.insert(session.id)
                    let turn = session.since.timeIntervalSince(before.since)
                    Notifier.done(session, turn: before.phase == .running ? turn : nil)
                } else if session.phase == .running {
                    unseen.remove(session.id)
                }
            }
        }
        unseen.formIntersection(visible.map(\.id))
        let foundIDs = Set(found.map(\.id))
        cleared = cleared.filter { foundIDs.contains($0.key) }
        sessions = visible
        loaded = true
        scannedAt = .now
    }

    var waitingCount: Int { sessions.count { $0.phase == .waiting } }
    var runningCount: Int { sessions.count { $0.phase == .running } }
    var hasUnseenDone: Bool { sessions.contains { $0.phase == .done && unseen.contains($0.id) } }

    func markSeen() {
        unseen = unseen.filter { id in sessions.contains { $0.id == id && $0.phase == .waiting } }
    }

    func clear(_ session: Session) {
        cleared[session.id] = session.since
        sessions.removeAll { $0.id == session.id }
        unseen.remove(session.id)
    }

    func clearFinished() {
        for session in sessions where session.phase == .done { clear(session) }
    }

    func open(_ id: Session.ID) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        unseen.remove(id)
        Focus.show(session.target)
    }
}
