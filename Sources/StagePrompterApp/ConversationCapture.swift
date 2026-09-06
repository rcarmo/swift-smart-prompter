import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit
import Speech
import StagePrompterCore

@MainActor
final class ConversationCapture: NSObject {
    var onTranscript: ((Speaker, String, Bool) -> Void)?
    var onLevel: ((Speaker, Float) -> Void)?
    var onStatus: ((String) -> Void)?
    var onFailure: ((String) -> Void)?

    private var stream: SCStream?
    private var callChannel: SpeechAnalyzerChannel?
    private var microphoneChannel: SpeechAnalyzerChannel?
    private var isStopping = false

    func start(
        localeIdentifier: String,
        contextualStrings _: [String],
        microphoneDeviceID: String?,
        callApplicationBundleIdentifier: String?,
        onlyMe: Bool
    ) async throws {
        guard stream == nil else { return }

        let speechAuthorised = await requestSpeechAuthorization()
        guard speechAuthorised else { throw CaptureError.speechPermissionDenied }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw CaptureError.microphonePermissionDenied
        }

        onStatus?("Preparing on-device transcription…")
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )
        guard let display = content.displays.first else { throw CaptureError.noDisplay }

        let filter: SCContentFilter
        if !onlyMe, let bundleIdentifier = callApplicationBundleIdentifier {
            let applications = content.applications.filter {
                $0.bundleIdentifier == bundleIdentifier
            }
            guard !applications.isEmpty else {
                throw CaptureError.callApplicationUnavailable
            }
            filter = SCContentFilter(
                display: display,
                including: applications,
                exceptingWindows: []
            )
        } else {
            let ownApplication = content.applications.filter {
                $0.processID == ProcessInfo.processInfo.processIdentifier
            }
            filter = SCContentFilter(
                display: display,
                excludingApplications: ownApplication,
                exceptingWindows: []
            )
        }

        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.queueDepth = 1
        configuration.showsCursor = false
        configuration.capturesAudio = !onlyMe
        configuration.captureMicrophone = true
        configuration.microphoneCaptureDeviceID = microphoneDeviceID
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 1

        let locale = Locale(identifier: localeIdentifier)
        let microphoneChannel = SpeechAnalyzerChannel(speaker: .you)
        let callChannel = onlyMe ? nil : SpeechAnalyzerChannel(speaker: .call)
        wire(channel: microphoneChannel)
        if let callChannel {
            wire(channel: callChannel)
        }

        do {
            try await microphoneChannel.start(locale: locale)
            try await callChannel?.start(locale: locale)

            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            if !onlyMe {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .main)
            }
            try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: .main)
            try await stream.startCapture()

            self.callChannel = callChannel
            self.microphoneChannel = microphoneChannel
            self.stream = stream
            onStatus?(onlyMe ? "Transcribing your microphone on this Mac" : "Transcribing both inputs on this Mac")
        } catch {
            await callChannel?.stop()
            await microphoneChannel.stop()
            throw error
        }
    }

    func stop() async {
        guard !isStopping else { return }
        isStopping = true
        defer { isStopping = false }

        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
        await callChannel?.stop()
        await microphoneChannel?.stop()
        callChannel = nil
        microphoneChannel = nil
        onLevel?(.you, 0)
        onLevel?(.call, 0)
    }

    private func wire(channel: SpeechAnalyzerChannel) {
        channel.onTranscript = { [weak self] speaker, text, isFinal in
            self?.onTranscript?(speaker, text, isFinal)
        }
        channel.onStatus = { [weak self] message in
            self?.onStatus?(message)
        }
    }

    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            requestSpeechAuthorization { authorised in
                continuation.resume(returning: authorised)
            }
        }
    }

    nonisolated private func requestSpeechAuthorization(
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        SFSpeechRecognizer.requestAuthorization { status in
            completion(status == .authorized)
        }
    }
}

extension ConversationCapture: SCStreamOutput {
    func stream(
        _: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard sampleBuffer.isValid,
              let buffer = sampleBuffer.audioPCMBuffer
        else { return }

        switch outputType {
        case .audio:
            onLevel?(.call, buffer.normalisedLevel)
            callChannel?.append(buffer)
        case .microphone:
            onLevel?(.you, buffer.normalisedLevel)
            microphoneChannel?.append(buffer)
        default:
            break
        }
    }
}

extension ConversationCapture: SCStreamDelegate {
    nonisolated func stream(_: SCStream, didStopWithError error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            guard let self, !isStopping else { return }
            onFailure?("Audio capture stopped: \(message)")
        }
    }
}

private extension CMSampleBuffer {
    var audioPCMBuffer: AVAudioPCMBuffer? {
        guard let formatDescription = formatDescription,
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(
                formatDescription
              ),
              let format = AVAudioFormat(streamDescription: streamDescription)
        else { return nil }

        let frameCount = AVAudioFrameCount(numSamples)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount

        var requiredSize = 0
        var retainedBlockBuffer: CMBlockBuffer?
        let preflight = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            self,
            bufferListSizeNeededOut: &requiredSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &retainedBlockBuffer
        )
        guard preflight == noErr else { return nil }

        let rawBufferList = UnsafeMutableRawPointer.allocate(
            byteCount: requiredSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBufferList.deallocate() }

        let audioBufferList = rawBufferList.assumingMemoryBound(to: AudioBufferList.self)
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            self,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferList,
            bufferListSize: requiredSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &retainedBlockBuffer
        )
        guard status == noErr else { return nil }

        let sourceBuffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        guard sourceBuffers.count == destinationBuffers.count else { return nil }

        for index in sourceBuffers.indices {
            let source = sourceBuffers[index]
            guard let sourceData = source.mData,
                  let destinationData = destinationBuffers[index].mData
            else { continue }
            let byteCount = min(
                Int(source.mDataByteSize),
                Int(destinationBuffers[index].mDataByteSize)
            )
            destinationData.copyMemory(from: sourceData, byteCount: byteCount)
        }
        return buffer
    }
}

private extension AVAudioPCMBuffer {
    var normalisedLevel: Float {
        guard frameLength > 0 else { return 0 }
        let sampleCount = Int(frameLength)
        var sum: Float = 0

        if let channels = floatChannelData {
            for index in 0..<sampleCount {
                let sample = channels[0][index]
                sum += sample * sample
            }
        } else if let channels = int16ChannelData {
            for index in 0..<sampleCount {
                let sample = Float(channels[0][index]) / Float(Int16.max)
                sum += sample * sample
            }
        } else {
            return 0
        }

        let rms = sqrt(sum / Float(sampleCount))
        return min(max(rms * 4, 0), 1)
    }
}

private enum CaptureError: LocalizedError {
    case callApplicationUnavailable
    case microphonePermissionDenied
    case noDisplay
    case speechPermissionDenied

    var errorDescription: String? {
        switch self {
        case .callApplicationUnavailable:
            "The selected call app is no longer running. Refresh the audio inputs and choose it again."
        case .microphonePermissionDenied:
            "Microphone access is required to transcribe your side of the call."
        case .noDisplay:
            "No display is available for call audio capture."
        case .speechPermissionDenied:
            "Speech Recognition access is required for on-device transcription."
        }
    }
}
