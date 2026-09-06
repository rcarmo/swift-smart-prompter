import Foundation
import NaturalLanguage

public enum TopicMatcher {
    private static let commonStopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "by", "for", "from", "i", "in", "is", "it", "of",
        "on", "or", "our", "that", "the", "their", "this", "to", "we", "what", "with", "you", "your",
        "about", "ask", "confirm", "discuss", "explain", "mention", "opening", "talk",
    ]

    private static let localeStopWords: [String: Set<String>] = [
        "de": ["der", "die", "das", "den", "dem", "des", "ein", "eine", "und", "oder", "von", "zu", "mit", "bestätigen", "fragen", "erklären", "besprechen", "erwähnen"],
        "es": ["el", "la", "los", "las", "de", "del", "un", "una", "y", "o", "en", "para", "con", "confirmar", "preguntar", "explicar", "discutir", "mencionar", "hablar", "sobre"],
        "fr": ["le", "la", "les", "de", "des", "du", "un", "une", "et", "ou", "en", "pour", "avec", "confirmer", "demander", "expliquer", "discuter", "mentionner", "parler"],
        "it": ["il", "lo", "la", "i", "gli", "le", "di", "del", "un", "una", "e", "o", "in", "per", "con", "confermare", "chiedere", "spiegare", "discutere", "menzionare", "parlare"],
        "nl": ["de", "het", "een", "en", "of", "van", "voor", "met", "bevestigen", "vragen", "uitleggen", "bespreken", "vermelden"],
        "pt": ["a", "o", "as", "os", "de", "da", "do", "das", "dos", "um", "uma", "e", "ou", "em", "para", "por", "com", "confirmar", "perguntar", "explicar", "discutir", "mencionar", "falar", "sobre", "abertura"],
    ]

    public static func isCovered(
        topic: String,
        by transcript: String,
        languageCode: String? = nil
    ) -> Bool {
        let topicTokens = significantTokens(in: topic, languageCode: languageCode)
        guard !topicTokens.isEmpty else { return false }

        let transcriptTokens = Set(tokens(in: transcript, languageCode: languageCode).map(canonicalToken))
        let matches = topicTokens.filter { topicToken in
            transcriptTokens.contains { transcriptToken in
                tokensAreRelated(topicToken, transcriptToken)
            }
        }.count
        let required = topicTokens.count == 1 ? 1 : max(2, Int(ceil(Double(topicTokens.count) * 0.5)))
        return matches >= required
    }

    public static func significantTokens(
        in text: String,
        languageCode: String? = nil
    ) -> Set<String> {
        let stopWords = commonStopWords.union(localeStopWords[languageCode ?? ""] ?? [])
        return Set(tokens(in: text, languageCode: languageCode)
            .filter { !stopWords.contains($0) && $0.count > 2 }
            .map(canonicalToken))
    }

    private static func tokensAreRelated(_ left: String, _ right: String) -> Bool {
        if left == right { return true }
        let shorterCount = min(left.count, right.count)
        guard shorterCount >= 7 else { return false }
        return left.commonPrefix(with: right).count >= min(8, shorterCount - 1)
    }

    private static func canonicalToken(_ token: String) -> String {
        if token.hasSuffix("ies"), token.count > 5 {
            return String(token.dropLast(3)) + "y"
        }
        if token.hasSuffix("s"), token.count > 4 {
            return String(token.dropLast())
        }
        return token
    }

    private static func tokens(in text: String, languageCode: String?) -> [String] {
        let normalized = text.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: languageCode ?? Locale.current.identifier)
        )
            .lowercased()
        guard let languageCode else { return basicTokens(in: normalized) }

        let language = NLLanguage(rawValue: languageCode)
        guard NLTagger.availableTagSchemes(for: .word, language: language).contains(.lemma) else {
            return basicTokens(in: normalized)
        }

        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = normalized
        tagger.setLanguage(language, range: normalized.startIndex..<normalized.endIndex)
        var result: [String] = []
        tagger.enumerateTags(
            in: normalized.startIndex..<normalized.endIndex,
            unit: .word,
            scheme: .lemma,
            options: [.omitPunctuation, .omitWhitespace]
        ) { tag, range in
            let token = tag?.rawValue ?? String(normalized[range])
            if !token.isEmpty {
                result.append(token)
            }
            return true
        }
        return result
    }

    private static func basicTokens(in text: String) -> [String] {
        text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
