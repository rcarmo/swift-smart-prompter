import AppKit
import StagePrompterCore
import SwiftUI

struct PrompterView: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.09, blue: 0.12), Color(red: 0.12, green: 0.10, blue: 0.17)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().overlay(.white.opacity(0.12))
                if model.isListening {
                    liveView
                } else {
                    setupView
                }
            }
        }
        .preferredColorScheme(.dark)
        .background(WindowConfigurationView())
        .alert("Smart Prompter", isPresented: failureBinding) {
            Button("OK") { model.resetAfterFailure() }
        } message: {
            if case let .failed(message) = model.state { Text(message) }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: model.isListening ? "waveform.circle.fill" : "text.bubble.fill")
                .font(.title2)
                .foregroundStyle(model.isListening ? .mint : .purple)
            Text(model.statusText)
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
            if model.isListening {
                Button {
                    model.showCuePanel()
                } label: {
                    Label("Show Cue", systemImage: "rectangle.on.rectangle")
                }
                .buttonStyle(.bordered)
                Button {
                    Task { await model.stop() }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding(14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }

    private var setupView: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("TALKING POINTS")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextEditor(text: $model.script)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.white.opacity(0.12))
                    }
                    .accessibilityLabel("Talking points, one per line")
            }

            HStack {
                Text("Speech language")
                    .foregroundStyle(.secondary)
                Spacer()
                if model.isLoadingSpeechLocales {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Loading installed speech languages")
                } else if model.speechLocaleOptions.isEmpty {
                    Text("No supported languages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Menu {
                        Section("Downloaded") {
                            ForEach(model.installedSpeechLocaleOptions) { locale in
                                languageButton(locale)
                            }
                        }

                        if !model.downloadableSpeechLocaleOptions.isEmpty {
                            Divider()
                            Menu {
                                ForEach(model.downloadableSpeechLocaleOptions) { locale in
                                    Button {
                                        model.selectSpeechLocale(locale.id)
                                    } label: {
                                        Label(locale.name, systemImage: "arrow.down.circle")
                                    }
                                }
                            } label: {
                                Label("Get More Languages…", systemImage: "globe.badge.chevron.backward")
                            }
                        }
                    } label: {
                        Label(
                            model.selectedSpeechLocaleOption?.name ?? model.localeIdentifier,
                            systemImage: model.selectedSpeechLocaleOption?.isInstalled == true
                                ? "globe"
                                : "arrow.down.circle"
                        )
                    }
                    .menuStyle(.button)
                    .frame(maxWidth: 210, alignment: .trailing)
                    .accessibilityLabel("Speech language")
                }
            }

            if model.selectedSpeechLocaleOption?.isInstalled == false {
                Text("This language downloads when listening starts.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("AUDIO INPUTS")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        model.refreshAudioSources()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help("Refresh microphones and running applications")
                    .accessibilityLabel("Refresh audio inputs")
                }

                audioSourcePicker(
                    title: "Microphone",
                    selection: $model.selectedMicrophoneID,
                    options: model.microphoneOptions
                )
                Toggle(isOn: $model.onlyMe) {
                    Label("Only me", systemImage: "person.wave.2")
                }
                .toggleStyle(.switch)
                .help("Transcribe only your microphone using one speech analyzer")

                if model.onlyMe {
                    Text("Uses one transcriber and does not analyse call audio.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    audioSourcePicker(
                        title: "Call audio",
                        selection: $model.selectedCallAudioID,
                        options: model.callAudioOptions
                    )
                    Text("Choose a running call app to exclude other system sounds.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Label(model.intelligenceStatus, systemImage: "apple.intelligence")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                Task { await model.start() }
            } label: {
                Label("Start listening", systemImage: "waveform.badge.mic")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .disabled(model.state == .starting || model.isLoadingSpeechLocales || model.speechLocaleOptions.isEmpty)
        }
        .padding(16)
    }

    private var liveView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 8) {
                    inputMeter(title: "You", source: model.selectedMicrophoneName, level: model.microphoneLevel, colour: .mint)
                    if !model.onlyMe {
                        inputMeter(title: "Call", source: model.selectedCallAudioName, level: model.callLevel, colour: .purple)
                    }
                    Text(model.transcriptionStatus)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))

                topicList

                DisclosureGroup("Recent transcript", isExpanded: $model.showTranscript) {
                    transcriptScroller
                }
                .font(.caption)

                Text(model.onlyMe
                    ? "Only your microphone is being transcribed. Audio and transcript stay on this Mac."
                    : "Microphone is labelled You; system call audio is labelled Call. Audio and transcript stay on this Mac.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
        }
    }

    private func audioSourcePicker(
        title: String,
        selection: Binding<String>,
        options: [AudioSourceOption]
    ) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Picker(title, selection: selection) {
                ForEach(options) { option in
                    Text(option.name).tag(option.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 220, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func languageButton(_ locale: SpeechLocaleOption) -> some View {
        Button {
            model.selectSpeechLocale(locale.id)
        } label: {
            if locale.id == model.localeIdentifier {
                Label(locale.name, systemImage: "checkmark")
            } else {
                Text(locale.name)
            }
        }
    }

    private func inputMeter(
        title: String,
        source: String,
        level: Float,
        colour: Color
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .frame(width: 28, alignment: .trailing)
            ProgressView(value: Double(level), total: 1)
                .progressViewStyle(.linear)
                .tint(colour)
            Text(source)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 100, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) audio from \(source)")
        .accessibilityValue("\(Int(level * 100)) percent")
    }

    private var topicList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SCRIPT")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(model.topics.filter(\.isCovered).count)/\(model.topics.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ForEach(model.topics) { topic in
                Button {
                    model.toggleCovered(id: topic.id)
                } label: {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: topic.isCovered ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(topic.isCovered ? .mint : .secondary)
                        Text(topic.text)
                            .strikethrough(topic.isCovered)
                            .foregroundStyle(topic.isCovered ? .secondary : .primary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(topic.text), \(topic.isCovered ? "covered" : "not covered")")
            }
        }
    }

    private var transcriptView: some View {
        VStack(alignment: .leading, spacing: 7) {
            if model.transcript.isEmpty {
                Text("Waiting for speech…")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.transcript.suffix(6)) { line in
                    HStack(alignment: .top, spacing: 8) {
                        Text(line.speaker.rawValue)
                            .fontWeight(.semibold)
                            .foregroundStyle(line.speaker == .you ? .mint : .purple)
                            .frame(width: 34, alignment: .trailing)
                        Text(line.text)
                            .foregroundStyle(line.isFinal ? .primary : .secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var transcriptScroller: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                transcriptView
                Color.clear
                    .frame(height: 1)
                    .id("transcript-end")
            }
            .frame(minHeight: 64, idealHeight: 120, maxHeight: 160)
            .accessibilityLabel("Recent transcript entries")
            .onChange(of: model.transcript) { _, _ in
                scrollTranscriptToEnd(using: proxy)
            }
            .onChange(of: model.showTranscript) { _, isExpanded in
                if isExpanded {
                    scrollTranscriptToEnd(using: proxy)
                }
            }
        }
    }

    private func scrollTranscriptToEnd(using proxy: ScrollViewProxy) {
        Task { @MainActor in
            await Task.yield()
            proxy.scrollTo("transcript-end", anchor: .bottom)
        }
    }

    private var failureBinding: Binding<Bool> {
        Binding(
            get: {
                if case .failed = model.state { return true }
                return false
            },
            set: { isPresented in
                if !isPresented { model.resetAfterFailure() }
            }
        )
    }
}

private struct WindowConfigurationView: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        ConfiguringView()
    }

    func updateNSView(_: NSView, context _: Context) {}

    private final class ConfiguringView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
            window?.setFrameAutosaveName("StagePrompterWindow")
            window?.isMovableByWindowBackground = true
        }
    }
}
