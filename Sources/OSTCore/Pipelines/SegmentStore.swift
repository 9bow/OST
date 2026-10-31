import Foundation

public actor SegmentStore {
    private var finalized: [TranscriptSegment] = []
    private var volatile: [AudioSource: TranscriptSegment] = [:]

    public init() {}

    @discardableResult
    public func merge(_ event: TranscriptEvent, limit: Int = 3) -> [TranscriptSegment] {
        guard case .segment(var segment) = event else { return visibleSegments(limit: limit) }
        let source = segment.audioSource

        if segment.isFinal {
            if let preview = volatile[source], preview.id == segment.id {
                segment = preservingTranslation(from: preview, in: segment)
                volatile[source] = nil
            }
            if let index = finalized.firstIndex(where: { $0.id == segment.id }) {
                finalized[index] = preservingTranslation(from: finalized[index], in: segment)
            } else if let lastIndex = finalized.indices.last,
                      finalized[lastIndex].audioSource == source,
                      normalized(finalized[lastIndex].sourceText) == normalized(segment.sourceText),
                      overlaps(finalized[lastIndex], segment) {
                finalized[lastIndex] = preservingTranslation(from: finalized[lastIndex], in: segment)
            } else {
                finalized.append(segment)
            }
        } else {
            if let index = finalized.firstIndex(where: { $0.id == segment.id }) {
                var correction = preservingTranslation(from: finalized[index], in: segment)
                correction.isFinal = true
                finalized[index] = correction
                return visibleSegments(limit: limit)
            }
            if let latestFinal = finalized.last,
               latestFinal.audioSource == source,
               normalized(latestFinal.sourceText) == normalized(segment.sourceText),
               overlaps(latestFinal, segment) {
                return visibleSegments(limit: limit)
            }
            if let current = volatile[source],
               current.id != segment.id,
               current.startTime > segment.startTime {
                return visibleSegments(limit: limit)
            }
            if let existing = volatile[source], existing.id == segment.id {
                volatile[source] = preservingTranslation(from: existing, in: segment)
            } else {
                volatile[source] = segment
            }
        }
        return visibleSegments(limit: limit)
    }

    public func applyTranslation(
        segmentID: UUID,
        text: String,
        limit: Int = 3
    ) -> [TranscriptSegment] {
        if let source = volatile.first(where: { $0.value.id == segmentID })?.key {
            volatile[source]?.translatedText = text
        } else if let index = finalized.firstIndex(where: { $0.id == segmentID }) {
            finalized[index].translatedText = text
        }
        return visibleSegments(limit: limit)
    }

    public func visibleSegments(limit: Int = 3) -> [TranscriptSegment] {
        guard limit > 0 else { return [] }
        let previews = volatile.values.sorted {
            if $0.startTime != $1.startTime { return $0.startTime < $1.startTime }
            return $0.audioSource.rawValue < $1.audioSource.rawValue
        }.suffix(limit)
        let finalizedTail = finalized.suffix(max(0, limit - previews.count))
        return Array(finalizedTail) + previews
    }

    public func clear() {
        finalized.removeAll(keepingCapacity: false)
        volatile.removeAll(keepingCapacity: false)
    }

    private func preservingTranslation(
        from existing: TranscriptSegment,
        in replacement: TranscriptSegment
    ) -> TranscriptSegment {
        guard replacement.translatedText == nil else { return replacement }
        var replacement = replacement
        replacement.translatedText = existing.translatedText
        return replacement
    }

    private func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private func overlaps(_ first: TranscriptSegment, _ second: TranscriptSegment) -> Bool {
        let firstEnd = first.endTime ?? first.startTime
        let secondEnd = second.endTime ?? second.startTime
        return first.startTime <= secondEnd && second.startTime <= firstEnd
    }
}

public actor AutomaticLanguageStabilizer {
    private var current: SupportedLanguage?
    private var candidate: SupportedLanguage?
    private var candidateCount = 0

    public init() {}

    public func observe(_ detected: SupportedLanguage) -> SupportedLanguage {
        guard let current else {
            current = detected
            candidate = nil
            candidateCount = 0
            return detected
        }
        if detected == current {
            candidate = nil
            candidateCount = 0
            return current
        }
        if candidate == detected {
            candidateCount += 1
        } else {
            candidate = detected
            candidateCount = 1
        }
        if candidateCount >= 2 {
            self.current = detected
            candidate = nil
            candidateCount = 0
            return detected
        }
        return current
    }

    public func reset() {
        current = nil
        candidate = nil
        candidateCount = 0
    }
}
