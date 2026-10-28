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
            wordTimestamps: true  // lets speaker separation split mid-segment
        )

        // Our own short pieces instead of long-form decoding or WhisperKit's
        // VAD chunker — both dropped whole windows of real meeting speech
        // without an error. See SpeechChunks.
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: audio.path)
        let floor = SpeechChunks.noiseFloor(samples)
        var segments: [TranscriptSegment] = []
        for range in SpeechChunks.split(samples) {
            segments += try await decode(samples, range, floor: floor, pipe: pipe, options: options)
        }
        return segments
    }

    /// Transcribe one piece. Whisper sometimes ends a window early — before
    /// writing anything, or halfway — more often the longer the piece. An
    /// empty answer is retried as two halves, and four seconds or more left
    /// untouched at either end is retried on its own, until what remains is
    /// too short to hold speech.
    private func decode(
        _ samples: [Float], _ range: Range<Int>, floor: Float, pipe: WhisperKit, options: DecodingOptions
    ) async throws -> [TranscriptSegment] {
        let offset = TimeInterval(range.lowerBound) / TimeInterval(SpeechChunks.sampleRate)
        let results = try await pipe.transcribe(
            audioArray: SpeechChunks.leveled(samples[range], noiseFloor: floor), decodeOptions: options)
        let segments = results.flatMap(\.segments).compactMap { seg -> TranscriptSegment? in
            let text = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let words = (seg.words ?? []).compactMap { w -> TimedWord? in
                let word = w.word.trimmingCharacters(in: .whitespaces)
                guard !word.isEmpty else { return nil }
                return TimedWord(
                    start: offset + TimeInterval(w.start),
                    end: offset + TimeInterval(w.end),
                    text: word
                )
            }
            return TranscriptSegment(
                start: offset + TimeInterval(seg.start),
                end: offset + TimeInterval(seg.end),
                text: text,
                words: words
            )
        }
        let minimum = 4 * SpeechChunks.sampleRate
        guard let first = segments.first, let last = segments.last else {
            guard range.count >= 2 * minimum else { return [] }
            let middle = range.lowerBound + range.count / 2
            return try await decode(samples, range.lowerBound..<middle, floor: floor, pipe: pipe, options: options)
                + decode(samples, middle..<range.upperBound, floor: floor, pipe: pipe, options: options)
        }
        func sample(_ time: TimeInterval) -> Int {
            min(max(Int(time * TimeInterval(SpeechChunks.sampleRate)), range.lowerBound), range.upperBound)
        }
        var head: [TranscriptSegment] = []
        var tail: [TranscriptSegment] = []
        let spokenFrom = sample(first.words.first?.start ?? first.start)
        let spokenTo = sample(last.words.last?.end ?? last.end)
        if spokenFrom - range.lowerBound >= minimum {
            head = try await decode(samples, range.lowerBound..<spokenFrom, floor: floor, pipe: pipe, options: options)
        }
        if range.upperBound - spokenTo >= minimum {
            tail = try await decode(samples, spokenTo..<range.upperBound, floor: floor, pipe: pipe, options: options)
        }
        return head + segments + tail
    }

    func release() async {
        await pipe?.unloadModels()
        pipe = nil
    }
}
