import AppKit
import SwiftUI

final class FloatingStatusWindowController: NSWindowController {
    private let viewModel = FloatingStatusViewModel()
    private var hideWorkItem: DispatchWorkItem?

    init() {
        let contentView = FloatingStatusView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: contentView)
        let size = NSSize(width: 148, height: 148)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentViewController = hostingController
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        super.init(window: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showRecording() {
        show(title: "Recording", detail: "Press Fn to stop", phase: .recording)
    }

    func showTranscribing() {
        show(title: "Transcribing", detail: "Sending audio to OpenRouter", phase: .working)
    }

    func showPolishing() {
        show(title: "Polishing", detail: "Formalizing with GPT", phase: .working)
    }

    func showSuccess(_ detail: String) {
        show(title: "Done", detail: detail, phase: .success)
        hide(after: 1.25)
    }

    func showNoSpeech() {
        show(title: "No Speech", detail: "Nothing useful detected", phase: .neutral)
        hide(after: 1.2)
    }

    func showCanceled() {
        show(title: "Canceled", detail: "Esc pressed", phase: .neutral)
        hide(after: 1.0)
    }

    func showError(_ message: String) {
        show(title: "Error", detail: message, phase: .error)
        hide(after: 4.0)
    }

    func hide() {
        hideWorkItem?.cancel()
        window?.orderOut(nil)
    }

    private func show(title: String, detail: String, phase: FloatingStatusPhase) {
        hideWorkItem?.cancel()
        viewModel.title = title
        viewModel.detail = detail
        viewModel.phase = phase
        positionWindow()
        window?.orderFrontRegardless()
    }

    private func hide(after delay: TimeInterval) {
        hideWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.window?.orderOut(nil)
        }

        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func positionWindow() {
        guard let window else {
            return
        }

        let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        let size = window.frame.size
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.minY + 72
        )
        window.setFrameOrigin(origin)
    }
}

enum FloatingStatusPhase {
    case recording
    case working
    case success
    case neutral
    case error

    var tint: Color {
        switch self {
        case .recording:
            return .red
        case .working:
            return .blue
        case .success:
            return .green
        case .neutral:
            return .gray
        case .error:
            return .orange
        }
    }

    var symbolName: String {
        switch self {
        case .recording:
            return "mic.fill"
        case .working:
            return "waveform"
        case .success:
            return "checkmark"
        case .neutral:
            return "minus"
        case .error:
            return "exclamationmark"
        }
    }
}

final class FloatingStatusViewModel: ObservableObject {
    @Published var title = "Ready"
    @Published var detail = "Fn"
    @Published var phase: FloatingStatusPhase = .working
}

private struct FloatingStatusView: View {
    @ObservedObject var viewModel: FloatingStatusViewModel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.black.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )

            VStack(spacing: 10) {
                statusGlyph

                VStack(spacing: 4) {
                    Text(viewModel.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(viewModel.detail)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(width: 112)
                }
            }
            .padding(14)
        }
        .frame(width: 148, height: 148)
    }

    @ViewBuilder
    private var statusGlyph: some View {
        switch viewModel.phase {
        case .recording:
            RecordingGlyph(tint: viewModel.phase.tint)
        case .working:
            LoadingGlyph(tint: viewModel.phase.tint)
        default:
            StaticGlyph(tint: viewModel.phase.tint, symbolName: viewModel.phase.symbolName)
        }
    }
}

private struct RecordingGlyph: View {
    let tint: Color

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let pulse = 0.92 + 0.12 * normalizedSine(time, speed: 2.1)
            let ringScale = 0.92 + 0.18 * normalizedSine(time, speed: 2.8)
            let ringOpacity = 0.18 + 0.22 * normalizedSine(time, speed: 2.8)
            let bounce = 1.0 + 0.05 * sin(time * 5.0)

            ZStack {
                Circle()
                    .fill(tint.opacity(0.12))
                    .frame(width: 60, height: 60)
                    .scaleEffect(ringScale)

                Circle()
                    .stroke(tint.opacity(ringOpacity), lineWidth: 2)
                    .frame(width: 60, height: 60)
                    .scaleEffect(ringScale)

                VStack(spacing: 7) {
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(0..<4, id: \.self) { index in
                            let barTime = time * 5.4 + Double(index) * 0.85
                            let height = 6 + 14 * normalizedSine(barTime, speed: 1.0)
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(tint)
                                .frame(width: 4, height: height)
                        }
                    }
                    .frame(height: 24)

                    Image(systemName: "mic.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(tint)
                }
                .scaleEffect(pulse * bounce)
                .shadow(color: tint.opacity(0.22), radius: 10, x: 0, y: 0)
            }
        }
        .frame(width: 72, height: 72)
    }
}

private struct LoadingGlyph: View {
    let tint: Color

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let primaryRotation = Angle.degrees(time * 220)
            let secondaryRotation = Angle.degrees(-time * 160)

            ZStack {
                Circle()
                    .fill(tint.opacity(0.11))
                    .frame(width: 60, height: 60)

                Circle()
                    .stroke(tint.opacity(0.22), lineWidth: 2)
                    .frame(width: 60, height: 60)

                Circle()
                    .trim(from: 0.12, to: 0.42)
                    .stroke(tint, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .frame(width: 40, height: 40)
                    .rotationEffect(primaryRotation)

                Circle()
                    .trim(from: 0.55, to: 0.78)
                    .stroke(tint.opacity(0.45), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: 48, height: 48)
                    .rotationEffect(secondaryRotation)

                Circle()
                    .fill(tint)
                    .frame(width: 5, height: 5)
                    .offset(y: -18)
                    .rotationEffect(primaryRotation)
            }
        }
        .frame(width: 72, height: 72)
    }
}

private struct StaticGlyph: View {
    let tint: Color
    let symbolName: String

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.18))
                .frame(width: 56, height: 56)

            Circle()
                .stroke(tint.opacity(0.55), lineWidth: 2)
                .frame(width: 56, height: 56)

            Image(systemName: symbolName)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(tint)
        }
        .frame(width: 72, height: 72)
    }
}

private func normalizedSine(_ value: Double, speed: Double) -> Double {
    (sin(value * speed) + 1) / 2
}
