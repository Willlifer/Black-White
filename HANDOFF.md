# Handoff — 2026-10-06

**Where:** `C:\Users\ferth\Documents\Black White`. The game is in `game/` (Godot 4.7, GDScript). Phases 0–6 are done; we're in Phase 7 (balance and polish from playtests).

**Git:**
- `main` is the full internal history: everything except Godot caches and Ableton `.asd` files.
- The GitHub remote `origin` (`Willlifer/Black-White`) gets a **barebones export** on branch `github`, built on top of the remote's README commit. The export excludes `design/art/` renders, `Visual References/`, the raw Ableton projects, the root loop WAVs, `Audio Barks/` sources, `archive/` and the concept docx.
- First push on 2026-10-05: internal `a20f29d` was exported as `03653ab` on GitHub `main`.
- 2026-10-06: internal `aa5ef11` was exported as `cc156eb`. The worktree `../bw-export` (branch `github`) is kept for future exports. After `git checkout main -- …`, also `git rm` any files that were deleted on main.
- **Re-export in a separate worktree, never by switching branches here.** Switching branches deletes the excluded files from this folder until you switch back:
  `git worktree add ../bw-export github`, then in `../bw-export` run `git checkout main -- . ':!design/art/*.png' ':!design/art/*.gif' ':!design/audio/*.wav' ':!design/audio/*.png' ':!archive' ':!Visual References' ':!BlackWhite Loop Project' ':!Low fish Beat Project' ':!Audio Barks' ':!BlackWhite Loop.wav' ':!Drum Beat.wav' ':!Black and white concept..docx'`, then commit and run `git push origin github:main`.

**Green as of the last check:** `--self-test` (all suites), `--ui-probe`, `--flow-probe`, and autoplay with zero `SCRIPT ERROR`.

## What just landed (2026-10-06)
- 2026-10-04/05 design pass: `history/2026-10-04_05-sessions.md`.
- Lanes: two choices per pick, no XP (D174–D179); two weapons and imbues (D180–D185); rooms, Standard/Hard (D186–D190).
- Finishing pass (D191–D195): **a lost fight levels the squad too** (LEVEL_ON_LOSS true); swaps are free and **unlimited**, shown as a ~0.5 s holster-and-draw (`design/art/weapons2_swap_strip.png`) with a tiny white class tag; enemies carry a second weapon from fight 3; Branch out's find is the fight's tier; XP/expertise-gate leftovers fixed.
- Re-tune (D194): enemy level = its stage; curve 0.85 0.95 1.7 0.7 1.25 0.9 1.1 1.0 0.97 1.0; Hard ×1.18. Sim: Standard 66–95 %, rounds 6–7 from fight 3, Giant 100 %. Fight 4 stuck at 45 % (L-18). Loose on purpose: re-tune after the enchantment/shop/encounter lanes (L-19).
- **Special encounters (D208–D214):** fights 1–2 skip the room screen (choice from fight 3). A third of the Hard rooms from fight 3 are an encounter (Horde of 10, Colossus on 7 hexes with a line thrust, Blanks immune to elements and ×2 from melee, Elemental Beings immune to physical), built at the squad's level, Hard pay. Physical vs elemental lives in `BWFormulas.damage_class`. Renders: `design/art/encounters_*.png`. Balance: L-20.
- **HP bars + card fit (D215–D218):** bars are black with white pips at/above 50%, white with black pips below, numbers only on hover, a pulse at the flip; over-unit bars clamp below the turn order; item cards fit unscrolled; no "Sword · Sword". Renders `design/art/hpbar_*.png` (`tools/hpbar_shots.gd`). Watch: L-21, L-22.
- **Cleanup + accessibility (D227–D232):** glossary stops (Charge, light/dark grey, Covering Fire); `hides_hair` per head piece; the gear panel fits 16:9; over-unit bars hide behind HUD panels; VFX shaders pre-warm offscreen at boot (`tools/prewarm_probe.gd`: worst first-use frame +26–29 ms → +2–3 ms); **Settings › Accessibility › Element kanji** (off by default): 火水氷雷風闇光 on tiles (weight = level), markers, cards, picks, rooms. Renders `design/art/a11y_*.png` (`tools/a11y_shots.gd`).

## Do this first
1. **The author plays a full run** (`game\run.bat`), then sends notes. Most open items are AWAITING PLAY (`LEDGER.md` L-1, L-3, L-20).
2. **Cheap OWED items while waiting:** L-10 (art docs name pass), L-8 (VFX polish). The author's read of the element kanji (D231) at play distance.
3. Keep `HANDOFF.md` ≤ 40 lines, and rewrite it at the end of each session.

## Known exposures
- Review renders (`design/art/*.png|gif`, ~250 MB) are only in the local repo and on this disk. Back up the `.git` folder (e.g. `git bundle create D:\backup\bw.bundle --all`) if the drive matters.
- DECISIONS numbers are handed out in reserved ranges to parallel agents. Check the file's last number before adding rows.
