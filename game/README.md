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
| UI review frames | `godot --path . -- --ui-shots` (roster 0/3/6 picks, codex tabs, the boot screen (D381), results → `design/art/ui_*.png`) |
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
| Auto-equip (D315–D318) | rules `src/core/auto_equip.gd` (`BWAutoEquip`: priority, profile, `plan_all` / `plan_unit`, `apply` / `undo`) · tests `SUITE=test_auto_equip` · review frames: `[SHOTS=<dir>] godot --path . --resolution 1920x1080 --script res://tools/autoequip_shots.gd` (→ `design/art/autoequip_preview\|after\|unit\|hall.png`) · the ui-probe presses O → Apply → Undo |
| Tutorial (D223–D226) | `godot --path . -- --tutorial` (open it; title key T) · `[SHOTS=<dir>] godot --path . -- --tutorial-probe` (steps through all 50 steps with synthetic input and checks every lesson; exit 0 = ok; SHOTS → `tutorial_*.png`). The script is `src/game/tutorial/tutorial_script.gd` (steps as data, `dry_run()` on the rules); map `maps/tutorial/yard.json` |
| HP bars + item card fit (D215–D218) | `[SHOTS=<dir>] [MODE=combat\|cards] [RES=1920x1080] [TAG=_x] godot --path . --script res://tools/hpbar_shots.gd` (→ `design/art/hpbar_*.png`: combat above/below 50%, hover, the flip, the Colossus clamp, the shop and gear cards; RES opens a real window of that size) |
| Accessibility + cleanup review (D227–D232) | `[SHOTS=<dir>] [MODE=all\|board\|panel\|helm\|settings\|gear] godot --path . --resolution 1920x1080 --script res://tools/a11y_shots.gd` (element kanji on the board / cards, bars hidden behind the log, full helms, the Accessibility setting, the gear panel at 16:9 → `design/art/a11y_*.png`) |
| Shader pre-warm A/B (D232) | `[BW_PREWARM=0] godot --path . --resolution 1920x1080 --disable-vsync -s res://tools/prewarm_probe.gd` (each VFX shader's first-use frame, cold vs warmed; `BW_PREWARM=0` also turns the boot warm pass off, `BW_PREWARM_LOG=1` prints its cost) |
| Animation fit sweep + encounter motion (D219–D222) | `godot --headless --path . --script res://tools/anim_audit.gd` (every skill used once: its events and the clip it plays, `BWClipRoute`) · `godot --path . --resolution 1600x900 --script res://tools/anim2_shots.gd [-- --only colossus_walk\|colossus_thrust\|being\|horde\|blank\|jab]` (→ `design/art/anim2_*.png`) · one suite: `SUITE=test_animation [ONLY=test_markers] godot --headless --path . --script res://tools/one_suite.gd` |
| Playtest 1 fixes (D233–D238) | `[SHOTS=<dir>] godot --path . --resolution 1920x1080 --script res://tools/playtest1_shots.gd` (→ `design/art/playtest1_*.png`: the gear panel's discard pile, the grid sorted by Element, the shop's free scrolls and the scroll flow, the hall's drawn first perks) |
| Ice/water spine (D261–D268) | review frames: `RES=1920x1080 [SHOTS=<dir>] [ONLY=slide,walk,pillar,steam,shock,rink] godot --path . --script res://tools/icewater_shots.gd` (→ `design/art/v3_icewater_*.png`: a Charge shoving onto a rink with its slide ghost and SLAM, the slam played, a walk ending in a slide, a pillar blocking a shot, a steam pool, the electrified preview and the live field with its ramp, a radius-1 rink with pillars) · one suite: `SUITE=test_icewater`. Rules: ELEMENTS.md §14 |
| Boss fight | `godot --path . -- --combat arena --boss` |
| Weather (D249–D254) | `godot --path . -- --combat <map> --autoplay --weather rain\|ashfall\|eclipse\|blizzard\|gale` · review frames: `[SHOTS=<dir>] [ONLY=rain,gale] godot --path . --resolution 1920x1080 --script res://tools/weather_shots.gd` (→ `design/art/weather_<kind>.png`) · the room card: `WEATHER=<kind> FIGHT=5 … room_shots.gd` (→ `weather_room.png`) · balance: `RUNS=12 POLICY=mixed ROOMS=mixed WEATHER=1 campaign_sim` (paired clear sky vs each weather, fights 5–10). Rules: design/WEATHER.md |
| The Twins (D255–D260) | `godot --path . -- --combat twins --autoplay` (a run at fight 4, its first three, on the court; also `--boss twins`; D355: a card at fight 4 against the Obelisks) · fast balance: `[RUNS=n] [TWINS=hp,mult] [TRACE=1] godot --headless --path . --script res://tools/twins_sim.gd` (whole run: `BOSS=twins STOP_AT=4 campaign_sim`, env TWINS) · review frames: `[SHOTS=<dir>] godot --path . --resolution 1920x1080 --script res://tools/twins_shots.gd` (→ `design/art/twins_*.png`) · one suite: `SUITE=test_twins` |
| 6v6 (D319–D324) | `godot --path . -- --combat commons --autoplay` (six a side on Commons, the map's `deploy_count`; prints a PERF line: AI turns, frames) · whole run: `MAP=commons RUNS=1 TRACE_SIM=1 campaign_sim` (every fight on that map, worst AI turn per fight) · AI cost: `[FIGHT=6] [SEEDS=3] [BOARD=commons\|big19\|both] [CAPS=hexes,targets] godot --headless --path . --script res://tools/sixes_perf.gd` (`CAPS=0,0`: no pruning) · review frames: `godot --path . --resolution 1920x1080 --script res://tools/sixes_shots.gd` (→ `design/art/6v6_*.png`) · one suite: `SUITE=test_sixes`. A map fields `deploy_count` a side (absent = 3; design/MAPS.md) |
| 6v6 modes (D327–D334) | Split Front: `godot --path . -- --combat splitfront --mode splitfront [--divider fire\|ice\|wind] --autoplay` · Stop the Horde: `… --combat horde --mode horde [--fight n] --autoplay` (a run's six levelled to the fight; PERF line) · balance: `RUNS=n POLICY=mixed [SIX=1] [STOP_AT=5] [SPLIT=mult,wind_hp] [HORDE=grunt_mult,grunt_hp,elite_mult[,fella_pct]] campaign_sim` (SIX=1: every 6v6 mode paired at fights 8 and 10) · review frames: `[ONLY=split\|horde] godot --path . --resolution 1920x1080 --script res://tools/mode_shots.gd` (→ `design/art/mode_split_*.png`, `mode_horde_*.png`) · the Horde alone on campaign squads (D351): `CAMPAIGN=<snapshot dir> MODE=horde [HORDE=grunt_mult,grunt_hp,elite_mult,fella_pct] [WAVES=c:g:e;...] castle_sim` · Horde renders: `ONLY=horde … mode_shots.gd` (→ `horde2_group_move\|fella_flee\|fella_close\|plate.png`) · **group turns** (D347): give units a shared `group_turn` key; the mode's `group_order` sets the resolve order; the screen plays the block at once (`_play_group`) · one suite: `SUITE=test_objectives`. The framework: `BWObjectives` (src/core/objectives.gd; objects, verdicts, waves, exits); a mode is one `BWObjectiveMode` file listed in `BWObjectives.MODES`; the schedule is `BWSchedule.TABLE` (D353, design/MAPS.md "The schedule") |
| Schedule (D353–D358) | `BWSchedule` (src/core/schedule.gd): `TABLE` fight → cards (single, standard, hard, obelisks, twins, split, six, giant), `SIX_POOL` and the no-repeat `draw_six`; `BWRooms` rolls the cards (`cards`, `roll`, `room_for`, `battle_opts` for the Split Front divider) · the second Split Front map: `python tools/split_maps.py` (→ `maps/fords.json`), `--combat fords --mode splitfront [--divider ice]` · card renders: `FIGHT=4\|5\|8 NAME=sched_fight4 godot --path . --resolution 1600x900 --script res://tools/room_shots.gd` · sim: `RUNS=n POLICY=mixed ROOMS=mixed [SEED0=n] [BOSS=obelisks\|twins] campaign_sim` (D353 card policy; prints "by card" win rates) · one suite: `SUITE=test_schedule` |
| Castle modes (D335–D342) | Defend: `godot --path . -- --combat keep --mode defend [--fight n] --autoplay` · Storm: `… --combat stronghold --mode storm --autoplay` (a run's six levelled to the fight; PERF line) · maps: `python tools/castle_maps.py` (builds and checks `keep.json` and `stronghold.json`: the 2-turn perch rule, the gate the only ground way in) · balance on real squads: `SNAPSHOT=<dir> RUNS=n POLICY=mixed campaign_sim` (saves the six before fights 8 and 10), then `CAMPAIGN=<dir> [MODE=defend\|storm] [FIGHT=8,10] [GATE=x] [EMULT=x] [EHP=x] [SLOW=1] godot --headless --path . --script res://tools/castle_sim.gd` (win rate, rounds, endings, AI turn times; without CAMPAIGN it plays quick `--mode` squads) · `CASTLE="d_gate,d_mult,d_hp,s_gate,s_mult,s_hp" campaign_sim` · review frames: `[SHOTS=<dir>] godot --path . --resolution 1920x1080 --script res://tools/castle_shots.gd` (→ `design/art/mode_defend_*.png`, `mode_storm_*.png`) · one suite: `SUITE=test_castle`. Rules: `BWCastle` (src/core/castle.gd: high ground, the gate, the march AI, the soldiers), `BWCastleDefend`, `BWCastleStorm`; look: `BWCastleView`, `BWCastleObjectView` |
| Weapon movement (D359–D364, D371–D374) | rules `src/core/weapon_move.gd` (`BWWeaponMove`: move by the class drawn at turn start, jump 2 / lance 4, the Rough-Footed trait, pickable weapon passives (HighGrounder: `PASSIVES`, offered by `BWPicks` as "passive:<id>", stored in `known_skills`, no slot), high ground) and `data/weapons.csv` `move`, `jump`, `traits`, `passives` · tests `SUITE=test_weapon_move` · what jump 1 / 2 / 4 open per map and the reach cost: `godot --headless --path . --script res://tools/jump_maps.gd` · HighGrounder pick and a lance climbing 4: `RES=1920x1080 [ONLY=pick,lance,bow] godot --path . --script res://tools/jump2_shots.gd` (→ `design/art/jump2_*.png`) · review frames: `RES=1920x1080 [SHOTS=<dir>] [ONLY=lance,bow,axe,leap] godot --path . --script res://tools/move_shots.gd` (→ `design/art/move_lance\|bow\|axe\|leap.png`) · D375 free climbs within the jump; D376/D377 Updraft (Tailwind: +1 jump, +1 on its holder's gales; `BWWeaponMove.updraft*`), tests `test_free_climb_within_jump`, `test_updraft_*`, renders `RES=1920x1080 ONLY=updraft … tools/updraft_shots.gd` (→ `updraft_ally|holder.png`) |
| Wind and dark (D269–D276) | rules `src/core/wind_modes.gd` (`BWWind`: modes, fields, caps, Wind Wall, AI mode) and `src/core/curse.gd` (`BWCurse`: Rot, gravity); view `combat/wind_view.gd` (`BWWindView`: field marks, walls, the gravity swirl, Rot marks, the forecast's mode toggle) · tests `SUITE=test_wind_dark` · review frames: `[SHOTS=<dir>] [ONLY=fields,toggle,cleave,wall,rot,gravity] godot --path . --resolution 1920x1080 --script res://tools/wind_dark_shots.gd` (→ `design/art/v3_wind_*.png`, `v3_dark_*.png`) · Wind Wall is the wind_wall keystone (D293) |
| Wind shaping (D365–D370) | rules `src/core/wind_shape.gd` (`BWWindShape`: shapes, options, `pre` / `post`, gale equivalents, the AI's ≤ 4 sims); view `combat/wind_shape_view.gd` (`BWWindShapeView`: the WIND SHAPING strip, mouse side / arrows / Tab / wheel, board arrows, ghosts, SLAM and INTO-hazard tags) · tests `SUITE=test_wind_shape` · the ui-probe parts a wind Ley Line right with → · review frames: `[SHOTS=<dir>] [ONLY=ley,rain,single] godot --path . --resolution 1920x1080 --script res://tools/wind_shape_shots.gd` (→ `design/art/wind2_ley_left\|right\|blast.png`, `wind2_rain_draw\|burst.png`, `wind2_single_push\|hold.png`). Rules: ELEMENTS.md §18 |
| Fire, light, thunder (D285–D292) | rules `src/core/overheat.gd` (`BWOverheat`: Overheat, Conflagration, Trailblazer, Phoenix Heart), `src/core/beams.gd` (`BWBeams`: beams, Empowered, Dawn, Prism, Overflow, Magnify), `src/core/thunder_keys.gd` (`BWThunderKeys`: Static Blades, Blast Rider, Daisy Chain); view `combat/elements_view.gd` (`BWElementsView`) · tests `SUITE=test_fire_light_thunder` · review frames: `[SHOTS=<dir>] [ONLY=overheat,beam,magnify,blades,rider] godot --path . --resolution 1920x1080 --script res://tools/flt_shots.gd` (→ `design/art/v3_fire_*.png`, `v3_light_*.png`, `v3_thunder_*.png`) · grant a keystone for review with `u.keystones = ["<id>"]` or `u.fx["ks:<id>"] = true`. Rules: ELEMENTS.md §15 |
| Polish pass 3 (D343–D346) | word floaters `src/game/combat/floaters.gd` (`BWFloaters`: small stacked tags, the turn-order clamp for every floater), names `combat/name_labels.gd` (`BWNameLabels`: focus names full size, others where they fit), Rot marks in `wind_view.gd`, the dark squall in `squall_view.gd`; Overfreeze once per action (`test_overfreeze_once_per_action`) · review frames: `[SHOTS=<dir>] [ONLY=sixes,rot,floaters,threes] godot --path . --resolution 1920x1080 --script res://tools/polish3_shots.gd` (→ `design/art/polish3_6v6_midfight\|floaters\|rot\|3v3_names\|rot_3v3.png`); the chain + immune and dark squall frames are `final_shots.gd ONLY=dive` / `squall_shots.gd ONLY=dark` with SHOTS= |
| Squall, Overfreeze (D309–D314) | rules `src/core/squall.gd` (`BWSquall`), `src/core/overfreeze.gd` (`BWOverfreeze`); view `combat/squall_view.gd` (`BWSquallView`) · tests `test_squall_overfreeze` · review frames: `[SHOTS=<dir>] [ONLY=light,dark,freeze] godot --path . --resolution 1920x1080 --script res://tools/squall_shots.gd` (→ `design/art/v3_squall_*.png`, `v3_overfreeze_*.png`). Rules: ELEMENTS.md §17 |
| Wind, ice, water and dark keystones (D293–D300) | rules `src/core/ks_wind.gd`, `ks_ice.gd`, `ks_water.gd`, `ks_dark.gd` (battle hooks: `keystone_fx.gd`, BWKeystoneFx); action defs `flash_freeze`, `tidal_release`, `glacier_shatter` (Break Pillar), Wind Wall now needs the keystone (`BWKeystones.grant(u, "wind_wall")`); view `combat/keystone_view.gd` (BWKeystoneView: Frozen, Doom, gale 3, the wave, tags on the HP bar) · tests `SUITE=test_keystones_c3` · review frames: `[SHOTS=<dir>] [ONLY=eye,freeze,glacier,tidal,doom,rot,twins] godot --path . --resolution 1920x1080 --script res://tools/keystones_c3_shots.gd` (→ `design/art/v3_c3_*.png`). Rules: ELEMENTS.md §16 |
| Overhaul final pass (D301–D308) | Blast Rider's free **Self-detonate** (def `self_detonate`, `BWThunderKeys.self_det_ready` / `self_detonate`), the L-30 riders (Sunpath beam move, Static Field `fuse_guard`, Gale Force mode, Wildfire wild ring, Water set pools 25), the AI's Wind Wall (`BWKsWind.ai_wall`), summed recap / log lines, the banner fix (`BWCombatUI.banner_gone`, review tools await it) · tests in `test_fire_light_thunder` (self_detonate, dagger_dive, l30_riders) and `test_keystones_c3` (ai_wind_wall, keystone_cap) · review frames: `[SHOTS=<dir>] [ONLY=card,dive] godot --path . --resolution 1920x1080 --script res://tools/final_shots.gd` (→ `design/art/v3_final_card.png`, `_card_enemy`, `v3_final_dive_1\|2\|3.png`) · the campaign sim prints per-keystone win rates (D308) |
| Special encounters (D208–D213) | `godot --path . -- --combat <map> --encounter horde\|colossus\|blank\|being [--fight n] --autoplay` (a squad levelled to fight n, default 5) · review frames: `[SHOTS=<dir>] [FIGHT=n] godot --path . --resolution 1920x1080 --script res://tools/encounter_shots.gd` (→ `design/art/encounters_*.png`: horde, colossus, blank, being, immune, blank_x2) · room cards: `ENC=<kind> FIGHT=5 godot --path . --resolution 1600x900 --script res://tools/room_shots.gd` (→ `encounters_room_<kind>.png`) · balance: `RUNS=n POLICY=mixed SHADOW=1 ENC=1 [ENC_TUNE=...] campaign_sim` |
| Audio capture | `godot --path . -- --audio-capture` (61 s scripted run → `design/audio/capture.wav`; analyse with `python tools/audio/analyse_capture.py`) |
| Rebuild SFX / music layers | `python tools/audio/make_sfx.py` · `python tools/audio/make_music.py`, then `--import` (see design/audio/AUDIO.md); both re-run `make_drop2.py` (the author's drop 2, D239–D241) |
| Drop 2 audio capture (D242) | `godot --path . -- --drop2 --audio-capture` (87 s → `design/audio/capture_drop2.wav`; `python tools/audio/analyse_drop2.py`) |
| Hair rank review (D146–D148) | `godot --path . --resolution 1800x1250 -s res://tools/hair_ranks_preview.gd` (→ `design/art/hair_ranks_*.png`) |
| Portraits (D156) | `godot --path . -s res://tools/portrait_shots.gd [-- --cold] [--res 1920x1080] [--out <dir>]` (every roster unit, the Giant, the stones, a rank-up, helmets at 104→34 px; `--cold` clears the cache and prints first-render cost) · live feeds mid-hit: `-s res://tools/live_portrait_shots.gd` · frame cost A/B: `BW_FRAME_LOG=1 BW_LIVE_BENCH=1 [BW_LIVE=0] godot --path . --disable-vsync -- --combat arena --autoplay` |
| Bow shots and arrows (D164–D166) | `godot --path . --resolution 1600x900 -s res://tools/ranged_preview.gd` (→ `design/art/ranged_bow_sheet.png`) · `SHOTS=<dir> MODE=flat\|arcing\|rain\|split\|pierce\|pin\|throw\|perf godot --path . --script res://tools/ranged_shots.gd`, then `python tools/ranged_strip.py <dir>/<mode>_frames ../design/art/ranged_<mode> 12` |
| Rebuild rig | `blender -b --python tools/blender/build_base_rig.py` (see design/art/RIG.md) |
| Obelisks (D140–D145) | `godot --path . -- --combat obelisks --autoplay` · balance and the fight-4 damage scale: `[RUNS=n TRIES=n POLICY=mixed OB_HP= PULSE_L= PULSE_W= ENEMIES= TRACE=1] godot --headless --path . --script res://tools/obelisk_sim.gd` · D378 shared pool (`BWBattle.stone_pool`, `_stones_sync`; tune with `OB_HP`): review frames `RES=1920x1080 ONLY=obelisks godot --path . --script res://tools/updraft_shots.gd` (→ `obelisk_shared_plate|card.png`) · review frames: `godot --path . --script res://tools/obelisk_shots.gd` (→ `design/art/obelisks_*.png`) · models: `blender -b --factory-startup --python tools/blender/build_obelisks.py` |

## Building a Windows release (D395, D396)

- Once: Godot 4.7 stable export templates in `%APPDATA%\Godot\export_templates\4.7.stable\`
  (`windows_release_x86_64.exe` etc., from the official `Godot_v4.7-stable_export_templates.tpz`; installed 2026-10-07).
- From the repo root: `build_windows.bat` (or `./build_windows.sh` in Git Bash; `GODOT` overrides the binary).
  It imports, exports preset **"Windows Desktop"** to `dist/BlackWhite-<date>/` (`BlackWhite.exe`,
  `BlackWhite.pck`, `BlackWhite.console.exe`, `README.txt` from `packaging/README.txt`) and zips it to
  `dist/BlackWhite-<date>.zip` (~72 MB). Send the zip; the exe needs the pck beside it. `dist/` is git-ignored.
- Check it: `dist\BlackWhite-<date>\BlackWhite.console.exe -- --combat obelisks --autoplay` (0 `SCRIPT ERROR`),
  or `-- --shot <dir> --count 4` for title frames.
- Self-test on an export: `build_windows.bat tests` → a debug export with `tests/` in `dist/selftest/`, then
  `dist\selftest\BlackWhite.console.exe --headless -- --self-test`. Raw-file suites fail there by design (D396).
- Filters: FileAccess-loaded files (`*.csv`, `*.json`, `*.txt`) are included explicitly; `tools/`, test suites,
  `art/source/`, `art/icon/` are left out. A new data file of another extension loaded by path needs adding to the
  preset's include filter. Saves: `%APPDATA%\Godot\app_userdata\Black - White\`.
- Before the final build: bake animations (`tools/build_anims.gd`) if the game warns "BWAnimClips … stale".

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
maps/          Map JSON, in the HexMapEditor format plus "spawns"/"deploy"/"deploy_count" (D319).
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
  slides.gd      BWSlides — ice slides (D261): slide_path (pure), walking slides in reachable(), push slides, slams
  pools.gd       BWPools — pools, steam, rinks, electrified water and ice pillars (D262–D265, ELEMENTS §14); view: combat/icewater_view.gd
  weather.gd     BWWeather — the room weather tag and its cycle-tick rules (D249–D254, design/WEATHER.md); view: combat/weather_view.gd
  rooms.gd       BWRooms — the cards before each fight from fight 3 (D186–D189, D208, D353): rolls BWSchedule's cards, the map queue, Hard tuning and pay
  schedule.gd    BWSchedule — the run schedule as data (D353): fight -> cards, the 6v6 pool and its no-repeat draw (D356)
  phases.gd      BWPhases — the boss phase framework (D255): a data script of phases (HP thresholds, KOs with a delay)
                 whose rules a boss reads; the battle state is BWBattle.boss; battle hooks dispatch per boss kind
  twins.gd       BWTwins — the Twins, a boss card at fight 4 (D256-D258, D355): paint, own-colour heal, the beam, swap, rage, AI, reward
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
                 downtime, end card; boot (D381: over the shader pre-warm, fades onto the title);
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
