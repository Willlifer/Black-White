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
game/tools/audio/make_drop2.py       the author's drop 2: trims, levels, merges into both manifests ("Drop 2" below)
game/tools/audio/analyse_drop2.py    the drop-2 capture analysis -> capture_drop2_report.json
game/src/game/music.gd               BWMusic: layered, beat-synced, cue/intensity/sting
game/src/game/voice.gd               BWVoice: barks and grunts (start offset + level per clip, Voice bus)
game/src/game/audio/audio.gd         BWAudio: buses, effects, per-bus volume settings
game/src/game/audio/sfx.gd           BWSfx: variation pick, 3D/2D playback, mix table, loops
game/src/game/audio/director.gd      BWAudioDirector: attaches listeners via SceneTree.node_added; button sounds
game/src/game/audio/unit_audio.gd    BWUnitAudio: animation markers / clips / foot locks → SFX + grunts
game/src/game/audio/combat_audio.gd  BWCombatAudio: battle events (timed to their replay) → SFX, intensity, stings
game/src/game/audio/screen_audio.gd  BWScreenAudio: title / roster / downtime moments
game/src/game/audio/audio_capture.gd BWAudioCapture: the --audio-capture run
game/tests/test_audio.gd             7 tests, ~1200 checks (test_drop2: drop-2 trims, cues, hooks)
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

**Cues** (`BWMusic.CUES`, dB per layer; a layer not listed is off). Current
as of drop 2 (D239); `bright` (the loop +12 st) and the 108 BPM `battle` set
are the author's 10/4 changes:

| Cue | Set | Layers |
|---|---|---|
| title | arpeggio (drop 2) | arpeggio +6 |
| roster | slow | bright −1, full −7 |
| rest (prep, picks, results, downtime) | chillin (drop 2) | chillin +6.5 |
| rooms | rooms (drop 2) | rooms +3 |
| prebattle | main | low_beat +6.5, kick +2.5 (drop 2) |
| tutorial | moderato (drop 2) | moderato +4.5 |
| combat | battle (108) | full −4, bright −3, drums 0, drums_top −10 · **intensity 1:** full −3, bright −2, drums_top −5, air −12 · **2:** full −2, bright −1, drums_top −2, air −8, voice_pad −11, kick −6 |
| boss | boss | full 0, bright −4, drums 0, drums_top −3, air −7, voice_pad −7, kick −5 |
| stings | — | `BWMusic.sting(kind)`: one at a time on UI; music ducked −11 dB for the sting's body, back over 1.8 s (see Drop 2) |

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

## Drop 2: the author's cues (2026-10-06, D239–D242)

The author's brief: "I tried making it multiuse based on the description"
(AUDIO-NEEDS.md). Twelve WAVs in `design/audio/`, all 44.1 kHz 16-bit
stereo, read and never written. `make_drop2.py` writes the game copies; the
`.asd` files are Ableton's and ignored.

**Measured** (loudness = BS.1770-ish integrated, ungated, mono sum, with the
max 400 ms momentary in brackets; tempo from onset-grid fits; key from a
chroma profile, so treat it as a pitch centre):

| File | Length | Lead / trail silence | Peak · RMS · loudness | Tempo · loop | Pitch centre | Character |
|---|---|---|---|---|---|---|
| Low Beat | 16.00 s | 0 / 0 | −6.6 · −20.9 · −21.5 (−19.2) | 120.0, exactly 8 bars; the end cuts a held note (seam jump 0.041, 4× the 99th-pct step) | C / E bass (C3, E2 alternating) | dark: 94% of energy < 300 Hz, centroid 154 Hz; beat + bass |
| MainTheme Arpeggio | 14.00 s | 0.86 / 0 | −3.2 · −23.4 · −22.5 (−18.1) | free (rubato, ~74); 4 phrases 3.25 / 3.06 / 3.03 / 3.79 s; the 13.99 s onset restarts the figure | D major (D–A–C–D) | tonal arpeggio, centroid 386 Hz |
| Music Rooms | 7.18 s | 0.34 / 0 (decays to −52 dB) | −16.8 · −34.1 · −34.1 (−31.8) | loose ~112 (onset fit rel. 0.35); a phrase and its ring-out, not bar-aligned | C major (C–E–G) | tonal, quiet (+14.7 dB to level) |
| chillin main theme | 7.50 s | 0.16 / 0 (−55 dB) | −9.3 · −32.6 · −30.8 (−25.5) | 3 chords 2.25 s apart (≈107 if one a bar) | A major-ish (bass F#, D, G, E) | three decaying sustained chords, sparse |
| moderato main loopish | 8.00 s | 0.84 / 0 | −5.2 · −19.7 · −19.2 (−15.1) | free; a 3.585 s figure (1.31 + 2.27 s), twice; the file ends 12 ms before the third | A major | busy arpeggio, 50% < 300 Hz |
| no snare beat | 8.00 s | 0 / 0 | −5.5 · −28.4 · −28.7 (−25.0) | 120.0 (onsets within 3.4 ms), exactly 4 bars, clean seam | — (kick ~39 / 78 Hz) | kick only: 98% < 300 Hz, percussive +10.7 dB over harmonic |
| shop purchase | 7.65 s | 0.87 / 2.15 | −15.2 · −36.1 · −32.9 (−29.4) | — (4 notes in 1.3 s) | C (C–G–C) | soft pluck figure, 2.7 s body + reverb |
| sting level up | 7.65 s | 0.16 / 2.37 | −15.8 · −34.9 · −31.8 (−28.7) | — | C major (C–G–E) | rising notes, 3.0 s body |
| sting pick reveal | 8.00 s | 0.62 / 0 (still −41 dB at the end: tail cut) | −7.5 · −27.1 · −27.4 (−24.2) | busy for 7 s (not a 1–3 s sting) | E minor (E/G, D, C) | continuous phrase, 7.1 s body |
| sting room hard | 7.18 s | 0.15 / 1.96 | −11.5 · −34.3 · −31.0 (−27.9) | — | E with D# (a minor second) | 2.6 s body |
| cursed or bad | 7.65 s | 0.41 / 2.68 | −10.1 · −34.7 · −30.1 (−26.1) | — | E, D#, G | 1.8 s body |
| very good event | 7.65 s | 0.80 / 0 (−54 dB) | −9.3 · −27.4 · −26.2 (−23.0) | — | C major | a crescendo peaking ~4.5 s in, 4.9 s body |

Common to all: no clipping (highest peak −3.2 dBFS); nothing above 4 kHz
(< 0.3% of energy); centroids 128–583 Hz. The stings centre on C; the game's
loop is F# minor / A major (the stings play over ducked music).

**Where they play:**

| Game file | From | Plays |
|---|---|---|
| `layers/drop2/arpeggio.wav` (13.13 s) | MainTheme Arpeggio, 0.86 → 13.99 s | **title** (and the end card) |
| `layers/drop2/chillin.wav` (6.74 s) | chillin, 3 × 2.248 s from the first chord, ring-out wrapped into the head | **rest**: the hall (prep, picks, results, downtime) |
| `layers/drop2/moderato.wav` (7.17 s) | moderato, two 3.585 s cycles from the first onset | **tutorial** |
| `layers/drop2/rooms.wav` (6.85 s) | Music Rooms, from the first onset, with its own decay | **rooms** (the room choice) |
| `layers/low_beat.wav` (main set) | Low Beat, last 8 ms faded to zero | **prebattle**, alone with the kick: its C/E bass against the loop scores chroma r −0.24 … −0.34 on the four F# bars, so it is not layered under `full` / `bright` |
| `layers/kick.wav`, `battle/kick.wav`, `boss/kick.wav` | no snare beat ×2; re-timed to 108 / 132.3 by WSOLA anchored on the 16th | prebattle; **combat intensity 2** (−6 dB); **boss** (−5 dB) |
| `sfx/sting_level_up_1.wav` | sting level up | **results**: one sting per screen, 0.7 s in, when anyone levelled (every fight levels the whole squad, D194, so not once per unit) |
| `sfx/sting_pick_reveal_1.wav` | sting pick reveal | **any picker opening** (hall, mid-fight, tutorial); fades out over 0.8 s when the pick is taken |
| `sfx/sting_room_hard_1.wav` | sting room hard | **a Hard room taken** (encounters included) |
| `sfx/shop_purchase_1.wav` | shop purchase | **shop**: a trade or a scroll used (scrolls are free since D236, so there is no separate "buy") |
| `sfx/sting_bad_1.wav` | cursed or bad | **a cursed piece put on** (the squad's worn cursed count rises, in the gear panel or through a scroll in the shop); **the defeat sting** |
| `sfx/sting_good_1.wav` | very good event | **Wander's jackpot** (on its report card); **the victory sting** |

Not mapped: a 3-piece **set bonus** (PASSIVES-v2.md is a draft; nothing in
code fires one) and a **failed event** (no downtime outcome fails: Wander's
"Nothing happened" still gives +1). The procedural `sting_victory` /
`sting_defeat` stay in the manifest, unused.

**Processing:** stings and the shop sound are cut 5 ms before their first
onset (the first 10 ms frame within 30 dB of the loudest), end where they
fall 48 dB under it (+50 ms, a 0.15 s fade; 0.35 s when the file ends
first), and are levelled like the procedural SFX: −16 LUFS-ish momentary,
peaks ≤ −1 dBFS. `sfx.json` marks them `"drop": 2` with their source, trim
and `body_s` (until 20 dB under the peak). The music copies get the layers'
−20 dB K-RMS, peak-bound with no limiter (arpeggio −21.4, chillin −24.5 and
the kicks −24.8 … −25.6 are peak-bound). A single phrase loop is quieter
than a stack of layers, so its cue gain is above 0 dB (`BWMusic.MAX_DB` 8).
`make_music.py` and `make_sfx.py` re-run `make_drop2` at their end, so a
rebuild keeps drop 2 in both manifests.

**Playback rules (D239, D240):**
- The four drop-2 loops are `BWMusic.FREE` sets: one layer, their own length,
  no bar grid. A cue change leaves them on the next frame (the 0.9 s deck
  crossfade), and any set is entered from its start. Only the four
  re-timings of the 8-bar loop share a progression.
- One sting at a time: a new one fades the last out over 0.3 s. The music
  ducks −11 dB for the sting's `body_s` − 0.3 s, then comes back over 1.8 s.
  `BWMusic.stop_sting()` (a picker closing) lifts the duck over 1.0 s.
- Sting mix (`BWSfx.MIX`): good / bad +0.5, level up +1, room hard 0, pick
  reveal −7 (it runs under the cards), shop −6 (no duck).

**Verified** (87 s capture: `godot --path game -- --drop2 --audio-capture`,
then `python game/tools/audio/analyse_drop2.py` → `capture_drop2_report.json`.
Every sting goes through the hook that plays it in the game, except the
jackpot / victory / defeat, which are called directly):

| Section | Loudness | Momentary max | Peak | Clipped |
|---|---|---|---|---|
| title (arpeggio) | −20.4 LUFS | −16.2 | −6.3 dBFS | 0 |
| rest (chillin) | −22.8 | −14.8 | −3.0 | 0 |
| rooms | −19.9 | −17.1 | −6.2 | 0 |
| prebattle (Low Beat + kick) | −20.6 | −15.7 | −6.4 | 0 |
| tutorial (moderato) | −19.6 | −15.4 | −8.1 | 0 |
| combat at intensity 2 (+ kick) | −17.6 | −13.5 | −3.3 | 0 |
| boss (+ kick) | −16.8 | −14.4 | −3.4 | 0 |

Phase 6's title and roster sat at −20.3, combat −19.5, boss −17.9. chillin
reads low integrated because its chords decay to −50 dB between hits; its
momentary max is level with the others.

- **Cue changes:** out of a free set in 24–174 ms (the 174 ms is the room
  screen's first frame); into the boss set on the 108 BPM bar (1.13 s).
- **Stings:** all eight found in the recording by cross-correlation with
  their file (score 0.90–1.00), starting −1.5 … +8.8 ms from the frame they
  were asked for (within a frame). Each body's momentary max sits 0–3 dB
  under the music it ducked: level up −17.5 vs −14.9, room hard −18.3 vs
  −17.6, pick reveal −14.8 vs −15.8, cursed −17.5 vs −15.4, jackpot −17.6,
  victory −17.3, defeat −17.4.
- **The shop sound** (not ducked) peaks at −14.8 over −16.2 of music. Under
  the music its match score is only 0.5, so its measured offset (+97 ms)
  isn't reliable; the log has it starting on the frame of the trade.

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
