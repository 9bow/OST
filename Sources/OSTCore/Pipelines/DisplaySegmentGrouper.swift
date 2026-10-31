import Foundation

public enum DisplaySegmentGrouper {
    public static func group(
        _ segments: [TranscriptSegment],
        maximumCharacters: Int = 180,
        maximumDuration: Duration = .seconds(12)
    ) -> [TranscriptSegment] {
        var grouped: [TranscriptSegment] = []
        for segment in segments {
            guard segment.isFinal,
                  let previous = grouped.last,
                  previous.isFinal,
                  previous.audioSource == segment.audioSource,
                  previous.language == segment.language,
                  !hasTerminalPunctuation(previous.sourceText),
                  joined(previous.sourceText, segment.sourceText).count <= maximumCharacters,
                  duration(from: previous, through: segment) <= maximumDuration else {
                grouped.append(segment)
                continue
            }

            var merged = previous
            merged.sourceText = joined(previous.sourceText, segment.sourceText)
            if let translation = segment.translatedText {
                merged.translatedText = previous.translatedText.map {
                    joined($0, translation)
                } ?? translation
            }
            merged.endTime = segment.endTime ?? previous.endTime
            grouped[grouped.count - 1] = merged
        }
        return grouped
    }

    private static func hasTerminalPunctuation(_ text: String) -> Bool {
        guard let last = text.trimmingCharacters(in: .whitespacesAndNewlines).last else {
            return false
        }
        return ".?!。？！".contains(last)
    }

    private static func joined(_ first: String, _ second: String) -> String {
        let first = first.trimmingCharacters(in: .whitespacesAndNewlines)
        let second = second.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !first.isEmpty else { return second }
        guard !second.isEmpty else { return first }
        let attachesToPrevious = second.first.map {
            ".,?!:;，。？！、".contains($0)
        } ?? false
        return first + (attachesToPrevious ? "" : " ") + second
    }

    private static func duration(
        from first: TranscriptSegment,
        through last: TranscriptSegment
    ) -> Duration {
        (last.endTime ?? last.startTime) - first.startTime
    }
}
