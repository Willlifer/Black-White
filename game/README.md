# Black | White — game project

Godot **4.7 standard** (not .NET), GDScript only. No plugins, no addons.

## Run

| What | Command |
|---|---|
| Play | `run.bat`, or open this folder in Godot and press F5 |
| Self-test | `test.bat`, or `godot --headless --path . -- --self-test` |
| Balance sheet | `godot --headless --path . -- --forecast` |
| One fight, AI vs AI | `godot --path . -- --combat arena --autoplay` |
| One screen | `godot --path . -- --screen roster` (title, roster, prep, prebattle, downtime, results) |
| Fixed roster roll (D154) | add `--seed N` to any run: the roster screen opens on that roll (R re-rolls reproducibly), a new run uses it; probes, shots and the self-test default to seed 1 |
| Hall / title review frames | `SHOTS=<dir> MODE=hall\|prep\|progress\|title [GIF=<dir>] godot --path . --script res://tools/phase5_shots.gd` (→ `phase5_*.png`; GIF frames for `phase5_progress_day.gif`) |
| Save frames | add `--shot <dir> --every 1.0 --count 8` to any windowed run |
| Input probe | `godot --path . -- --ui-probe` (clicks/keys through combat, the pause menu + settings, F, hold-to-skip, a glossary hover; exit 0 = ok) |
| Battle / run summary frames (D119–D121) | `[SHOTS=<dir>] godot --path . --script res://tools/summary_shots.gd` (a real AI-played run → `design/art/summary_win\|loss\|run.png`) |
| UI review frames | `godot --path . -- --ui-shots` (roster 0/3/6 picks, codex tabs, loading, results → `design/art/ui_*.png`) |
| Flow probe | `godot --path . -- --flow-probe` (every screen transition, the hall prep's equip and give, the downtime choices, the day, the per-unit result cards and their pickers; exit 0 = ok) |
| Downtime review (D127–D132) | `[SHOTS=<dir>] [MODE=hall\|cards\|rogue] godot --path . --script res://tools/downtime2_shots.gd` (→ `design/art/downtime2_*.png`) |
| Campaign sim | `RUNS=n godot --headless --path . --script res://tools/campaign_sim.gd` (policies specialize / branch / wander / mixed) |
| Presentation review (D100–D102) | `RES=1920x1080 SHOTS=<dir> MODE=callout\|crit\|status\|clip [SLOW=6] [CLIP=spin UNIT=pip] godot --path . --script res://tools/present_shots.gd`; `python tools/present_strip.py <dir>/crit_frames <dir>` (crit strip + GIF) |
| Readability review (D160–D163) | `RES=1920x1080 [SHOTS=<dir>] godot --path . --script res://tools/readability_shots.gd` (blast preview, confirm box, slow beat, recap, tile cards → `design/art/read_*.png`) |
| UX pass review (D122–D126) | `RES=1920x1080 [SHOTS=<dir>] [MODE=all\|settings\|pause\|gloss\|codex\|tiers] godot --path . --script res://tools/ux_shots.gd` (→ `design/art/ux_*.png`) |
| Default settings | add `--defaults` to any run: ignore `user://settings.cfg` (probes, the self-test and review tools always do) |
| Fight pace | `godot --headless --path . -- --pace [--support]` (`--support`: every kit carries its class's support skills, D112) |
| UI pass review (D109–D113) | `RES=1920x1080 SHOTS=<dir> [MODE=all\|callout\|odds] godot --path . --script res://tools/uipass_shots.gd` (→ `uipass_*.png`) |
| Cast / spectacle VFX review (D167–D170) | `RES=1600x900 SHOTS=<dir> [MODE=all\|surge\|ley\|tempest\|dive\|elements\|fists\|chamber\|spin\|warcry\|siphon\|saturate\|bolt\|truth\|triumph] godot --path . --script res://tools/vfx_shots.gd` (prints a Tempest frame-time readout), then `python tools/vfx_strip.py <dir>` → `design/art/casts_*.png` (design/art/VFX.md) |
| Boss fight | `godot --path . -- --combat arena --boss` |
| Audio capture | `godot --path . -- --audio-capture` (61 s scripted run → `design/audio/capture.wav`; analyse with `python tools/audio/analyse_capture.py`) |
| Rebuild SFX / music layers | `python tools/audio/make_sfx.py` · `python tools/audio/make_music.py`, then `--import` (see design/audio/AUDIO.md) |
| Hair rank review (D146–D148) | `godot --path . --resolution 1800x1250 -s res://tools/hair_ranks_preview.gd` (→ `design/art/hair_ranks_*.png`) |
| Portraits (D156) | `godot --path . -s res://tools/portrait_shots.gd [-- --cold] [--res 1920x1080] [--out <dir>]` (every roster unit, the Giant, the stones, a rank-up, helmets at 104→34 px; `--cold` clears the cache and prints first-render cost) · live feeds mid-hit: `-s res://tools/live_portrait_shots.gd` · frame cost A/B: `BW_FRAME_LOG=1 BW_LIVE_BENCH=1 [BW_LIVE=0] godot --path . --disable-vsync -- --combat arena --autoplay` |
| Bow shots and arrows (D164–D166) | `godot --path . --resolution 1600x900 -s res://tools/ranged_preview.gd` (→ `design/art/ranged_bow_sheet.png`) · `SHOTS=<dir> MODE=flat\|arcing\|rain\|split\|pierce\|pin\|throw\|perf godot --path . --script res://tools/ranged_shots.gd`, then `python tools/ranged_strip.py <dir>/<mode>_frames ../design/art/ranged_<mode> 12` |
| Rebuild rig | `blender -b --python tools/blender/build_base_rig.py` (see design/art/RIG.md) |
| Obelisks (D140–D145) | `godot --path . -- --combat obelisks --autoplay` · balance and the fight-4 damage scale: `[RUNS=n TRIES=n POLICY=mixed OB_HP= PULSE_L= PULSE_W= ENEMIES= TRACE=1] godot --headless --path . --script res://tools/obelisk_sim.gd` · review frames: `godot --path . --script res://tools/obelisk_shots.gd` (→ `design/art/obelisks_*.png`) · models: `blender -b --factory-startup --python tools/blender/build_obelisks.py` |

## Controls (combat)

Temporal Sea V8's camera (D49): left-drag orbits (pitch 15–85°), right- or
middle-drag pans, wheel zooms, arrows pan, Space recentres, Q/E rotate 60°.
Left click: move to a grey hex, attack a pulsing enemy, or aim a skill from
the menu beside the unit (forecast opens; hover a number for its formula).
Enter confirms · Esc first closes the newest open window (a tooltip, card, codex, panel, menu, D171), then backs out one step: forecast → second pick (Transfer,
Grapple Throw, D109) → aiming → **undo the move** (D48) → with nothing left to back out of, the
**pause menu** (D124: resume, settings, codex & glossary, quit) · T ends the turn · F11 / Alt+Enter toggles fullscreen.

Cutscenes (D122/D123): basic attacks, counters and setup skills play in place; quick skills zoom
briefly; long-cooldown and once-per-battle skills, crits and KOs get the full cutscene. **Hold Space
(or the right mouse button) to fast-forward** any playback; **F** cycles Default → Fast → Minimal.
Hover any dotted-underlined word (forecast, unit cards, gear, picks, codex) for its definition (D125).
Readability (D160–D163): while you aim, the board shows the action's whole outcome (hatched hexes that
detonate / glaze / gale / spread, chain-arc arches, a damage sticker on every unit it touches, red on your
own side; "−96" exact, "≈96" an expected value); hover any hex for its tile card; after a big action a recap line sits
by the log (and the full detail goes into it); detonations and arcs get a short slow-motion beat.
Settings: title screen **S**, or the pause menu (`user://settings.cfg`).

Both `.bat` files expect Godot at
`%USERPROFILE%\Downloads\Godot_v4.7-stable_win64.exe\`; set `GODOT` to point
elsewhere.

The self-test prints PASS/FAIL per suite and writes a JSON report to
`user://self_test_report.json`. It exits 0 when everything passes and 1 when
anything fails, including data errors.

## Layout

```
data/          CSV tables (the contract is design/SCHEMA.md). Editable in Excel.
maps/          Map JSON, in the HexMapEditor format plus "spawns"/"deploy".
src/core/      The framework: pure rules, no nodes. Usable in another game.
  hex.gd         BWHex — odd-r hex math (from Temporal Sea V8)
  board.gd       BWBoard — terrain, elevation, movement, line of sight
  tiles.gd       BWTiles — elements on the ground (design/ELEMENTS.md)
  formulas.gd    BWFormulas — every combat number, each with its explanation
  unit.gd        BWUnit — a character sheet plus battle state
  progression.gd BWProgression — XP, levels, affinity, expertise
  turn_queue.gd  BWTurnQueue — speed order
  battle.gd      BWBattle — one fight as rules; emits events for the view
  skills.gd      BWSkills — the skills' tuning numbers, statuses, reactions (lookups are facades)
  skill_def.gd / skill_registry.gd / skill_defs/   BWSkillDef, BWSkillRegistry: one file per skill (D89)
  picks.gd       BWPicks — element perks (data/perks.csv) and weapon-skill picks (D90, D91)
  effects.gd     BWEffects — enchantments + abilities → battle hooks
  ai.gd          BWAI — enemy turns (and the obelisks' pulses, D145)
  obelisk.gd     BWObelisk — the neutral objective stones of the Obelisks map (D140–D145)
  battle_stats.gd BWBattleStats — the end-of-battle summary, tallied from battle.history (D119–D121)
  run.gd         BWRun — one run: squad, items, loot, downtime, shop, saves (v5: the run's roster roll)
  roster_gen.gd  BWRosterGen — the roster roll: weapon, element, stats (class profiles), clothes from a seed (D150–D152)
  barks.gd       BWBarks — picks bark lines (design/BARKS.md)
  forecast_sheet.gd  the Gate 0 balance printout
  data.gd        BWData — CSV loader
src/game/      Presentation. Reads core, never the reverse.
  game.gd        BWGame — the run's screen flow and autosave
  combat/        board view, unit views (BWCharacter; use_rig=false = primitives), HUD, combat screen + cutscene
  screens/       title, roster, prep (the hall before fight 1, D84), pre-battle, results,
                 downtime, end card; loading (the old map-orbit intro, unused since D84);
    downtime/    BWHall (the marble hall: floor + reflection, columns, windows, spotlights,
                 time of day) and the downtime widgets (the three choice tiles, chips, the arrow), D83/D127;
                 codex.gd = BWCodex, the rules overlay: `BWCodex.summon(self, "weapons")`, Esc closes
    prebattle/   item icons (rendered from the glbs, cached), item tile + card, paperdoll,
                 stat panel, unit hover card, gear and shop panels (D77, D78);
                 review renders: tools/prebattle_shots.gd
  portraits.gd   BWPortraits — head-and-shoulders snapshots per look, memory + user://portraits/v1 (D156);
                 BWWidgets.Portrait draws them, BWWidgets.LivePortrait is the big panels' live feed
  look.gd        BWLook — palette and shared materials
  esc.gd         BWEsc — the Esc stack: every closable window registers; Esc closes the newest (D171)
  text.gd        BWText — display names: `label(id)`, `weapon(wc)`, sentence case (D172)
  settings.gd    BWSettings — user://settings.cfg: volumes, display, cutscene mode, readouts (D124)
  glossary.gd    BWGlossary — data/glossary.csv → hoverable [hint] terms; Rich / TipButton (D125)
  combat/vfx_casts.gd, hit_feel.gd  BWVfxCasts (cast circles, element releases, spectacles), BWHitFeel (shake, hit-stop, numbers, final-KO slow-mo), D167–D170
  combat/cutscene_tier.gd  BWCutsceneTier — event → minimal / short / full (D122)
  combat/readability.gd    BWReadability — blast preview driver, tile card, recap, slow beat (D160–D163);
  combat/blast_preview.gd  BWBlastPreview draws BWBattle.simulate (the action on a clone, expected rolls)
  screens/settings_panel.gd, pause_menu.gd   BWSettingsPanel, BWPauseMenu (D124)
  music.gd / voice.gd   loops and pitch-shifted barks
  character/     BWCharacterRig (base rig), hair, clothing, armour, weapons;
                 BWCharacter assembles them, BWCharacterPose poses them
                 (design/art/CHARACTERS.md)
  ui_probe.gd / flow_probe.gd   drive the real game with synthetic input
shaders/       flat (with per-instance dim), outline, starfield, marble_floor + light_cone (the hall)
audio/         the author's loops and barks (copied from the project root)
tests/         test_*.gd suites, run by self_test.gd
tools/         keep_csv.py — run after adding a CSV (see below)
```

## Rules for working here

- **Core never touches nodes.** The battle emits events (`move`, `attack`,
  `paint`, `detonate`, `ko` …). The view replays them. The self-test plays
  whole fights headless with the same calls.
- **Every combat number comes from BWFormulas**, and each one carries its
  formula and values for the hover window.
- **New CSV table → run `python tools/keep_csv.py`.** By default Godot
  imports CSVs as translation tables, and the self-test fails if one slips
  through.
- **Adding a weapon skill** (D89): one file `src/core/skill_defs/<key>.gd` that
  `extends BWSkillDef`, calls `define({key, name, weapon, cd, targeting, range, desc, clip, power, …}, order)`
  in `_init`, and overrides only the hooks it changes (`plan`, `forecast_mods`, `ground`, `after_paint`,
  `ai_score` …; read `upgraded(u)` for an Improve rider). The registry loads it; it joins its class's
  learnable pool. Add one test in `tests/` that previews and resolves it. Perks: a row in `data/perks.csv`.
- **Engine hooks for skills** (D97, `BWSkillDef`, all no-ops by default):
  - `zone(b, u, p, hex) -> Array`: hexes `u` holds until its next turn. Enemy movement
    entering one stops there (it can't path through); `on_zone_enter(b, holder, mover)` fires.
  - `overwatch(b, u, p) -> int`: a radius. The first enemy action attacking an ally within it
    (before the holder's next turn) draws the holder's basic attack after it resolves, if in
    range (`overwatch` + a `counter` event, cause "overwatch"); `on_overwatch` may answer instead.
  - `place(b, v, hex)` / `BWBattle.place_unit`: set `v` on a free, in-bounds, non-jagged hex
    (Grapple Throw). No crossing damage; immune displace refuses.
  - `b.add_status(v, "pinned", u)`: any status from the table (Pinned = −2 move).
  - **Second pick** (D109): row `"second_pick": "hex"` + `second_targets(b, u, el, target)`; the
    player's choice reaches `plan` as `p.choice` (`BWBattle.NOWHERE` = choose automatically, which
    is what the AI passes). `skill_preview` / `use_skill` take it as an optional last argument.
  - `strike_preview(b, u, p)`: a strike made through `attack()` after the skill (Vault), shown in
    the confirm box (D110). Damaging self-centred skills always confirm.
  - `ai_support(b, u, row) -> {target, element, score}`: a support skill the AI may spend its
    action on (D112); a granted basic follow-up is added by BWAI. Free actions use `ai_free_wanted`.
- **Element perks** (D93): a row in `data/perks.csv` with a key from `BWEffects.KEYS`; the
  rules are ELEMENTS.md §13. `tools/enemy_stats.gd` prints fight 1/5/9 enemy squads (D99); the per-fight enemy curve is `BWRun.ENEMY_CURVE` (D133).
- **The roster is identity + roll** (D150). `data/roster.csv` holds names, gender, seat, hair,
  friendliness, voice and element locks; `BWData.table("roster")` is the active roll
  (`BWRosterGen.roll`, seed 1 by default). A run uses its own `roster_rows`. Tests needing one
  particular kit use `BWRosterKits.unit(id)` (tests/roster_kits.gd). On the select screen R re-rolls.
- **Seeds reproduce.** All randomness goes through the battle's `rng`, so the
  same seed gives the same fight, event for event.
