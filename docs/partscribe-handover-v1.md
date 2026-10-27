# PartScribe — handover v1

**Mål:** PARTs egen lokale møteopptaker og transkriberer for Mac, som forstår norsk. Bygget som fork av [humanitas-labs/quill](https://github.com/humanitas-labs/quill) (MIT). Ingenting forlater maskinen.

**Vedlagt:** `partscribe-v1.patch` — et utestet første utkast til NB-Whisper-motoren (skrevet på Linux, aldri kompilert). Start der.

---

## Bakgrunn (allerede avklart, ikke undersøk på nytt)

**Quill i korte trekk:** Swift-binær med menylinje-ikon (macOS 15+, Apple Silicon). Tar opp mikrofon (`me`) og systemlyd (`them`) som to separate CAF-spor, transkriberer etter stopp og skriver `transcript.md` + `transcript.json` i `~/Recordings/<dato>/`. Har `on_stop`-hook som kjører en shell-kommando med sesjonsmappa som argument etter at transkriptet er skrevet.

**Motoren er isolert:** `macos/Sources/quill/Transcription/TranscriptionEngine.swift` er en protokoll med fire ting — `name`, `model`, `prepare()`, `transcribe(_ audio: URL) -> [TranscriptSegment]`, `release()`. Opptak, capture recovery, me/them-merging og transkriptformat skal **ikke** røres.

**Hvorfor ikke Quills standardmotor:** Parakeet TDT v2 er kun engelsk. Parakeet v3 dekker 25 europeiske språk, men **ikke norsk**. Apples SpeechAnalyzer støttet heller ikke norsk ved lansering.

**Valgt motor: NB-Whisper** (Nasjonalbiblioteket, Apache 2.0). Bokmål + nynorsk, mye bedre enn OpenAI Whisper på norsk (FLEURS bokmål WER: NB large 6,6 vs OpenAI large-v3 10,4; nynorsk 12,6 vs 30,0; selv NB *small* gir 8,3).

**Runtime: WhisperKit** (argmax, Core ML / Neural Engine). En ferdig Core ML-konvertering av `nb-whisper-small` finnes: `Barrymanalow/nb-whisper-coreml` (bruk `model: "nb-whisper-small"`, `modelRepo: "Barrymanalow/nb-whisper-coreml"`). Den er en uoffisiell community-konvertering, verifisert til å laste og transkribere norsk, men ikke grundig benchmarket.

**Kjent felle:** Tvinger man norsk språktoken på engelsk lyd, får man flytende norsk *oversettelse* i stedet for feil. Engelske møter må gå via Parakeet.

---

## Oppgaver

### 1. Fork og bygg (v1)
- Fork `humanitas-labs/quill` til PARTs GitHub som `partscribe`. Behold MIT-lisensen og kreditering til Quill i README.
- Bruk `partscribe-v1.patch` (`git apply`). Den:
  - legger WhisperKit til i `macos/Package.swift`
  - legger til `Transcription/NBWhisperEngine.swift`
  - lar `TranscriptionCoordinator.preparedEngine()` velge motor ut fra config (`"nb-whisper"` | `"parakeet"`)
  - setter `"nb-whisper"` som standard i `Config.swift`
- **Få det til å kompilere.** Sjekk spesielt mot WhisperKit-versjonen som faktisk løses:
  - `WhisperKitConfig(model:modelRepo:)`
  - `DecodingOptions`-parametrene (`task`, `language`, `usePrefillPrompt`, `skipSpecialTokens`, `withoutTimestamps`, `chunkingStrategy: .vad`)
  - `transcribe(audioPath:decodeOptions:)` returtype og `segments`-feltene (`start`/`end` er `Float`)
  - `unloadModels()`
- Fjern eventuelle Whisper-spesialtokens som lekker inn i teksten (`<|...|>`).

### 2. Test med ekte norsk lyd
- Ta opp et kort møte på norsk (gjerne med bergensk) og et på engelsk.
- Sjekk: kommer `transcript.md` ut, stemmer tidsstemplene, er me/them riktig fordelt, ingen gjentakelser på slutten (kjent Whisper-problem på lange filer — derfor VAD-chunking).
- Mål tid per time lyd og rapporter.

### 3. Norsk/engelsk-bryter
- Legg til et valg i menylinja: **Norsk** (NB-Whisper) / **Engelsk** (Parakeet). Lagre valget i config. Valget gjelder neste transkripsjon.
- Oppdater `quill doctor` så den også sjekker om NB-Whisper-modellen er lastet ned (i dag sjekker den bare Parakeet).

### 4. Omdøp
- Binær, menylinje-tekst, notifikasjoner, config-sti (`~/.config/partscribe/`) og LaunchAgent-navn → `partscribe`. Hold det til navn — ikke endre oppførsel.

---

## Senere (v2+, ikke start før v1 virker)
- **Bedre kvalitet:** Konverter `NbAiLab/nb-whisper-medium` eller `-large` til Core ML med argmax' `whisperkittools`, og pek `NBWhisperEngine` dit (init tar `repo` og `variant`).
- **Møtenotat:** Bruk `on_stop`-hooken til å lage oppsummering / beslutninger / oppgaver fra `transcript.md`.
- **Flere personer på "them":** FluidAudio (allerede en avhengighet) har offline diarisering basert på Pyannote Core ML.
- **Følg med på:** Nasjonalbibliotekets nye Qwen3-ASR-baserte modeller (`NbAiLab/nb-asr-qwen06b-*`, lukket beta, foreløpig kun Python/CUDA) og [speech-swift](https://github.com/ivan-digital/qwen3-asr-swift), som kjører Qwen3-ASR på Apple Silicon. Det kan bli neste kvalitetshopp.

## Avgrensning
- Kun Mac. Ingen sky, ingen API-nøkler, ingen opplasting av lyd.
- Ikke skriv om opptakskoden eller transkriptformatet.
