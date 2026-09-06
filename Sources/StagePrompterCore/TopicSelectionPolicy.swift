import Foundation

public enum TopicSelectionPolicy {
    public static func allowsOrderOverride(
        topic: String,
        evidence: String,
        recentTranscript: String,
        languageCode: String? = nil
    ) -> Bool {
        let normalisedEvidence = normalised(evidence)
        let normalisedTranscript = normalised(recentTranscript)
        guard normalisedEvidence.count >= 3,
              normalisedTranscript.contains(normalisedEvidence)
        else { return false }

        return TopicMatcher.hasSignificantOverlap(
            topic: topic,
            text: evidence,
            languageCode: languageCode
        )
    }

    private static func normalised(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
