import Foundation

public enum Speaker: String, Sendable {
    case you = "You"
    case call = "Call"
}

public struct TranscriptLine: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let speaker: Speaker
    public var text: String
    public var isFinal: Bool

    public init(id: UUID = UUID(), speaker: Speaker, text: String, isFinal: Bool) {
        self.id = id
        self.speaker = speaker
        self.text = text
        self.isFinal = isFinal
    }
}
