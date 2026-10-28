import Foundation

/// Prepares a track for Whisper. Two failure modes seen on real meeting
/// audio, both silent: long-form decoding (and WhisperKit's VAD chunker)
/// sometimes ends a 30-second window without writing anything, and quiet
/// voices — someone sitting away from the laptop — come out as nothing at
/// all. Short pieces cut at the quietest moment each fit one decoding window,
/// and levelling each piece lifts quiet voices to speaking volume. Only the
/// copy sent to the model is changed; the recording stays as it was.
enum SpeechChunks {
    static let sampleRate = 16_000

    /// Cut points for pieces between `minLength` and `maxLength` seconds,
    /// each ending at the quietest 100 ms in its allowed window. Short pieces
    /// on purpose: on a real meeting, 8–12 s pieces kept nearly everything
    /// while 15–29 s pieces lost up to half the windows.
    static func split(
        _ samples: [Float], minLength: Double = 8, maxLength: Double = 12
    ) -> [Range<Int>] {
        let frame = sampleRate / 10
        let minFrames = Int(minLength * 10)
        let maxFrames = Int(maxLength * 10)
        let energy = frameLevels(samples[...])

        var ranges: [Range<Int>] = []
        var first = 0  // in frames
        while energy.count - first > maxFrames {
            let window = (first + minFrames)..<(first + maxFrames)
            let cut = window.min { energy[$0] < energy[$1] }!
            ranges.append((first * frame)..<(cut * frame))
            first = cut
        }
        if first * frame < samples.count {
            ranges.append((first * frame)..<samples.count)
        }
        return ranges
    }

    /// The room's background level for a whole track: the quiet end of its
    /// 100 ms frame levels, ignoring digital silence (capture gaps). Measured
    /// once per track, so a piece where one quiet voice talks throughout
    /// isn't mistaken for noise.
    static func noiseFloor(_ samples: [Float]) -> Float {
        let levels = frameLevels(samples[...]).filter { $0 > 1e-5 }.sorted()
        guard !levels.isEmpty else { return 1e-4 }
        return levels[levels.count / 5]
    }

    /// Automatic gain: follow the loudness in 100 ms frames and scale each
    /// toward `target`, never attenuating and never boosting more than
    /// `maxGain`. Frames near the noise floor are capped at a lower gain so
    /// room noise isn't pumped up into something the model hears as words.
    /// Gain falls fast (a loud voice starting) and rises slowly (it
    /// stopping), and a soft limiter keeps peaks from clipping.
    static func leveled(
        _ samples: ArraySlice<Float>, noiseFloor floor: Float,
        target: Float = 0.08, maxGain: Float = 20, silenceGain: Float = 4
    ) -> [Float] {
        let frame = sampleRate / 10
        let levels = frameLevels(samples)
        guard !levels.isEmpty else { return [] }

        func wanted(_ level: Float) -> Float {
            let cap = level < floor * 2 ? silenceGain : maxGain
            return min(cap, max(1, target / max(level, 1e-5)))
        }
        var gains: [Float] = []
        var current = wanted(levels[0])
        for level in levels {
            let next = wanted(level)
            current = next < current ? next : current + (next - current) * 0.15
            gains.append(current)
        }

        var out = [Float](repeating: 0, count: samples.count)
        for (i, sample) in samples.enumerated() {
            let y = sample * gains[i / frame]
            // Linear below 0.5, then bends smoothly toward ±1.
            out[i] = abs(y) < 0.5 ? y : (y > 0 ? 1 : -1) * (0.5 + 0.5 * tanh((abs(y) - 0.5) / 0.5))
        }
        return out
    }

    private static func frameLevels(_ samples: ArraySlice<Float>) -> [Float] {
        let frame = sampleRate / 10
        return stride(from: samples.startIndex, to: samples.endIndex, by: frame).map {
            rms(samples[$0..<min($0 + frame, samples.endIndex)])
        }
    }

    private static func rms(_ slice: ArraySlice<Float>) -> Float {
        guard !slice.isEmpty else { return 0 }
        return (slice.reduce(0) { $0 + $1 * $1 } / Float(slice.count)).squareRoot()
    }
}
