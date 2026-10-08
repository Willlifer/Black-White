# Black | White

A B/W stick-figure hex tactics game in Godot 4.7 (GDScript). Pick 6 of 20,
fight 10 battles 3v3 with downtime between, then face the Giant. There's no
story and no main character. Hair colour (= element) is the only hue.

The author's original brief is preserved verbatim in `design/KICKOFF.md`.
It is **historical**: many of its numbers and rules were later changed (see
DECISIONS). Read it for intent, never for current rules.

## Start here

1. `HANDOFF.md`: the state right now, and what to do first.
2. `LEDGER.md`: what is owed, blocked, waiting on play, or settled.
3. Open only the docs your task needs (table below).

## Which doc answers what (and which wins)

| Doc | Answers | Lifespan |
|---|---|---|
| `design/*.md` | **What the game is now**: rules, elements, skills, picks, roster, maps, art and audio specs. **Current truth.** | Edited in place |
| `DECISIONS.md` | **Why and when** a rule became what it is, and who ruled (Author vs Claude). Append-only; superseded rows are marked. | Permanent |
| `LEDGER.md` | What's owed, blocked, awaiting play, or watched. One row per item. | Weeks |
| `HANDOFF.md` | State now and what to do first. Rewritten each session, ≤ 40 lines. | One session |
| `PLAN.md` | The phase plan and phase status. | Project |
| `game/README.md` | How to run, test, render reviews, and add content (skills, perks, maps). | Edited in place |
| `history/` | Session summaries, for orientation only. | Permanent |

If a design doc and DECISIONS disagree, the design doc is current, unless the
DECISIONS row is newer and the doc wasn't updated. Then fix the doc.

## Run and verify

The console binary is `C:\Users\ferth\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe`.
Run from `game/`:

- `--headless --path . --import`, after adding scripts or classes
- `--headless --path . -- --self-test`: all suites, exit 0 or 1, JSON report. **Must be green.**
- `--path . -- --ui-probe` / `-- --flow-probe`: windowed synthetic input. Both must exit 0.
- `--path . -- --combat <map> --autoplay [--shot dir]`: watch or capture a fight. Zero `SCRIPT ERROR` lines.
- `--headless --path . --script res://tools/campaign_sim.gd` (env RUNS, POLICY): a whole-run balance sim.
- Review renders go to `design/art/` (local only; the GitHub repo excludes them).

`--seed N` fixes the roster roll and the map order. Probes and tests default to seed 1.

## Standing author preferences

These are durable and easy to get wrong:

- **The author verifies by playing** and by looking at renders. Show images and say what you looked at. Never claim visuals you didn't see.
- **Extend the established style; don't reinvent it.** It's B/W, low poly, with inked outlines; hair and element FX carry the only colour.
- **Go easy on "−hit" and dodge stacking** (the author: "not a hard rule, just don't go crazy on dodges or combat will feel bad"). Modest values are fine; prefer statuses that change options (no skills, no crit, reach, move).
- **Builds want rule-changers, not small numbers.** The author's playstyle is combo and kiting. Passives that only add a few percent feel ignorable; each element needs keystones that define an archetype (Element Overhaul, design/ELEMENTS-v3.md).
- **No announced personalities.** Personality is discovered; element and weapon carry it.
- **Randomness wants agency.** Random rolls are welcome, but offer a choice where a build is at stake (e.g. Branch out's two cards).
- **"If we win, we win."** The Giant isn't forced to be unbeatable.
- **Minor ambiguities:** make the call that makes the game more fun, log it in DECISIONS as Claude, and keep going. Ask only when it's genuinely the author's decision.
- **Reviews on mobile:** the author often reviews through Remote Control, so long write-ups go in a Claude Doc or artifact.

## Project rules

- The rules core (`game/src/core`) never touches nodes. Every number goes through `BWFormulas` with a breakdown. Seeds reproduce.
- Content is data: `game/data/*.csv` (imported as "keep"), skills are one file each in `src/core/skill_defs/`, and maps are JSON.
- Parallel agents: give each an owned file set and a reserved DECISIONS number range. Shared files get small Edit-tool edits only.
- Git (D489): **work on `dev`, ship finals to `main` (production).** Internal repo: commit on `dev`; for a final, merge `dev` into `main`. GitHub (`Willlifer/Black-White`) gets a barebones export (no review renders, references, raw audio projects or archive) via the `../bw-export` worktree: routine pushes go to GitHub `dev`, finals to GitHub `main`. Every push to GitHub `main` runs CI (`.github/workflows/release.yml`, D488): import, self-test, export, smoke test, then a GitHub Release with the exe. A red run publishes nothing. Push to `main` only when the author asks for a final. See `HANDOFF.md`.
