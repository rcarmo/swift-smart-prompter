import Foundation
import FoundationModels
import Observation
import Speech
import StagePrompterCore

struct SpeechLocaleOption: Identifiable {
    let id: String
    let name: String
    let isInstalled: Bool
}

@Generable
private struct CoachAdvice {
    @Guide(description: "Only the exact, natural words the user should say aloud next. No introduction, rationale, label, quotation marks, or coaching commentary.")
    var wordsToSay: String

    @Guide(description: "At most two one-based numbers of points directly and substantively covered by the recent conversation. Return an empty array when uncertain.")
    var coveredPointNumbers: [Int]

    @Guide(description: "The one-based number of the still-active point that wordsToSay advances. Prefer earlier points when relevance is otherwise similar, but allow a later point when it clearly fits the conversation better. Return zero when wordsToSay only answers the other speaker.")
    var targetPointNumber: Int
}

@MainActor
@Observable
final class AppModel {
    enum State: Equatable {
        case ready
        case starting
        case listening
        case failed(String)
    }

    var script: String {
        didSet { UserDefaults.standard.set(script, forKey: Self.scriptKey) }
    }
    var localeIdentifier: String {
        didSet { UserDefaults.standard.set(localeIdentifier, forKey: Self.localeKey) }
    }
    var topics: [PromptTopic] = []
    var transcript: [TranscriptLine] = []
    var suggestion = "Add your talking points, then start listening."
    var suggestionLabel = "NEXT CUE"
    var state: State = .ready
    var intelligenceStatus = "Checking Apple Intelligence…"
    var transcriptionStatus = "Inputs not started"
    var microphoneLevel: Float = 0
    var callLevel: Float = 0
    var showTranscript = true
    var speechLocaleOptions: [SpeechLocaleOption] = []
    var isLoadingSpeechLocales = true
    var microphoneOptions: [AudioSourceOption] = []
    var callAudioOptions: [AudioSourceOption] = []
    var selectedMicrophoneID: String {
        didSet { UserDefaults.standard.set(selectedMicrophoneID, forKey: Self.microphoneKey) }
    }
    var selectedCallAudioID: String {
        didSet { UserDefaults.standard.set(selectedCallAudioID, forKey: Self.callAudioKey) }
    }
    var onlyMe: Bool {
        didSet { UserDefaults.standard.set(onlyMe, forKey: Self.onlyMeKey) }
    }

    private let capture = ConversationCapture()
    private let cuePanel = CuePanelController()
    private var adviceTask: Task<Void, Never>?
    private var suggestionTopicID: UUID?
    private var suggestionIsGenerated = false
    private var lastRepliedCallID: UUID?
    private var recentCues: [String] = []
    private var manuallyUncoveredTopicIDs = Set<UUID>()
    private var translatedTopicTexts: [UUID: String] = [:]
    private static let scriptKey = "talkingPoints"
    private static let localeKey = "speechLocale"
    private static let microphoneKey = "microphoneDeviceID"
    private static let callAudioKey = "callAudioSourceID"
    private static let onlyMeKey = "onlyMeListeningMode"

    init() {
        script = UserDefaults.standard.string(forKey: Self.scriptKey) ?? """
        Opening: confirm the goal of the call
        Ask about the current situation and constraints
        Explain the proposed approach and its benefits
        Discuss timing and ownership
        Confirm decisions and next steps
        """
        localeIdentifier = UserDefaults.standard.string(forKey: Self.localeKey)
            ?? Locale.preferredLanguages.first
            ?? "en-US"
        let microphones = AudioSourceCatalog.microphones()
        let callSources = AudioSourceCatalog.callApplications()
        microphoneOptions = microphones
        callAudioOptions = callSources
        let storedMicrophone = UserDefaults.standard.string(forKey: Self.microphoneKey)
        selectedMicrophoneID = microphones.contains(where: { $0.id == storedMicrophone })
            ? storedMicrophone ?? AudioSourceCatalog.systemDefaultMicrophoneID
            : AudioSourceCatalog.systemDefaultMicrophoneID
        let storedCallAudio = UserDefaults.standard.string(forKey: Self.callAudioKey)
        selectedCallAudioID = callSources.contains(where: { $0.id == storedCallAudio })
            ? storedCallAudio ?? AudioSourceCatalog.allSystemAudioID
            : AudioSourceCatalog.allSystemAudioID
        onlyMe = UserDefaults.standard.bool(forKey: Self.onlyMeKey)
        capture.onTranscript = { [weak self] speaker, text, isFinal in
            self?.receiveTranscript(speaker: speaker, text: text, isFinal: isFinal)
        }
        capture.onLevel = { [weak self] speaker, level in
            if speaker == .you {
                self?.microphoneLevel = level
            } else {
                self?.callLevel = level
            }
        }
        capture.onStatus = { [weak self] message in
            self?.transcriptionStatus = message
        }
        capture.onFailure = { [weak self] message in
            Task { await self?.failCapture(message: message) }
        }
        refreshIntelligenceStatus()
        Task { [weak self] in
            await self?.loadSpeechLocales()
        }
    }

    var isListening: Bool { state == .listening || state == .starting }

    var uncoveredTopics: [PromptTopic] { topics.filter { !$0.isCovered } }

    var installedSpeechLocaleOptions: [SpeechLocaleOption] {
        speechLocaleOptions.filter(\.isInstalled)
    }

    var downloadableSpeechLocaleOptions: [SpeechLocaleOption] {
        speechLocaleOptions.filter { !$0.isInstalled }
    }

    var selectedSpeechLocaleOption: SpeechLocaleOption? {
        speechLocaleOptions.first { $0.id == localeIdentifier }
    }

    var selectedMicrophoneName: String {
        microphoneOptions.first(where: { $0.id == selectedMicrophoneID })?.name ?? "Unavailable"
    }

    var selectedCallAudioName: String {
        callAudioOptions.first(where: { $0.id == selectedCallAudioID })?.name ?? "Unavailable"
    }

    var statusText: String {
        switch state {
        case .ready: "Ready"
        case .starting: "Starting…"
        case .listening: onlyMe ? "Listening to you" : "Listening on this Mac"
        case .failed: "Needs attention"
        }
    }

    func start() async {
        let parsedTopics = PromptTopic.parse(script: script)
        guard !parsedTopics.isEmpty else {
            state = .failed("Add at least one talking point before starting.")
            return
        }

        topics = parsedTopics
        transcript = []
        recentCues = []
        lastRepliedCallID = nil
        manuallyUncoveredTopicIDs = []
        translatedTopicTexts = [:]
        suggestionLabel = "OPEN WITH"
        suggestion = parsedTopics[0].text
        suggestionTopicID = parsedTopics[0].id
        suggestionIsGenerated = false
        state = .starting
        transcriptionStatus = "Preparing topic language…"
        translatedTopicTexts = await TopicLanguageAdapter.translations(
            for: parsedTopics,
            script: script,
            targetLocale: Locale(identifier: localeIdentifier)
        )
        suggestion = translatedTopicTexts[parsedTopics[0].id] ?? parsedTopics[0].text
        transcriptionStatus = "Requesting audio access…"
        do {
            try await capture.start(
                localeIdentifier: localeIdentifier,
                contextualStrings: parsedTopics.map { translatedTopicTexts[$0.id] ?? $0.text },
                microphoneDeviceID: selectedMicrophoneID == AudioSourceCatalog.systemDefaultMicrophoneID
                    ? nil
                    : selectedMicrophoneID,
                callApplicationBundleIdentifier: selectedCallAudioID == AudioSourceCatalog.allSystemAudioID
                    ? nil
                    : selectedCallAudioID,
                onlyMe: onlyMe
            )
            await loadSpeechLocales()
            state = .listening
            cuePanel.show(model: self)
            scheduleAdvice()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop() async {
        adviceTask?.cancel()
        adviceTask = nil
        await capture.stop()
        cuePanel.hide()
        state = .ready
        transcriptionStatus = "Inputs stopped"
        suggestion = uncoveredTopics.first?.text ?? "All talking points covered."
        suggestionTopicID = uncoveredTopics.first?.id
        suggestionIsGenerated = false
    }

    func resetAfterFailure() {
        state = .ready
    }

    func showCuePanel() {
        cuePanel.show(model: self)
    }

    func refreshAudioSources() {
        let microphones = AudioSourceCatalog.microphones()
        let callSources = AudioSourceCatalog.callApplications()
        microphoneOptions = microphones
        callAudioOptions = callSources
        if !microphones.contains(where: { $0.id == selectedMicrophoneID }) {
            selectedMicrophoneID = AudioSourceCatalog.systemDefaultMicrophoneID
        }
        if !callSources.contains(where: { $0.id == selectedCallAudioID }) {
            selectedCallAudioID = AudioSourceCatalog.allSystemAudioID
        }
    }

    func selectSpeechLocale(_ identifier: String) {
        localeIdentifier = identifier
    }

    func toggleCovered(id: UUID) {
        guard let index = topics.firstIndex(where: { $0.id == id }) else { return }
        if topics[index].isCovered {
            topics[index].isCovered = false
            manuallyUncoveredTopicIDs.insert(id)
        } else {
            topics[index].isCovered = true
            manuallyUncoveredTopicIDs.remove(id)
        }
        suggestionLabel = "NEXT POINT"
        showNextUncoveredFallback()
        scheduleAdvice()
    }

    private func receiveTranscript(speaker: Speaker, text: String, isFinal: Bool) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let index = transcript.lastIndex(where: { $0.speaker == speaker && !$0.isFinal }) {
            transcript[index].text = text
            transcript[index].isFinal = isFinal
        } else {
            transcript.append(TranscriptLine(speaker: speaker, text: text, isFinal: isFinal))
        }
        if transcript.count > 12 {
            transcript.removeFirst(transcript.count - 12)
        }
        suggestionLabel = speaker == .call ? "REPLY NOW" : "NEXT POINT"

        let combined = transcript.map(\.text).joined(separator: " ")
        let languageCode = Locale(identifier: localeIdentifier).language.languageCode?.identifier
        var newlyCovered = Set<UUID>()
        for index in topics.indices
            where !topics[index].isCovered
                && !manuallyUncoveredTopicIDs.contains(topics[index].id)
        {
            if TopicMatcher.isCovered(
                topic: translatedTopicTexts[topics[index].id] ?? topics[index].text,
                by: combined,
                languageCode: languageCode
            ) {
                topics[index].isCovered = true
                newlyCovered.insert(topics[index].id)
            }
        }
        if uncoveredTopics.isEmpty || suggestionTopicID.map(newlyCovered.contains) == true {
            showNextUncoveredFallback()
        }
        if isFinal {
            scheduleAdvice()
        }
    }

    private func scheduleAdvice() {
        guard state == .listening else { return }
        adviceTask?.cancel()
        adviceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            await self?.generateAdvice()
        }
    }

    private func generateAdvice() async {
        let model = SystemLanguageModel.default
        guard model.isAvailable else { return }

        let recentTranscript = transcript.suffix(8)
            .map { "\($0.speaker.rawValue): \($0.text)" }
            .joined(separator: "\n")
        let latestTranscriptLineID = transcript.last?.id
        let latestTranscriptSpeaker = transcript.last?.speaker
        let remainingTopics = uncoveredTopics
        guard !remainingTopics.isEmpty else { return }
        let remaining = remainingTopics.enumerated()
            .map { offset, topic in
                let number = offset + 1
                guard let translated = translatedTopicTexts[topic.id],
                      translated.localizedCaseInsensitiveCompare(topic.text) != .orderedSame
                else { return "\(number). \(topic.text)" }
                return "\(number). \(topic.text)\n   In the conversation language: \(translated)"
            }
            .joined(separator: "\n")
        let priorCues = recentCues.suffix(6).joined(separator: "\n- ")

        let session = LanguageModelSession(instructions: """
        Write only the exact words the user could naturally say next in a live call.
        Write in the language identified by locale \(localeIdentifier), matching the recent conversation.
        The script and conversation may use different languages. Compare their meaning across languages, using any supplied conversation-language version of a point as an aid rather than as a separate point.
        If the latest Call utterance asks a question, makes a request, or raises an objection, respond to it first.
        Use only facts present in the script or transcript. When a fact is missing, ask a short clarifying question.
        Otherwise, move the conversation to the most relevant point the user still needs to discuss.
        Script order expresses priority. Prefer an earlier active point when candidates fit the conversation equally well, but choose a later point when it is clearly more relevant.
        Do not repeat a checklist item verbatim. Use one conversational sentence, no more than 24 words.
        Do not repeat any recent cue. Advance to another uncovered point instead.
        Return target point zero only for a direct reply to the latest Call utterance. Otherwise select one numbered active point.
        A point is covered only when the recent conversation directly states, explains, or answers its core subject. Similar context alone does not count. When uncertain, leave it uncovered. Mark no more than two points per update.
        The target point must remain uncovered and must not also appear in coveredPointNumbers.
        Never use a person's name or an uncommon proper noun from the transcript.
        Never explain why the sentence is useful. Never introduce the sentence. Never mention points, scripts, coaching, or transitions.
        """)
        do {
            let response = try await session.respond(to: """
            Numbered uncovered points:
            \(remaining)

            Recent conversation:
            \(recentTranscript.isEmpty ? "The call has just started." : recentTranscript)

            Recent cues that must not be repeated:
            \(priorCues.isEmpty ? "None." : "- \(priorCues)")
            """, generating: CoachAdvice.self)
            guard !Task.isCancelled else { return }
            var modelCoveredTopicIDs = Set<UUID>()
            for number in Array(Set(response.content.coveredPointNumbers)).prefix(2) {
                guard remainingTopics.indices.contains(number - 1) else { continue }
                let topicID = remainingTopics[number - 1].id
                guard !manuallyUncoveredTopicIDs.contains(topicID),
                      let index = topics.firstIndex(where: { $0.id == topicID })
                else { continue }
                topics[index].isCovered = true
                modelCoveredTopicIDs.insert(topicID)
            }
            if uncoveredTopics.isEmpty || suggestionTopicID.map(modelCoveredTopicIDs.contains) == true {
                showNextUncoveredFallback()
            }

            guard let cue = CueSanitizer.usableCue(from: response.content.wordsToSay),
                  !CueSanitizer.isNearDuplicate(cue, of: recentCues)
            else { return }

            let targetTopicID: UUID?
            if response.content.targetPointNumber == 0 {
                guard latestTranscriptSpeaker == .call,
                      let latestTranscriptLineID,
                      transcript.last?.id == latestTranscriptLineID,
                      lastRepliedCallID != latestTranscriptLineID
                else { return }
                targetTopicID = nil
                lastRepliedCallID = latestTranscriptLineID
            } else {
                let targetIndex = response.content.targetPointNumber - 1
                guard remainingTopics.indices.contains(targetIndex) else { return }
                let candidateID = remainingTopics[targetIndex].id
                guard topics.contains(where: { $0.id == candidateID && !$0.isCovered }) else {
                    return
                }
                guard candidateID != suggestionTopicID || !suggestionIsGenerated else { return }
                targetTopicID = candidateID
            }

            suggestion = cue
            suggestionTopicID = targetTopicID
            suggestionIsGenerated = true
            recentCues.append(cue)
            if recentCues.count > 12 {
                recentCues.removeFirst(recentCues.count - 12)
            }
        } catch {
            intelligenceStatus = "Apple Intelligence paused; topic tracking still works"
        }
    }

    private func showNextUncoveredFallback() {
        if let next = uncoveredTopics.first {
            suggestion = translatedTopicTexts[next.id] ?? next.text
            suggestionTopicID = next.id
        } else {
            suggestion = "All points are covered. Confirm decisions, owners, and timing."
            suggestionTopicID = nil
        }
        suggestionIsGenerated = false
    }

    private func failCapture(message: String) async {
        adviceTask?.cancel()
        adviceTask = nil
        await capture.stop()
        cuePanel.hide()
        transcriptionStatus = "Capture stopped"
        state = .failed(message)
    }

    private func refreshIntelligenceStatus() {
        switch SystemLanguageModel.default.availability {
        case .available:
            intelligenceStatus = "Apple Intelligence ready"
        case let .unavailable(reason):
            switch reason {
            case .appleIntelligenceNotEnabled:
                intelligenceStatus = "Enable Apple Intelligence for contextual coaching"
            case .deviceNotEligible:
                intelligenceStatus = "Topic tracking only on this Mac"
            case .modelNotReady:
                intelligenceStatus = "Apple Intelligence model is not ready"
            @unknown default:
                intelligenceStatus = "Apple Intelligence unavailable"
            }
        }
    }

    private func loadSpeechLocales() async {
        async let speechSupported = SpeechTranscriber.supportedLocales
        async let speechInstalled = SpeechTranscriber.installedLocales
        async let dictationSupported = DictationTranscriber.supportedLocales
        async let dictationInstalled = DictationTranscriber.installedLocales

        let supportedLocales = await speechSupported + dictationSupported
        let installedLocales = await speechInstalled + dictationInstalled
        let options = Self.makeSpeechLocaleOptions(
            from: supportedLocales,
            installedLocales: installedLocales
        )
        speechLocaleOptions = options
        if !options.contains(where: { $0.id == localeIdentifier }) {
            localeIdentifier = Self.defaultSpeechLocaleIdentifier(from: options)
        }
        isLoadingSpeechLocales = false
    }

    private static func makeSpeechLocaleOptions(
        from locales: [Locale],
        installedLocales: [Locale]
    ) -> [SpeechLocaleOption] {
        let installedIdentifiers = Set(installedLocales.map(localeKey))
        var seenIdentifiers = Set<String>()
        return locales
            .filter { seenIdentifiers.insert(localeKey($0)).inserted }
            .map { locale in
                SpeechLocaleOption(
                    id: locale.identifier,
                    name: Locale.current.localizedString(forIdentifier: locale.identifier)
                        ?? locale.identifier,
                    isInstalled: installedIdentifiers.contains(localeKey(locale))
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func localeKey(_ locale: Locale) -> String {
        locale.identifier.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    private static func defaultSpeechLocaleIdentifier(from options: [SpeechLocaleOption]) -> String {
        guard !options.isEmpty else { return "" }
        let preferred = Locale(identifier: Locale.preferredLanguages.first ?? "en-US")
        if let exact = options.first(where: { $0.id == preferred.identifier }) {
            return exact.id
        }
        if let languageMatch = options.first(where: {
            Locale(identifier: $0.id).language.languageCode == preferred.language.languageCode
        }) {
            return languageMatch.id
        }
        return options[0].id
    }
}
