# Handoff — 2026-10-09 (end of the 10-07 → 10-09 sessions)

**Where:** `C:\Users\ferth\Documents\Black White`, game in `game/` (Godot 4.7, GDScript). Phase 7: balance and polish from the author's playtests. The author verifies by playing; their feel is the goal, not the sim.

**Git (D489):** work on `dev`, finals merge `dev` → `main` **only when the author says "push a final"**. Internal `dev` is committed through D495 (`e00751d`); GitHub `dev` = `d305d1d`; GitHub `main` = `2672293` (the web build). Export in the `../bw-export` worktree (branch `github`), never by switching branches here: `git fetch origin && git merge origin/main && git merge origin/dev`, then `git checkout dev -- . <excludes>` (`':!design/art/*.png' ':!design/art/*.gif' ':!design/art/*.jpg' ':!design/audio/*.wav' ':!design/audio/*.png' ':!archive' ':!Visual References' ':!BlackWhite Loop Project' ':!Low fish Beat Project' ':!Audio Barks' ':!BlackWhite Loop.wav' ':!Drum Beat.wav' ':!Black and white concept..docx'`), `git rm` what dev deleted, commit, `git push origin github:dev`.

**Shipping:** a final = rebuild the browser build (`build_web.bat`, commit `web/`, D492; Vercel deploys GitHub main: https://black-white-game-pied.vercel.app/), export, push `github:dev` then `github:main`. GitHub `main` runs CI (D488: self-test, one-file exe, smoke test, GitHub Release). Local exe: `build_windows.bat` → `dist/BlackWhite-<date>.exe` (D466, one file, no zip). Another Claude session made the web build; an open Godot editor once overwrote `boot.gd` with a stale copy, so check edits survived before committing.

## What these sessions changed (details: DECISIONS D379–D495, `history/2026-10-07_09-sessions.md`)
- **Direction (author):** painting the board for you and against the enemy is the core fun. Every weapon paints its own way, and single-target "number" skills got cut. Identities: sword = mobile weaver of lines; axe = wide directional AoEs + big charges; lance = mobile utility; daggers = spellblade AoE (a risky staff); staff = safe painter; bow = remote trigger. **Pistol and fists benched.**
- **Elements:**
  - Ice: Unsteady replaces slides and rinks.
  - Fuses: any element ignites one.
  - Wind: one spread-only gale tile; Squall and Updraft kept.
  - Steam removed (fire + water douses).
  - Max 3 elements.
  - Inversion: radius 2, swap only.
  - Pressured: ranged −10% with a foe within 2.
  - Thunder rings take the colours of the consumed elements.
- **Kits:**
  - Sword: Riposte release, En Passant, Blade Dance (2), Thread the Needle, Tapestry.
  - Axe: Charge 7 + Momentum, Cleave widens, Sunder fissure, Reckless Arc, Bellow, Hook.
  - Lance Charge.
  - Daggers: Daggerleap away, Consume barrier, Fan of Knives r2, Overload, Kindle.
- **Keystones v3:** 14 (2 per element, at most 2 element keystones per unit), each giving a title. The old 21 became enchantments or were removed. 8 duo perks; the other pairs are shelved, as are weapon keystones. Leviathos uses the 1-hex fallback. Lava Walker: cap 4, reacts as fire 1.
- **Run:**
  - Rolling 27-name roster pool and a featured scroll.
  - Fatigue: heals halve at round 15 and stop at 20.
  - The Giant: 5000 HP, % effects on a 500 base, all 6 deploy, about 92% wins over 20 rounds.
  - HP bars by team.
  - Hair always shows under hats.
  - Pre-battle rows show real gear and elements.
- **Audio:** stings retuned to A (the C originals one switch away); music ducks under stings; 21 `ph_*` placeholders for the author to replace (`design/audio/AUDIO-NEEDS.md`).

## Do this first
1. **Wait for the author's playtest notes**, then act on them. Don't stress-test unasked.
2. On "push a final": run the Shipping steps above.
3. Waiting on play: Lava Walker 4 (L-52), Keystones v3 builds (L-48), the BALANCE-2026-10-08 concerns (L-50: La Niña +12, bows +7, duo perks rare, light tiles heal enemies), the tutorial with no wind lesson (L-49).
4. Deferred by the author: the AI pass (feel is fine), more duo pairs, weapon keystones, the true 7-hex Leviathos.

**Green (2026-10-09):** self-test 825/825, zero SCRIPT ERROR; ui-probe 119/119; flow-probe exit 0. Back up `.git` now and then (`git bundle create D:\backup\bw.bundle --all`); the review renders live only on this disk.
