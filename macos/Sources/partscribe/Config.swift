import Foundation

/// Optional user config at ~/.config/partscribe/config.json:
///
///     {
///       "recordings_dir": "~/Recordings",
///       "transcription": { "enabled": true, "engine": "nb-whisper", "diarization": true },
///       "mic_voice_processing": true,
///       "floating_window": true,
///       "meeting_notes": true,
///       "on_stop": "my-hook"
///     }
///
/// Resolution order for the recordings root: --out flag > config file >
/// ~/Recordings. `on_stop` is a shell command spawned with the session
/// directory as its argument — after the transcript is written, or right
/// after recording when transcription is disabled.
enum Config {
    static let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/partscribe/config.json")

    static let defaultRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Recordings", isDirectory: true)

    /// The configured recordings root, or nil if no config file / no key.
    static func recordingsDir() -> URL? {
        guard let dir = load()?["recordings_dir"] as? String, !dir.isEmpty else { return nil }
        return URL(fileURLWithPath: (dir as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// Shell command to spawn after each session's transcript is written (or
    /// after recording, if transcription is disabled), or nil.
    static func onStop() -> String? {
        guard let cmd = load()?["on_stop"] as? String, !cmd.isEmpty else { return nil }
        return cmd
    }

    /// Whether finished recordings are transcribed automatically. Default on.
    static func transcriptionEnabled() -> Bool {
        transcription()?["enabled"] as? Bool ?? true
    }

    /// Configured engine name: "nb-whisper" (PartScribe default, Norwegian)
    /// or "parakeet" (English). Anything else warns and falls back.
    static func transcriptionEngine() -> String {
        transcription()?["engine"] as? String ?? "nb-whisper"
    }

    /// Whether each track is split into numbered speakers ("them 1",
    /// "them 2"). Default on.
    static func diarizationEnabled() -> Bool {
        transcription()?["diarization"] as? Bool ?? true
    }

    /// Whether notat.md is written after each transcript. Default on; needs
    /// Apple Intelligence, and is skipped quietly without it.
    static func meetingNotesEnabled() -> Bool {
        load()?["meeting_notes"] as? Bool ?? true
    }

    /// Whether the floating panel is shown. Default on.
    static func floatingWindow() -> Bool {
        load()?["floating_window"] as? Bool ?? true
    }

    static func setTranscriptionEngine(_ engine: String) throws {
        try update { json in
            var transcription = json["transcription"] as? [String: Any] ?? [:]
            transcription["engine"] = engine
            json["transcription"] = transcription
        }
    }

    static func setFloatingWindow(_ visible: Bool) throws {
        try update { $0["floating_window"] = visible }
    }

    /// Persist a choice made in the menu. Read-modify-write so every other
    /// key in the file survives; atomic so a crash never leaves a
    /// half-written config. Throws rather than clobbering a malformed file.
    private static func update(_ change: (inout [String: Any]) -> Void) throws {
        var json: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: path.path) {
            guard let existing = load() else { throw ConfigError.malformed(path) }
            json = existing
        }
        change(&json)
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: path, options: .atomic)
    }

    enum ConfigError: Error, CustomStringConvertible {
        case malformed(URL)

        var description: String {
            switch self {
            case .malformed(let url): return "\(url.path) is not valid JSON — fix it by hand first"
            }
        }
    }

    private static func transcription() -> [String: Any]? {
        load()?["transcription"] as? [String: Any]
    }

    /// Apple voice processing (acoustic echo cancellation) on the mic, so
    /// speaker playback doesn't bleed into the mic track and get transcribed
    /// as "me". Default off — the live voice unit ducks all other playback,
    /// and on headphones there's no echo to cancel anyway. Set true when
    /// recording meetings through the speakers.
    static func micVoiceProcessing() -> Bool {
        load()?["mic_voice_processing"] as? Bool ?? false
    }

    /// Parse the config file. A malformed config is reported on stderr rather
    /// than silently ignored — recordings landing in an unexpected place is
    /// worse than a warning.
    private static func load() -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        guard
            let data = try? Data(contentsOf: path),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            FileHandle.standardError.write(
                Data(
                    "warning: \(path.path) is not valid JSON — ignoring config\n".utf8
                ))
            return nil
        }
        return json
    }

    /// Resolve the recordings root from an optional CLI override.
    static func resolveRoot(cliOverride: String?) -> URL {
        if let cliOverride {
            return URL(
                fileURLWithPath: (cliOverride as NSString).expandingTildeInPath,
                isDirectory: true
            )
        }
        return recordingsDir() ?? defaultRoot
    }
}
