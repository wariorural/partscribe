# PartScribe — plan v1

Kilde: `partscribe-handover-v1.md` + `partscribe-v1.patch` (ligger i mappa til repoet er klonet, flyttes da til `docs/`).
Mål for natt-økta 27.–28.10.2026: oppgave 1 og 3 ferdig og verifisert, oppgave 4 påbegynt. Oppgave 2 trenger Mario (mikrofon- og systemlyd-tillatelser må klikkes av et menneske).

## Funn fra forarbeidet (27.10, før lunsj)

Verktøy på maskinen
- macOS 26.6.2, Apple Silicon. Swift 6.3.2 via Command Line Tools — **ikke Xcode**. `swift build` virker uten Xcode (testet på tomt pakke-prosjekt).
- `gh` er logget inn som `wariorural`, ingen organisasjoner synlige. Ingen `partscribe`-repo finnes.
- Ingen quill installert, ingen `~/.config/quill`, ingen `~/Recordings`.
- `say -v Nora` (nb_NO) finnes → kan lage norsk testlyd lokalt uten mikrofon.

Quill (upstream, master, sist pushet 27.09.2026)
- `Package.swift`: swift-tools 6.0, macOS 15, FluidAudio 0.15.5 løst. Swift 6-språkmodus → strict concurrency.
- Motor-protokollen er nøyaktig som handoveren sier. `TranscriptionCoordinator.preparedEngine()` er eneste sted motoren velges.
- Config leses kun; ingen skrive-funksjon i dag. Språkbryteren trenger en liten `Config.write`.
- `Doctor.checkTranscription()` sjekker bare Parakeet-cache via FluidAudio.
- Navnet «quill» ligger i: `Quill.swift` (commandName, loggtekst, notifikasjonstitler), `MenuBarController.swift` («Quit quill»), `Install.swift` (label `com.digimata.quill`, `/usr/local/bin/quill`, `/tmp/quill.*.log`), `Config.swift` (`~/.config/quill`), `Info.plist` (bundle-id, navn, TCC-tekster), `TranscriptionCoordinator.swift` (notifikasjoner), `Package.swift` (target `quill` + `-sectcreate`-sti), `scripts/*`, tester (`QuillTests`).

WhisperKit — patchen sjekket mot v1.1.1 (nyeste, 08.10.2026)
- **Feil i patchen:** `from: "0.9.0"` låser til 0.x (siste er 0.18.0). Må være `from: "1.1.1"`. Alt under er verifisert mot 1.1.1:
- `WhisperKitConfig(model:modelRepo:)` ✓
- `DecodingOptions(task:language:usePrefillPrompt:skipSpecialTokens:withoutTimestamps:chunkingStrategy:)` ✓ alle finnes, `.vad` finnes.
- `transcribe(audioPath:decodeOptions:)` → `[TranscriptionResult]` (open class, `@unchecked Sendable`) med `.segments: [TranscriptionSegment]`, `start`/`end` er `Float` ✓
- `unloadModels()` er `open func ... async` ✓
- Språkkode `"no"` og `"nn"` finnes i WhisperKits språktabell ✓
- Tokenizer velges fra modellens dimensjoner (51865 × 768 → `.small` → `openai/whisper-small`), lastes fra Hugging Face ved første kjøring. Krever nett én gang, som modellen.
- WhisperKit-pakken heter nå `argmax-oss-swift` i manifestet, men produktet er fortsatt `WhisperKit` og URL-identiteten `whisperkit` → patchens `.product(name: "WhisperKit", package: "WhisperKit")` skal gå.

Modellen
- `Barrymanalow/nb-whisper-coreml` finnes, oppdatert 01.08.2026, mappe `nb-whisper-small/` med riktig WhisperKit-layout. ~480 MB (encoder 176 + decoder 307). Brukes allerede av «papegøye» (norsk/engelsk dikteringsdaemon) — så det er bevist at den laster.

## Avklart med Mario (27.10, etter lunsj)

1. **GitHub:** fork til `wariorural/partscribe`.
2. **Installasjon:** bygg i natt, binær blir liggende i `macos/.build/release/`. Mario kjører `sudo ./scripts/install-macos` i morgen (valg A). Ikke installer til `~/.local/bin` uten beskjed.
3. **Testing uten Mario:** Nora-lyd i falsk sesjonsmappe via `resumePending()` er godkjent. `partscribe transcribe <mappe>`-kommando: ikke avkreftet, men utenfor handoveren — lag den bare hvis den trengs for å teste, og si det i rapporten.
4. **Menyspråk:** oversett hele menyen til norsk (menypunkter, statuslinjer, notifikasjoner, TCC-tekster i Info.plist). Følg `~/.claude/part/stemme.md` for tone.
5. **Bundle-id:** `no.part.partscribe`. Fjær-ikonet beholdes inntil videre.
6. **Ekte testlyd:** Mario legger et norsk opptak i `testlyd/`. Når det ligger der: samme test som Nora-lyden (fase 3), rapporter WER-inntrykk og tid.

## Plan — natt 27.→28.10

### Fase 1 — Fork og klon
- [ ] `gh repo fork humanitas-labs/quill --fork-name partscribe --clone=false` (konto wariorural)
- [ ] Klon inn i `Code/partscribe/` (mappa har bare handover + patch; flytt dem til `docs/`)
- [ ] README: behold MIT, legg til «Basert på Quill (humanitas-labs), MIT»-avsnitt
- Verifisering: `git remote -v` viser fork som origin og upstream

### Fase 2 — Patch og kompiler (handover oppg. 1)
- [ ] `git apply partscribe-v1.patch`
- [ ] Rett `from: "0.9.0"` → `from: "1.1.1"` i `macos/Package.swift`
- [ ] `swift build -c release` i `macos/` — første gang henter WhisperKit + avhengigheter (tar tid)
- [ ] Rett kompileringsfeil. Forventet: strict-concurrency-advarsler rundt `WhisperKit`-klassen (ikke Sendable) inni actoren — bør gå siden den aldri krysser isolasjonsgrensen.
- [ ] Legg inn filter mot `<|...|>`-tokens i `NBWhisperEngine.transcribe` (regex, kun hvis `skipSpecialTokens` ikke tar alt — sjekk output først, ikke legg til blindt)
- [ ] `swift test` grønn (eksisterende tester rører ikke motoren)
- Verifisering: `.build/release/quill doctor` kjører og rapporterer

### Fase 3 — Røyktest med syntetisk norsk lyd (erstatning for oppg. 2 til Mario kan ta opp)
- [ ] `say -v Nora -o mic.aiff "<2–3 min norsk tekst>"` → konverter til CAF (`afconvert -f caff -d aac`)
- [ ] Lag `~/Recordings/test-nora/` med `meta.json` (v1-skjema, les `SessionMeta.swift` for format) + `mic.caf`
- [ ] Start daemon, la `resumePending()` kjøre, vent på `transcript.md`
- [ ] Sjekk: norsk tekst ut, ingen `<|…|>`, tidsstempler monotone, ingen gjentakelser på slutten, `engine: nb-whisper (nb-whisper-small)` i header
- [ ] Mål tid: lydlengde / transkripsjonstid → noter «sek per time lyd»
- [ ] Samme test med engelsk `say -v Samantha` og `engine: "nb-whisper"` → dokumenter oversettelsesfellen konkret (forventet: flytende norsk)
- [ ] Samme engelske fil med `engine: "parakeet"` → bekreft at Parakeet-veien fortsatt virker etter patch

### Fase 4 — Norsk/engelsk-bryter (oppg. 3)
- [ ] `Config.setTranscriptionEngine(_:)` — les JSON, sett `transcription.engine`, skriv atomisk tilbake. Behold andre nøkler urørt.
- [ ] Menylinje: undermeny/to avkrysningsvalg «Norsk (NB-Whisper)» / «Engelsk (Parakeet)» under skilleren, hake på gjeldende. Valget gjelder neste transkripsjon (motoren releases etter hver kø, så ingen omlasting midt i jobb).
- [ ] `Doctor.checkTranscription()`: sjekk valgt motor. For nb-whisper: finnes WhisperKit-cachen (`~/Documents/huggingface/models/Barrymanalow/nb-whisper-coreml/nb-whisper-small/` — verifiser faktisk sti i WhisperKit 1.1.1 `downloadBase`-default) ellers warn «~480 MB lastes ned ved første transkripsjon».
- Verifisering: bytt i menyen → `cat ~/.config/<navn>/config.json` viser endringen; `doctor` viser riktig modell-status for begge

### Fase 5 — Omdøp (oppg. 4) — kun navn, ingen oppførsel
- [ ] `Package.swift`: target/produkt `partscribe`, sectcreate-sti `Sources/partscribe/Info.plist`, testtarget `PartScribeTests`
- [ ] `git mv macos/Sources/quill macos/Sources/partscribe`, samme for Tests
- [ ] `Quill.swift` → `PartScribe.swift`: commandName, abstract, loggtekst, notifikasjonstitler
- [ ] `Config.path` → `~/.config/partscribe/config.json`
- [ ] `Install.swift`: label `no.part.partscribe`, `/usr/local/bin/partscribe`, `/tmp/partscribe.*.log`
- [ ] `Info.plist`: bundle-id `no.part.partscribe`, navn, TCC-tekster på norsk
- [ ] `MenuBarController`: hele menyen på norsk («Start opptak», «Stopp opptak», «Åpne opptaksmappe», «Avslutt PartScribe», statuslinjer «● tar opp · 28:11» osv.)
- [ ] `TranscriptionCoordinator`: notifikasjonstitler
- [ ] `scripts/build-macos`, `scripts/install-macos`: binærnavn og `PARTSCRIBE_INSTALL_DIR`
- [ ] README/macos/README: navn + Quill-kreditering
- Verifisering: `grep -ri quill macos/ scripts/` gir bare treff i krediteringstekst; `swift build` + `swift test` grønn; `partscribe doctor` kjører

### Fase 6 — Avslutt økta
- [ ] Commit per fase, push til fork
- [ ] `AGENTS.md` i repoet: stack, hvor ting bor, fellene (WhisperKit-pin, oversettelsesfellen, sudo-install)
- [ ] Oppdater denne fila med status + målte tall
- [ ] Rapport til Mario: hva er grønt, hva venter på tillatelser/sudo, hva målte jeg
- [ ] Hvis `testlyd/` har fått innhold: kjør fase 3 på den også

## Ikke nå (v2+, fra handoveren)
- Egen Core ML-konvertering av nb-whisper-medium/large
- Møtenotat via `on_stop`
- Diarisering på «them» (FluidAudio)
- Qwen3-ASR-modellene fra NB

## Hverdagsbruk — idéer etter v1 (avklart 27.10)
PWA vurdert og forkastet: nettleser får ikke systemlyd uten dialog per møte, og Core ML/NB-Whisper finnes ikke der. Menylinje er riktig form. Det som gjør den lettere i møter:
- Global hurtigtast for start/stopp (så ikonet ikke må finnes under skjermdeling)
- «Åpne siste transkript» i menyen
- `on_stop` → send transkript til Notion / lag møtenotat (= v2 «Møtenotat»)
