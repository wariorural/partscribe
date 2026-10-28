import XCTest

@testable import partscribe

final class SpeechChunksTests: XCTestCase {
    private let rate = SpeechChunks.sampleRate

    /// `seconds` of a steady tone at `level`, with silent stretches where given.
    private func audio(seconds: Int, level: Float = 0.1, silences: [ClosedRange<Double>] = []) -> [Float] {
        (0..<(seconds * rate)).map { i in
            let t = Double(i) / Double(rate)
            if silences.contains(where: { $0.contains(t) }) { return 0 }
            return level * sin(Float(i) * 0.05)
        }
    }

    func testShortAudioIsOnePiece() {
        let ranges = SpeechChunks.split(audio(seconds: 10))
        XCTAssertEqual(ranges, [0..<(10 * rate)])
    }

    func testPiecesCoverEverythingWithinBounds() {
        let samples = audio(seconds: 95)
        let ranges = SpeechChunks.split(samples)
        XCTAssertEqual(ranges.first?.lowerBound, 0)
        XCTAssertEqual(ranges.last?.upperBound, samples.count)
        for (a, b) in zip(ranges, ranges.dropFirst()) {
            XCTAssertEqual(a.upperBound, b.lowerBound)
        }
        for range in ranges.dropLast() {
            XCTAssertTrue((8 * rate)...(12 * rate) ~= range.count)
        }
    }

    func testCutsAtTheQuietMoment() {
        let ranges = SpeechChunks.split(audio(seconds: 30, silences: [10.0...10.3]))
        let cut = Double(ranges[0].upperBound) / Double(rate)
        XCTAssertTrue((10.0...10.3).contains(cut), "cut at \(cut)")
    }

    func testQuietSpeechIsLiftedAndLoudIsLeftAlone() {
        // A quiet voice talking throughout, in a room whose floor is lower.
        let quiet = audio(seconds: 2, level: 0.005)
        let lifted = SpeechChunks.leveled(quiet[...], noiseFloor: 0.0005)
        XCTAssertTrue(lifted.map(abs).max()! > quiet.map(abs).max()! * 10)

        let loud = audio(seconds: 2, level: 0.3)
        XCTAssertEqual(SpeechChunks.leveled(loud[...], noiseFloor: 0.0005), loud)
    }

    func testRoomNoiseIsBarelyLifted() {
        let noise = audio(seconds: 2, level: 0.001)
        let leveled = SpeechChunks.leveled(noise[...], noiseFloor: 0.001)
        XCTAssertTrue(leveled.map(abs).max()! <= noise.map(abs).max()! * 4.01)
    }

    func testLevelledAudioNeverClips() {
        let leveled = SpeechChunks.leveled(audio(seconds: 2, level: 0.9)[...], noiseFloor: 0.0005)
        XCTAssertTrue(leveled.map(abs).max()! <= 1)
    }
}
