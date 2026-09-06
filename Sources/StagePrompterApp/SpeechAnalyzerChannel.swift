@preconcurrency import AVFAudio
import Foundation
import Speech
import StagePrompterCore

@MainActor
final class SpeechAnalyzerChannel {
    var onTranscript: ((Speaker, String, Bool) -> Void)?
    var onStatus: ((String) -> Void)?

    private let speaker: Speaker
    private var analyzer: SpeechAnalyzer?
    private var speechTranscriber: SpeechTranscriber?
    private var dictationTranscriber: DictationTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzerFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?
    private var resultTask: Task<Void, Never>?

    init(speaker: Speaker) {
        self.speaker = speaker
    }

    func start(locale: Locale) async throws {
        if let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            let transcriber = SpeechTranscriber(
                locale: supportedLocale,
                preset: .progressiveTranscription
            )
            speechTranscriber = transcriber
            resultTask = speechResultTask(for: transcriber)
            try await prepare(module: transcriber, locale: supportedLocale)
        } else if let supportedLocale = await DictationTranscriber.supportedLocale(
            equivalentTo: locale
        ) {
            let transcriber = DictationTranscriber(
                locale: supportedLocale,
                preset: .progressiveLongDictation
            )
            dictationTranscriber = transcriber
            resultTask = dictationResultTask(for: transcriber)
            try await prepare(module: transcriber, locale: supportedLocale)
        } else {
            throw SpeechChannelError.unsupportedLocale(locale.identifier)
        }

    }

    private func prepare(module: any SpeechModule, locale: Locale) async throws {
        try await ensureAssets(for: module, locale: locale)

        let analyzer = SpeechAnalyzer(modules: [module])
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [module]
        ) else {
            throw SpeechChannelError.noCompatibleAudioFormat
        }

        let (inputSequence, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.analyzer = analyzer
        self.analyzerFormat = analyzerFormat
        inputContinuation = continuation

        try await analyzer.start(inputSequence: inputSequence)
    }

    private func ensureAssets(for module: any SpeechModule, locale: Locale) async throws {
        let status = await AssetInventory.status(forModules: [module])
        switch status {
        case .installed:
            return
        case .supported, .downloading:
            let localeName = Locale.current.localizedString(forIdentifier: locale.identifier)
                ?? locale.identifier
            onStatus?("Downloading \(localeName) transcription…")
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                try await request.downloadAndInstall()
            }
            _ = try? await AssetInventory.reserve(locale: locale)
        case .unsupported:
            throw SpeechChannelError.unsupportedLocale(locale.identifier)
        @unknown default:
            throw SpeechChannelError.unsupportedLocale(locale.identifier)
        }
    }

    private func speechResultTask(for transcriber: SpeechTranscriber) -> Task<Void, Never> {
        Task { [weak self, transcriber] in
            do {
                for try await result in transcriber.results {
                    guard let self else { return }
                    let text = String(result.text.characters)
                    if !text.isEmpty {
                        onTranscript?(speaker, text, result.isFinal)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.onStatus?("\(self?.speaker.rawValue ?? "Speech") transcription: \(error.localizedDescription)")
            }
        }
    }

    private func dictationResultTask(for transcriber: DictationTranscriber) -> Task<Void, Never> {
        Task { [weak self, transcriber] in
            do {
                for try await result in transcriber.results {
                    guard let self else { return }
                    let text = String(result.text.characters)
                    if !text.isEmpty {
                        onTranscript?(speaker, text, result.isFinal)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.onStatus?("\(self?.speaker.rawValue ?? "Speech") transcription: \(error.localizedDescription)")
            }
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let analyzerFormat else { return }
        do {
            let converted = try convert(buffer, to: analyzerFormat)
            inputContinuation?.yield(AnalyzerInput(buffer: converted))
        } catch {
            onStatus?("\(speaker.rawValue) audio conversion: \(error.localizedDescription)")
        }
    }

    func stop() async {
        inputContinuation?.finish()
        inputContinuation = nil
        if let analyzer {
            await analyzer.cancelAndFinishNow()
        }
        resultTask?.cancel()
        resultTask = nil
        self.analyzer = nil
        speechTranscriber = nil
        dictationTranscriber = nil
        analyzerFormat = nil
        converter = nil
        converterInputFormat = nil
    }

    private func convert(
        _ input: AVAudioPCMBuffer,
        to outputFormat: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        if input.format == outputFormat { return input }

        if converter == nil || converterInputFormat != input.format {
            converter = AVAudioConverter(from: input.format, to: outputFormat)
            converterInputFormat = input.format
        }
        guard let converter else { throw SpeechChannelError.couldNotCreateConverter }

        let rateRatio = outputFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * rateRatio)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw SpeechChannelError.couldNotCreateOutputBuffer
        }

        let provider = ConverterInputProvider(buffer: input)
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if provider.wasSupplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            provider.wasSupplied = true
            inputStatus.pointee = .haveData
            return provider.buffer
        }
        if let conversionError { throw conversionError }
        guard status != .error else { throw SpeechChannelError.conversionFailed }
        return output
    }
}

private nonisolated final class ConverterInputProvider: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    var wasSupplied = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}

private enum SpeechChannelError: LocalizedError {
    case conversionFailed
    case couldNotCreateConverter
    case couldNotCreateOutputBuffer
    case noCompatibleAudioFormat
    case unsupportedLocale(String)

    var errorDescription: String? {
        switch self {
        case .conversionFailed: "Speech audio conversion failed."
        case .couldNotCreateConverter: "Could not create a speech audio converter."
        case .couldNotCreateOutputBuffer: "Could not allocate a speech audio buffer."
        case .noCompatibleAudioFormat: "The installed speech model has no compatible audio format."
        case let .unsupportedLocale(identifier): "Speech transcription is not supported for \(identifier)."
        }
    }
}
