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

## Status 28.10 formiddag — flytende vindu + talerskille

Gjort og verifisert:
- Flytende vindu (oppe til høyre, kan flyttes, husker plassen) med status, start/stopp og siste transkript. Kan slås av og på i menyen. Sett på skjermbilde.
- «Åpne siste transkript» (⌘T) i menyen.
- Talerskille: 38/38 tester grønne. Ekte enkelttaler-opptak deles ikke. Nora skilles perfekt fra britiske TTS-stemmer, mens nordiske TTS-stemmer smelter sammen (se AGENTS.md). NB-Whisper med ordtidsstempler er like rask (12 s på 94 s lyd), og gjentakelsen ved chunk-grensen forsvant. Parakeet virker fortsatt.

Venter på Mario:
- `sudo ./scripts/install-macos` og `launchctl kickstart -k gui/$(id -u)/no.part.partscribe` for å få den nye versjonen i bruk.
- Ekte videomøte med flere folk. Det er første ordentlige test av talerskillet og systemlyden. Se etter: blir riktig antall «them N»? Deles replikker feil på grensene?
- Sjekk om det flytende vinduet synes for de andre når du deler skjermen.

Neste kandidater: utjevning av enkeltord som havner hos feil taler (hvis det viser seg i ekte møter), navngi talere etter møtet, hurtigtast, møtenotat via on_stop.

## Status etter natt-økta 27.10 (kl. 19–19.35)

Grønt (verifisert):
- Bygg: `swift build -c release` grønt mot WhisperKit 1.1.1 og FluidAudio 0.15.5, uten nye advarsler fra egen kode.
- Tester: 32/32 grønne via `scripts/test-macos-uten-xcode` (ingen XCTest uten Xcode).
- `partscribe doctor` kjører og sjekker modellen til valgt motor (testet ok, mangler og ok igjen).
- Nora, norsk, 94 s: 17 segmenter. Ingen `<|…|>`, monotone tidsstempler, header `engine: nb-whisper (nb-whisper-small)`. Én ordfeil (korrekturlesast → «korrektuleses»), ellers ordrett. Tall normaliseres pent: «kl. 12», «65 %», «f.eks.». Én gjentatt halvsetning ved en chunk-grense («For eksempel på biblioteket.»). Syntetisk tale er lett, så dette sier lite om ekte møter.
- Fart, varm: 94 s lyd på ~9 s (12 s med oppstart) ≈ **6 min per time lyd**. Kald første kjøring med ny bundle-id: +~3 min.
- Oversettelsesfellen, Samantha på engelsk gjennom nb-whisper: flytende norsk og upålitelig («who owns the launch» → «hvem eier lunsjen?», «Friday at noon» falt bort).
- Parakeet på samme engelske fil: ordrett, 1 s transkripsjon (+~60 s nedlasting første gang). Modellen ligger nå i cachen.
- `Config.setTranscriptionEngine` testet i en egen harness: bytter motor, beholder andre nøkler og skriver gyldig JSON.

Venter på Mario:
- ~~Fork/push~~ — gjort 28.10: Mario godkjente offentlig fork. `origin` = wariorural/partscribe, `upstream` = humanitas-labs/quill.
- **Menyen er ikke sett med øynene.** Den bygger og kjører, men jeg har ikke klikket den. Sjekk at haken flytter seg mellom Norsk og Engelsk, og at `~/.config/partscribe/config.json` oppdateres.
- ~~Install og ekte testopptak~~ — gjort 28.10 kl. 09: installert i /usr/local/bin, LaunchAgent på, TCC godkjent. To korte opptak med mikrofon ble transkribert på 2–3 s, ordrett nok. Systemlyd («them») er ennå ikke testet med en ekte samtale.
- Fjæra kan bli skjult bak hakket på MacBook når menylinja er full. macOS sier ikke fra.
- `testlyd/` var tom. Ikke testet med ekte opptak.

Uløst:
- Én kald kjøring (første gang med bundle-id `com.digimata.quill`) ga **0 segmenter** uten feil. Prøvde å gjenskape det med kald kjøring på `no.part.partscribe`, men den ga alle 17. Årsaken er ukjent. Et tomt transkript markeres som ferdig og prøves ikke på nytt.

## Plan — natt 27.→28.10

### Fase 1 — Fork og klon
- [x] `gh repo fork humanitas-labs/quill --fork-name partscribe --clone=false` (konto wariorural) — offentlig, godkjent av Mario
- [x] Klon inn i `Code/partscribe/` (mappa har bare handover + patch; flytt dem til `docs/`)
- [x] README: behold MIT, legg til «Basert på Quill (humanitas-labs), MIT»-avsnitt
- Verifisering: `git remote -v` viser fork som origin og upstream

### Fase 2 — Patch og kompiler (handover oppg. 1)
- [x] `git apply partscribe-v1.patch`
- [x] Rett `from: "0.9.0"` → `from: "1.1.1"` i `macos/Package.swift`
- [x] `swift build -c release` i `macos/` — første gang henter WhisperKit + avhengigheter (tar tid)
- [x] Rett kompileringsfeil. Forventet: strict-concurrency-advarsler rundt `WhisperKit`-klassen (ikke Sendable) inni actoren — bør gå siden den aldri krysser isolasjonsgrensen. — ingen
- [x] Legg inn filter mot `<|...|>`-tokens i `NBWhisperEngine.transcribe` (regex, kun hvis `skipSpecialTokens` ikke tar alt — sjekk output først, ikke legg til blindt) — trengtes ikke, ingen tokens i output
- [x] `swift test` grønn (eksisterende tester rører ikke motoren) — via scripts/test-macos-uten-xcode
- Verifisering: `.build/release/quill doctor` kjører og rapporterer

### Fase 3 — Røyktest med syntetisk norsk lyd (erstatning for oppg. 2 til Mario kan ta opp)
- [x] `say -v Nora -o mic.aiff "<2–3 min norsk tekst>"` → konverter til CAF (`afconvert -f caff -d aac`)
- [x] Lag `~/Recordings/test-nora/` med `meta.json` (v1-skjema, les `SessionMeta.swift` for format) + `mic.caf` — brukte `--out` mot scratch i stedet for ~/Recordings
- [x] Start daemon, la `resumePending()` kjøre, vent på `transcript.md` — første kald kjøring ga 0 segmenter, se Uløst
- [x] Sjekk: norsk tekst ut, ingen `<|…|>`, tidsstempler monotone, ingen gjentakelser på slutten, `engine: nb-whisper (nb-whisper-small)` i header
- [x] Mål tid: lydlengde / transkripsjonstid → noter «sek per time lyd»
- [x] Samme test med engelsk `say -v Samantha` og `engine: "nb-whisper"` → dokumenter oversettelsesfellen konkret (forventet: flytende norsk)
- [x] Samme engelske fil med `engine: "parakeet"` → bekreft at Parakeet-veien fortsatt virker etter patch

### Fase 4 — Norsk/engelsk-bryter (oppg. 3)
- [x] `Config.setTranscriptionEngine(_:)` — les JSON, sett `transcription.engine`, skriv atomisk tilbake. Behold andre nøkler urørt.
- [x] Menylinje: undermeny/to avkrysningsvalg «Norsk (NB-Whisper)» / «Engelsk (Parakeet)» under skilleren, hake på gjeldende. Valget gjelder neste transkripsjon (motoren releases etter hver kø, så ingen omlasting midt i jobb). — to valg direkte i menyen, ikke undermeny; ikke sett visuelt
- [x] `Doctor.checkTranscription()`: sjekk valgt motor. For nb-whisper: finnes WhisperKit-cachen (`~/Documents/huggingface/models/Barrymanalow/nb-whisper-coreml/nb-whisper-small/` — verifiser faktisk sti i WhisperKit 1.1.1 `downloadBase`-default) ellers warn «~480 MB lastes ned ved første transkripsjon».
- Verifisering: bytt i menyen → `cat ~/.config/<navn>/config.json` viser endringen; `doctor` viser riktig modell-status for begge

### Fase 5 — Omdøp (oppg. 4) — kun navn, ingen oppførsel
- [x] `Package.swift`: target/produkt `partscribe`, sectcreate-sti `Sources/partscribe/Info.plist`, testtarget `PartScribeTests`
- [x] `git mv macos/Sources/quill macos/Sources/partscribe`, samme for Tests
- [x] `Quill.swift` → `PartScribe.swift`: commandName, abstract, loggtekst, notifikasjonstitler
- [x] `Config.path` → `~/.config/partscribe/config.json`
- [x] `Install.swift`: label `no.part.partscribe`, `/usr/local/bin/partscribe`, `/tmp/partscribe.*.log`
- [x] `Info.plist`: bundle-id `no.part.partscribe`, navn, TCC-tekster på norsk
- [x] `MenuBarController`: hele menyen på norsk («Start opptak», «Stopp opptak», «Åpne opptaksmappe», «Avslutt PartScribe», statuslinjer «● tar opp · 28:11» osv.)
- [x] `TranscriptionCoordinator`: notifikasjonstitler
- [x] `scripts/build-macos`, `scripts/install-macos`: binærnavn og `PARTSCRIBE_INSTALL_DIR`
- [x] README/macos/README: navn + Quill-kreditering
- Verifisering: `grep -ri quill macos/ scripts/` gir bare treff i krediteringstekst; `swift build` + `swift test` grønn; `partscribe doctor` kjører

### Fase 6 — Avslutt økta
- [x] Commit per fase, push til fork
- [x] `AGENTS.md` i repoet: stack, hvor ting bor, fellene (WhisperKit-pin, oversettelsesfellen, sudo-install)
- [x] Oppdater denne fila med status + målte tall
- [x] Rapport til Mario: hva er grønt, hva venter på tillatelser/sudo, hva målte jeg
- [ ] Hvis `testlyd/` har fått innhold: kjør fase 3 på den også — tom

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
