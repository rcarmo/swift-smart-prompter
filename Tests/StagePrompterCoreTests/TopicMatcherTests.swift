import Testing
@testable import StagePrompterCore

@Suite("Topic matching")
struct TopicMatcherTests {
    @Test("Script parsing removes common list markers")
    func parsesScript() {
        let topics = PromptTopic.parse(script: "- Pricing model\n2. Delivery schedule\n\n* Next steps")
        #expect(topics.map(\.text) == ["Pricing model", "Delivery schedule", "Next steps"])
    }

    @Test("A topic is covered when most significant words appear")
    func recognisesCoveredTopic() {
        #expect(TopicMatcher.isCovered(
            topic: "Customer migration timeline",
            by: "Let us discuss the timeline for the customer migration."
        ))
    }

    @Test("Unrelated conversation does not cover a topic")
    func rejectsUnrelatedTranscript() {
        #expect(!TopicMatcher.isCovered(
            topic: "Security review and data retention",
            by: "The delivery date should be early next week."
        ))
    }

    @Test("The matcher does not depend on the sample script's vocabulary")
    func recognisesArbitraryTopic() {
        #expect(TopicMatcher.isCovered(
            topic: "Review observability dashboards",
            by: "Next, we reviewed all of the observability dashboards."
        ))
    }

    @Test("Portuguese inflections cover a Portuguese point")
    func recognisesPortugueseTopic() {
        #expect(TopicMatcher.isCovered(
            topic: "Discutir prazos e responsabilidades",
            by: "Qual é o prazo e quem será responsável pela entrega?",
            languageCode: "pt"
        ))
    }

    @Test("French inflections cover a French point")
    func recognisesFrenchTopic() {
        #expect(TopicMatcher.isCovered(
            topic: "Discuter délais et responsabilités",
            by: "Quel est le délai et qui sera responsable de la livraison ?",
            languageCode: "fr"
        ))
    }

    @Test("A later point requires verbatim, topic-related evidence")
    func validatesOrderOverrideEvidence() {
        let transcript = "Before we finish, can we agree on the delivery window?"
        #expect(TopicSelectionPolicy.allowsOrderOverride(
            topic: "Agree delivery window and dependencies",
            evidence: "delivery window",
            recentTranscript: transcript
        ))
        #expect(!TopicSelectionPolicy.allowsOrderOverride(
            topic: "Agree delivery window and dependencies",
            evidence: "budget approval",
            recentTranscript: transcript
        ))
        #expect(!TopicSelectionPolicy.allowsOrderOverride(
            topic: "Review security requirements",
            evidence: "delivery window",
            recentTranscript: transcript
        ))
    }

    @Test("A spoken cue is accepted without changing it")
    func acceptsSpokenCue() {
        #expect(CueSanitizer.usableCue(from: "What timing would work best for your team?") == "What timing would work best for your team?")
    }

    @Test("A lightly reworded cue is treated as a repeat")
    func detectsRepeatedCue() {
        #expect(CueSanitizer.isNearDuplicate(
            "Could you describe the current constraints for your team?",
            of: ["Could you describe your team's current constraints?"]
        ))
    }

    @Test("Model commentary is never shown as a cue")
    func rejectsModelCommentary() {
        #expect(CueSanitizer.usableCue(
            from: "Sure, here's a natural bridge to the most relevant uncovered point: What timing works?"
        ) == nil)
    }
}
