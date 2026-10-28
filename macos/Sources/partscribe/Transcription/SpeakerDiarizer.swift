import FluidAudio
import Foundation

/// One stretch of a track where a single diarized speaker talks, relative to
/// the track's own start.
struct SpeakerTurn: Sendable, Equatable {
    let start: TimeInterval
    let end: TimeInterval
    let speaker: String
}

/// Tells speakers apart within one track, using FluidAudio's offline pipeline
/// (pyannote segmentation, WeSpeaker embeddings, VBx clustering). Runs on the
/// whole file after recording, so it sees every voice before deciding how
/// many there are. Like the engines, it is prepared when the queue has work
/// and released when it drains.
actor SpeakerDiarizer {
    private var manager: OfflineDiarizerManager?

    func prepare() async throws {
        guard manager == nil else { return }
        let manager = OfflineDiarizerManager()
        try await manager.prepareModels()
        self.manager = manager
    }

    func turns(in audio: URL) async throws -> [SpeakerTurn] {
        // OfflineDiarizerManager is a plain non-Sendable class. This actor is
        // its only owner and the coordinator diarizes one file at a time, so
        // it never runs concurrently with itself.
        guard let owned = manager else { return [] }
        nonisolated(unsafe) let manager = owned
        let result = try await manager.process(audio)
        return result.segments.map {
            SpeakerTurn(
                start: TimeInterval($0.startTimeSeconds),
                end: TimeInterval($0.endTimeSeconds),
                speaker: $0.speakerId
            )
        }
    }

    func release() {
        manager = nil
    }
}
