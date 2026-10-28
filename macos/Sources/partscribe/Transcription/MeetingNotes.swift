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

    /// Characters of input per model call. Norwegian costs more tokens per
    /// character than English; 6000 overflowed the ~4k-token context once
    /// instructions and the answer were added.
    static let budget = 3000

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
            let text = pieces[0]
            let summary = try await ask(Prompt.summary, text)
            let decisions = try await ask(Prompt.decisions, text)
            let tasks = try await ask(Prompt.tasks, text)
            let questions = try await ask(Prompt.questions, text)
            body = """
                ## Sammendrag

                \(summary.trimmingCharacters(in: .whitespacesAndNewlines))

                ## Beslutninger

                \(bullets(decisions))

                ## Oppgaver

                \(bullets(tasks))

                ## Åpne spørsmål

                \(bullets(questions))
                """
        }

        let note = """
            # Møtenotat · \(dir.lastPathComponent)

            \(body.trimmingCharacters(in: .whitespacesAndNewlines))

            ---
            _Utkast laget lokalt av Apple Intelligence fra transcript.md. Modellen er liten og blander særlig ofte meninger og beslutninger. Sjekk mot transkriptet før du deler det._

            """
        try Data(note.utf8).write(to: dir.appendingPathComponent("notat.md"), options: .atomic)
    }

    // MARK: -

    private enum Prompt {
        static let instructions = """
            Du lager møtenotater på norsk bokmål fra transkripsjoner av møter. \
            Skriv bare det som faktisk ble sagt. Ikke finn på navn, tall, frister, beslutninger eller oppgaver. \
            En beslutning er bare noe noen tydelig sa var bestemt eller avtalt. \
            En oppgave er når en bestemt person sier at hen skal gjøre noe, eller blir bedt om det og sier ja. \
            Diskusjon, idéer, meninger og ønsker er verken beslutninger eller oppgaver. \
            Talerne heter me, them, me 1, them 2 og så videre. Skriv dem nøyaktig slik, med liten forbokstav, \
            eller bruk navnet hvis noen ble tiltalt med navn. \
            Transkripsjonen er maskinlaget og kan ha feilhørte ord.
            """
        static let points = """
            Her er en del av en møtetranskripsjon. Skriv korte stikkord om hva som ble diskutert. \
            Skriv deretter, hver for seg, beslutninger og oppgaver som ble sagt tydelig, og spørsmål som ble stilt uten å bli besvart. \
            Skriv "ingen" der det ikke finnes noe.
            """
        static let merge = """
            Her er stikkord fra flere deler av samme møte. Slå dem sammen til én liste med stikkord. \
            Fjern gjentakelser, men behold alle beslutninger, oppgaver og ubesvarte spørsmål.
            """
        static let summary = """
            Skriv to til fire setninger om hva møtet under handlet om. Bare setningene, ingen overskrift.
            """
        static let decisions = """
            List beslutningene som tydelig ble tatt i møtet under, én per linje, med "- " foran. \
            Ble det ikke tatt noen tydelige beslutninger, skriv bare "- Ingen".
            """
        static let tasks = """
            Hvem skal gjøre hva etter møtet under? Skriv én linje per person og ting, på formen "- hvem: hva". \
            Ta med alt noen sa de skal gjøre, fikk ansvar for eller ble bedt om å gjøre. \
            Legg til fristen i parentes bare hvis den ble sagt.
            """
        static let questions = """
            List spørsmål som ble stilt i møtet under og som ingen svarte på, én per linje, med "- " foran. \
            Ikke lag egne spørsmål. Finnes det ingen, skriv bare "- Ingen".
            """
    }

    @available(macOS 26, *)
    private static func ask(_ task: String, _ text: String) async throws -> String {
        // A fresh session per call: each piece stands alone and nothing
        // accumulates in the small context.
        // Permissive guardrails: summarising the user's own meeting is a
        // content transformation, and the default filter refused ordinary
        // Norwegian idiom ("kutte i tanna") as unsafe.
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        let session = LanguageModelSession(model: model, instructions: Prompt.instructions)
        let response = try await session.respond(
            to: "\(task)\n\n\(text)",
            // A cap on the answer: without one the model sometimes keeps
            // writing until it overflows the context and the call fails.
            // Greedy, so the same meeting always gives the same note.
            options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 500)
        )
        return response.content
    }

    /// Keep the model's list lines (it writes "-", "*", "•" or "1."
    /// bullets), drop repeats, "none" lines and chatter around them, and
    /// normalise to "- ".
    static func bullets(_ text: String) -> String {
        var seen = Set<String>()
        let lines = text.split(separator: "\n").compactMap { raw -> String? in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let marker = line.firstMatch(of: /^(?:[-*•]|\d+[.)])\s+/) else { return nil }
            // The model sometimes notes the absence of a deadline; drop that.
            let item = String(line[marker.range.upperBound...])
                .replacing(/\s*\([^)]*(?:ingen|ikke|uten)[^)]*\)/.ignoresCase(), with: "")
                .trimmingCharacters(in: .whitespaces)
            guard !item.isEmpty, !item.lowercased().hasPrefix("ingen"),
                seen.insert(item.lowercased()).inserted
            else { return nil }
            return "- " + item
        }
        return lines.isEmpty ? "- Ingen" : lines.joined(separator: "\n")
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
