import Foundation

public struct PromptTopic: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public var isCovered: Bool

    public init(id: UUID = UUID(), text: String, isCovered: Bool = false) {
        self.id = id
        self.text = text
        self.isCovered = isCovered
    }

    public static func parse(script: String) -> [PromptTopic] {
        script
            .split(whereSeparator: \.isNewline)
            .map { line in
                line.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: #"^[-*\d.)\s]+"#, with: "", options: .regularExpression)
            }
            .filter { !$0.isEmpty }
            .map { PromptTopic(text: $0) }
    }
}
