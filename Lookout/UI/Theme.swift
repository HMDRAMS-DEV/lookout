import AppKit
import SwiftUI

/// Pacer's look: the popover sits on the system menu material with translucent tiles. Type is big
/// and tightly tracked. Each phase has one color: blue running, amber waiting, green done.
enum Theme {
    static let ink = Color(light: 0x0D0D0D, dark: 0xFFFFFF)
    static let accent = Color(light: 0x2563EB, dark: 0x5B8DEF)
    static let waiting = Color(light: 0xD97706, dark: 0xFBBF24)
    static let done = Color(light: 0x16A34A, dark: 0x4ADE80)
    static let claude = Color(light: 0xD97757, dark: 0xE08A6D)
    /// A neutral fill that works on any background, including the menu material.
    static let quietWash = Color.primary.opacity(0.07)

    static let waitingNS = NSColor(light: 0xD97706, dark: 0xFBBF24)
    static let doneNS = NSColor(light: 0x16A34A, dark: 0x4ADE80)

    static func color(_ phase: Phase) -> Color {
        switch phase {
        case .waiting: waiting
        case .running: accent
        case .done: done
        }
    }

    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold)
    }
}

/// "Lookout" with a dot after it, the way Pacer ends with its "you are here" dot.
struct Wordmark: View {
    var size: CGFloat = 20

    var body: some View {
        let dot = size * 0.3
        HStack(alignment: .firstTextBaseline, spacing: size * 0.3) {
            Text("Lookout").display(size).foregroundStyle(.primary)
            Circle().fill(Theme.accent)
                .frame(width: dot, height: dot)
                .background(Circle().fill(Theme.accent.opacity(0.28)).frame(width: dot * 1.9, height: dot * 1.9))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lookout")
    }
}

extension View {
    /// Display type: semibold and tightly tracked, after Cosmos.
    func display(_ size: CGFloat) -> some View {
        font(Theme.display(size)).tracking(-size * 0.035)
    }

    /// A translucent rounded tile that lets the menu material show through.
    func tile() -> some View {
        background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(light: light, dark: dark))
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    convenience init(light: UInt32, dark: UInt32) {
        self.init(name: nil) { appearance in
            NSColor(hex: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        }
    }
}

enum Format {
    static func ago(_ date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        return "\(span(seconds)) ago"
    }

    /// "40s", "12m", "2h 5m", "3d".
    static func span(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86400 { return s % 3600 < 60 ? "\(s / 3600)h" : "\(s / 3600)h \(s % 3600 / 60)m" }
        return "\(s / 86400)d"
    }
}

/// Primary and secondary buttons in the calm style.
struct PillButtonStyle: ButtonStyle {
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .foregroundStyle(prominent ? .white : Theme.ink)
            .background(prominent ? Theme.accent : Theme.quietWash, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

/// A quiet round icon button, like the ones along the bottom of system menus.
struct IconButton: View {
    let symbol: String
    let help: String
    var size: CGFloat = 24
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.5, weight: .medium))
                .foregroundStyle(hovering ? .primary : .secondary)
                .frame(width: size, height: size)
                .background(hovering ? Theme.quietWash : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// The agent's mark in a soft square, with a phase dot in the corner. The dot breathes while the
/// agent runs.
struct AgentBadge: View {
    let agent: Agent
    let phase: Phase
    var size: CGFloat = 32

    @State private var breathing = false

    var body: some View {
        let tint = agent == .claude ? Theme.claude : Theme.ink
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                let dot = size * 0.32
                ZStack {
                    if phase == .running {
                        Circle().fill(Theme.color(phase).opacity(0.35))
                            .scaleEffect(breathing ? 1.9 : 1)
                            .opacity(breathing ? 0 : 1)
                    }
                    Circle().fill(Theme.color(phase))
                }
                .frame(width: dot, height: dot)
                .padding(1.5)
                .background(Circle().fill(.background))
                .offset(x: dot * 0.3, y: dot * 0.3)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { breathing = true }
            }
            .accessibilityLabel("\(agent.name), \(phase.title)")
    }

    private var symbol: String {
        switch agent {
        case .claude: "asterisk"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .cursor: "cursorarrow"
        }
    }
}
