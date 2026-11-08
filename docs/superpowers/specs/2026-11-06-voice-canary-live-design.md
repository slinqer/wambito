# Voice capture: Canary live, without Vosk on eligible phones

Status: design, 2026-11-06. Builds on `2026-11-05-voice-canary-design.md` (merged in #43: Vosk live,
Canary or Parakeet on release). Prototype: local branch `spike/canary-live` (commit 60b548c).

## 1. Goal

On the phones that already get Canary, the text the person sees while talking comes from Canary
itself, not Vosk: the right words appear while they speak ("dos", not "doce"), and the
"Refinando…" step mostly disappears. Those phones stop needing Vosk at all: one download, about
150 MB instead of 190 MB.

Everything else stays as it is: phones that do not qualify, Italian and Portuguese (Parakeet, see
§3), and the F-Droid build keep Vosk live plus, where they have one, the precise pass on release.

## 2. What the spike measured (S25 Ultra, the founder's 19 Spanish phrases)

A replay tool (`wambito-sim-stream`, built against sherpa-onnx 2.0.1 with the NDK) re-decoded the
audio heard so far every 0.5 s, screen on:

| | per pass, median | p90 | max |
|---|---|---|---|
| 4 threads, every 0.5 s | 89 ms | 125 ms | 185 ms |
| 1 thread, every 0.5 s | 135 ms | 199 ms | 265 ms |
| 4 threads, every 0.3 s | 94 ms | 144 ms | 251 ms |

- Final text: 16/19 exactly what was said, the 3 others with every amount right (spelling only:
  "Regaló", "nuevee", "Parkin").
- The first 0.5 s gives invented words ("Señor Presidente", "Bonnie"); mid-phrase the last word is
  often cut ("Bandy Lecher" → "Pan y leche"). Earlier words changed in 10 of 74 passes; 0.3 s gives
  more changes, not fewer.
- A pass costs more as the phrase grows (4.5 s of audio: 175 ms): long dictation needs segments.
- In the app (the prototype: first pass after 1 s, then every 0.5 s, last word held back) the
  founder found it "funciona muy bien".

Not measured: a mid-range phone, battery and heat over many phrases, Parakeet live.

## 3. Who gets what

| Phone and language | Live text | On release | Downloads |
|---|---|---|---|
| Qualifies for Canary (arm64, ≥ 3 GB, not low-RAM), es/en, Play/GitHub build | Canary | last Canary pass of the open segment | Canary only |
| Qualifies for Parakeet (≥ 5 GiB), it/pt | Vosk | Parakeet (as today) | Vosk + Parakeet |
| Anything else, or the F-Droid build | Vosk | Vosk (as today) | Vosk |

Parakeet stays on release until it is measured live (it is three times Canary's size).

People who already have Vosk on an eligible phone keep it: it is the fallback (§4.5). Nothing is
deleted behind their back; "Borrar los modelos de voz" in Settings deletes everything as now.

## 4. How it works

### 4.1 The flow in the sheet

1. Tap 🎤: recording starts at once (as now); the precise model was warmed up when the sheet opened.
2. Nothing is shown during the first second of speech.
3. Then the text updates every 0.5 s: the segments already closed (§4.2), then the open segment
   without its last word.
4. A pause of 1.5 s ends the listen, as now (`endOfSpeechPause`), now measured by the VAD.
5. On release: one last pass over the open segment, with its last word. "Refinando…" appears only
   if that pass takes more than 300 ms; it is bounded by `refineLimit` (3 s), and on timeout the last
   live text stands.

### 4.2 Segments (Kotlin, `voice/`)

- Silero VAD (`silero_vad.onnx`, 644 KB, MIT, run by sherpa-onnx's `Vad`) splits the recording at
  pauses. A closed segment is decoded once and frozen; only the open segment is re-decoded, so a
  pass never grows past one phrase. A segment longer than 10 s is closed at the next quiet frame.
- Passes run on their own thread, one at a time. The next pass starts 0.5 s after the last one
  started, or `2 × its duration` if that is longer: a slow phone updates less often instead of
  falling behind.
- The recording stays in memory only (the 30 s cap and the rules of `PcmBuffer` hold).
- The logic (when to pass, what to freeze, what to show) lives in a plain class, `LiveTranscript`,
  that takes a recognizer and a VAD as interfaces, so it is unit-tested without sherpa-onnx.

### 4.3 Events (`wambito/voice/events`)

- New: `live {text}`, the whole text to show (closed segments + open segment).
- New: `speech_end`, the VAD's 1.5 s of silence after speech (the Dart side stops, as it does on
  Vosk's results today).
- On release: `refining` (only after 300 ms), then `refined {text}` or `refine_failed`, then `done`,
  as now. With live mode the "refine" is the last pass of the open segment.
- The listen args gain `live: true`; without it everything is as today.

### 4.4 Dart (`lib/capture/engine/`)

- A `CanaryLiveEngine` (or a mode of `VoskEngine`) for eligible es/en: it starts the channel with no
  Vosk model path and `live: true`, shows `live` texts, stops on `speech_end`, and keeps the 8 s
  "nothing heard" and 30 s limits.
- The engine is chosen per listen: live when the precise model is installed and the phone qualifies;
  otherwise the current Vosk engine.

### 4.5 Download and fallback (`models_download.dart`, `capture_download.dart`)

- Eligible es/en phones are offered Canary alone: "Descargar voz (150 MB)". The current joint
  Vosk + Canary offer stays for Parakeet languages.
- The VAD model ships inside the APK as an asset (644 KB), not downloaded.
- If the precise model fails to load or answer (a broken file, too little memory at that moment),
  that listen ends with an error, a toast offers "Usar el modelo básico" (Vosk download, 40 MB), and
  from then on that phone uses Vosk + Canary on release, as today.
- Already-installed Vosk on an eligible phone: used only as that fallback.

## 5. Licences

Silero VAD (MIT, snakers4) is added to About, with its licence text. Nothing else changes.

## 6. Tests

- Kotlin: `LiveTranscript` with a fake recognizer and VAD: first pass after 1 s, one pass at a time,
  the back-off, last word held back until release, segments frozen, the 10 s split.
- Dart: the live engine shows `live` texts, stops on `speech_end`, falls back to the last live text
  on a refine timeout, and the engine choice per phone and language.
- Download: the offer is Canary-only on eligible es/en, joint for it/pt; the fallback toast.

## 7. Open

- A mid-range phone (and battery and heat): measure before a public release; the back-off is the
  safety net, not a measurement.
- Parakeet live, later, once measured.
- Whether to drop the "Refinando…" label entirely if the last pass is always under 300 ms.

## 8. Order of the work

1. `LiveTranscript` + VAD in Kotlin, with its tests.
2. Channel: `live` args and events.
3. Dart engine and the choice per listen.
4. Download offer, the bundled VAD, the fallback toast, About.
5. A trial build on the founder's phone.
