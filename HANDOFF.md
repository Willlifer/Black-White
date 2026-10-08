# Handoff — 2026-10-08 (the 10× Giant, six against him)

**Where:** `C:\Users\ferth\Documents\Black White`. The game is in `game/` (Godot 4.7, GDScript). Phases 0–6 are done; we're in Phase 7 (balance and polish from playtests).

**Git:**
- `main` is the full internal history. Everything through D478 is committed (`f8641da`: tutorial + glossary refresh, the balance pass).
- **Uncommitted:** D485-D487 (this pass, the 10× Giant). Commit it on its own.
- The GitHub remote `origin` (`Willlifer/Black-White`) gets a **barebones export** on branch `github`: re-export in the `../bw-export` worktree, never by switching branches here (`git checkout main -- . ':!design/art/*.png' ':!design/art/*.gif' ':!design/audio/*.wav' ':!design/audio/*.png' ':!archive' ':!Visual References' ':!BlackWhite Loop Project' ':!Low fish Beat Project' ':!Audio Barks' ':!BlackWhite Loop.wav' ':!Drum Beat.wav' ':!Black and white concept..docx'`, `git rm` what main deleted, commit, `git push origin github:main`). Last export: internal `aa5ef11` → `cc156eb` (2026-10-06).

**Green as of 2026-10-08 (after D485-D487):** `--self-test` 822/822 in 74 suites, zero SCRIPT ERROR lines; `--flow-probe` exit 0; `--combat arena --boss --autoplay` (six units) ran to the end with zero SCRIPT ERROR; `build_windows.sh` built `dist/BlackWhite-2026-10-08.exe`. Run the tutorial probe alone (it fails "save untouched" if another probe writes run.json).

## This pass (D485-D487, LEDGER L-51)
- **The Giant has 5000 HP** (`BWRun.GIANT_HP`, its `fixed_hp`). CON is untouched: `fixed_hp` bypasses it and CON only feeds HP.
- **Percentages read 500:** `BWUnit.pct_base_hp()` (500 for the Giant, max HP otherwise) is the base of every "% of max HP" amount: tiles, reactions, slams, Doom, La Niña, arcs, Death Knell, heals, shields, the forecast, AI estimates, hit feel. Thresholds still read 5000. Breakdowns say "(% of 500, the Giant's pct base)".
- **No Fatigue in the Giant fight** (D486): 15/20 become 45/60 there, a stall backstop only (`BWBattle.giant_fight()`, `heal_fade()`).
- **HP bar:** pips are per 10% (D215), so 5000 reads like 500. Renders: `design/art/giant10_full.png`, `_62.png`, `_31.png` (`tools/giant10_shots.gd`).
- **Six against him** (D487, the author on L-51: "Bring the 6 man squad, no other changes"): `BWRun.GIANT_DEPLOY` 6 in `deploy_for` (min squad size); the arena keeps 3 for normal rooms. Render: `design/art/giant10_deploy6.png`.
- **Measured** (24 runs, same seeds): 500 HP / 3 deployed 100%, 5.4 rounds; 5000 / 3: 29%, 38.5 rounds, 2.5 deaths of 3; **5000 / 6 (current): 92%, 20.3 mean rounds (max 39), 2.5 deaths of 6.** L-51 settled.

## Earlier today (committed; details in DECISIONS)
- Balance pass D473-D478 (Fatigue, fight 3, La Niña 1.5%, Obelisks 280, Twins, Storm at 8; design/BALANCE-2026-10-08.md, L-50).
- Tutorial + glossary refresh D467-D472 (L-49). Keystones v3 D443-D465 (L-48). Weapon kits v2/v3, systems pass 5.

## Do this first
1. **Commit** D485-D487.
2. **The author plays a Giant fight** with the six: a ~20-round bag, won ~9 in 10 in the sim.
3. **The author plays** the tutorial (L-49) and a run with Keystones v3 builds (L-48), and rules on the BALANCE concerns (L-50), L-45 and the L-48 flags.
4. Cheap OWED while waiting: L-13 (the bow sling yoke, the planted staff).

## Known exposures
- Review renders (`design/art/*.png|gif`, ~250 MB+) live only in the local repo and on this disk. Back up `.git` (`git bundle create D:\backup\bw.bundle --all`).
- The sim's 16–24-run rates move about ±10 points per fight; read trends, not single cells.
