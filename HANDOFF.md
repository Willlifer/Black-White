# Handoff — 2026-10-05

**Where:** `C:\Users\ferth\Documents\Black White`. The game is in `game/` (Godot 4.7, GDScript). Phases 0–6 are done; we're in Phase 7 (balance and polish from playtests).

**Git:**
- `main` is the full internal history: everything except Godot caches and Ableton `.asd` files.
- The GitHub remote `origin` (`Willlifer/Black-White`) gets a **barebones export** on branch `github`, built on top of the remote's README commit. The export excludes `design/art/` renders, `Visual References/`, the raw Ableton projects, the root loop WAVs, `Audio Barks/` sources, `archive/` and the concept docx.
- Re-export after each internal commit: check out `github`, then `git checkout main -- <tracked paths minus the excludes>`, then commit and push.

**Green as of the last check:** `--self-test` (all suites), `--ui-probe`, `--flow-probe`, and autoplay with zero `SCRIPT ERROR`.

## What just landed (session 2026-10-05)
The whole design pass is in `history/2026-10-04_05-sessions.md`:
- perks and skill picks
- the downtime redesign (Specialize / Branch out / Wander)
- the randomized roster and rank-coloured hair
- the Obelisks fight 4
- the new HP formula and difficulty curve
- live portraits and the readability tools
- bow animation and arrows, cast VFX and hit feel

## Do this first
1. **The author plays a full run** (`game\run.bat`), then sends notes. Most open items are AWAITING PLAY (`LEDGER.md` L-1, L-3).
2. **Cheap OWED items while waiting:** L-6 (shader pre-warm), L-4 (helmets hide hair), L-9 (glossary links), L-10 (art docs name pass).
3. Keep `HANDOFF.md` ≤ 40 lines, and rewrite it at the end of each session.

## Known exposures
- Review renders (`design/art/*.png|gif`, ~250 MB) are only in the local repo and on this disk. Back up the `.git` folder (e.g. `git bundle create D:\backup\bw.bundle --all`) if the drive matters.
- DECISIONS numbers are handed out in reserved ranges to parallel agents. Check the file's last number before adding rows.
