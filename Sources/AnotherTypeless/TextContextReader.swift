import AppKit
import ApplicationServices

/// Reads text context from the currently focused application using Accessibility API
final class TextContextReader {
    enum ReadError: LocalizedError {
        case noFocusedElement
        case noTextValue
        case accessibilityDenied
        case unsupportedElement

        var errorDescription: String? {
            switch self {
            case .noFocusedElement:
                return "No focused UI element found"
            case .noTextValue:
                return "Focused element has no text content"
            case .accessibilityDenied:
                return "Accessibility permission not granted"
            case .unsupportedElement:
                return "Element type does not support text reading"
            }
        }
    }

    struct TextContext {
        let fullText: String
        let selectedText: String?
        let selectedRange: CFRange?
        let cursorPosition: Int?
    }

    /// Attempts to read text context from the currently focused application
    func readContext() -> Result<TextContext, ReadError> {
        guard AXIsProcessTrusted() else {
            return .failure(.accessibilityDenied)
        }

        // Get the system-wide focused UI element
        guard let focusedElement = getFocusedElement() else {
            return .failure(.noFocusedElement)
        }

        // Try to read various text attributes
        let fullText = getValue(for: focusedElement, attribute: kAXValueAttribute as CFString) as? String
        let selectedText = getValue(for: focusedElement, attribute: kAXSelectedTextAttribute as CFString) as? String
        let selectedRangeValue = getValue(for: focusedElement, attribute: kAXSelectedTextRangeAttribute as CFString)

        // Extract CFRange from AXValue if available
        var range: CFRange = CFRange(location: 0, length: 0)
        var rangePtr: CFRange?
        if let selectedRangeValue = selectedRangeValue {
            let axValue = unsafeBitCast(selectedRangeValue, to: AXValue.self)
            if AXValueGetValue(axValue, .cfRange, &range) {
                rangePtr = range
            }
        }

        // If we have full text, we can derive cursor position from selected range
        let cursorPosition: Int? = {
            if let r = rangePtr, r.length == 0 {
                return r.location
            }
            return nil
        }()

        guard fullText != nil || selectedText != nil else {
            return .failure(.noTextValue)
        }

        return .success(TextContext(
            fullText: fullText ?? "",
            selectedText: selectedText,
            selectedRange: rangePtr,
            cursorPosition: cursorPosition
        ))
    }

    /// Extracts text before cursor (up to maxLength characters)
    func readTextBeforeCursor(maxLength: Int = 1000) -> Result<String, ReadError> {
        let result = readContext()

        switch result {
        case .success(let context):
            guard !context.fullText.isEmpty else {
                return .failure(.noTextValue)
            }

            // If we have cursor position, extract text before it
            if let cursorPos = context.cursorPosition {
                let startIndex = max(0, cursorPos - maxLength)
                let text = context.fullText
                let start = text.index(text.startIndex, offsetBy: startIndex)
                let end = text.index(text.startIndex, offsetBy: cursorPos)
                return .success(String(text[start..<end]))
            }

            // Fallback: return last maxLength characters
            let text = context.fullText
            if text.count <= maxLength {
                return .success(text)
            }
            let start = text.index(text.endIndex, offsetBy: -maxLength)
            return .success(String(text[start...]))

        case .failure(let error):
            return .failure(error)
        }
    }

    /// Reads the current line where the cursor is located
    func readCurrentLine() -> Result<String, ReadError> {
        let result = readContext()

        switch result {
        case .success(let context):
            guard !context.fullText.isEmpty else {
                return .failure(.noTextValue)
            }

            guard let cursorPos = context.cursorPosition else {
                // No cursor position, return last 200 chars as fallback
                let text = context.fullText
                if text.count <= 200 {
                    return .success(text)
                }
                let start = text.index(text.endIndex, offsetBy: -200)
                return .success(String(text[start...]))
            }

            let text = context.fullText

            // Find line start (search backwards for newline)
            var lineStart = text.startIndex
            if cursorPos > 0 {
                let cursorIndex = text.index(text.startIndex, offsetBy: min(cursorPos, text.count))
                var searchIndex = text.index(before: cursorIndex)

                while searchIndex > text.startIndex {
                    if text[searchIndex].isNewline {
                        lineStart = text.index(after: searchIndex)
                        break
                    }
                    searchIndex = text.index(before: searchIndex)
                }
            }

            // Find line end (search forwards for newline)
            let cursorIndex = text.index(text.startIndex, offsetBy: min(cursorPos, text.count))
            var lineEnd = text.endIndex
            var searchIndex = cursorIndex

            while searchIndex < text.endIndex {
                if text[searchIndex].isNewline {
                    lineEnd = searchIndex
                    break
                }
                searchIndex = text.index(after: searchIndex)
            }

            return .success(String(text[lineStart..<lineEnd]))

        case .failure(let error):
            return .failure(error)
        }
    }

    private func getFocusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: CFTypeRef?

        let appResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApp
        )

        guard appResult == .success, let app = focusedApp else {
            return nil
        }

        var focusedElement: CFTypeRef?
        let elementResult = AXUIElementCopyAttributeValue(
            app as! AXUIElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard elementResult == .success, let element = focusedElement else {
            return nil
        }

        return (element as! AXUIElement)
    }

    private func getValue(for element: AXUIElement, attribute: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        return result == .success ? value : nil
    }
}
