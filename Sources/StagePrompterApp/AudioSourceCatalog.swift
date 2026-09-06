import AppKit
import AVFoundation

struct AudioSourceOption: Identifiable, Hashable {
    let id: String
    let name: String
}

@MainActor
enum AudioSourceCatalog {
    static let systemDefaultMicrophoneID = "system-default"
    static let allSystemAudioID = "all-system-audio"

    static func microphones() -> [AudioSourceOption] {
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        ).devices
        let deviceOptions = devices
            .map { AudioSourceOption(id: $0.uniqueID, name: $0.localizedName) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return [AudioSourceOption(id: systemDefaultMicrophoneID, name: "System Default")] + deviceOptions
    }

    static func callApplications() -> [AudioSourceOption] {
        var seenBundleIdentifiers = Set<String>()
        let applications = NSWorkspace.shared.runningApplications.compactMap { application -> AudioSourceOption? in
            guard application.activationPolicy == .regular,
                  application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  let bundleIdentifier = application.bundleIdentifier,
                  let name = application.localizedName,
                  seenBundleIdentifiers.insert(bundleIdentifier).inserted
            else { return nil }
            return AudioSourceOption(id: bundleIdentifier, name: name)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        return [AudioSourceOption(id: allSystemAudioID, name: "All System Audio")] + applications
    }
}
