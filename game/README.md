# Black | White — game project

Godot **4.7 standard** (not .NET), GDScript only. No plugins, no addons.

## Run

| What | Command |
|---|---|
| Play | `run.bat`, or open this folder in Godot and press F5 |
| Self-test | `test.bat`, or `godot --headless --path . -- --self-test` |
| Balance sheet | `godot --headless --path . -- --forecast` |
| One fight, AI vs AI | `godot --path . -- --combat arena --autoplay [--carry]` (exits 2 s after the battle; `--carry`: everyone carries a second weapon, D195) |
| One screen | `godot --path . -- --screen roster` (title, roster, prep, prebattle, downtime, results) |
| Fixed roster roll (D154) | add `--seed N` to any run: the roster screen opens on that roll (R re-rolls reproducibly), a new run uses it; probes, shots and the self-test default to seed 1 |
| Hall / title review frames | `SHOTS=<dir> MODE=hall\|prep\|progress\|title [GIF=<dir>] godot --path . --script res://tools/phase5_shots.gd` (→ `phase5_*.png`; GIF frames for `phase5_progress_day.gif`) |
| Save frames | add `--shot <dir> --every 1.0 --count 8` to any windowed run |
| Input probe | `godot --path . -- --ui-probe` (clicks/keys through combat, the pause menu + settings, F, hold-to-skip, a glossary hover; exit 0 = ok) |
| Battle / run summary frames (D119–D121) | `[SHOTS=<dir>] godot --path . --script res://tools/summary_shots.gd` (a real AI-played run → `design/art/summary_win\|loss\|run.png`) |
| UI review frames | `godot --path . -- --ui-shots` (roster 0/3/6 picks, codex tabs, loading, results → `design/art/ui_*.png`) |
| Flow probe | `godot --path . -- --flow-probe` (every screen transition, the drawn first perks (D233), the hall prep's equip and give, the discard pile and sorting (D234/D235), a free scroll (D236), the downtime choices, the day, the per-unit result cards and their pickers; exit 0 = ok) |
| Downtime review (D127–D132) | `[SHOTS=<dir>] [MODE=hall\|cards] godot --path . --script res://tools/downtime2_shots.gd` (→ `design/art/downtime2_*.png`) |
| Two-choice review (D174–D176) | `[SHOTS=<dir>] godot --path . --script res://tools/choice2_shots.gd` (→ `design/art/choice2_*.png`: the hall's 2 tiles with the Branch out cards, a 2-card perk and skill pick) |
| Campaign sim | `RUNS=n [POLICY=mixed] [ROOMS=standard\|hard\|mixed\|all] godot --headless --path . --script res://tools/campaign_sim.gd` (downtime policies specialize / branch / wander / mixed; room policy D188, win rate per room kind per fight) |
| Room select (D186–D190) | `godot --path . --resolution 1600x900 --script res://tools/room_shots.gd` (→ `design/art/rooms_select.png`, `rooms_hover.png`; env FIGHT (default 3: fights 1–2 have no choice, D208), SEED, ENC) · `-- --screen rooms` |
| Presentation review (D100–D102) | `RES=1920x1080 SHOTS=<dir> MODE=callout\|crit\|status\|clip [SLOW=6] [CLIP=spin UNIT=pip] godot --path . --script res://tools/present_shots.gd`; `python tools/present_strip.py <dir>/crit_frames <dir>` (crit strip + GIF) |
| Readability review (D160–D163) | `RES=1920x1080 [SHOTS=<dir>] godot --path . --script res://tools/readability_shots.gd` (blast preview, confirm box, slow beat, recap, tile cards → `design/art/read_*.png`) |
| UX pass review (D122–D126) | `RES=1920x1080 [SHOTS=<dir>] [MODE=all\|settings\|pause\|gloss\|codex\|tiers] godot --path . --script res://tools/ux_shots.gd` (→ `design/art/ux_*.png`) |
| Default settings | add `--defaults` to any run: ignore `user://settings.cfg` (probes, the self-test and review tools always do) |
| Fight pace | `godot --headless --path . -- --pace [--support]` (`--support`: every kit carries its class's support skills, D112) |
| UI pass review (D109–D113) | `RES=1920x1080 SHOTS=<dir> [MODE=all\|callout\|odds] godot --path . --script res://tools/uipass_shots.gd` (→ `uipass_*.png`) |
| Cast / spectacle VFX review (D167–D170) | `RES=1600x900 SHOTS=<dir> [MODE=all\|surge\|ley\|tempest\|dive\|elements\|fists\|chamber\|spin\|warcry\|siphon\|saturate\|bolt\|truth\|triumph] godot --path . --script res://tools/vfx_shots.gd` (prints a Tempest frame-time readout), then `python tools/vfx_strip.py <dir>` → `design/art/casts_*.png` (design/art/VFX.md) |
| Weapons pass review (D180–D182) | `[SHOTS=<dir>] [MODE=gear\|carry] [VIEWS=back,front,side] godot --path . --resolution 1920x1080 --script res://tools/weapons2_shots.gd` (gear panel with two weapon slots, the imbued card, carried weapons → `design/art/weapons2_*.png`; the combat menu before / after a swap: `SWAP_SHOTS=<dir> godot --path . -- --ui-probe`) |
| Enchantments v2 + shop review (D196–D205) | `[SHOTS=<dir>] [MODE=shop\|knell] godot --path . --resolution 1920x1080 --script res://tools/ench2_shots.gd` (the shop with its featured scrolls, a scroll card, the scroll flow, a cursed card, a Death Knell KO → `design/art/ench2_*.png`) |
| Tutorial (D223–D226) | `godot --path . -- --tutorial` (open it; title key T) · `[SHOTS=<dir>] godot --path . -- --tutorial-probe` (steps through all 50 steps with synthetic input and checks every lesson; exit 0 = ok; SHOTS → `tutorial_*.png`). The script is `src/game/tutorial/tutorial_script.gd` (steps as data, `dry_run()` on the rules); map `maps/tutorial/yard.json` |
| HP bars + item card fit (D215–D218) | `[SHOTS=<dir>] [MODE=combat\|cards] [RES=1920x1080] [TAG=_x] godot --path . --script res://tools/hpbar_shots.gd` (→ `design/art/hpbar_*.png`: combat above/below 50%, hover, the flip, the Colossus clamp, the shop and gear cards; RES opens a real window of that size) |
| Accessibility + cleanup review (D227–D232) | `[SHOTS=<dir>] [MODE=all\|board\|panel\|helm\|settings\|gear] godot --path . --resolution 1920x1080 --script res://tools/a11y_shots.gd` (element kanji on the board / cards, bars hidden behind the log, full helms, the Accessibility setting, the gear panel at 16:9 → `design/art/a11y_*.png`) |
| Shader pre-warm A/B (D232) | `[BW_PREWARM=0] godot --path . --resolution 1920x1080 --disable-vsync -s res://tools/prewarm_probe.gd` (each VFX shader's first-use frame, cold vs warmed; `BW_PREWARM=0` also turns the boot warm pass off, `BW_PREWARM_LOG=1` prints its cost) |
| Animation fit sweep + encounter motion (D219–D222) | `godot --headless --path . --script res://tools/anim_audit.gd` (every skill used once: its events and the clip it plays, `BWClipRoute`) · `godot --path . --resolution 1600x900 --script res://tools/anim2_shots.gd [-- --only colossus_walk\|colossus_thrust\|being\|horde\|blank\|jab]` (→ `design/art/anim2_*.png`) · one suite: `SUITE=test_animation [ONLY=test_markers] godot --headless --path . --script res://tools/one_suite.gd` |
| Playtest 1 fixes (D233–D238) | `[SHOTS=<dir>] godot --path . --resolution 1920x1080 --script res://tools/playtest1_shots.gd` (→ `design/art/playtest1_*.png`: the gear panel's discard pile, the grid sorted by Element, the shop's free scrolls and the scroll flow, the hall's drawn first perks) |
| Boss fight | `godot --path . -- --combat arena --boss` |
| Weather (D249–D254) | `godot --path . -- --combat <map> --autoplay --weather rain\|ashfall\|eclipse\|blizzard\|gale` · review frames: `[SHOTS=<dir>] [ONLY=rain,gale] godot --path . --resolution 1920x1080 --script res://tools/weather_shots.gd` (→ `design/art/weather_<kind>.png`) · the room card: `WEATHER=<kind> FIGHT=5 … room_shots.gd` (→ `weather_room.png`) · balance: `RUNS=12 POLICY=mixed ROOMS=mixed WEATHER=1 campaign_sim` (paired clear sky vs each weather, fights 5–10). Rules: design/WEATHER.md |
| The Twins (D255–D260) | `godot --path . -- --combat twins --autoplay` (a run at fight 7, its first three, on the court; also `--boss twins`) · fast balance: `[RUNS=n] [TWINS=hp,mult] [TRACE=1] godot --headless --path . --script res://tools/twins_sim.gd` (whole run: campaign_sim's fight 7 row, env TWINS) · review frames: `[SHOTS=<dir>] godot --path . --resolution 1920x1080 --script res://tools/twins_shots.gd` (→ `design/art/twins_*.png`) · one suite: `SUITE=test_twins` |
| Special encounters (D208–D213) | `godot --path . -- --combat <map> --encounter horde\|colossus\|blank\|being [--fight n] --autoplay` (a squad levelled to fight n, default 5) · review frames: `[SHOTS=<dir>] [FIGHT=n] godot --path . --resolution 1920x1080 --script res://tools/encounter_shots.gd` (→ `design/art/encounters_*.png`: horde, colossus, blank, being, immune, blank_x2) · room cards: `ENC=<kind> FIGHT=5 godot --path . --resolution 1600x900 --script res://tools/room_shots.gd` (→ `encounters_room_<kind>.png`) · balance: `RUNS=n POLICY=mixed SHADOW=1 ENC=1 [ENC_TUNE=...] campaign_sim` |
| Audio capture | `godot --path . -- --audio-capture` (61 s scripted run → `design/audio/capture.wav`; analyse with `python tools/audio/analyse_capture.py`) |
| Rebuild SFX / music layers | `python tools/audio/make_sfx.py` · `python tools/audio/make_music.py`, then `--import` (see design/audio/AUDIO.md); both re-run `make_drop2.py` (the author's drop 2, D239–D241) |
| Drop 2 audio capture (D242) | `godot --path . -- --drop2 --audio-capture` (87 s → `design/audio/capture_drop2.wav`; `python tools/audio/analyse_drop2.py`) |
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
**pause menu** (D124: resume, settings, codex & glossary, quit) · T ends the turn · **Swap weapon** (menu, under Attack) draws the carried weapon: free, as often as you like (D181, D195) · F11 / Alt+Enter toggles fullscreen.

Cutscenes (D122/D123): basic attacks, counters, setup skills and skills aimed at the ground that hurt nobody (D237) play in place; quick skills zoom
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
  progression.gd BWProgression — levels (one per fight, won or lost, D179/D194), affinity, expertise
  turn_queue.gd  BWTurnQueue — speed order
  battle.gd      BWBattle — one fight as rules; emits events for the view
  skills.gd      BWSkills — the skills' tuning numbers, statuses, reactions (lookups are facades)
  skill_def.gd / skill_registry.gd / skill_defs/   BWSkillDef, BWSkillRegistry: one file per skill (D89)
  picks.gd       BWPicks — element perks (data/perks.csv) and weapon-skill picks (D90, D91)
  effects.gd     BWEffects — enchantments + abilities → battle hooks
  enchant_v2.gd  BWEnchant — the v2 keys (on_event, pity, drawback, swap), the loop caps (design/ENCHANTMENTS-v2.md)
  ai.gd          BWAI — enemy turns (and the obelisks' pulses, D145)
  obelisk.gd     BWObelisk — the neutral objective stones of the Obelisks map (D140–D145)
  battle_stats.gd BWBattleStats — the end-of-battle summary, tallied from battle.history (D119–D121)
  run.gd         BWRun — one run: squad, items, loot, downtime, shop + imbuement scrolls (D203), saves (v8)
  weather.gd     BWWeather — the room weather tag and its cycle-tick rules (D249–D254, design/WEATHER.md); view: combat/weather_view.gd
  rooms.gd       BWRooms — the room choice before each fight from fight 3 (D186–D189, D208): two rooms, the map queue, Hard tuning and pay
  phases.gd      BWPhases — the boss phase framework (D255): a data script of phases (HP thresholds, KOs with a delay)
                 whose rules a boss reads; the battle state is BWBattle.boss; battle hooks dispatch per boss kind
  twins.gd       BWTwins — the Twins at fight 7 (D256-D258): paint, own-colour heal, the beam, swap, rage, AI, reward
  encounters.gd  BWEncounters — special encounters in the Hard room's place (D208–D212): Horde, Colossus, Blanks, Elemental Beings;
                 the damage classes are BWFormulas.damage_class (D209)
  roster_gen.gd  BWRosterGen — the roster roll: weapon, element, stats (class profiles), clothes from a seed (D150–D152)
  barks.gd       BWBarks — picks bark lines (design/BARKS.md)
  forecast_sheet.gd  the Gate 0 balance printout
  data.gd        BWData — CSV loader
src/game/      Presentation. Reads core, never the reverse.
  game.gd        BWGame — the run's screen flow and autosave
  combat/        board view, unit views (BWCharacter; use_rig=false = primitives), HUD, combat screen + cutscene
  screens/       title, roster, prep (the hall before fight 1, D84), room select (D190; rooms/map_thumbs.gd = BWMapThumbs), pre-battle, results,
                 downtime, end card; loading (the old map-orbit intro, unused since D84);
    downtime/    BWHall (the marble hall: floor + reflection, columns, windows, spotlights,
                 time of day) and the downtime widgets (the three choice tiles, chips, the arrow), D83/D127;
                 codex.gd = BWCodex, the rules overlay: `BWCodex.summon(self, "weapons")`, Esc closes
    prebattle/   item icons (rendered from the glbs, cached), item tile + card, paperdoll,
                 stat panel, unit hover card, gear and shop panels (D77, D78); the discard pile (D234);
                 inv_sort.gd = BWInvSort, the grids' sort (D235);
                 review renders: tools/prebattle_shots.gd
  portraits.gd   BWPortraits — head-and-shoulders snapshots per look, memory + user://portraits/v1 (D156);
                 BWWidgets.Portrait draws them, BWWidgets.LivePortrait is the big panels' live feed
  look.gd        BWLook — palette and shared materials
  esc.gd         BWEsc — the Esc stack: every closable window registers; Esc closes the newest (D171)
  text.gd        BWText — display names: `label(id)`, `weapon(wc)`, sentence case (D172)
  settings.gd    BWSettings — user://settings.cfg: volumes, display, cutscene mode, readouts (D124)
  glossary.gd    BWGlossary — data/glossary.csv → hoverable [hint] terms; Rich / TipButton (D125) and stop phrases (D227)
  kanji.gd       BWKanji — the element kanji setting (D231): glyphs, BBCode, the subset font (art/fonts/bw_kanji.ttf, OFL, CREDITS.txt);
                 combat/kanji_layer.gd = BWKanjiLayer, the kanji on the tile tops
  shader_warm.gd BWShaderWarm — the boot-time offscreen VFX shader pre-warm (D232)
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
