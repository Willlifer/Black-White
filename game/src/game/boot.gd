extends Node
## Entry point. User args (after `--`):
##   --self-test                 run the deterministic self-test and exit (0 = green)
##   --forecast                  print the balance sheet and exit
##   --pace [--support]          AI-vs-AI fight pace (--support: support skills in every kit, D112)
##   --combat <map>              jump straight into a fight on maps/<map>.json
##   --autoplay                  let the AI play the player side too (exits 2 s after the battle ends)
##   --carry                     every unit also carries a second weapon (another class, D193/D195: swaps)
##   --boss                      fight the Giant instead
##   --encounter <kind> [--fight n]  a special encounter (horde|colossus|blank|being, D208)
##   --mode splitfront|horde|defend|storm [--fight n] [--divider fire|ice|wind]  a 6v6 mode with a run's six (D327-D333; use with --combat)
##                               against a squad levelled and geared to fight n (default 5)
##   --weather <kind>            D249: the fight's weather (rain|ashfall|eclipse|blizzard|gale)
##   --shot <dir> [--every s] [--count n]   save n real rendered frames, then quit
##   --screen <title|roster|prep|rooms|prebattle|downtime|results|boot>   open one screen on a sample run (boot: D381, held at 67%)
##   --ui-probe                  drive combat with synthetic input and check it responds
##   --tutorial                  open the tutorial (D223); --tutorial-probe steps through all of it
##                               with synthetic input (SHOTS=<dir>: review frames), exit 0 = completed
##   --flow-probe                walk the real game through every screen transition
##   --ui-shots [dir]            render roster / codex / boot / results review frames
##                               to <dir>/ui_*.png (default design/art), then quit
##   --audio-capture [dir]       record a scripted 61 s run (title, roster, combat, boss)
##                               from the Master bus to <dir>/capture.wav + capture.json
##                               (default design/audio); analyse with tools/audio/analyse_capture.py
##   --drop2 --audio-capture [dir]   D242: the drop-2 run (title, hall, rooms, pre-battle, picker,
##                               shop, cursed, jackpot, tutorial, combat, boss, victory, defeat) ->
##                               capture_drop2.wav/.json; tools/audio/analyse_drop2.py
##   --duck --audio-capture [dir]    D411: the sting duck run -> capture_duck*.wav/.json;
##                               tools/audio/analyse_duck.py
##   --seed N                    D154: the roster roll's seed (BWRosterGen): the roster screen
##                               opens on it, a new run and every tool use it; also the
##                               --combat fight seed. Probes, shots and the self-test
##                               default to BWRosterGen.DEFAULT_SEED; play is random.
##   --defaults                  ignore user://settings.cfg this run (and never write it);
##                               every probe, the self-test and the shot tools imply it (D124)
## With no args the game starts normally.

const REPORT_PATH := "user://self_test_report.json"
## D124: runs that must not see (or change) the player's saved settings.
const ISOLATED_FLAGS := ["--defaults", "--self-test", "--pace", "--forecast", "--ui-probe", "--flow-probe",
	"--ui-shots", "--audio-capture", "--shot", "--autoplay", "--tutorial-probe"]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if OS.has_feature("web"):
		BWWebInstanceShim.install(get_tree())                                  # ---- D492: WebGL instance-uniform cap
	BWSettings.init(Array(args).any(func(a): return a in ISOLATED_FLAGS))     # ---- D124
	_seed_roster(args)                                                         # ---- D154
	if "--self-test" in args:
		_self_test.call_deferred()
		return
	if "--pace" in args:
		print(BWPaceReport.render(40, "--support" in args))
		get_tree().quit(0)
		return
	if "--forecast" in args:
		print(BWForecastSheet.render())
		get_tree().quit(0)
		return
	# Sound for every windowed path: buses, SFX, the listeners, the music (Phase 6).
	BWMusic.ensure(self)
	BWEsc.ensure(self)                              # ---- D171: Esc closes the newest open window
	BWSettings.apply_all()                          # ---- D124: volumes (buses exist now), window, UI size
	BWShaderWarm.start(self)                        # ---- D232 (L-6): VFX shaders warm offscreen under the first screen
	for n in [BWMusic._inst, BWSfx._inst]:          # ---- D124: music and UI sounds carry on under the pause menu
		if n and is_instance_valid(n):
			n.process_mode = Node.PROCESS_MODE_ALWAYS
	if "--audio-capture" in args:
		var ac := BWAudioCapture.new()
		ac.drop2 = "--drop2" in args                # D242: the author's drop 2 cues and stings
		ac.placeholders = "--placeholders" in args  # D394: the ph_* placeholders + short pick reveal
		ac.duck = "--duck" in args                  # D411: the sting duck (music stems before / after it)
		ac.out_dir = _arg(args, "--audio-capture", ProjectSettings.globalize_path("res://").path_join("../design/audio").simplify_path())
		add_child(ac)
		return
	if "--shot" in args:
		var cap := BWCapture.new()
		cap.out_dir = _arg(args, "--shot", "user://shots")
		cap.every = float(_arg(args, "--every", "1.0"))
		cap.count = int(_arg(args, "--count", "6"))
		add_child(cap)
	if "--flow-probe" in args:
		add_child(BWFlowProbe.new())
		return
	if "--ui-shots" in args:
		var us := BWUIShots.new()
		us.out_dir = _arg(args, "--ui-shots", "")
		add_child(us)
		return
	if "--ui-probe" in args:
		add_child(BWUIProbe.new())
		return
	if "--tutorial-probe" in args:                  # ---- D223: step through the whole tutorial
		add_child(BWTutorialProbe.new())
		return
	if "--tutorial" in args:                        # ---- D223: open the tutorial straight away
		var tut := BWTutorial.new()
		tut.finished.connect(func(_c): get_tree().quit())
		add_child(tut)
		BWMusic.play("tutorial")
		return
	if "--screen" in args:
		_one_screen(_arg(args, "--screen", "title"))
		return
	if "--combat" in args:
		_quick_combat(_arg(args, "--combat", "arena"), "--autoplay" in args, int(_arg(args, "--seed", "1")), "--boss" in args, "--carry" in args)
		return
	_start_game()


## Display: the game opens maximized (project.godot) and scales from its
## 1600×900 design size to any window, 4K included — UI by canvas_items
## stretch, 3D at native resolution. F11 or Alt+Enter toggles fullscreen.
func _input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.keycode == KEY_F11 or (ev.keycode == KEY_ENTER and ev.alt_pressed):
			BWSettings.toggle_fullscreen()            # D124: remembered in settings.cfg
			get_viewport().set_input_as_handled()


## D154: `--seed N` fixes the roster roll; every isolated run (probes, shots,
## the self-test) is fixed to the default seed when no --seed is given.
func _seed_roster(args: PackedStringArray) -> void:
	var s := -1
	if "--seed" in args:
		s = int(_arg(args, "--seed", str(BWRosterGen.DEFAULT_SEED)))
	elif Array(args).any(func(a): return a in ISOLATED_FLAGS and a != "--defaults"):
		s = BWRosterGen.DEFAULT_SEED
	if s < 0:
		return
	BWRosterGen.fixed_seed = s
	BWData.use_roster(BWRosterGen.roll(BWData.identities(), s), s)


func _arg(args: PackedStringArray, key: String, fallback: String) -> String:
	var i := args.find(key)
	if i >= 0 and i + 1 < args.size() and not args[i + 1].begins_with("--"):
		return args[i + 1]
	return fallback


func _self_test() -> void:
	var report := BWSelfTest.run()
	var data_ok: bool = report.data_errors.is_empty()
	var f := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	print(BWSelfTest.summary(report))
	print("report: " + ProjectSettings.globalize_path(REPORT_PATH))
	get_tree().quit(0 if report.passed and data_ok else 1)


## A fight with the first three roster entries against three from the
## middle of the roster. Development shortcut until the run flow exists.
func _quick_combat(map_name: String, autoplay: bool, seed_value: int, boss: bool = false, carry: bool = false) -> void:
	var roster := BWData.table("roster")
	var players: Array = []
	var enemies: Array = []
	var count := BWRun.deploy_count_of(map_name)       # D319: the map's deploy count (6 on Commons)
	if boss and _arg(OS.get_cmdline_user_args(), "--boss", "") != "twins":
		count = BWRun.GIANT_DEPLOY                     # D487: the whole squad of six against the Giant
	for i in count:
		players.append(BWUnit.from_roster(roster[i]))
		enemies.append(BWUnit.from_roster(roster[(i + 10) % roster.size()]))
	if carry:                            # D195: a carried weapon of another class each, so the AI swaps
		var run := BWRun.start([], seed_value)
		var classes := BWRun.weapon_classes()
		for u in players + enemies:
			var wc: String = classes[(classes.find(u.weapon_class) + 3) % classes.size()]
			var m: Array = BWData.table("equipment").filter(func(r): return str(r.slot) == "main_hand" and str(r.weight) == wc)
			if not m.is_empty():
				if u.equipment.get("main_hand", {}).is_empty():
					var mh := run.make_item(u.weapon_model, "E")
					if mh.is_empty():
						continue
					u.equipment["main_hand"] = mh
				u.equipment[BWUnit.SECOND] = run.make_item(str(m[0].id), "E")
				u.expertise[wc] = int(u.expertise.get(u.weapon_class, 0))
				u.sync_weapon()
	var twins := _arg(OS.get_cmdline_user_args(), "--boss", "") == "twins" or map_name in [BWRun.TWINS_MAP, "twins"]
	if boss and not twins:
		enemies = [BWRun.new().make_boss()]
	if twins:
		# D256: the Twins: a run at fight 7, its first three levelled and geared to it, on the court
		var trun := BWRun.start(BWData.table("roster").slice(0, 6).map(func(r): return str(r.id)), seed_value)
		var tn := BWRun.TWINS_FIGHT
		for u in trun.squad:
			BWProgression.level_up(u, tn - u.level)
			BWPicks.auto_resolve(u)
			for slot in BWRun.ARMOR_SLOTS:
				var bases: Array = BWData.table("equipment").filter(func(r): return r.slot == slot)
				u.equipment[slot] = trun.make_item(str(bases[absi(hash(u.id + slot)) % bases.size()].id), trun.tier_for(tn))
			u.equipment["main_hand"] = trun.make_item(u.weapon_model, trun.tier_for(tn))
		trun.fight = tn
		players = trun.squad.slice(0, 3)
		trun.prepare_for_battle(players)
		enemies = trun.enemies_for(tn, { "kind": BWRooms.BOSS, "boss": BWSchedule.TWINS, "map": BWRun.TWINS_MAP, "fight": tn, "enemies": [] })   # D355
		map_name = BWRun.TWINS_MAP
	var enc := _arg(OS.get_cmdline_user_args(), "--encounter", "")
	if enc in BWEncounters.KINDS:
		# D208: a run at fight n: its first three, levelled and geared to the fight, vs the encounter
		var run := BWRun.start(BWData.table("roster").slice(0, 6).map(func(r): return str(r.id)), seed_value)
		var n := int(_arg(OS.get_cmdline_user_args(), "--fight", "5"))
		for u in run.squad:
			BWProgression.level_up(u, n - u.level)
			BWPicks.auto_resolve(u)
			for slot in BWRun.ARMOR_SLOTS:
				var bases: Array = BWData.table("equipment").filter(func(r): return r.slot == slot)
				u.equipment[slot] = run.make_item(str(bases[absi(hash(u.id + slot)) % bases.size()].id), run.tier_for(n))
			u.equipment["main_hand"] = run.make_item(u.weapon_model, run.tier_for(n))
		run.fight = n
		players = run.squad.slice(0, 3)
		run.prepare_for_battle(players)
		enemies = BWEncounters.build(run, n, enc)
	var md := _arg(OS.get_cmdline_user_args(), "--mode", "")
	if md in ["splitfront", "horde", "defend", "storm"]:   # D341: the castles too
		# D327-D333: a run at the mode's fight (Split Front 5, the Horde 8 or --fight n),
		# its six levelled and geared, against the mode's enemies on its map
		var mrun := BWRun.start(BWData.table("roster").slice(0, 6).map(func(r): return str(r.id)), seed_value)
		var mn := int(_arg(OS.get_cmdline_user_args(), "--fight", str(BWRun.SPLIT_FIGHT if md == "splitfront" else BWRun.SIX_FIGHTS[0])))
		for u in mrun.squad:
			BWProgression.level_up(u, mn - u.level)
			BWPicks.auto_resolve(u)
			for slot in BWRun.ARMOR_SLOTS:
				var bases: Array = BWData.table("equipment").filter(func(r): return r.slot == slot)
				u.equipment[slot] = mrun.make_item(str(bases[absi(hash(u.id + slot)) % bases.size()].id), mrun.tier_for(mn))
			u.equipment["main_hand"] = mrun.make_item(u.weapon_model, mrun.tier_for(mn))
		mrun.fight = mn
		players = mrun.squad.slice(0, 6)
		mrun.prepare_for_battle(players)
		if str(BWBoard.load_file("res://maps/%s.json" % map_name).objective.get("mode", "")) != md:
			map_name = BWRun.MODE_MAPS[md]             # D354: `--combat fords --mode splitfront` keeps its map
		var room := { "kind": BWRooms.STANDARD, "map": map_name, "fight": mn, "mode": md,
			"enemies": BWRooms._draw_ids(mrun, mn, [], false, 6) }
		enemies = mrun.enemies_for(mn, room)
	var s := BWCombatScreen.new()
	s.configure("res://maps/%s.json" % map_name, players, enemies, [], seed_value)
	s.weather_kind = _arg(OS.get_cmdline_user_args(), "--weather", "")   # D249
	s.mode_opts = { "divider": _arg(OS.get_cmdline_user_args(), "--divider", "") } if "--divider" in OS.get_cmdline_user_args() else {}   # D328
	s.autoplay = autoplay
	s.finished.connect(func(w, _b): print("battle over: ", w))
	if autoplay and not "--shot" in OS.get_cmdline_user_args():
		# D195 check: an autoplay fight exits on its own once it is over (verification runs)
		s.finished.connect(func(_w, _b): get_tree().create_timer(2.0).timeout.connect(get_tree().quit))
	add_child(s)
	BWMusic.play("boss" if boss or twins else "combat")


## Development shortcut: one screen on a sample run (first six of the roster,
## one fight played on paper), for screenshots and quick iteration.
func _one_screen(which: String) -> void:
	BWMusic.ensure(self)
	var ids := BWData.table("roster").slice(0, 6).map(func(r): return str(r.id))
	var run := BWRun.start(ids, 99)
	var e := run.enemies_for(1)
	for x in e:
		x.hp = 0
	var report := run.after_fight(true, run.squad.slice(0, 3), e, e, [])
	var s: Node
	match which:
		"title": s = BWTitleScreen.new()
		"boot":                                    # D381: held mid-warm for review renders
			var bs := BWBootScreen.new()
			bs.freeze_at = 0.67
			add_child(bs)
			return
		"roster": s = BWRosterScreen.new()
		"prebattle":
			s = BWPrebattleScreen.new()
			s.set("run", run)
		"downtime":
			s = BWDowntimeScreen.new()
			s.set("run", run)
		"prep":
			s = BWPrepScreen.new()
			s.set("run", run)
		"rooms":
			s = BWRoomScreen.new()                  # D190
			e = run.enemies_for(2)                  # D208: the choice starts at fight 3
			run.after_fight(true, run.squad.slice(0, 3), e, e, [])
			s.set("run", run)
		"results":
			s = BWResultsScreen.new()
			s.set("run", run)
			s.set("report", report)
	if s:
		add_child(s)
		var cue: String = { "title": "title", "roster": "roster", "prebattle": "prebattle", "rooms": "rooms" }.get(which, "rest")
		BWMusic.play(cue)                          # D239: each screen with its own cue


## D381: the title builds under the boot screen while the warm pass runs,
## then the boot screen fades away onto it.
func _start_game() -> void:
	add_child(BWGame.new())
	add_child(BWBootScreen.new())
