#!/usr/bin/env swift

import Foundation
import ApplicationServices

// Inline the TextContextReader for testing
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

    func readContext() -> Result<TextContext, ReadError> {
        guard AXIsProcessTrusted() else {
            return .failure(.accessibilityDenied)
        }

        guard let focusedElement = getFocusedElement() else {
            return .failure(.noFocusedElement)
        }

        let fullText = getValue(for: focusedElement, attribute: kAXValueAttribute as CFString) as? String
        let selectedText = getValue(for: focusedElement, attribute: kAXSelectedTextAttribute as CFString) as? String
        let selectedRange = getValue(for: focusedElement, attribute: kAXSelectedTextRangeAttribute as CFString) as? AXValue

        var range: CFRange = CFRange(location: 0, length: 0)
        var rangePtr: CFRange?
        if let selectedRange = selectedRange {
            if AXValueGetValue(selectedRange, .cfRange, &range) {
                rangePtr = range
            }
        }

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

// Test the reader
print("Testing TextContextReader...")
print("Please focus on a text field and wait 3 seconds...")
sleep(3)

let reader = TextContextReader()
let result = reader.readContext()

switch result {
case .success(let context):
    print("\n✅ Successfully read context:")
    print("Full text length: \(context.fullText.count) characters")
    print("Full text preview: \(String(context.fullText.prefix(100)))")
    if let selected = context.selectedText {
        print("Selected text: \(selected)")
    }
    if let cursor = context.cursorPosition {
        print("Cursor position: \(cursor)")
    }
case .failure(let error):
    print("\n❌ Failed to read context: \(error.localizedDescription)")
}
