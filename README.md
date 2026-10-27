<p align="center"><img src="docs/icon.png" width="96" alt="PartScribe"></p>

# PartScribe

PARTs lokale møteopptaker og transkriberer for Mac, som forstår norsk. Tar opp mikrofonen din og lyden fra samtalen som to spor, transkriberer dem på maskinen med [NB-Whisper](https://huggingface.co/NbAiLab), og skriver et tidsstemplet `me` / `them`-transkript. Ingenting forlater maskinen.

## 1. Installer

```sh
./scripts/build-macos
sudo ./scripts/install-macos
partscribe install --launch-at-login   # valgfritt
```

Krever macOS 15+ og Apple Silicon.

## 2. Bruk

Velg **Norsk (NB-Whisper)** eller **Engelsk (Parakeet)** i menyen før møtet. NB-Whisper på engelsk lyd gir flytende norsk oversettelse, ikke engelsk tekst.

1. Klikk fjæra i menylinja og velg **Start opptak**. Første gang spør macOS om tilgang til mikrofon og systemlyd.
2. Velg **Stopp opptak** når møtet er ferdig. Transkriberingen starter av seg selv.
3. Transkriptet havner i `~/Recordings/<yyyy.MM.dd-HHmm>/transcript.md`, ved siden av lyden.

Oppsett, CLI og feilsøking står i [macOS-dokumentasjonen](macos/README.md) (engelsk, arvet fra Quill).

## 3. Plattformer

Bare macOS. `windows/` og `linux/` er arvet fra Quill og brukes ikke.

## 4. Lisens

[MIT](LICENSE).

PartScribe er PARTs fork av [Quill](https://github.com/humanitas-labs/quill) fra Humanitas Labs (MIT), med [NB-Whisper](https://huggingface.co/NbAiLab) fra Nasjonalbiblioteket som norsk motor. Lisens og opphavsrett til Quill er beholdt i [LICENSE](LICENSE).
