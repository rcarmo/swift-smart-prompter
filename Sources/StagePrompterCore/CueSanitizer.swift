import Foundation

public enum CueSanitizer {
    public static func usableCue(from response: String) -> String? {
        let cue = response
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cue.isEmpty else { return nil }

        let lowercased = cue.lowercased()
        let modelCommentary = [
            "natural bridge",
            "uncovered point",
            "here's what",
            "here’s what",
            "here is what",
            "as your coach",
        ]
        guard !lowercased.hasPrefix("sure,"),
              !modelCommentary.contains(where: lowercased.contains)
        else { return nil }

        return cue
    }

    public static func isNearDuplicate(_ cue: String, of priorCues: [String]) -> Bool {
        let cueWords = normalisedWords(in: cue)
        guard !cueWords.isEmpty else { return true }

        return priorCues.contains { priorCue in
            let priorWords = normalisedWords(in: priorCue)
            guard !priorWords.isEmpty else { return false }
            let sharedCount = cueWords.intersection(priorWords).count
            let smallerCount = min(cueWords.count, priorWords.count)
            return Double(sharedCount) / Double(smallerCount) >= 0.75
        }
    }

    private static func normalisedWords(in text: String) -> Set<String> {
        Set(text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty })
    }
}
