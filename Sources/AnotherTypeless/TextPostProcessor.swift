import Foundation

enum TextPostProcessor {
    static func process(_ text: String, language: RecognitionLanguage, cleanFillers: Bool) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !result.isEmpty else {
            return ""
        }

        if cleanFillers {
            result = removeFillers(from: result, language: language)
        }

        result = normalizeWhitespace(result)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func hasMeaningfulContent(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }

        let compact = trimmed.unicodeScalars.filter { scalar in
            !(CharacterSet.whitespacesAndNewlines.contains(scalar) ||
              CharacterSet.punctuationCharacters.contains(scalar) ||
              CharacterSet.symbols.contains(scalar))
        }

        let normalized = String(String.UnicodeScalarView(compact))
        guard !normalized.isEmpty else {
            return false
        }

        let folded = normalized.lowercased()
        if noiseTokens.contains(folded) {
            return false
        }

        if normalized.count == 1 {
            return !singleGlyphFillers.contains(folded)
        }

        return true
    }

    private static func removeFillers(from text: String, language: RecognitionLanguage) -> String {
        var result = text

        switch language {
        case .auto:
            result = replace(#"(嗯+|呃+|额+|那个|就是|然后然后|啊这个|这个这个)"#, in: result)
            result = replace(#"\b(um+|uh+|erm+|like|you know|i mean|sort of|kind of|basically)\b"#, in: result)
            result = replace(#"(えー+|あの+|その+)"#, in: result)
            result = replace(#"(음+|어+|그니까)"#, in: result)
            result = replace(#"\b(eh+|em+|este|bueno)\b"#, in: result)
            result = replace(#"\s+([，。！？、；：])"#, in: result, with: "$1")
        case .zhCN:
            result = replace(#"(嗯+|呃+|额+|那个|就是|然后然后|啊这个|这个这个)"#, in: result)
            result = replace(#"\s+([，。！？、；：])"#, in: result, with: "$1")
        case .enUS:
            result = replace(#"\b(um+|uh+|erm+|like|you know|i mean|sort of|kind of|basically)\b"#, in: result)
        case .jaJP:
            result = replace(#"(えー+|あの+|その+)"#, in: result)
        case .koKR:
            result = replace(#"(음+|어+|그니까)"#, in: result)
        case .esES:
            result = replace(#"\b(eh+|em+|este|bueno)\b"#, in: result)
        }

        return result
    }

    private static func normalizeWhitespace(_ text: String) -> String {
        var result = text
        result = replace(#"[ \t]{2,}"#, in: result, with: " ")
        result = replace(#"\n{3,}"#, in: result, with: "\n\n")
        result = replace(#"\s+([,.!?;:])"#, in: result, with: "$1")
        return result
    }

    private static func replace(_ pattern: String, in text: String, with replacement: String = "") -> String {
        text.replacingOccurrences(
            of: pattern,
            with: replacement,
            options: [.regularExpression, .caseInsensitive]
        )
    }

    private static let singleGlyphFillers: Set<String> = [
        "嗯", "啊", "呃", "额", "哦", "呀", "え", "음", "어"
    ]

    private static let noiseTokens: Set<String> = [
        "嗯", "嗯嗯", "啊", "呃", "额", "哦", "呀", "uh", "um", "erm", "eh", "hm", "mm", "え", "음", "어"
    ]
}
