import SwiftUI

struct MenuBarLabel: View {
    @Environment(Store.self) private var store
    @State private var frame = 0

    var body: some View {
        Image(nsImage: MenuBarIcon.image(mark, count: store.runningCount + store.waitingCount))
            .task(id: store.runningCount > 0) {
                while store.runningCount > 0, !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(200))
                    frame += 1
                }
            }
    }

    /// What needs you outranks what finished, which outranks what runs.
    private var mark: MenuBarIcon.Mark {
        if store.waitingCount > 0 { return .waiting }
        if store.hasUnseenDone { return .done }
        if store.runningCount > 0 { return .running(frame: frame) }
        return .calm
    }
}

/// Sits on the system menu material, so it reads like part of macOS.
struct PopoverView: View {
    @Environment(Store.self) private var store
    @Environment(\.openWindow) private var openWindow
    /// What was new when the popover opened. Those rows keep a marker until it closes.
    @State private var fresh: Set<Session.ID> = []
    @State private var cursorConnected = Hooks.cursorInstalled

    private static let maxRows = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Wordmark(size: 20)
                Spacer()
                Text(summary)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if !store.notificationsAllowed {
                NotificationsTile()
            }

            if Hooks.cursorPresent, !cursorConnected {
                CursorTile { cursorConnected = Hooks.cursorInstalled }
            }

            if store.sessions.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("All quiet")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Lookout watches Claude Code, Codex, and Cursor.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .tile()
            } else if store.sessions.count > Self.maxRows {
                ScrollView { list }
                    .frame(height: 440)
                    .scrollIndicators(.never)
            } else {
                list
            }

            footer
        }
        .padding(14)
        .frame(width: 340)
        .onAppear {
            fresh = store.unseen
            store.markSeen()
            cursorConnected = Hooks.cursorInstalled
            Notifier.refresh()
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Phase.allCases, id: \.self) { phase in
                let sessions = store.sessions.filter { $0.phase == phase }
                if !sessions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(phase.title.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 4)
                        ForEach(sessions) { session in
                            SessionTile(session: session, fresh: fresh.contains(session.id)) {
                                store.open(session.id)
                            } clear: {
                                withAnimation(.snappy) { store.clear(session) }
                            }
                        }
                    }
                }
            }
        }
    }

    private var summary: String {
        if store.waitingCount > 0 { return "\(store.waitingCount) need\(store.waitingCount == 1 ? "s" : "") you" }
        if store.runningCount > 0 { return "\(store.runningCount) running" }
        return store.sessions.isEmpty ? "" : "All done"
    }

    private var footer: some View {
        HStack(spacing: 4) {
            if let scanned = store.scannedAt {
                TimelineView(.periodic(from: .now, by: 10)) { context in
                    Text(context.date.timeIntervalSince(scanned) > 10 ? "Last checked \(Format.ago(scanned, now: context.date))" : "Watching")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if store.sessions.contains(where: { $0.phase == .done }) {
                IconButton(symbol: "checkmark.circle", help: "Clear finished") {
                    withAnimation(.snappy) { store.clearFinished() }
                }
            }
            IconButton(symbol: "gearshape", help: "Settings") { openSettings() }
            Menu {
                Button("Settings…") { openSettings() }
                Button("Clear Finished") { store.clearFinished() }
                Divider()
                Button("Quit Lookout") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(.secondary)
            .help("More")
        }
    }

    private func openSettings() {
        openWindow(id: WindowID.settings)
        NSApp.activate()
    }
}

/// Cursor needs a hook before Lookout can see its chats.
struct CursorTile: View {
    let changed: () -> Void
    @State private var failed = false

    var body: some View {
        HStack(spacing: 10) {
            AgentBadge(agent: .cursor, phase: .waiting, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Connect Cursor")
                    .font(.system(size: 13, weight: .semibold))
                Text(failed ? "Couldn't write ~/.cursor/hooks.json." : "So Lookout can see its chats.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button("Connect") {
                do {
                    try Hooks.installCursor()
                    changed()
                } catch {
                    failed = true
                }
            }
            .buttonStyle(PillButtonStyle())
        }
        .padding(12)
        .tile()
    }
}

/// Banners are the point, so say plainly when macOS has them off.
struct NotificationsTile: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.slash.fill")
                .font(.system(size: 18))
                .foregroundStyle(Theme.waiting)
            VStack(alignment: .leading, spacing: 2) {
                Text("Notifications are off")
                    .font(.system(size: 13, weight: .semibold))
                Text("Turn them on to hear when agents finish.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button("Allow") { Notifier.openSettings() }
                .buttonStyle(PillButtonStyle())
        }
        .padding(12)
        .tile()
    }
}

/// One session. Clicking it brings its window to the front.
struct SessionTile: View {
    let session: Session
    let fresh: Bool
    let open: () -> Void
    let clear: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                AgentBadge(agent: session.agent, phase: session.phase)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if hovering, session.phase == .done {
                    IconButton(symbol: "xmark", help: "Clear", size: 20, action: clear)
                } else {
                    time
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tile()
            .overlay(alignment: .leading) {
                if fresh {
                    Capsule().fill(Theme.color(session.phase))
                        .frame(width: 3, height: 18)
                        .offset(x: 1.5)
                }
            }
            .contentShape(Rectangle())
            .scaleEffect(hovering ? 1.015 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(session.cwd)
    }

    private var subtitle: String {
        [session.agent.name, session.project, session.detail]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var time: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            let elapsed = context.date.timeIntervalSince(session.since)
            Text(session.phase == .done ? Format.ago(session.since, now: context.date) : Format.span(elapsed))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(session.phase == .done ? Color.secondary : Theme.color(session.phase))
        }
    }
}
