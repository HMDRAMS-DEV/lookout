import AppKit

/// Draws the menu bar glyph: a dot inside a ring, like a lookout's "something there" ping. The ring
/// turns into a slowly spinning arc while an agent runs. The dot turns amber when one needs you and
/// green when one finished since you last looked. The number counts running and waiting sessions.
enum MenuBarIcon {
    enum Mark: Equatable {
        case calm
        case running(frame: Int)
        case waiting
        case done
    }

    static func image(_ mark: Mark, count: Int) -> NSImage {
        let label = count > 0 ? NSAttributedString(string: "\(count)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ]) : nil
        let textWidth = label.map { ceil($0.size().width) + 3 } ?? 0
        let size = NSSize(width: 18 + textWidth, height: 18)
        let tinted = mark == .waiting || mark == .done

        let image = NSImage(size: size, flipped: false) { _ in
            let center = NSPoint(x: 9, y: 9)
            let ink: NSColor = tinted ? .labelColor : .black

            let ring = NSBezierPath()
            if case .running(let frame) = mark {
                let start = CGFloat(-frame * 30)
                ring.appendArc(withCenter: center, radius: 6.4, startAngle: start, endAngle: start - 270, clockwise: true)
            } else {
                ring.appendOval(in: NSRect(x: center.x - 6.4, y: center.y - 6.4, width: 12.8, height: 12.8))
            }
            ring.lineWidth = 1.6
            ring.lineCapStyle = .round
            ink.setStroke()
            ring.stroke()

            let dotColor: NSColor = switch mark {
            case .waiting: Theme.waitingNS
            case .done: Theme.doneNS
            default: ink
            }
            dotColor.setFill()
            let radius: CGFloat = tinted ? 3.2 : 2.6
            NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()

            if let label {
                let text = NSMutableAttributedString(attributedString: label)
                text.addAttribute(.foregroundColor, value: ink, range: NSRange(location: 0, length: text.length))
                let height = text.size().height
                text.draw(at: NSPoint(x: 21, y: (18 - height) / 2))
            }
            return true
        }
        image.isTemplate = !tinted
        return image
    }
}
