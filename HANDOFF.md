# Handoff — 2026-10-08 (tutorial + glossary refresh; Keystones v3 and the kit passes committed)

**Where:** `C:\Users\ferth\Documents\Black White`. The game is in `game/` (Godot 4.7, GDScript). Phases 0–6 are done; we're in Phase 7 (balance and polish from playtests).

**Git:**
- `main` is the full internal history. Everything through D466 is committed (`8dacef2`: systems pass 5, weapon kits v2/v3, Keystones v3 + duo perks, the one-file Windows exe).
- **Uncommitted:** D467-D472 (this pass) and whatever the parallel balance lane has touched (`BWFormulas`, csv number columns, `ENEMY_CURVE`, `battle.gd`, `tools/campaign_sim.gd`). Commit them separately.
- The GitHub remote `origin` (`Willlifer/Black-White`) gets a **barebones export** on branch `github`: re-export in the `../bw-export` worktree, never by switching branches here (`git checkout main -- . ':!design/art/*.png' ':!design/art/*.gif' ':!design/audio/*.wav' ':!design/audio/*.png' ':!archive' ':!Visual References' ':!BlackWhite Loop Project' ':!Low fish Beat Project' ':!Audio Barks' ':!BlackWhite Loop.wav' ':!Drum Beat.wav' ':!Black and white concept..docx'`, `git rm` what main deleted, commit, `git push origin github:main`). Last export: internal `aa5ef11` → `cc156eb` (2026-10-06).

**Green as of 2026-10-08 (after D467-D472):** `--self-test` 820/820 in 74 suites with **zero SCRIPT ERROR lines**, `--tutorial-probe` 71/71, `--ui-probe` 105/105, `--flow-probe` exit 0. Run the tutorial probe alone (it fails "save untouched" if another probe writes run.json).

## This pass (D467-D472, LEDGER L-49)
- **Glossary (D467):** dead rows gone (Gale 3, Frozen); stale ones rewritten (fuse, guard, pinned, scorched, backstab, momentum, riposte, empowered, doomed, draw in, base move, divider, gale); new rows: Element cap, Ignite, Leviathos, Barrier, Blade Dance, Fissure, Set line. Skill names get no rows (D227 stops them; the codex and skill hovers carry them).
- **Tutorial (D468):** 48 steps, 10 lessons. Jericho is thunder + fire + ice (the cap); the wind lesson is dropped; the intro names "paint the ground, then cash it in with a reaction"; fuse ignition by any element; Unsteady + Shatter; a Thunder Surge finale; titles on the perk step.
- **Text (D469):** codex element cards (douse, ignite, Unsteady, wind push, keystone line), the picker subtitle, pistol mentions, the closing card, `packaging/README.txt` (one-file exe, controls, a rules summary).
- **Tests (D470):** the two stray SCRIPT ERRORs fixed (`test_enemy_curve` uses `run.roster_row`; `test_consume` expects the douse).
- **Nit (D471):** a Sculptor's pillar has a flat top, so its crown no longer pokes through the unit standing on it.
- **Renders (D472):** `design/art/tut3_*.png`; `--tutorial-probe` takes `SHOT_STEPS=id,id`.

## Balance pass (D473-D478, LEDGER L-50, design/BALANCE-2026-10-08.md; uncommitted, its own commit)
- Measured (sim ledger D473, `PICKS=random`, `tools/ledger_merge.gd`): healing is 7% of HP lost (not outsized); 0 stalls. Changed: **Fatigue** (heals ×0.5 from round 15, none from 20, D474), fight 3 3v3 scale 0.8, La Niña 1.5%, Obelisks 280, Twins ×2.0 HP / ×1.3 stats (7-8 rounds, were 14-18), Storm at 8 ×0.7. After: Standard 80%, Hard 53-68%, bosses 58-79%, the Giant 100%.
- The author rules on the BALANCE concerns (La Niña's pull, bows, duo perk rarity, Leviathan rarely submerging). Text lane owes a Fatigue feed line/glossary row and La Niña's 1.5% in the glossary.

## Earlier today (committed; details in DECISIONS)
- Keystones v3 (D443-D465, ELEMENTS.md §20, L-48): 14 keystones with titles, 8 duo perks, old keystones as enchantments, saves v13.
- Weapon kits v2/v3 (D425-D442), axe pass (D414-D416), systems pass 5 (D417-D424: 3 elements, Inversion r2, pistols/fists benched, steam removed, Pressured), fuses + one wind tile (D405-D410), ice rework (D397-D402).

## Do this first
1. **Commit** D467-D472, then D473-D478 (the balance lane) on its own.
2. **The author plays** the tutorial once (L-49) and a full run with Keystones v3 builds (L-48: a Lava Walker, an Abyssal / Hopekiller dark team, a Leviathan, a Sculptor ice team, a duo perk) and an ice team for Unsteady (L-44).
3. **The author answers** L-45 (keep Updraft / Tailwind's gale move and the squall push?) and the L-48 flags (Self-detonate on Superconductor, Leviathos's 7-hex body).
4. Cheap OWED while waiting: L-13 (the bow sling yoke, the planted staff).

## Known exposures
- Review renders (`design/art/*.png|gif`, ~250 MB+) live only in the local repo and on this disk. Back up `.git` (`git bundle create D:\backup\bw.bundle --all`).
- The sim's 16–24-run rates move about ±10 points per fight; read trends, not single cells.
