import AVFoundation
import Foundation
import WhisperKit

/// NB-Whisper (Nasjonalbiblioteket) via WhisperKit's Core ML runtime.
/// Norwegian-first: forces the "no" language token and writes bokmål.
/// Models download once from Hugging Face into WhisperKit's cache.
///
/// Verified against WhisperKit 1.1.1. Output has no `<|…|>` tokens with
/// skipSpecialTokens, so no extra filtering is applied.
actor NBWhisperEngine: TranscriptionEngine {
    enum EngineError: Error, CustomStringConvertible {
        case notPrepared
        case unreadableAudio(URL, Error?)

        var description: String {
            switch self {
            case .notPrepared: return "nb-whisper engine used before prepare()"
            case .unreadableAudio(let url, let e):
                return "unreadable or empty audio \(url.lastPathComponent)"
                    + (e.map { ": \($0)" } ?? "")
            }
        }
    }

    nonisolated let name = "nb-whisper"
    nonisolated let model: String
    private let repo: String
    private let language: String

    private var pipe: WhisperKit?

    /// Defaults to the community Core ML conversion of nb-whisper-small.
    /// Swap `repo`/`variant` for your own conversion (e.g. nb-whisper-medium
    /// or -large converted with argmax's whisperkittools) once you have one.
    init(
        repo: String = "Barrymanalow/nb-whisper-coreml",
        variant: String = "nb-whisper-small",
        language: String = "no"
    ) {
        self.repo = repo
        self.model = variant
        self.language = language
    }

    func prepare() async throws {
        guard pipe == nil else { return }
        let config = WhisperKitConfig(model: model, modelRepo: repo)
        pipe = try await WhisperKit(config)
    }

    func transcribe(_ audio: URL) async throws -> [TranscriptSegment] {
        guard let pipe else { throw EngineError.notPrepared }

        // Same guard as ParakeetEngine: an empty CAF crashes AVFoundation
        // with an uncatchable ObjC exception, so probe first.
        do {
            let probe = try AVAudioFile(forReading: audio)
            guard probe.length > 0 else { throw EngineError.unreadableAudio(audio, nil) }
        } catch let error as EngineError {
            throw error
        } catch {
            throw EngineError.unreadableAudio(audio, error)
        }

        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            usePrefillPrompt: true,  // force the language token, skip detection
            skipSpecialTokens: true,
            withoutTimestamps: false,
            wordTimestamps: true,  // lets speaker separation split mid-segment
            chunkingStrategy: .vad  // long meetings: split on silence, not blind 30 s
        )
        let results = try await pipe.transcribe(audioPath: audio.path, decodeOptions: options)

        return results
            .flatMap(\.segments)
            .compactMap { seg in
                let text = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                let words = (seg.words ?? []).compactMap { w -> TimedWord? in
                    let word = w.word.trimmingCharacters(in: .whitespaces)
                    guard !word.isEmpty else { return nil }
                    return TimedWord(start: TimeInterval(w.start), end: TimeInterval(w.end), text: word)
                }
                return TranscriptSegment(
                    start: TimeInterval(seg.start),
                    end: TimeInterval(seg.end),
                    text: text,
                    words: words
                )
            }
    }

    func release() async {
        await pipe?.unloadModels()
        pipe = nil
    }
}
