# Handoff — 2026-10-07 (the Element Overhaul has landed)

**Where:** `C:\Users\ferth\Documents\Black White`. The game is in `game/` (Godot 4.7, GDScript). Phases 0–6 are done; we're in Phase 7 (balance and polish from playtests).

**Git:**
- `main` is the full internal history. The working tree holds the whole overhaul (lanes C1–C3 and this final pass) **uncommitted** on top of `f2ff1b1`: commit it as one "Element Overhaul" commit (or per lane) before the next session.
- The GitHub remote `origin` (`Willlifer/Black-White`) gets a **barebones export** on branch `github` (no `design/art/` renders, references, raw audio, `archive/`, the concept docx). Re-export in the `../bw-export` worktree, never by switching branches here: `git checkout main -- . ':!design/art/*.png' ':!design/art/*.gif' ':!design/audio/*.wav' ':!design/audio/*.png' ':!archive' ':!Visual References' ':!BlackWhite Loop Project' ':!Low fish Beat Project' ':!Audio Barks' ':!BlackWhite Loop.wav' ':!Drum Beat.wav' ':!Black and white concept..docx'`, `git rm` anything deleted on main, commit, `git push origin github:main`. Last export: internal `aa5ef11` → `cc156eb` (2026-10-06).

**Green as of 2026-10-07:** `--self-test` 643/643 in 57 suites, `--ui-probe`, `--flow-probe`, `--tutorial-probe` (exit 0), autoplay on arena, lake, tinderbox, catacombs, ravine, twins and obelisks with zero `SCRIPT ERROR`.

## What landed: the Element Overhaul (design/ELEMENTS-v3.md, the author's rulings at its top)
- **Spine (D261–D268):** ice slides and pillars, pools, steam, rinks, electrified water. ELEMENTS.md §14.
- **Wind and dark (D269–D276):** wind modes (Gust/Vortex/Becalm) on every weapon, fields, caps, Wind Wall; dark's Rot (curse) and gravity (void).
- **C1 (D277–D284):** the rank ladder (keystones at ranks 3 and 6, max 2), 21 keystones in `data/keystones.csv`, enemy keystones by stage, 28 perks, 2/3-piece element sets, save v11.
- **C2 (D285–D292):** fire Overheat, light beams/Empowered/Dawn, Prism, Overflow, Magnify, Static Blades, Blast Rider, Daisy Chain. ELEMENTS.md §15.
- **C3 (D293–D300):** wind, ice, water and dark keystones; the Twins float. ELEMENTS.md §16 (renumbered from §14.5–14.9, D305).
- **Final pass (D301–D308):**
  - Unit cards no longer leak BBCode: an `=` in a hint payload broke the tag (D301). Keystone cap enforced in `grant`; the old 3-keystone render was the shot tool (D302).
  - Recap and log sum per unit and cause; the banner always clears and review tools wait for it (D303).
  - The AI raises Wind Walls (D304). Magnify text and §16 docs fixed (D305).
  - **Self-detonate**, Blast Rider's free action, enables the dagger bomber dive (D306). All five L-30 riders are built (D307).
  - **Re-tune (D308):** curve 0.97 1.05 1.95 0.7 1.35 1.15 1.1 1.1 1.0 1.03, Twins HP ×2.6 / stats ×1.25. Sim (24 runs, Standard): 87 62 75 54 87 70 62 79 75 75 %, Hard 12–25 under, rounds 6–8 from fight 3, Giant 95%. Also fixed a reach-tree cycle that hung `path_to`.
- Review renders `design/art/v3_*.png`; this pass `v3_final_card*.png`, `v3_final_dive_1|2|3.png` (`tools/final_shots.gd`).
- **Squall + Overfreeze (D309-D314, ELEMENTS.md §17):** wind on light/dark 2+ sends a 3-tick front (+1, push 1 out); fresh ice on glazed water shatters (12%, rink, no pillar). LEDGER L-35; renders `v3_squall_*`, `v3_overfreeze_*` (`tools/squall_shots.gd`).

## Also landed: auto-equip (D315-D318, LEDGER L-35)
- Gear panel: **Optimize all [O]** (header; most-used unit first, may take from units used less) and **Optimize** (one unit, inventory only); a diff preview with Apply / Cancel, then one-step **Undo optimize**. Core `BWAutoEquip` (`src/core/auto_equip.gd`), `test_auto_equip`, ui-probe presses O → Apply → Undo. Renders `design/art/autoequip_*.png` (`tools/autoequip_shots.gd`).

## Also landed: 6v6 infrastructure (D319-D324, LEDGER L-36; the 6v6 modes lane, D325-D326, builds on it)
- Map `deploy_count` (3 default, 6 big) through setup, pre-battle (six slots, auto-placed, Auto), rooms, `campaign_sim` (MAP=commons) and `--combat`; big-board camera; 12-unit turn order; AI pruning on big maps only (worst turn ~500 → ~130 ms, `tools/sixes_perf.gd`). Test map **Commons** (17×15, not in the rotation). Green then: self-test 674/674 in 60 suites, both probes, `--combat commons --autoplay`. Renders `design/art/6v6_*.png`.

## Do this first
1. **Commit** the overhaul (see Git above).
2. **The author plays a full run** (`game\run.bat`) with keystone builds: dagger Blast Rider, a light beam team, a Rot/Doom team. Most rows are AWAITING PLAY: LEDGER L-24 (Twins), L-31, L-33, L-34 (this pass), L-18 (the Obelisks still 54%).
3. Cheap OWED items while waiting: L-10 (art docs name pass), L-8 / L-13 (VFX and animation nits).
4. Keep `HANDOFF.md` ≤ 40 lines, and rewrite it at the end of each session.

## Known exposures
- Review renders (`design/art/*.png|gif`, ~250 MB+) are only in the local repo and on this disk. Back up `.git` (`git bundle create D:\backup\bw.bundle --all`).
- The sim's 16–24-run rates move about ±10 points per fight; read trends, not single cells. A stray long-running `--self-test` Godot process (not started by this pass) was using CPU on 2026-10-07; check Task Manager if sims run slow.
