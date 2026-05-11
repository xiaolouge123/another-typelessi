import AppKit

enum StatusBarIconState {
    case idle
    case recording
    case working
    case success
    case warning
    case error

    var accentColor: NSColor {
        switch self {
        case .idle:
            return .secondaryLabelColor
        case .recording:
            return .systemRed
        case .working:
            return .systemBlue
        case .success:
            return .systemGreen
        case .warning:
            return .systemOrange
        case .error:
            return .systemRed
        }
    }

    var fillAlpha: CGFloat {
        switch self {
        case .idle:
            return 0.08
        case .recording:
            return 0.22
        case .working:
            return 0.16
        case .success:
            return 0.15
        case .warning, .error:
            return 0.18
        }
    }

    var strokeAlpha: CGFloat {
        switch self {
        case .idle:
            return 0.82
        default:
            return 0.95
        }
    }
}

enum StatusBarIconFactory {
    static func image(for state: StatusBarIconState) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let accent = state.accentColor
            let outerRect = NSRect(x: 3.5, y: 3.5, width: 11, height: 11)
            let outerPath = NSBezierPath(
                roundedRect: outerRect,
                xRadius: 2.6,
                yRadius: 2.6
            )

            accent.withAlphaComponent(state.fillAlpha).setFill()
            outerPath.fill()

            accent.withAlphaComponent(state.strokeAlpha).setStroke()
            outerPath.lineWidth = 1.45
            outerPath.stroke()

            drawInnerGeometry(in: rect, state: state, accent: accent)
            return true
        }

        image.isTemplate = false
        return image
    }

    private static func drawInnerGeometry(in rect: NSRect, state: StatusBarIconState, accent: NSColor) {
        switch state {
        case .working:
            drawWorkingGeometry(accent: accent)
        case .error:
            drawErrorGeometry(accent: accent)
        default:
            drawSquareGeometry(state: state, accent: accent)
        }
    }

    private static func drawSquareGeometry(state: StatusBarIconState, accent: NSColor) {
        let centerRect: NSRect
        switch state {
        case .recording:
            centerRect = NSRect(x: 7, y: 7, width: 4, height: 4)
        case .success:
            centerRect = NSRect(x: 7.25, y: 7.25, width: 3.5, height: 3.5)
        default:
            centerRect = NSRect(x: 7.4, y: 7.4, width: 3.2, height: 3.2)
        }

        let centerPath = NSBezierPath(
            roundedRect: centerRect,
            xRadius: 0.9,
            yRadius: 0.9
        )

        accent.withAlphaComponent(state == .idle ? 0.78 : 1.0).setFill()
        centerPath.fill()

        if state == .recording {
            let cornerRect = NSRect(x: 5.2, y: 5.2, width: 1.9, height: 1.9)
            let cornerPath = NSBezierPath(roundedRect: cornerRect, xRadius: 0.6, yRadius: 0.6)
            accent.withAlphaComponent(0.55).setFill()
            cornerPath.fill()
        }
    }

    private static func drawWorkingGeometry(accent: NSColor) {
        let rects = [
            NSRect(x: 6.1, y: 7.2, width: 1.8, height: 3.6),
            NSRect(x: 8.3, y: 6.1, width: 1.8, height: 5.8),
            NSRect(x: 10.5, y: 7.2, width: 1.8, height: 3.6)
        ]

        accent.withAlphaComponent(0.95).setFill()
        rects.forEach { rect in
            NSBezierPath(roundedRect: rect, xRadius: 0.8, yRadius: 0.8).fill()
        }
    }

    private static func drawErrorGeometry(accent: NSColor) {
        accent.withAlphaComponent(0.95).setStroke()

        let first = NSBezierPath()
        first.lineWidth = 1.5
        first.lineCapStyle = .round
        first.move(to: NSPoint(x: 6.8, y: 6.8))
        first.line(to: NSPoint(x: 11.2, y: 11.2))
        first.stroke()

        let second = NSBezierPath()
        second.lineWidth = 1.5
        second.lineCapStyle = .round
        second.move(to: NSPoint(x: 11.2, y: 6.8))
        second.line(to: NSPoint(x: 6.8, y: 11.2))
        second.stroke()
    }
}
