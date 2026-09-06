import Foundation
import NaturalLanguage
import StagePrompterCore
@preconcurrency import Translation

enum TopicLanguageAdapter {
    static func translations(
        for topics: [PromptTopic],
        script: String,
        targetLocale: Locale
    ) async -> [UUID: String] {
        let sample = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sample.count >= 30,
              let detectedLanguage = NLLanguageRecognizer.dominantLanguage(for: sample),
              detectedLanguage != .undetermined,
              let targetCode = targetLocale.language.languageCode?.identifier,
              detectedLanguage.rawValue != targetCode
        else { return [:] }

        let sourceLanguage = Locale.Language(identifier: detectedLanguage.rawValue)
        let targetLanguage = targetLocale.language
        let availability = LanguageAvailability()
        guard await availability.status(from: sourceLanguage, to: targetLanguage) == .installed else {
            return [:]
        }

        let session = TranslationSession(installedSource: sourceLanguage, target: targetLanguage)
        guard await session.isReady else { return [:] }

        do {
            var result: [UUID: String] = [:]
            for topic in topics {
                let response = try await session.translate(topic.text)
                let text = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    result[topic.id] = text
                }
            }
            return result
        } catch {
            return [:]
        }
    }
}
