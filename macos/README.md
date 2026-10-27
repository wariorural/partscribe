# PartScribe for macOS

A minimal, fully local macOS meeting recorder + transcriber. One menu-bar
click records your mic and all system audio as two separate tracks; when you
stop, partscribe transcribes both on-device and writes a speaker-tagged transcript.
Nothing ever leaves the machine.

The macOS implementation is a single Swift binary with a menu-bar tray and no
app bundle.

## Install

```sh
cd partscribe
./scripts/build-macos
sudo ./scripts/install-macos
partscribe install --launch-at-login   # optional — runs in the background on login
```

For direct development inside this platform package:

```sh
cd macos
swift build -c release
```

**Requires:** macOS 15+ (Core Audio process taps for system audio — no
virtual device, no kernel extension). Apple Silicon recommended for
transcription speed.

## How to use

1. **Run it** (`partscribe` in a terminal, or the LaunchAgent).
2. **Click the feather in the menu bar → Start opptak.** First use prompts
   for microphone and System Audio Recording permissions. While recording, the
   icon turns red with a running elapsed counter, and macOS shows the purple
   recording indicator.
3. **Click → Stopp opptak** when the meeting ends. Transcription starts
   automatically (the menu shows progress); a notification fires when the
   transcript is ready.

Each session lands in `~/Recordings/<yyyy.MM.dd-HHmm>/`:

| File | Contents |
|---|---|
| `mic.caf` | your side (default input device, AAC) |
| `system.caf` | everything the Mac played — the other side of the call (AAC) |
| `mic-002.caf`, `system-002.caf`, … | additional segments, present only if capture had to restart mid-session (see below) |
| `meta.json` | start/end timestamps, duration, per-track segments/offsets, and capture status (`complete`/`recovered`/`incomplete`) |
| `transcript.json` | canonical transcript — engine provenance + timed, speaker-tagged segments |
| `transcript.md` | the same transcript rendered for reading |
| `transcribe.log` | transcription progress/errors for this session |

Two tracks on purpose: speech models do better on clean single-source audio,
and mic-vs-system is free two-party diarization — `me` vs `them` with no
speaker-identification model. CAF on purpose: unlike m4a, it needs no
finalization pass — if the process dies mid-meeting, everything already
written is still readable.

## Capture recovery

macOS audio routes are not stable for the length of a meeting — connecting or
disconnecting AirPods, or changing the default device, can silently stop a
capture stream. PartScribe watches both tracks (a one-second watchdog over callback
progress, plus route-change notifications) and, if a track stalls, restarts it
on the current route into a new numbered segment (`mic-002.caf`, …). The
already-recorded segment is never modified.

What you see while recording:

- feather red, `● recording · 28:11` — both tracks healthy;
- feather orange, `◐ recovering microphone · 28:11` — a track stalled and is
  being restarted (up to three attempts);
- feather orange, `⚠ microphone capture lost · 28:14` — recovery failed; you
  get one notification, and the session will be marked incomplete;
- `△ system audio silent` — secondary diagnostic: the system track is running
  but delivering exact digital silence (may be legitimate — nothing playing).

At stop you get a notification if the session was anything other than
`complete`, and the transcript header carries the same status. Transcription
still runs — every segment that has audio is transcribed and merged on the
session clock, with the gap left visible in the timestamps.

After an incident, inspect `meta.json` in the session folder: each track lists
its `segments` (with session-clock start/end offsets and frame counts) and
`interruptions` (when the stall was detected, when capture resumed, how many
attempts it took). `status` tells you whether the track is `complete`,
`recovered` (usable, with a bounded gap), or `incomplete` (audio missing at
the tail or an unrecovered stall).

## Transcription

Built in, on-device, automatic. Two engines, switched from the menu
(**Norsk (NB-Whisper)** / **Engelsk (Parakeet)**); the choice is written to
the config and applies to the next transcription.

- **nb-whisper** (default) — [NB-Whisper](https://huggingface.co/NbAiLab)
  small from the National Library of Norway, via
  [WhisperKit](https://github.com/argmaxinc/WhisperKit) 1.1.1 and the community
  Core ML conversion `Barrymanalow/nb-whisper-coreml`. Bokmål output, forced
  Norwegian language token. ~480 MB, cached in
  `~/Documents/huggingface/models/`. **Norwegian only:** English audio comes
  out as fluent (and lossy) Norwegian translation, not as an error.
- **parakeet** — Parakeet TDT 0.6B v2 (English) via
  [FluidAudio](https://github.com/FluidInference/FluidAudio)'s Core ML port.
  ~600 MB.

Models download once on first transcription; `partscribe doctor` tells you
whether the selected engine's model is cached so you're never downloading
after an important meeting.

Each track is transcribed separately, shifted by its start offset so both
share one clock, and merged by timestamp. Jobs run in a serial queue — you can
start a new recording while the last one transcribes. Unfinished jobs resume
on next launch (the filesystem is the queue: a session with `meta.json` but no
`transcript.json` is pending). Failures append to the session's
`transcribe.log` and never block later jobs.

## Config

Optional, at `~/.config/partscribe/config.json`:

```json
{
  "recordings_dir": "~/Recordings",
  "transcription": { "enabled": true, "engine": "nb-whisper" },
  "on_stop": "my-hook"
}
```

- `recordings_dir` — where sessions land. Resolution order: `--out` flag >
  config > `~/Recordings`.
- `transcription.enabled` — set `false` to just record.
- `transcription.engine` — `"nb-whisper"` (default) or `"parakeet"`.
- `mic_voice_processing` — Apple's echo cancellation on the mic (default off).
  Set `true` when recording meetings through the speakers, so playback doesn't
  bleed into the mic track and get transcribed twice as "me". The trade: while
  the voice unit is live, macOS ducks other playback slightly (`.min` ducking
  is configured, but it can't be zeroed). On headphones there's no echo to
  cancel, so raw capture is the better default.
- `on_stop` — shell command spawned with the session directory as its
  argument, **after the transcript is written** (or right after recording if
  transcription is disabled). Wire it to whatever comes next: summarization,
  filing, indexing.

## CLI

```sh
partscribe                        # run the menu-bar daemon (^C to quit)
partscribe run --out <dir>        # custom recordings root (default ~/Recordings)
partscribe doctor                 # check permissions, recordings folder, models
partscribe install --launch-at-login
partscribe install --uninstall
```

## Stack

- **Swift** — single SPM executable target
- **Core Audio process tap** (`AudioHardwareCreateProcessTap`, macOS 14.2+) —
  system audio capture via a private aggregate device
- **AVAudioEngine** — mic capture
- **AVAudioFile** — streaming AAC encode into CAF
- **FluidAudio / Parakeet** — on-device Core ML transcription
- **NSStatusItem** — the whole UI

## Gotchas

- A global tap records *everything* the Mac plays — notification dings,
  music, all of it. Don't play Spotify during meetings (or ask for a
  per-process picker if it bothers you).
- If recordings come out silent, check System Settings → Privacy & Security →
  Screen & System Audio Recording.
- Parakeet v2 is English-only. Other languages will come with the Whisper
  engine.
- The binary embeds its Info.plist (`__TEXT,__info_plist`) so TCC can
  attribute permissions to partscribe itself when running as a LaunchAgent.
