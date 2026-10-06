# Black | White — build plan

The finish line: **a game you can open and send units through a little adventure.**
Title → pick 6 of 20 → (pick 3, place, fight → downtime) × 10 → the boss.

Commercial-grade polish is the bar we climb toward, not the bar we start at.
Placeholders first, then art; each phase ends at a gate you check before the
next one starts. Decisions made along the way go in `DECISIONS.md`.

New project lives in `game/` (fresh Godot 4.7, GDScript). The copied V8
`godot/` is a parts bin: logic is lifted out of it file by file, nothing in it
is edited.

## Status (2026-10-05)

| Phase | State |
|---|---|
| 0 Foundation | done |
| 1 Paper | done (docs adopted, provisional calls in DECISIONS) |
| 2 Greybox run | done (Gate 2 played) |
| 3 Character art | done (Gate 3 approved: rig, hair v2, clothing, armour, weapons, fists) |
| 4 Animation | done (style bar approved; full matrix, hit variants, handling idles, projectiles) |
| 5 Presentation | done (title, marble hall + prep, animated element tiles, HUD in V8 language) |
| 6 Audio | done (procedural SFX, adaptive layered music from the author's loops) |
| 7 Balance & polish | in progress: picks, downtime redesign, randomized roster, objective map, readability + VFX passes (see HANDOFF / LEDGER) |

---

## How to read the lanes

- **Serial** — one track, because everything after depends on it.
- **Parallel** — independent lanes that can run at the same time; each lane
  says what it needs before it can start.
- A **gate** is where you look/play and say go, change, or stop.

---

## Phase 0 — Foundation  ·  serial

Nothing else in code can start until this exists.

1. Fresh project `game/`: `project.godot`, folder layout, `README.md`,
   `run.bat` / `test.bat` launch scripts.
2. Self-test runner: `godot --headless --path game -- --self-test` → structured
   report, non-zero exit on failure. Every later phase adds checks to it.
3. Lift combat logic from V8 (logic only, rewritten to the new rules where they differ):
   hex math, map loader (HexMapEditor JSON), speed turn queue, weapon table,
   weapon skills, element-on-tile charge grid, tile effects, progression bands.
4. New combat resolver with your formulas: HP, damage bases, hit/avoid,
   glance, crit, resist, three damage-taken formulas, affinity/opposites,
   XP/affinity/expertise awards. Every formula unit-tested, and each returns
   its own "formula / values / result" breakdown (the forecast hover needs it).
5. Terrain reduced to: neutral, grassy (spreads fire), muddy (2× move), jagged (impassable).

**Gate 0:** self-test green; you read a printed forecast for a sample fight
and the numbers feel right.

## Phase 1 — Paper  ·  parallel, can start alongside Phase 0

Docs only, no code; each is a reviewable file the game reads later.

| Lane | Output | Needs |
|---|---|---|
| Roster | 20 characters: name, weapon, element, stats 1–6, friendliness | — |
| Equipment & enchantments | every armor/weapon piece, 3 enchantments each, rank tiers E→A, stat bands, learnable abilities | — |
| Barks | friendly/neutral/unfriendly × ally attacking, ally KO, healing received, downtime advice; trust stages (meeting → squad) | Roster (for voice), but can draft by friendliness tag first |
| Element rules | tile behaviour per element, intensity thresholds, the opposites table | Phase 0 step 3 read of the charge grid |

**Gate 1:** you review the four documents. This is the cheapest point to change content.

## Phase 2 — The greybox adventure  ·  mostly serial

Capsule bodies, coloured hair blobs, white hexes with black borders, starfield.
Ugly on purpose — this is where we find out whether it's fun.

| Order | Piece | Parallel? |
|---|---|---|
| a | 5 maps (3v3 arena, paintball, Hyrule bridge, hill → ravine, one original), with spawns + elevation | **Parallel** with b–c once the map format is fixed in Phase 0 |
| b | Combat screen: speed turns, move-then-act / act-then-move, arrow + area highlight, forecast window with formula hover, simple enemy AI, win/lose | Serial |
| c | Combat cutscene v1: dim all but attacker, target and their tiles; FOV tighten; placeholder strike/react | After b |
| d | Pre-battle: review units, equip, pick 3, place in rows, Begin Battle | After b |
| e | Roster select (20 → 6), downtime (2 actions each, progress day, 5-second results scroll), shop trades, re-imbue (removed later, D202), loot table | After d |
| f | Run structure: title → roster → (pre-battle → combat → downtime) × 10 → boss | After e |

**Gate 2 — the important one:** you play a full run start to boss on placeholders.
We tune numbers and rules here, before any art is made to fit them.

## Phase 3 — Character art pipeline  ·  serial spine, then parallel

| Order | Piece | Parallel? |
|---|---|---|
| a | Base stick-figure rig in Blender, proportions from the references, outline shader, Blender → glTF → Godot round trip proven on one figure | **Serial** — every asset after this is built on this rig |
| b | Hair archetypes (10), clothing (14 × 3 greys), equipment (22 pieces × 7 element variants), weapons (22) | **Parallel** — four independent lanes, all on the rig from 3a |
| c | Dress the roster: hair + colour by element, clothing (every piece used), defaults | After roster (Phase 1) + 3b |

**Gate 3:** turntable renders of all 20 in game-scale and close-up.

## Phase 4 — Animation  ·  serial start, then fan out

1. Style bar first: idle → walk → strike → stricken, one figure, pushed until the bounce/flow reads right. **You review before anything else is animated.**
2. Then fan out in parallel: locomotion variants (heavy weapon, bow, limp), actions (strike per weapon class, cast, channel), reactions (stricken, kneel, block, fumble block, dodge, fall), celebrate. Plus the transitions between them.

**Gate 4:** you watch the clip matrix in game.

## Phase 5 — Presentation  ·  parallel once Phases 3–4 have assets

Title screen (fade in, orbiting the arena, "Black | White") · roster
semicircle with face/stat panels · downtime marble hall with spotlights and
poses · combat cutscene v2 with real animation, camera and weapon auras · tile
element shaders with intensity levels.

## Phase 6 — Audio  ·  parallel, any time after Phase 0

Blocked on two things only you can do (see below). Then: title loop, slowed
roster loop, adaptive combat music (drum layer + tempo up in combat, down
out of it), pitch-shifted barks per character.

## Phase 7 — Balance, polish, stabilise

Full-run playtests, formula tuning, boss tuning, visual verification renders,
perf, cleanup. Repeats until it matches the brief.

---

## What I need from you (not blocking Phase 0–2)

1. **Ableton exports.** From BlackWhite Loop and Low fish Beat, export each
   loop as WAV, **with drums and melody as separate stems** (File → Export
   Audio/Video → Selected tracks / All individual tracks). Stems are what make
   "add the drumline in combat" possible.
2. **The barks as WAV.** Godot can't read `.m4a`. Re-export them from
   Ableton (or any recorder) as WAV.
