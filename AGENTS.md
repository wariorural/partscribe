# PartScribe — for agenter

PARTs lokale møteopptaker og transkriberer for Mac. Fork av [Quill](https://github.com/humanitas-labs/quill) (MIT) med NB-Whisper som norsk motor. Status og plan står i `tasks/todo.md`, ikke her.

## Stack
- Én Swift-binær, menylinje-ikon, ingen .app-bundle. Swift 6 (strict concurrency), macOS 15+, Apple Silicon.
- Motorer bak `Transcription/TranscriptionEngine.swift`:
  - `nb-whisper` (standard): `NBWhisperEngine.swift`, WhisperKit 1.1.1, modell `Barrymanalow/nb-whisper-coreml` / `nb-whisper-small` (~480 MB).
  - `parakeet`: `ParakeetEngine.swift`, FluidAudio 0.15.5, kun engelsk (~600 MB).
- Valg av motor: `Config.transcriptionEngine()`, satt fra menyen via `Config.setTranscriptionEngine(_:)`.
- Talerskille: `Transcription/SpeakerDiarizer.swift` (FluidAudio `OfflineDiarizerManager`, ~21 MB modeller i `~/Library/Application Support/FluidAudio/Models/speaker-diarization`). Ordene fordeles på talere i `Transcript.bySpeaker` (testet i `SpeakerLabelTests`). Slås av med `transcription.diarization: false`.
- UI: menylinja (`UI/MenuBarController.swift`) og det flytende vinduet (`UI/FloatingPanel.swift`) viser alltid samme tilstand via `AppController.show`.

## Hvor ting bor
- Kode: `macos/Sources/partscribe/`. Tester: `macos/Tests/PartScribeTests/`.
- Config: `~/.config/partscribe/config.json`. Opptak: `~/Recordings/<yyyy.MM.dd-HHmm>/`.
- Modell-cache: `~/Documents/huggingface/models/Barrymanalow/nb-whisper-coreml/nb-whisper-small/` (WhisperKits standard). Parakeet: FluidAudios cache.
- LaunchAgent: `no.part.partscribe`, logger i `/tmp/partscribe.{out,err}.log`.
- Handover og opprinnelig patch: `docs/partscribe-handover-v1.md`, `docs/partscribe-v1.patch`.
- `testlyd/` er gitignored (private opptak).

## Rør ikke
Opptak, capture recovery og transkriptformatet (feltene i transcript.json) er Quills og skal ikke endres. Unntak, avtalt med Mario 28.10: talerskillet nummererer `speaker`-feltet («them 1», «them 2») når et spor har flere talere. Ett spor med én taler skal fortsatt gi ren `me`/`them`.

## Kommandoer
- Bygg: `./scripts/build-macos` (eller `swift build -c release` i `macos/`). Første gang tar ca. 3 min.
- Test uten Xcode: `./scripts/test-macos-uten-xcode`. Maskinen har bare Command Line Tools, som mangler XCTest. Skriptet oversetter testene midlertidig til swift-testing og tilbakestiller med git. Med Xcode holder `swift test`.
- Sjekk: `macos/.build/release/partscribe doctor`.
- Installer: `sudo ./scripts/install-macos`. Krever Mario (sudo).

## Teste uten mikrofon
Lag en falsk sesjon og la `resumePending()` plukke den opp ved oppstart:
```sh
say -v Nora -o x.aiff "norsk tekst" && afconvert -f caff -d aac x.aiff mic.caf
mkdir -p <root>/2026.01.01-1200-test && mv mic.caf <root>/2026.01.01-1200-test/
echo '{"started":"2026-01-01T12:00:00Z","files":{"mic":"mic.caf"}}' > <root>/2026.01.01-1200-test/meta.json
macos/.build/release/partscribe run --out <root>   # vent på transcript.md, så ^C
```
Bruk `--out` mot en scratch-mappe, ikke `~/Recordings`. Opptak med ekte mikrofon og systemlyd krever TCC-tillatelser som bare Mario kan klikke.

## Feller
- **Talerskille testes dårlig med syntetisk tale.** Apples norske, svenske og danske stemmer (Nora, Alva, Sara) blir én klynge. Nora mot britiske stemmer skilles perfekt, men de britiske stemmene slås sammen med hverandre. Ekte møter er eneste gode test. Ekte opptak med én taler deles ikke.
- **Ord på grensen mellom talere** kan havne hos feil taler når Whispers ordtidsstempler er unøyaktige. Det er sett på engelsk TTS som leser norsk og ikke testet med ekte tale. Ingen utjevning er lagt inn ennå.
- **v2-sesjoner med flere segmentfiler per spor** (etter en capture recovery) får talerskillet per fil, så «them 1» i to filer er ikke nødvendigvis samme person.
- **Flytende vindu i skjermdeling:** `sharingType = .none` ber macOS holde panelet utenfor skjermopptak. Det stopper `screencapture`, men ikke alle opptaksveier respekterer det. Ikke verifisert mot Teams/Meet/Zoom.
- **WhisperKit-pin:** `from: "1.1.1"`. Patchens opprinnelige `0.9.0` låste til 0.x.
- **Oversettelsesfellen:** NB-Whisper med tvunget norsk språktoken på engelsk lyd gir flytende norsk *oversettelse*, og den er upålitelig («launch» → «lunsjen»). Engelske møter skal gå gjennom Parakeet.
- **Kald første kjøring:** Første transkripsjon med en ny bundle-id tar ~3 min ekstra (Core ML/ANE kompilerer modellen). Cachen ser ut til å være knyttet til bundle-id, ikke til binæren, så ombygging gjør den ikke kald igjen. Én gang ga en kald kjøring 0 segmenter uten noen feil. Det er ikke gjenskapt, og årsaken er ukjent. Et tomt transkript skrives som ferdig og prøves ikke på nytt: slett `transcript.*` i sesjonsmappa og start på nytt.
- **Gjentakelse ved chunk-grense:** VAD-oppdelingen kan gjenta et halvt utsagn der to biter møtes (sett én gang på 94 s lyd).
- `<|…|>`-tokens lekker ikke med `skipSpecialTokens: true`, så det er ikke lagt inn noe filter.
- Meny, varsler og TCC-tekster er på norsk. CLI-hjelp, `doctor` og logger er fortsatt engelske.
