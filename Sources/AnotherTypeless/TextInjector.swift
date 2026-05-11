import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum InjectionResult {
    case pasted
    case copied
    case copiedBecauseAccessibilityMissing
}

final class TextInjector {
    func requestAccessibilityPermission() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func insert(text: String, mode: OutputMode, restoreClipboard: Bool) -> InjectionResult {
        switch mode {
        case .clipboardOnly:
            writeClipboard(text)
            return .copied
        case .pasteAtCursor:
            guard AXIsProcessTrusted() else {
                writeClipboard(text)
                return .copiedBecauseAccessibilityMissing
            }

            let snapshot = PasteboardSnapshot.capture()
            writeClipboard(text)
            sendPasteShortcut()

            if restoreClipboard {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    snapshot.restore()
                }
            }

            return .pasted
        }
    }

    private func writeClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func sendPasteShortcut() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCode = CGKeyCode(kVK_ANSI_V)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = .maskCommand

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

private struct PasteboardSnapshot {
    private let items: [NSPasteboardItem]

    static func capture() -> PasteboardSnapshot {
        let copiedItems = (NSPasteboard.general.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()

            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }

            return copy
        }

        return PasteboardSnapshot(items: copiedItems)
    }

    func restore() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        guard !items.isEmpty else {
            return
        }

        pasteboard.writeObjects(items)
    }
}
