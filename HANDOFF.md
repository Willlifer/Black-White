# Handoff — 2026-10-09 (playtest fixes: the Split Front plate, Lava Walker 4, HP bars by team)

**Where:** `C:\Users\ferth\Documents\Black White`. The game is in `game/` (Godot 4.7, GDScript). Phases 0–6 are done; we're in Phase 7 (balance and polish from playtests).

**Git (D489):** work on `dev`; finals merge `dev` → `main`. Committed through D492 (the web build). **Uncommitted on `dev`: D493-D495 (this pass)** — the lead commits it on its own. GitHub export in the `../bw-export` worktree (branch `github`), never by switching branches here: `git fetch origin && git merge origin/main`, then `git checkout dev -- . <the excludes>` (`':!design/art/*.png' ':!design/art/*.gif' ':!design/art/*.jpg' ':!design/audio/*.wav' ':!design/audio/*.png' ':!archive' ':!Visual References' ':!BlackWhite Loop Project' ':!Low fish Beat Project' ':!Audio Barks' ':!BlackWhite Loop.wav' ':!Drum Beat.wav' ':!Black and white concept..docx'`), `git rm` what dev deleted, commit, `git push origin github:dev`. A final also pushes `github:main` (CI → a GitHub Release, D488).

## This pass (D493-D495, LEDGER L-52)
- **D493 the mode plate:** the Split Front / Horde plate (`prebattle/mode_plate.gd`, CanvasLayer 2) covered the gear panel's header and ate its clicks. It ignores the mouse now and hides while Equipment, the Shop or the codex is open, back on close. The ui-probe opens Equipment on a Split Front pre-battle, clicks a header option under the old plate rect, equips by double-click, and checks the Horde's plate under the Shop.
- **D494 Lava Walker:** cap 4 (`BWTiles.LAVA_MAX`). No fizzle: `BWTiles._lava_route` meets any other arrival as fire 1 and a reaction spends that step (lava n → n − 1): thunder a fire-1 blast (Powder Keg applies), water a douse, a gale carries fire 1 off, ice glazes, Inversion flips a step, a gale's water copy douses, squalls via `route_at`. Light / dark and another's fire don't react. Event `lava_react` replaces `fizzle`. The "fire 5 shows as fire 1" bug was the tile shader (dark crust, flames cut and faded); lava now draws hotter than 3. Keystone text, glossary (Fizzle row removed), ELEMENTS §20 + Powder Keg row updated.
- **D495 HP bars by team:** allies black with white pips over a dark-grey well, everyone else (enemies, Giant, Twins, stones) white with black pips over a light-grey well; the ghost / forecast cut is a grey past the well; outline kept; no 50% flip. `hp_bar.gdshader` `ally`, `BWHPBar3D.ally_side`, `BWWidgets.HPBar.palette`; `tests/test_hpbar_d495.gd`.
- Renders (looked at): `design/art/fix492_split_gear.png`, `fix492_split_back.png`, `fix492_lava4.png`, `fix492_hpbars.png` (`tools/fix492_shots.gd`).

**Green as of 2026-10-09 (after D493-D495):** `--self-test` 825/825 in 75 suites, zero SCRIPT ERROR; `--ui-probe` 119/119 exit 0; `--flow-probe` exit 0; `--combat splitfront --mode splitfront --divider fire --autoplay` ran to the end (9 rounds) with zero SCRIPT ERROR.

## Do this first
1. **Commit** D493-D495 on `dev`.
2. **The author plays** a Lava Walker build (is 4 + a step per reaction too big a nerf?) and a fight reading the new bars (L-52).
3. Still waiting on play: the Giant with six (L-51 settled), the tutorial (L-49), Keystones v3 builds (L-48), the BALANCE concerns (L-50), L-45.
4. Cheap OWED while waiting: L-13 (the bow sling yoke, the planted staff).

## Known exposures
- Review renders (`design/art/*.png|gif`, ~250 MB+) live only in the local repo and on this disk. Back up `.git` (`git bundle create D:\backup\bw.bundle --all`).
- The sim's 16–24-run rates move about ±10 points per fight; read trends, not single cells.
