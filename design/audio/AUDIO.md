# Audio (Phase 6)

All of the audio is built from the author's two loops, the two Low fish
voice takes and the 12 barks. The rest is procedural synthesis (numpy and
scipy, deterministic, no third-party samples), so the result is licence-clean.

**An honest note first.** I can't listen. Every sound here was designed by
ear-less reasoning and checked by measurement (levels, peaks, timing,
spectra), not by taste. The procedural SFX are a **first pass**: clean,
consistent, correctly timed placeholders that hold up a mix. Real recordings
will sound better, and the drop-in path below is built for them.

| Want to… | Run |
|---|---|
| Rebuild all SFX | `python game/tools/audio/make_sfx.py` (≈4 s; `--only hit` for a subset) |
| Rebuild the music layers | `python game/tools/audio/make_music.py` (≈15 s) |
| Record a 61 s in-engine capture | `godot --path game -- --audio-capture` (windowed) → `design/audio/capture.wav`, `capture_sfx.wav`, `capture.json` |
| Analyse it | `python game/tools/audio/analyse_capture.py` → `capture_report.json`, `waveform.png`, `spectrogram.png`, `sfx_sync.png` |
| Tests | `test_audio.gd`, part of `-- --self-test` |

Then run `godot --headless --path game --import` after rebuilding.

## Files

```
game/tools/audio/bwdsp.py            shared DSP: WAV io, filters (incl. circular for loops), loudness, limiter, WSOLA, PNG writer
game/tools/audio/make_sfx.py         106 SFX WAVs + audio/sfx/sfx.json (variations, bus, levels, peak time)
game/tools/audio/make_music.py       16 layer WAVs in 3 tempo sets + audio/music/layers/layers.json
game/tools/audio/analyse_capture.py  capture analysis + PNGs
game/src/game/music.gd               BWMusic: layered, beat-synced, cue/intensity/sting
game/src/game/voice.gd               BWVoice: barks and grunts (start offset + level per clip, Voice bus)
game/src/game/audio/audio.gd         BWAudio: buses, effects, per-bus volume settings
game/src/game/audio/sfx.gd           BWSfx: variation pick, 3D/2D playback, mix table, loops
game/src/game/audio/director.gd      BWAudioDirector: attaches listeners via SceneTree.node_added; button sounds
game/src/game/audio/unit_audio.gd    BWUnitAudio: animation markers / clips / foot locks → SFX + grunts
game/src/game/audio/combat_audio.gd  BWCombatAudio: battle events (timed to their replay) → SFX, intensity, stings
game/src/game/audio/screen_audio.gd  BWScreenAudio: title / roster / downtime moments
game/src/game/audio/audio_capture.gd BWAudioCapture: the --audio-capture run
game/tests/test_audio.gd             6 tests, ~940 checks
```

## SFX

All files are 44.1 kHz 16-bit, levelled to **−16 LUFS-ish**: the maximum 400 ms
K-weighted RMS, raised iteratively through a 1.5 ms look-ahead limiter. Every
peak is at or under **−1 dBFS**; all 106 files are within ±1.5 dB of the target. The mix
then lives in `BWSfx.MIX` (per sound, dB) and the bus levels, not in the
files. Pitch jitter is ±3.5% per play, and the same variation never plays twice in a row.

| Sound (variations) | How it's made |
|---|---|
| `swing_light` (4) | noise through a band sweeping 650 → 2.6k → 1.1 kHz (STFT-domain mask), plus a narrow "edge whistle" band |
| `swing_heavy` (3) | wider, darker sweep 220 → 900 Hz + a 90–190 Hz body band |
| `swing_axe` (3) | mid sweep, amplitude-tumbled at ~24 Hz (the head chopping air) |
| `hit_flesh` (4) | 170 → 55 Hz pitched thump + low noise burst + 500–1400 Hz slap + click, tanh saturation |
| `hit_crit` (3) | deeper thump, 2.4 kHz burst, crack, and a damped metal ring (modes 1 : 2.76 : 5.4 : 8.93) |
| `hit_glance` (3) | 1.8–5.2 kHz noise gated by a ~150 Hz stick-slip pulse + two small modes |
| `hit_block` (3) | inharmonic metal modes (1 : 1.58 : 2.37 : 3.11 : 4.2 : 5.73, f0 ≈ 470 Hz) + strike burst + thump |
| `hit_miss` (3) | short thin whoosh peaking at ~4 kHz |
| `bow_draw` (2) | stick-slip impulses accelerating 30 → 100 Hz, each exciting wood modes, + a rising squeak |
| `bow_release` (3) | Karplus-Strong string at ~118 Hz + thwip burst + limb slap |
| `arrow_thunk` (3) | wooden thump + wood modes + a 42 Hz quivering shaft band |
| `pistol_shot` (3) | N-wave crack + broadband burst + 130 → 48 Hz boom, saturated, + short synthetic room |
| `flintlock_shot` (2) | flint click, pan-flash hiss, then (~85 ms later) a deeper boom, smoke hiss and a longer room |
| `cast_whoom` (3) | rising band 140 → 900 Hz + sub glide + a soft harmonic tone; loudest at 0.13 s (= coil → release) |
| `bolt_fizz` (3) | 2.8–7.5 kHz hiss with crackle-density AM + a rising vibrato whistle |
| `channel_loop` (2) | 2.0 s seamless hum (all partials multiples of 0.5 Hz, 4 Hz tremolo, wrapped noise bed) |
| `elem_fire` (3) | whoomph + ~34 exponentially spaced crackle clicks + roar bed |
| `elem_water` (3) | splash burst + bloop + ~24 rising droplet chirps |
| `elem_ice` (3) | glassy crack + ~32 high pings (2.5–7 kHz, two modes each) |
| `elem_thunder` (3) | jittered 95 Hz saw, gated by crackle bursts, band-passed and saturated, + snap |
| `elem_wind` (3) | wide gust sweep with a 7 Hz flutter + whistle |
| `elem_dark` (3) | 80 → 320 → 65 Hz band whoosh + 46 Hz sub, 31 Hz ring-mod shiver |
| `elem_light` (3) | A-major bell arpeggio (A5 C#6 E6, partials 1 : 2 : 2.76 : 4.07 : 5.4) + sparkle |
| `heal` (2) | detuned tone gliding up a fifth from A4 + a bell + sparkle |
| `tile_detonate` (3) | burst whose band falls 3.5k → 180 Hz + 90 → 30 Hz boom + thunder crackles + room |
| `tile_glaze` (2) | crystal clicks accelerating (freezing) + a groaning 120 Hz creak + a final ping |
| `tile_gale` (2) | two overlapping gust swells with a 5 Hz sway |
| `step_stone` (6) | heel thump + 1.5–5 kHz grit + a later toe scuff |
| `ko_thud` (2) | two body impacts (seat, then back, ~0.22 s apart) + cloth + a gear rattle |
| `ui_hover` (3) / `ui_click` (2) | 45 ms sine blip / blip + 420 Hz body |
| `ui_confirm` / `ui_cancel` / `ui_pick` (2 each) | rising fourth pluck / falling pluck, low-passed / thump + pluck |
| `ui_turn` (2) | two-bell chime (A5 → E6) |
| `ui_levelup` (2) | E-major (or A-major) arpeggio + bell + sparkle |
| `sting_victory` (2) | A-major arpeggio into a held pad chord + bell (3.2 s, stereo) |
| `sting_defeat` (2) | descending F#-minor line over a dark F# drone (3.4 s, stereo) |
| `progress_day` (2) | 5 s swell: a reverse-cymbal-style noise rise and an opening pad chord, resolving on a bell at 4.25 s (the progress screen's beat) |

UI and stings use the loop's tonality (F# minor / A major), so they sit with the music.

## Music

Measured first (numbers in `layers.json`):
- **BlackWhite loop:** 120 BPM, 8 bars plus a 0.32 s reverb tail.
  - 95% of its energy is below 300 Hz and there is nothing above 2.4 kHz (−70 dB).
  - The bass per bar is F# F# E E E E F# F#.
  - HPSS finds a percussive part 19 dB under the harmonic part, and its onsets sit at random against the 16th grid (29 ms mean deviation; random would be about 31). It has no separable beat.
- **Drum Beat:** the Low fish beat, 90 BPM, on the grid within 9.5 ms. It's tonal around B.
- **Low fish recordings:** two takes of a male voice (pitch 120–200 Hz, speech-like glides, a 90 BPM project). I did not use them as a melodic layer.

**Layers** (every set has every listed layer, all sample-for-sample the same length):

| Layer | What | main 120 | slow 102.0 | boss 132.3 |
|---|---|:-:|:-:|:-:|
| `full` | the loop, cut on the bar line, its tail wrapped into the head (seam jump 0.063 → 0.0009) | ✓ | ✓ | ✓ |
| `calm` | its harmonic part (HPSS), low-passed at 420 Hz: no attacks | ✓ | ✓ | ✓ |
| `air` | its harmonic part one octave up (WSOLA ×2, then decimated), high-passed at 500 Hz: a shimmer. A plain 2.5 kHz high-pass would be −82 dB, so there's nothing to pass | ✓ | | ✓ |
| `drums` | Drum Beat 90 → 120 BPM, pitch kept: **WSOLA anchored on every 16th**, so each hit lands exactly on the new grid (all 124 onsets kept; grid deviation 7.6 ms vs 8.8 ms for plain WSOLA) | ✓ | | ✓ |
| `drums_top` | drums high-passed at 5 kHz: hats and shakers | ✓ | | ✓ |
| `drums_half` | bars 1–4 at half-time (each 16th stretched to an 8th, anchored WSOLA) | ✓ | | |
| `voice_pad` | a granular pad from the voice takes: 150 steady voiced 20 ms frames (YIN), 70–120 ms grains retuned to the bass root and fifth per bar, about 55 grains/s per voice, in a circular 3 s room. Unintelligible by construction | ✓ | ✓ | ✓ |

- **Sets:** main is 705,600 samples (120 BPM). Slow is 830,000 (102.0 BPM), for roster and rest. Boss is 640,000 (132.3 BPM, +10.25%).
- **Tempo:** the slow and boss sets are re-timed offline with pitch-preserving WSOLA, done on three copies so the seam stretches like any other point, then crossfaded into what really followed the end. Chroma checks confirm the key doesn't move.
- **Seams:** every seam step is smaller than the layer's 99th-percentile sample step.
- **Loudness:** every layer is levelled to −20 dB K-RMS. Peaks are ≤ −1 dBFS without a limiter, because a limiter's gain state wouldn't match across the seam. The drum layers and `air` are peak-bound, which leaves them 0.3–6 dB quieter.

**Cues** (`BWMusic.CUES`, dB per layer; a layer not listed is off):

| Cue | Set | Layers |
|---|---|---|
| title | main | full 0, air −15 |
| roster | slow | full −1, calm −8 |
| prebattle | main | calm 0, air −12, drums_half −10 |
| rest | slow | calm 0, voice_pad −9 |
| combat | main | full −2, drums 0, drums_top −10 · **intensity 1:** full −1, drums_top −5, air −12 · **2:** full 0, drums_top −2, air −8, voice_pad −11 |
| boss | boss | full 0, drums 0, drums_top −3, air −7, voice_pad −7 |
| victory / defeat | — | `BWMusic.sting()`: the sting on UI, music ducked −11 dB for its length, back over 1.8 s |

How cues play:
- **Timing:** a cue change lands on the **next bar**, and an intensity change on the **next beat**. Layers fade in over 0.08 s and out over 0.45 s.
- **Changing set:** a change between sets crossfades on the outgoing bar line. The new set enters on the **same bar of the progression**.
- **Intensity** (from `BWCombatAudio`):
  - 0 at the start.
  - 1 once a squad member is under 50% or anyone is KO'd.
  - 2 when a squad member is under 25%, three units are down, or either side is down to its last unit.

## Buses

Master → limiter at −1 dB. Music (−7): Amplify (sting duck) and a Compressor
sidechained by Voice, which ducks it ~4 dB under barks (ratio 2, threshold −28 dB, 350 ms
release). MusicStretch (→ Music): PitchShift, used only by the
`runtime_tempo` option. SFX (−3), Voice (−1), UI (−6).

`BWAudio.set_volume(bus, 0..1)` and `get_volume(bus)`: 1 is the designed mix and 0 mutes.
The values are saved in `user://audio.cfg`. There's no settings UI yet.

## Hooks (all by listening; no combat, screen or clip code calls audio)

`BWAudioDirector` watches `SceneTree.node_added`:

- **Unit views → `BWUnitAudio`** (the animator's `marker` signal, its top clip and its foot lock):
  - **Strikes:**
    - `launch` plays a light, heavy (heavy/polearm sets) or axe (`strike_axe`) whoosh. It's delayed or started part-way in so its loudest 10 ms lands on `hit`.
    - `hit2` plays a second whoosh (daggers).
    - `release` plays a bow twang, pistol shot or flintlock shot (by `weapon_model`).
    - A bow strike starting plays the draw creak.
  - **Casts:**
    - The `cast` clip starting plays a whoom whose peak lands on `release`.
    - `release` plays the bolt fizz.
    - `channel` plays the hum loop while it's on top.
  - **Reactions** (stricken + the 5 variants, fumble, block, dodge, kneel), on `impact`: the sound of the blow the battle resolved.
    - miss → whiff
    - resisted → clank
    - glance → scrape (clank half the time on a block)
    - crit → ring
    - otherwise → flesh
    - plus an arrow thunk for bows and the element's hit for elemental blows.
  - `fall`'s `grounded` plays the KO thud.
  - **Footsteps:** each foot lock engaging plays a step, only while the root travels faster than 0.35 u/s. The Giant's steps are pitched down and louder. Units with no animator get a step per hex.
  - **Grunts and variants** (cooldowns in D69):
    - `stricken_rage`'s `shout` → "No" / "Hiyah"
    - `stricken_shrug`'s `catch` → "Hmm"
    - stumble → "Oogh"
    - flinch → "Ouch grunt"
    - knockback → "Oof" (+ a skid on `slide_end`)
    - other hits → a random Oof / Ouch grunt / Oogh
    - strikes → Hiyah / Yah, 30% of the time

    All at the character's `voice_pitch` (the Giant at 0.62).
- **Combat screen → `BWCombatAudio`** (battle events, sounded when their replay starts):
  - Each `attack`/`counter`/`skill`/`riposte` tells its targets what's coming.
  - `detonate`/`erupt` → boom at the hex
  - `paint` ice → glaze; wind → gale
  - `tile_damage` → the element's hit
  - `heal` → heal shimmer
  - a level-up → sting
  - a player `turn` → turn chime
  - `battle_end` → victory/defeat sting
  - HP/KO changes → intensity
- **Every BaseButton:**
  - hover or focus → tick
  - press → confirm (Begin, Lock, Progress…), cancel (Back, Clear, Undo, End turn…) or click
- **Title / roster / downtime → `BWScreenAudio`:**
  - title: start → confirm
  - roster: browse → tick, pick → pick, unpick → cancel
  - downtime: progress the day → the 5 s swell

Barks: `BWVoice` skips each recording's 0.4–0.9 s of leading silence and evens
out its level (the files sat 25 dB apart) from the `CLIPS` table.

## Verification (61 s in-engine capture, 48 kHz, windowed)

From `capture_report.json`:

| Section | Loudness | Momentary max | Peak | Clipped |
|---|---|---|---|---|
| title | −20.3 LUFS | −15.9 | −8.6 dBFS | 0 |
| roster (slow set) | −20.3 | −15.1 | −7.3 | 0 |
| combat | −19.5 | −13.6 | −5.8 | 0 |
| boss (+10%) | −17.9 | −14.2 | −3.8 | 0 |

- **No sample over −1 dBFS** anywhere.
- **Music changes vs the grid** (engine playback clock): 4 changes (3 bar, 1 beat), off by **3.5 ms on average and 6.8 ms at most**. One frame is 16.7 ms.
- **Recorded drum onsets vs the predicted grid:**
  - combat: median offset −4.7 ms, IQR 13 ms, 83% within 15 ms
  - boss: +4.8 ms, IQR 13 ms, 83% within 15 ms
  - The title section reads 20%, as expected: the loop has no beat.
- **SFX vs markers**, measured on a simultaneous SFX-bus stem. The Master limiter adds a fixed 2.0 ms look-ahead, which the analysis subtracts. Times are against the marker's true sub-frame crossing time, and the path latency is calibrated with three clicks.
  - All 13 immediate sounds started in the **same frame** their marker was handled, and all 13 were found in the recording.
  - The 9 markers played ahead by up to 1.5 frames (release, grounded, dodge impact…) landed within **±9 ms**.
  - The aligned whoosh peaks landed **−8 … +9 ms** from `hit`.
  - Frame-0 impacts can't be foreseen and land **9–18 ms** late. AudioStreamPlayer3D starts on the next physics tick (D70).
  - **12 of 13 are within one frame.**
  - Godot starts sounds on mix-block boundaries, so single sounds also scatter by about ±5 ms. The calibration clicks show it.
- **Not covered by the capture:** voice ducking under a bark, and the victory/defeat stings. The fight didn't end inside the window. Both are built on tested pieces: the bus layout test checks the compressor sidechain and the sting duck exists.

Pictures: `waveform.png` (both channels, RMS/peak, section bands, cue and
intensity switches, SFX ticks), `spectrogram.png` (log 30 Hz–16 kHz),
`sfx_sync.png` (250 ms zooms, marker vs sound).

## Swapping in real recordings

- **SFX:** drop a WAV over `game/audio/sfx/<name>_<n>.wav`. Any rate, mono or stereo works, but mono is best for world sounds.
  - Add variations by adding `<name>_5.wav` and raising `variants` in `sfx.json`.
  - Level the file to about −16 LUFS short-term with peaks ≤ −1 dBFS, or adjust `BWSfx.MIX`.
  - For whooshes, set `peak_s` in `sfx.json` to the moment of the swish. It's what lines them up with `hit`.
  - `test_audio` will flag peaks over −1 dBFS and loudness off by more than 1.5 dB. Re-run `make_sfx.py`'s measurement, or edit the manifest's `levels`, when you replace files.
- **Music layers:** replace `game/audio/music/layers/[set/]<layer>.wav` with exactly 8 bars at that set's tempo. That's 705,600 / 830,000 / 640,000 samples at 44.1 kHz, stereo. `test_audio` checks the length. Real stems from the Ableton sets (bass, pad, drums separately) would replace `calm`/`air`/`drums_top` far better than filtering a mix.
- **Barks:** replace `game/audio/barks/<clip>.wav` and update its row in `BWVoice.CLIPS`: [start s, gain dB].

## Decisions I made (D66–D70 in DECISIONS.md)

1. Tempo changes are pre-rendered sets (102 / 120 / 132.3 BPM), not a runtime pitch shift. The runtime path exists behind `BWMusic.runtime_tempo`.
2. I didn't ship a perc layer: the loop has no separable percussion. `air` is synthesised (an octave-up shimmer) because the loop has no highs. The hats come from the drum beat.
3. The Low fish voice takes became an unintelligible granular pad rather than a lead.
4. Anchored WSOLA (on the 16th grid) for drums, over global WSOLA or a phase vocoder.
5. Audio attaches by observing the scene tree, so no combat/screen edits. It reads some private fields and goes quiet if they're renamed.
6. Barks are trimmed and levelled by a table, not by editing the author's files.
7. Hit grunts have a 3.5 s per-unit cooldown and a 0.9 s global gap. Strike shouts happen 30% of the time.
8. The intensity thresholds (50% / 25% HP, KO counts, last unit standing).
9. Foreseeable markers are led by up to 1.5 frames. I did not raise the physics tick rate to fix frame-0 impacts.

## Where real recordings would help most

1. **Impacts** (`hit_flesh`, `hit_crit`, `hit_block`). They're heard on every blow and synthesis is weakest at "body".
2. **Footsteps.** They're the most repeated sound in the game (67 in 26 s of combat), and six synthetic variants will tire fastest.
3. **Separate stems from the two Ableton sets** (bass, pad, drums, hats). They would replace every filtered or derived layer and give real highs. The current loop export has nothing above 2.4 kHz.
4. **Pistol and flintlock, bow release, the element hits.** These are character sounds where a recording's grit matters more than timing.
5. **More barks at consistent levels**, especially short efforts (grunts, shouts) recorded without leading silence.
