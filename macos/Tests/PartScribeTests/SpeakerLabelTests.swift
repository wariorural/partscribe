import XCTest

@testable import partscribe

final class SpeakerLabelTests: XCTestCase {
    private func seg(_ start: TimeInterval, _ end: TimeInterval, _ text: String) -> TranscriptSegment {
        TranscriptSegment(start: start, end: end, text: text)
    }

    private func labels(_ groups: [(speaker: String, segments: [TranscriptSegment])]) -> [String: [String]] {
        Dictionary(uniqueKeysWithValues: groups.map { ($0.speaker, $0.segments.map(\.text)) })
    }

    func testNoTurnsKeepsPlainLabel() {
        let groups = Transcript.bySpeaker([seg(0, 2, "a"), seg(2, 4, "b")], turns: [], base: "them")
        XCTAssertEqual(labels(groups), ["them": ["a", "b"]])
    }

    func testSingleSpeakerKeepsPlainLabel() {
        let turns = [SpeakerTurn(start: 0, end: 10, speaker: "S7")]
        let groups = Transcript.bySpeaker([seg(0, 2, "a"), seg(3, 5, "b")], turns: turns, base: "me")
        XCTAssertEqual(labels(groups), ["me": ["a", "b"]])
    }

    func testSpeakersNumberedByFirstAppearance() {
        // Diarizer ids are arbitrary; numbering follows who speaks first.
        let turns = [
            SpeakerTurn(start: 0, end: 3, speaker: "S2"),
            SpeakerTurn(start: 3, end: 6, speaker: "S0"),
            SpeakerTurn(start: 6, end: 9, speaker: "S2"),
        ]
        let groups = Transcript.bySpeaker(
            [seg(0, 3, "hei"), seg(3, 6, "hallo"), seg(6, 9, "ja")], turns: turns, base: "them")
        XCTAssertEqual(groups.map(\.speaker), ["them 1", "them 2"])
        XCTAssertEqual(labels(groups), ["them 1": ["hei", "ja"], "them 2": ["hallo"]])
    }

    func testSegmentGoesToLargestOverlap() {
        let turns = [
            SpeakerTurn(start: 0, end: 4, speaker: "A"),
            SpeakerTurn(start: 4, end: 10, speaker: "B"),
        ]
        // 1 s with A, 3 s with B.
        let groups = Transcript.bySpeaker([seg(0, 1, "x"), seg(3, 7, "y")], turns: turns, base: "them")
        XCTAssertEqual(labels(groups), ["them 1": ["x"], "them 2": ["y"]])
    }

    func testSegmentSplitsWhereSpeakerChangesMidSentence() {
        let turns = [
            SpeakerTurn(start: 0, end: 2, speaker: "A"),
            SpeakerTurn(start: 2.2, end: 5, speaker: "B"),
        ]
        var merged = seg(0, 5, "Takk for i dag. Takk selv.")
        merged.words = [
            TimedWord(start: 0, end: 0.5, text: "Takk"),
            TimedWord(start: 0.5, end: 0.8, text: "for"),
            TimedWord(start: 0.8, end: 1.0, text: "i"),
            TimedWord(start: 1.0, end: 1.8, text: "dag."),
            TimedWord(start: 2.3, end: 2.8, text: "Takk"),
            TimedWord(start: 2.8, end: 3.4, text: "selv."),
        ]
        let groups = Transcript.bySpeaker([merged], turns: turns, base: "them")
        XCTAssertEqual(labels(groups), ["them 1": ["Takk for i dag."], "them 2": ["Takk selv."]])
        XCTAssertEqual(groups[1].segments.first?.start, 2.3)
    }

    func testSegmentInGapGoesToNearestTurn() {
        let turns = [
            SpeakerTurn(start: 0, end: 2, speaker: "A"),
            SpeakerTurn(start: 10, end: 12, speaker: "B"),
        ]
        let groups = Transcript.bySpeaker(
            [seg(0, 2, "a"), seg(8, 9, "nær B"), seg(10, 12, "b")], turns: turns, base: "them")
        XCTAssertEqual(labels(groups), ["them 1": ["a"], "them 2": ["nær B", "b"]])
    }
}
