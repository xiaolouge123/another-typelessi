import Foundation

/// Calculates similarity between two strings using Levenshtein distance
enum TextSimilarity {
    /// Returns similarity score between 0.0 and 1.0
    static func calculate(_ str1: String, _ str2: String) -> Double {
        let s1 = str1.trimmingCharacters(in: .whitespacesAndNewlines)
        let s2 = str2.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !s1.isEmpty, !s2.isEmpty else {
            return s1.isEmpty && s2.isEmpty ? 1.0 : 0.0
        }

        let distance = levenshteinDistance(s1, s2)
        let maxLength = max(s1.count, s2.count)
        return 1.0 - (Double(distance) / Double(maxLength))
    }

    /// Calculates Levenshtein distance between two strings
    private static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        let m = s1Array.count
        let n = s2Array.count

        guard m > 0 else { return n }
        guard n > 0 else { return m }

        var matrix = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m {
            matrix[i][0] = i
        }

        for j in 0...n {
            matrix[0][j] = j
        }

        for i in 1...m {
            for j in 1...n {
                let cost = s1Array[i - 1] == s2Array[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,      // deletion
                    matrix[i][j - 1] + 1,      // insertion
                    matrix[i - 1][j - 1] + cost // substitution
                )
            }
        }

        return matrix[m][n]
    }
}
