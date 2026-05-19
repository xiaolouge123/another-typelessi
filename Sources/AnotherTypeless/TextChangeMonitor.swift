import Foundation

/// Monitors text changes at cursor position after dictation output
final class TextChangeMonitor {
    private let contextReader = TextContextReader()
    private var monitoringTask: Task<Void, Never>?
    private let correctionStore: CorrectionStore

    // Recent outputs for multi-sentence matching
    private var recentOutputs: [(text: String, timestamp: Date, sessionID: Int)] = []
    private let recentOutputsLock = NSLock()

    init(correctionStore: CorrectionStore) {
        self.correctionStore = correctionStore
    }

    /// Starts monitoring for text changes after output
    func startMonitoring(
        outputText: String,
        sessionID: Int,
        duration: TimeInterval = 30.0,
        pollInterval: TimeInterval = 5.0
    ) {
        // Cancel any existing monitoring
        stopMonitoring()

        // Add to recent outputs for multi-sentence matching
        addRecentOutput(text: outputText, sessionID: sessionID)

        DictationLogger.shared.log(
            "monitor",
            "start sessionID=\(sessionID) duration=\(duration)s interval=\(pollInterval)s text=\(outputText.prefix(50))"
        )

        monitoringTask = Task { [weak self] in
            guard let self = self else { return }

            let startTime = Date()
            var lastReadText: String?
            var pollCount = 0

            while Date().timeIntervalSince(startTime) < duration {
                try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))

                guard !Task.isCancelled else {
                    DictationLogger.shared.log("monitor", "canceled sessionID=\(sessionID)")
                    return
                }

                pollCount += 1

                // Try to read current line at cursor (simpler and more accurate)
                let lineResult = self.contextReader.readCurrentLine()

                switch lineResult {
                case .success(let currentLine):
                    // Skip if line hasn't changed
                    if currentLine == lastReadText {
                        continue
                    }

                    lastReadText = currentLine

                    DictationLogger.shared.log(
                        "monitor",
                        "poll=\(pollCount) sessionID=\(sessionID) line=\(currentLine.count) chars: \"\(currentLine.prefix(50))\""
                    )

                    // Try to match with single output
                    if let match = self.findMatch(in: currentLine, originalOutput: outputText, sessionID: sessionID) {
                        DictationLogger.shared.log(
                            "monitor",
                            "matched sessionID=\(sessionID) similarity=\(String(format: "%.2f", match.similarity))"
                        )
                        self.correctionStore.append(match)
                        return // Stop monitoring after successful match
                    }

                    // Try to match with concatenated recent outputs (multi-sentence)
                    if let concatenatedMatch = self.findConcatenatedMatch(in: currentLine) {
                        DictationLogger.shared.log(
                            "monitor",
                            "matched-concat sessionID=\(concatenatedMatch.sessionID) similarity=\(String(format: "%.2f", concatenatedMatch.similarity))"
                        )
                        self.correctionStore.append(concatenatedMatch)
                        return
                    }

                case .failure(let error):
                    DictationLogger.shared.log(
                        "monitor",
                        "poll=\(pollCount) sessionID=\(sessionID) error=\(error.localizedDescription)"
                    )
                }
            }

            DictationLogger.shared.log(
                "monitor",
                "timeout sessionID=\(sessionID) polls=\(pollCount) no-match"
            )
        }
    }

    func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    private func addRecentOutput(text: String, sessionID: Int) {
        recentOutputsLock.lock()
        defer { recentOutputsLock.unlock() }

        let now = Date()
        recentOutputs.append((text: text, timestamp: now, sessionID: sessionID))

        // Remove outputs older than 60 seconds
        recentOutputs.removeAll { now.timeIntervalSince($0.timestamp) > 60.0 }
    }

    private func findMatch(
        in currentLine: String,
        originalOutput: String,
        sessionID: Int
    ) -> CorrectionRecord? {
        // Direct comparison - we're only looking at the current line now
        let similarity = TextSimilarity.calculate(originalOutput, currentLine)

        DictationLogger.shared.log(
            "monitor",
            "compare sessionID=\(sessionID) similarity=\(String(format: "%.2f", similarity)) original=\"\(originalOutput)\" current=\"\(currentLine)\""
        )

        guard similarity >= 0.7 else {
            return nil
        }

        // Avoid recording if text is identical
        guard originalOutput != currentLine else {
            DictationLogger.shared.log(
                "monitor",
                "skip-identical sessionID=\(sessionID)"
            )
            return nil
        }

        return CorrectionRecord(
            asrOutput: originalOutput,
            userCorrected: currentLine,
            similarity: similarity,
            sessionID: sessionID
        )
    }

    private func findConcatenatedMatch(in currentText: String) -> CorrectionRecord? {
        recentOutputsLock.lock()
        let outputs = recentOutputs
        recentOutputsLock.unlock()

        guard outputs.count >= 2 else {
            return nil
        }

        // Try concatenating last 2-5 outputs
        for count in 2...min(5, outputs.count) {
            let lastN = outputs.suffix(count)
            let concatenated = lastN.map(\.text).joined(separator: " ")
            let similarity = TextSimilarity.calculate(concatenated, currentText)

            if similarity >= 0.7, concatenated != currentText {
                // Use the most recent sessionID
                let sessionID = lastN.last?.sessionID ?? 0

                return CorrectionRecord(
                    asrOutput: concatenated,
                    userCorrected: currentText,
                    similarity: similarity,
                    sessionID: sessionID
                )
            }
        }

        return nil
    }
}
