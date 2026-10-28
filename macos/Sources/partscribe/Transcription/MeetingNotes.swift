import Foundation
import FoundationModels

/// Writes notat.md next to the transcript — summary, decisions, tasks and
/// open questions — with Apple's on-device system language model, so the
/// meeting still never leaves the Mac. The model's context holds only a few
/// thousand tokens, so a long transcript is noted piece by piece and the
/// pieces are merged before the final note is written.
enum MeetingNotes {
    enum NotesError: Error, CustomStringConvertible {
        case unavailable(String)
        case noTranscript(URL)

        var description: String {
            switch self {
            case .unavailable(let why): return "system language model unavailable: \(why)"
            case .noTranscript(let dir): return "no transcript.json in \(dir.lastPathComponent)"
            }
        }
    }

    /// Characters of input per model call: roughly half the context, leaving
    /// room for instructions and the answer.
    static let budget = 6000

    /// nil when notes can be made; otherwise why not, in words for `doctor`.
    static func unavailableReason() -> String? {
        guard #available(macOS 26, *) else { return "requires macOS 26" }
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(.appleIntelligenceNotEnabled): return "Apple Intelligence is turned off"
        case .unavailable(.modelNotReady): return "Apple Intelligence model is still downloading"
        case .unavailable(let reason): return "\(reason)"
        }
    }

    static func write(for dir: URL) async throws {
        if let why = unavailableReason() { throw NotesError.unavailable(why) }
        guard
            let data = try? Data(contentsOf: dir.appendingPathComponent("transcript.json")),
            let transcript = try? JSONDecoder().decode(Transcript.self, from: data)
        else { throw NotesError.noTranscript(dir) }
        guard #available(macOS 26, *) else { return }

        let lines = transcript.segments.map { "[\(clock($0.start_ms))] \($0.speaker): \($0.text)" }
        let body: String
        if lines.isEmpty {
            body = "## Sammendrag\n\nIngen tale i opptaket.\n"
        } else {
            var pieces = chunks(lines, limit: budget)
            if pieces.count > 1 {
                // Map: key points per piece. Reduce: merge until they fit one call.
                var points: [String] = []
                for piece in pieces { points.append(try await ask(Prompt.points, piece)) }
                while points.count > 1, points.joined(separator: "\n\n").count > budget {
                    var merged: [String] = []
                    for group in chunks(points, limit: budget) {
                        merged.append(try await ask(Prompt.merge, group))
                    }
                    points = merged
                }
                pieces = [points.joined(separator: "\n\n")]
            }
            body = try await ask(Prompt.note, pieces[0])
        }

        let note = """
            # Møtenotat · \(dir.lastPathComponent)

            \(body.trimmingCharacters(in: .whitespacesAndNewlines))

            ---
            _Laget lokalt av Apple Intelligence fra transcript.md. Sjekk mot transkriptet før du deler det._

            """
        try Data(note.utf8).write(to: dir.appendingPathComponent("notat.md"), options: .atomic)
    }

    // MARK: -

    private enum Prompt {
        static let instructions = """
            Du lager møtenotater på norsk bokmål fra transkripsjoner av møter. \
            Skriv bare det som faktisk ble sagt. Ikke finn på navn, tall, frister eller beslutninger. \
            Talerne heter me, them, them 1, them 2 og så videre; bruk de navnene. \
            Transkripsjonen er maskinlaget og kan ha feilhørte ord.
            """
        static let points = """
            Her er en del av en møtetranskripsjon. Skriv korte stikkord om hva som ble diskutert, \
            hvilke beslutninger som ble tatt, hvilke oppgaver som ble fordelt (hvem, hva, frist) \
            og hvilke spørsmål som står åpne.
            """
        static let merge = """
            Her er stikkord fra flere deler av samme møte. Slå dem sammen til én liste med stikkord. \
            Fjern gjentakelser, men behold alle beslutninger, oppgaver og åpne spørsmål.
            """
        static let note = """
            Lag et møtenotat ut fra teksten under. Bruk nøyaktig disse overskriftene i denne rekkefølgen: \
            ## Sammendrag, ## Beslutninger, ## Oppgaver, ## Åpne spørsmål. \
            Under Sammendrag: to til fire setninger. Under de andre: en punktliste der hver linje starter med "- ". \
            Under Oppgaver: skriv hvem som gjør hva, og frist hvis den ble nevnt. \
            Finnes det ingenting under en overskrift, skriv "- Ingen".
            """
    }

    @available(macOS 26, *)
    private static func ask(_ task: String, _ text: String) async throws -> String {
        // A fresh session per call: each piece stands alone and nothing
        // accumulates in the small context.
        let session = LanguageModelSession(instructions: Prompt.instructions)
        let response = try await session.respond(
            to: "\(task)\n\n\(text)",
            options: GenerationOptions(temperature: 0.2)
        )
        return response.content
    }

    /// Greedy line packing under a character limit. A single line longer than
    /// the limit gets a chunk of its own rather than being cut mid-sentence.
    static func chunks(_ lines: [String], limit: Int) -> [String] {
        var out: [String] = []
        var current = ""
        for line in lines {
            if !current.isEmpty, current.count + line.count + 1 > limit {
                out.append(current)
                current = ""
            }
            current += current.isEmpty ? line : "\n" + line
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    private static func clock(_ ms: Int) -> String {
        let s = ms / 1000
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}
