class_name BWCombatScreen
extends Node3D
## The combat screen. Owns a BWBattle (the rules) and presents it: board,
## units, camera, HUD, the attack cutscene. Player input becomes battle
## calls; every battle event is queued and replayed in order with timing, so
## the rules never wait on the view.
##
## Configure before adding to the tree:
##   var s := BWCombatScreen.new()
##   s.configure("res://maps/arena.json", players, enemies, placements, seed)

signal finished(winner: String, battle: BWBattle)
## A defender's reaction was chosen for a blow (as it starts): `reaction` is
## the pose name (dodge, block, fumble, kneel, stricken_flinch, _shrug,
## _stumble, _knockback, _rage); info = BWReactionPick's {tier, why} plus
## damage, crit, glance. The audio lane matches grunts on it; the clip's own
## markers (impact, shout, ...) come through BWAnimator.marker as well.
signal reaction_chosen(unit_id: String, reaction: String, info: Dictionary)
## D86/D87: a named rider floated over a struck unit at the blow's impact
## ("Spark", "Shatter", "Backstab", ...); the audio lane plays its sting.
signal rider_shown(unit_id: String, tag: String)
## D100: a skill's name was called out before its cast ("Fire Tempest");
## `element` is "" for a skill without one. The audio lane plays a whoosh.
signal skill_called(unit_id: String, text: String, element: String)
## D101: a crit's hit-stop flash began (the world is frozen for its length);
## the audio lane plays the sting.
signal crit_flashed(unit_id: String)
## D102: a Frost Ward shattered on this unit (the burst is playing).
signal ward_broken(unit_id: String)

const CINE_PITCH := 24.0     # degrees above horizontal for the side-on cutscene shot
const CINE_FOV := 24.0

var battle: BWBattle
var board_view: BWBoardView
var ui: BWCombatUI
var cam: Camera3D
var rig: BWCameraRig
var _views := {}            # unit id -> BWUnitView
var _queue: Array = []      # pending battle events
var _busy := false          # replaying events / cutscene
var _hover := Vector2i(-1, -1)
var _pending_target: BWUnit = null
var _skill := {}            # chosen skill: { key, element, row [, first] } while aiming (D109: `first` = the target, picking the second hex)
var _pending_skill := {}    # { key, element, hex, choice, hits } waiting on Confirm
var _cfg := {}
var autoplay := false       # player units are AI-driven too (demo / capture)
var trust_fn: Callable      # (a_id, b_id) -> trust stage; the run provides it
var barks: BWCombatBarks
var ranges: BWRangeOverlay       # V8 movement/attack radius (D59)
var ranged: BWRangedVFX          # ---- D165: arrows and thrown blades (combat/vfx_ranged.gd)
var picks_live := false          # ---- D91 picks (marked edit): the run turns rank-up picks on
var picker: BWPicker             # the open mid-fight picker (the flow probe answers it)
# ---- D122/D123 cutscene tiers and skipping (marked edit)
const SKIP_SCALE := 4.0          # hold Space / right mouse: playback at x4
const SKIP_DUCK_DB := -9.0       # SFX and Voice dip while skipping (they'd stack up)
var skipping := false            # the hold is down right now
var _freezing := false           # a crit hit-stop owns Engine.time_scale
var _pause_wanted := false       # Esc during playback: the menu opens when it ends
var last_tiers: Array = []       # [event type, tier name] per blow event played (probes / review)
var pause_menu: BWPauseMenu
var readability: BWReadability   # ---- D160-D163 (marked edit)
var vfx: BWVfxCasts              # ---- D167-D169 cast / spectacle VFX (marked edit)
var feel: BWHitFeel              # ---- D170 hit feel (marked edit)


func configure(map_path: String, players: Array, enemies: Array, placements: Array = [], seed_value: int = 1) -> void:
	_cfg = { "map": map_path, "players": players, "enemies": enemies, "at": placements, "seed": seed_value }


func _ready() -> void:
	var board := BWBoard.load_file(_cfg.get("map", "res://maps/arena.json"))
	battle = BWBattle.new(board, _cfg.get("seed", 1))
	battle.picks_live = picks_live                 # ---- D91 picks (marked edit)
	battle.event.connect(func(e): _queue.append(e))

	var we := WorldEnvironment.new()
	we.environment = BWLook.starfield_environment()
	add_child(we)

	board_view = BWBoardView.new()
	add_child(board_view)

	rig = BWCameraRig.new()
	add_child(rig)
	cam = rig.cam
	rig.clicked.connect(func(p: Vector2): _on_click(board_view.pick(cam, p)))

	ui = BWCombatUI.new()
	add_child(ui)
	barks = BWCombatBarks.new()
	barks.screen = self
	barks.trust_fn = trust_fn
	barks.rng.seed = int(_cfg.get("seed", 1)) * 13
	add_child(barks)
	vfx = BWVfxCasts.new()                          # ---- D167-D170 (marked edit)
	vfx.screen = self
	add_child(vfx)
	feel = BWHitFeel.new()
	feel.screen = self
	add_child(feel)                                 # ---- end D167-D170
	ui.action_pressed.connect(_on_action)
	ui.skill_chosen.connect(_on_skill_chosen)

	battle.setup(_cfg.get("players", []), _cfg.get("enemies", []), _cfg.get("at", []))
	board_view.build(board, battle.tiles)
	ranges = BWRangeOverlay.new(board_view)
	add_child(ranges)
	ranged = BWRangedVFX.new()            # ---- D165 arrows (marked edit): pooled flights, Arcing Shot / Rain
	ranged.screen = self
	add_child(ranged)
	if battle.units.any(func(x): return str(x.weapon_class) == "bow"):
		ranged.prewarm()                  # ---- end D165
	readability = BWReadability.new()     # ---- D160-D163 readability (marked edit): preview, tile card, recap, beat
	add_child(readability)
	readability.setup(self)
	BWPortraits.prewarm(battle.units)     # D156: hits the pre-battle's renders; the stones, direct runs
	for u in battle.units:
		var v: BWUnitView = BWObeliskView.new() if BWObelisk.is_objective(u) else BWUnitView.new()   # D145
		add_child(v)
		v.setup(u)
		v.position = _unit_pos(u.pos)
		_views[u.id] = v
	_face_all()
	var focus := BWLook.world(board.camera_focus, board.elevation(board.camera_focus))
	rig.follow(focus, true)
	ui.feed("[b]%s[/b]" % board.name)
	_queue.clear()          # setup's own events aren't replayed; show their state directly
	for e in battle.history:   # D129: except a rogue's line when it opens the fight
		if e.type == "disobey":
			_queue.append(e)
	ui.set_order(battle.queue.slice(maxi(battle.turn_index, 0)), battle.current(), BWTurnQueue.build(battle.units))
	ui.set_acting(battle.current(), battle.tiles)
	if battle.objective_mode():                      # ---- D140/D145: the objective, said once
		ui.set_objectives(battle.objectives())
		ui.banner("Break an obelisk", 2.6)
		ui.feed("[b]Objective:[/b] break either obelisk. Wiping the enemy does not end it; the stones pulse until one falls.")
		for o in battle.objectives():
			ui.feed("%s: %s" % [o.name, (o as BWObelisk).rule_text()])
	else:
		ui.banner("Battle start")
	get_tree().create_timer(1.6).timeout.connect(barks.on_start)
	_after_events()


# ---------------------------------------------------------------- input

func _process(_delta: float) -> void:
	# the action menu rides beside the acting unit, wherever the camera is
	var u := battle.current() if battle else null
	if u and _views.has(u.id):
		ui.set_menu_anchor(cam.unproject_position(_views[u.id].global_position + Vector3(0, 1.4, 0)))
	# D123: hold Space or the right mouse button through any playback to fast-forward it
	var want := _busy and bool(BWSettings.value("skip_hold")) and not get_tree().paused 		and (Input.is_key_pressed(KEY_SPACE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))
	if want != skipping:
		set_skipping(want)


## D123: fast-forward on/off. Every event still plays (and applies) in order;
## only the clock runs x4 and the holds collapse, so state never desyncs.
## SFX and Voice dip a little meanwhile and come back on release.
func set_skipping(on: bool) -> void:
	skipping = on
	if not _freezing:
		Engine.time_scale = SKIP_SCALE if on else 1.0
	for bus in ["SFX", "Voice"]:
		var i := AudioServer.get_bus_index(bus)
		if i < 0:
			continue
		if on:
			AudioServer.set_bus_volume_db(i, AudioServer.get_bus_volume_db(i) + SKIP_DUCK_DB)
		else:
			BWAudio._apply(bus)
	if on:
		ui.skip_hint(false)


## A hold inside a cutscene: collapses to almost nothing while skipping.
func _hold(sec: float) -> void:
	await get_tree().create_timer(sec * (0.15 if skipping else 1.0)).timeout


## D122: the tier for a blow event under the player's cutscene mode.
func _tier(e: Dictionary) -> Dictionary:
	var tc := BWCutsceneTier.tier_for(e, str(BWSettings.value("cutscenes")))
	last_tiers.append([str(e.get("type", "")), str(tc.name)])
	if last_tiers.size() > 64:
		last_tiers.pop_front()
	if vfx:
		vfx.begin(e, tc)                         # ---- D167: what the cast VFX play for this blow
	return tc


## D123: F cycles the cutscene mode (Default -> Fast -> Minimal).
func cycle_cutscene_mode() -> void:
	var m := BWCutsceneTier.next_mode(str(BWSettings.value("cutscenes")))
	BWSettings.put("cutscenes", m)
	ui.toast("Cutscenes: %s" % BWCutsceneTier.MODE_LABELS[m])


## D124: the pause menu (Esc with nothing to back out of). During playback
## it waits for the action to finish, so nothing is frozen mid-tween.
func open_pause() -> void:
	if pause_menu and is_instance_valid(pause_menu):
		return
	if _busy:
		_pause_wanted = true
		ui.toast("Menu after this action")
		return
	pause_menu = BWPauseMenu.open(self, "combat")
# ---- end D122/D123


## Camera input lives in BWCameraRig (V8 controls); clicks arrive via rig.clicked.
func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion and ev.button_mask == 0:
		_on_hover(board_view.pick(cam, ev.position))
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_T: _on_action("wait")
			KEY_ENTER, KEY_KP_ENTER: _on_action("confirm")
			KEY_ESCAPE: _on_action("cancel")
			KEY_F: cycle_cutscene_mode()           # ---- D123


func _player_turn() -> bool:
	var u := battle.current()
	return u != null and u.team == "player" and not BWAI.controls(u, autoplay) and not _busy and not battle.over


func _on_hover(h: Vector2i) -> void:
	if h == _hover:
		return
	_hover = h
	var under := battle.unit_at(h)
	if under:
		ui.set_card(under, battle.tiles, battle.current())
	elif battle.current():
		ui.set_card(null)
	if not _player_turn() or ui.forecast_open():
		return
	var u := battle.current()
	if not _skill.is_empty():
		if _skill.has("first"):                                   # D109: the second pick
			if h in _seconds(u):
				var pv2 := battle.skill_preview(u, _skill.key, _skill.element, _skill.first, h)
				if not pv2.is_empty():
					_show_options([], pv2.hexes, _skill.element)
					board_view.highlight([_skill.first], "target")
					board_view.highlight([h], "target")
					ui.hint("%s — %s" % [_skill.row.get("name", _skill.key), "  ·  ".join(pv2.notes)])
					return
			_show_options()
			return
		if h in battle.skill_targets(u, _skill.key, _skill.element) and str(_skill.row.get("second_pick", "")) == "hex":
			_show_options()                                       # D109: the first pick, no automatic second shown
			board_view.highlight([h], "target")
			ui.hint("%s — click to pick this, then choose the second hex  (Esc to cancel)" % _skill.row.get("name", _skill.key))
			return
		if h in battle.skill_targets(u, _skill.key, _skill.element):
			var pv := battle.skill_preview(u, _skill.key, _skill.element, h)
			if not pv.is_empty():
				# splash: "this will be hit", in the skill's element (V8's amber)
				_show_options([], pv.hexes + pv.get("ring", []), _skill.element)
				board_view.highlight([h], "target")
				if not (pv.get("notes", []) as Array).is_empty():     # D87: the skill's rider in words
					ui.hint("%s — %s" % [_skill.row.get("name", _skill.key), "  ·  ".join(pv.notes)])
				return
		_show_options()
		return
	if battle.can_move_to(u, h) and h != u.pos:
		_show_options(BWBoard.path_to(battle.reachable(u), h))
	else:
		_show_options()


func _on_click(h: Vector2i) -> void:
	if not _player_turn() or h == Vector2i(-1, -1):
		return
	var u := battle.current()
	var target := battle.unit_at(h)
	if ui.forecast_open():
		if target == _pending_target or (not _pending_skill.is_empty() and h in _pending_skill.get("hits", [_pending_skill.hex])):
			_on_action("confirm")
		return
	if not _skill.is_empty():
		_aim_skill(u, h)
		return
	if target and target.team != u.team and (not u.acted or "basic" in u.follow_up) and battle.in_range(u, target):
		_pending_target = target
		ui.show_forecast(u, target, battle.forecast_basic(u, target))
		board_view.clear_highlights()
		board_view.highlight([target.pos], "target")
		return
	if h != u.pos and battle.can_move_to(u, h):
		board_view.clear_highlights()
		battle.move(u, h)
		_after_events()


func _on_action(id: String) -> void:
	match id:
		"wait":
			if _player_turn() and not ui.forecast_open():
				board_view.clear_highlights()
				battle.end_turn()
				_after_events()
		"confirm":
			if _player_turn() and ui.forecast_open() and _pending_target:
				ui.hide_forecast()
				battle.attack(battle.current(), _pending_target)
				_pending_target = null
				_after_events()
			elif _player_turn() and ui.forecast_open() and not _pending_skill.is_empty():
				ui.hide_forecast()
				var ps := _pending_skill
				_pending_skill = {}
				_skill = {}
				battle.use_skill(battle.current(), ps.key, ps.element, ps.hex, ps.get("choice", BWBattle.NOWHERE))
				_after_events()
		"attack":
			_skill = {}
			_show_options()
		"cancel":
			if ui.forecast_open():
				ui.hide_forecast()
				_pending_target = null
				_pending_skill = {}
				# D110: a self-centred skill has no aiming step to go back to
				if not _skill.is_empty() and str(_skill.row.get("targeting", "")) == "self":
					_skill = {}
				_show_options()
			elif not _skill.is_empty() and _skill.has("first"):
				_skill.erase("first")                    # D109: back to the first pick
				_show_options()
			elif not _skill.is_empty():
				_skill = {}
				_show_options()
			elif _player_turn() and battle.can_undo_move(battle.current()):
				# Esc backs out one step at a time: forecast → aiming → the move itself (D48).
				battle.undo_move(battle.current())
				_after_events()
			elif picker == null:
				open_pause()                             # ---- D124: nothing left to back out of


func _on_skill_chosen(key: String, element: String) -> void:
	if not _player_turn() or ui.forecast_open():
		return
	var u := battle.current()
	var row := BWSkills.get_skill(key)
	if str(row.get("targeting", "")) == "self":
		if BWSkills.is_damaging(key):
			# D110: a self-centred attack shows its forecast and waits for Confirm
			var pv := battle.skill_preview(u, key, element, u.pos)
			if pv.is_empty():
				ui.hint("%s — %s: no one in reach" % [u.name, row.get("name", key)])
				return
			_skill = { "key": key, "element": element, "row": row }
			_open_confirm(u, pv, u.pos)
			return
		_skill = {}
		battle.use_skill(u, key, element, u.pos)
		_after_events()
		return
	_skill = { "key": key, "element": element, "row": row }
	_show_options()


## A click while aiming a skill: if it hits anyone (or strikes after, like
## Vault), show the forecast and wait for Confirm; a second-pick skill
## (D109) first asks for its second hex; otherwise (a leap, painting empty
## ground) just do it.
func _aim_skill(u: BWUnit, h: Vector2i) -> void:
	if _skill.has("first"):
		if not h in _seconds(u):
			return
		var pv2 := battle.skill_preview(u, _skill.key, _skill.element, _skill.first, h)
		if not pv2.is_empty():
			_open_confirm(u, pv2, _skill.first, h)
		return
	if not h in battle.skill_targets(u, _skill.key, _skill.element):
		return
	var pv := battle.skill_preview(u, _skill.key, _skill.element, h)
	if pv.is_empty():
		return
	if str(_skill.row.get("second_pick", "")) == "hex":
		_skill["first"] = h
		if not _seconds(u).is_empty():
			_show_options()                      # D109: now pick the second hex
			return
		_skill.erase("first")                    # nothing to choose (a braced foe): straight to the forecast
		_open_confirm(u, pv, h)
		return
	if pv.forecasts.is_empty() and (pv.get("strike", {}) as Dictionary).is_empty():
		var k: String = _skill.key
		var el: String = _skill.element
		_skill = {}
		battle.use_skill(u, k, el, h)
		_after_events()
		return
	_open_confirm(u, pv, h)


## D109: the legal second hexes for the chosen target.
func _seconds(u: BWUnit) -> Array[Vector2i]:
	return BWSkillRegistry.get_def(_skill.key).second_targets(battle, u, _skill.element, _skill.first)


## D110: the confirm box for a skill preview: the first victim's forecast
## (+N more), else the strike it makes after (Vault), else its notes in
## words; the shape on the board. Click a highlighted hex or Enter confirms.
func _open_confirm(u: BWUnit, pv: Dictionary, h: Vector2i, choice: Vector2i = BWBattle.NOWHERE) -> void:
	var nm := str(_skill.row.get("name", _skill.key))
	var ids: Array = pv.forecasts.keys()
	var at: Array = ids.map(func(id): return battle._unit(str(id)).pos)
	var strike: Dictionary = pv.get("strike", {})
	if not ids.is_empty():
		var fc0: Dictionary = pv.forecasts[ids[0]].duplicate()
		fc0["notes"] = (pv.get("notes", []) as Array) + (fc0.get("notes", []) as Array)    # D87
		ui.show_forecast(u, battle._unit(str(ids[0])), fc0, nm, ids.size() - 1)
	elif not strike.is_empty():
		var fs: Dictionary = (strike.forecast as Dictionary).duplicate()
		fs["notes"] = (pv.get("notes", []) as Array) + (fs.get("notes", []) as Array)
		ui.show_forecast(u, strike.unit, fs, nm)
		at = [strike.unit.pos]
	else:
		var notes: Array = (pv.get("notes", []) as Array).duplicate()
		if str(_skill.row.get("targeting", "")) == "self" and BWSkills.is_damaging(_skill.key):
			notes.append("No enemy in reach")
		ui.show_plan(u, nm, notes)
	var hits: Array = [h] + at + pv.hexes
	if choice != BWBattle.NOWHERE:
		hits.append(choice)
	_pending_skill = { "key": _skill.key, "element": _skill.element, "hex": h, "choice": choice, "hits": hits }
	ui.hint("%s — %s: click again or Enter to confirm  (Esc to go back)" % [u.name, nm])
	board_view.clear_highlights()
	ranges.display([], Color.BLACK, [], pv.hexes + pv.get("ring", []),
		BWLook.element_color(_skill.element) if _skill.element != "" else Color(0.15, 0.15, 0.17))
	board_view.highlight(at if not at.is_empty() else ([choice] if choice != BWBattle.NOWHERE else [h]), "target")


func _show_options(path: Array = [], splash: Array = [], splash_el: String = "") -> void:
	board_view.clear_highlights()
	var u := battle.current()
	if u == null:
		ranges.clear()
		return
	ui.set_skills(u, battle.skills_for(u), "" if _skill.is_empty() else "%s|%s" % [_skill.key, _skill.element])
	var rim := BWLook.element_color(u.element)
	var splash_col := BWLook.element_color(splash_el) if splash_el != "" else Color(0.15, 0.15, 0.17)
	if not _skill.is_empty() and _skill.has("first"):
		# D109 second pick: the legal second hexes in the same ink overlay, the first pick marked
		var sec := _seconds(u)
		ranges.display([], rim, sec, splash, splash_col)
		board_view.highlight(sec, "attack")      # pulsing ink: click one of these
		board_view.highlight([_skill.first], "target")
		var what := "where it lands" if _skill.key == "grapple_throw" else "where it goes"
		ui.hint("%s — %s: now click %s  (Esc: back to the first pick)" % [u.name, _skill.row.get("name", _skill.key), what])
		return
	if not _skill.is_empty():
		# aiming: the attack radius is the skill's legal targets (V8 targeting)
		var targets := battle.skill_targets(u, _skill.key, _skill.element)
		ranges.display([], rim, targets, splash, splash_col)
		board_view.highlight(targets.filter(func(h): return battle.unit_at(h) != null and battle.unit_at(h).team != u.team), "attack")
		ui.hint("%s — %s: click a hex in the ink radius  (Esc to cancel)" % [u.name, _skill.row.get("name", _skill.key)])
		return
	var foes_in_range: Array = battle.attack_targets(u).map(func(f): return f.pos)
	if not u.follow_up.is_empty():
		ranges.display([], rim, _attack_area(u) if "basic" in u.follow_up else [])
		if "basic" in u.follow_up:
			board_view.highlight(foes_in_range, "attack")
		ui.hint("%s — follow-up: %s, or T to skip" % [u.name, ", ".join(u.follow_up)])
		return
	var move: Array = []
	if battle.can_move(u):
		var r := battle.reachable(u)
		for h in r:
			if r[h].stop:
				move.append(h)      # the unit's own hex is part of the region (V8)
	# Before moving: the walk region, rimmed in the unit's element. Once it
	# can't move, its attack radius from where it stands, in ink.
	var attack: Array = _attack_area(u) if move.is_empty() and not u.acted else []
	ranges.display(move, rim, attack, [], Color(0, 0, 0, 0), path)
	if not u.acted:
		board_view.highlight(foes_in_range, "attack")
	var bits: PackedStringArray = []
	if battle.can_move(u): bits.append("click inside the rim to move")
	if battle.can_undo_move(u): bits.append("Esc to undo the move")
	if not u.acted: bits.append("click a pulsing enemy to attack")
	bits.append("T to end turn · Space recentres")
	ui.hint("%s — %s%s" % [u.name, ", ".join(bits), pulse_hint()])


## Every hex the unit's basic attack reaches from where it stands (V8
## attack_pattern: radius minus own hex and obstacles, sight-checked).
func _attack_area(u: BWUnit) -> Array:
	var out: Array = []
	var rng := battle.weapon_range(u)
	for h in battle.board.area(u.pos, rng):
		if h != u.pos and battle.board.is_passable(h) and battle._reaches(u.pos, h, rng):
			out.append(h)
	return out


# ---------------------------------------------------------------- the loop

## Replay queued events, then hand control to the player or run the AI.
func _after_events() -> void:
	if _busy:
		return
	_busy = true
	ui.set_actions_visible(false)
	ranges.clear()
	board_view.clear_highlights()
	while true:
		while not _queue.is_empty():
			await _play(_queue.pop_front())
			if battle.objective_mode():
				ui.set_objectives(battle.objectives())   # ---- D145: the stones' HP bars
		await _resolve_picks()                     # ---- D91 picks (marked edit): pause for owed picks
		if battle.over:
			break
		var u := battle.current()
		if u and BWAI.controls(u, autoplay):          # enemies, autoplay, and a rogue (D129)
			await get_tree().create_timer(0.35).timeout
			BWAI.take_turn(battle)
			continue
		if u and u.team == "player" and u.acted and u.follow_up.is_empty() and not battle.can_move(u):
			battle.end_turn()
			continue
		break
	_busy = false
	if skipping:
		set_skipping(false)                          # ---- D123
	if _pause_wanted and not battle.over:            # ---- D124
		_pause_wanted = false
		open_pause.call_deferred()
	if battle.over:
		await get_tree().create_timer(1.0).timeout
		finished.emit(battle.winner, battle)
		return
	ui.set_acting(battle.current(), battle.tiles)
	_show_options()
	ui.set_actions_visible(battle.current() != null and battle.current().team == "player" and not battle.current().rogue)


func _play(e: Dictionary) -> void:
	if readability:
		readability.played(e)               # ---- D162 recap (marked edit): groups events per action
	match e.type:
		"cycle":
			ui.set_order(battle.queue, null, [])
		"turn":
			barks.turn_passed()
			ui.set_acting(battle._unit(e.unit), battle.tiles)
			ui.set_order(battle.queue.slice(maxi(battle.turn_index, 0)), battle.current(), BWTurnQueue.build(battle.units))
			var v: BWUnitView = _views[e.unit]
			rig.follow(v.global_position)
			await get_tree().create_timer(0.3).timeout
		"move":
			match str(e.get("kind", "")):
				"leap":
					if vfx and vfx.dives(e, _queue):    # ---- D168: Dragoon Dive's leap, shadow, crash
						await vfx.dive(_views[e.unit], e.path)
					else:
						await _animate_leap(_views[e.unit], e.path)
				"charge", "shove", "knockback", "pull", "push": await _animate_slide(_views[e.unit], e.path, 0.07 if e.kind == "charge" else 0.12)
				_: await _animate_move(_views[e.unit], e.path)
		"undo_move":
			var uv: BWUnitView = _views[e.unit]
			var tw := create_tween()
			tw.tween_property(uv, "position", _unit_pos(e.to), 0.18).set_trans(Tween.TRANS_SINE)
			await tw.finished
			uv.refresh()
			board_view.refresh_tiles()
			ui.feed("%s steps back" % _name(e.unit))
		"attack":
			var rs := [{ "target": e.target, "result": e.result, "ko": e.ko, "target_hp": e.get("target_hp", -1), "tags": e.get("tags", []), "odds": e.get("odds", {}) }]
			var tc := _tier(e)                                      # ---- D122
			var what := "strike %d/%d" % [int(e.strike) + 1, int(e.strikes)] if int(e.get("strike", 0)) > 0 				else (str(e.get("pattern", "")).capitalize() if e.has("strikes") else "")
			if int(tc.tier) == BWCutsceneTier.MINIMAL:
				await _quick_hit(e.unit, rs, what, "", "", tc)
			else:
				await _cutscene(e.unit, rs, what, [], "", "", {}, tc)
			barks.after_action(battle._unit(e.unit), rs)
		"counter":
			var crs := [{ "target": e.target, "result": e.result, "ko": e.ko, "target_hp": e.get("target_hp", -1), "tags": e.get("tags", []), "odds": e.get("odds", {}) }]
			var ctc := _tier(e)                                     # ---- D122
			if int(ctc.tier) == BWCutsceneTier.MINIMAL:
				await _quick_hit(e.unit, crs, str(e.get("name", "Counter")), "", "", ctc)
			else:
				await _cutscene(e.unit, crs, str(e.get("name", "Counter")), [], "", "", {}, ctc)
		"erupt":
			ui.feed("[b]%s eruption[/b] (%s)" % [str(e.element).capitalize(), str(e.get("name", ""))])
			_shake(0.1)
			board_view.refresh_tiles()
		"stat_up":
			_float_text(_views[e.unit], "%s +%d %s" % [e.name, int(e.amount), "/".join(e.stats).to_upper()], Color.WHITE, 0.9)
		"guard":
			_float_text(_views[e.unit], "%s" % e.name, Color.WHITE, 0.8)
			ui.feed("%s raises a guard (%d%%)" % [_name(e.unit), int(e.pct)])
		"bonus_move":
			ui.feed("%s may move %d more" % [_name(e.unit), int(e.hexes)])
		"displace_resisted":
			_float_text(_views[e.unit], "held firm", Color.WHITE, 0.6)
		"skill":
			var sname := str(BWSkills.get_skill(e.skill).get("name", e.skill))
			var call := _callout_for(str(e.skill), str(e.get("element", "")))   # ---- D100: before the retarget suffix
			if e.get("retarget", false) and not e.results.is_empty():     # D87: the second cut turns
				sname += " → " + _name(e.results[0].target)
				board_view.reaction_burst("retarget", battle._unit(e.results[0].target).pos)
			var stc := _tier(e)                                     # ---- D122
			if ranged:
				ranged.context = e                                  # ---- D165: which shot the arrows are
			if ranged and ranged.owns(e):                           # ---- D165: Arcing Shot / Rain of Arrows, whole
				await ranged.play_area(e, stc, call if bool(stc.callout) else {})
			elif (e.results as Array).is_empty():
				await _setup_beat(e.unit, sname)
			elif int(stc.tier) == BWCutsceneTier.MINIMAL:
				await _quick_hit(e.unit, e.results, sname, str(e.get("element", "")), BWSkillRegistry.clip(e.skill), stc)
			else:
				await _cutscene(e.unit, e.results, sname, e.get("hexes", []), str(e.get("element", "")), BWSkillRegistry.clip(e.skill),
					call if bool(stc.callout) else {}, stc)
			if ranged:
				ranged.context = {}                                 # ---- D165
			barks.after_action(battle._unit(e.unit), e.results)
		# ---- D86/D87 riders (combat lane) ----
		"chain":
			board_view.chain_bolt(e.hex, e.to_hex)
			if readability:
				await readability.beat(e.to_hex)   # ---- D163 slow beat (marked edit)
			await get_tree().create_timer(0.12).timeout
			_float_text(_views[e.to], "-%d" % int(e.amount), BWLook.glow_color("thunder"), 0.8)
			_float_text(_views[e.from], "Chain", BWLook.glow_color("thunder"), 0.6)
			_views[e.to].refresh()
			ui.feed("[b]Chain lightning[/b]: %s → %s, %d" % [_name(e.from), _name(e.to), int(e.amount)])
			await get_tree().create_timer(0.45).timeout
		"reaction":
			board_view.reaction_burst(str(e.kind), e.hex)
			_shake(0.08)
			var rx := { "steam": "Steam burst", "eclipse": "Eclipse", "storm": "Storm" }
			ui.banner(str(rx.get(str(e.kind), e.kind)), 0.8)
			ui.feed("[b]%s![/b] (%s's second cut)" % [rx.get(str(e.kind), e.kind), _name(e.unit)])
			await get_tree().create_timer(0.5).timeout
		"status":                                    # ---- D102: glyphs, the author's short rules
			var sv: BWUnitView = _views.get(str(e.get("unit", "")))
			var skey := str(e.get("status", ""))
			var sinfo := BWCombatUI.status_info(skey, str(e.get("label", "")), str(e.get("rule", "")))
			if sv:
				_float_status(sv, skey, str(sinfo[0]), str(sinfo[1]))
				sv.refresh()
			ui.feed("%s is %s (%s)" % [_name(str(e.get("unit", ""))), sinfo[0], sinfo[1]])
		"status_end":                                # ---- D102: a ward or status fades with its data
			var ev: BWUnitView = _views.get(str(e.get("unit", "")))
			if ev:
				ev.refresh()
		"ward", "ward_up", "frost_ward":             # ---- D102: Frost Ward raised (any of the names the rules may use)
			var wv: BWUnitView = _views.get(str(e.get("unit", "")))
			if wv:
				wv.refresh()
				wv.set_ward(true)
				_float_text(wv, "Frost Ward", Color(0.92, 0.97, 1.0), 0.8)
			ui.feed("%s is warded: elemental effects are negated" % _name(str(e.get("unit", ""))))
		"ward_break":                                # ---- D102: the ward shatters
			var bv: BWUnitView = _views.get(str(e.get("unit", "")))
			if bv:
				bv.ward_break()
				ward_broken.emit(bv.unit.id)
				_float_text(bv, "Ward shattered", Color(0.92, 0.97, 1.0), 0.7)
				_shake(0.05)
			ui.feed("%s's Frost Ward shatters%s" % [_name(str(e.get("unit", ""))),
				(" (%s negated)" % str(e.element)) if str(e.get("element", "")) != "" else ""])
			await get_tree().create_timer(0.35).timeout
		"riposte_refund":
			ui.feed("%s's answer landed: Riposte back in %d" % [_name(e.unit), int(e.cd)])
		"fan":
			_float_text(_views[e.unit], "Fan the hammer", Color.WHITE, 0.7)
		"slam":
			_float_text(_views[e.unit], "SLAM", Color.WHITE, 0.7)
			_shake(0.1)
		# ---- end D86/D87 ----
		"riposte":
			ui.feed("[b]%s ripostes![/b]" % _name(e.unit))
			if not e.results.is_empty():
				var rtc := _tier(e)                                 # ---- D122: an answer, minimal unless it crits / KOs
				if int(rtc.tier) == BWCutsceneTier.MINIMAL:
					await _quick_hit(e.unit, e.results, "Riposte", str(e.element), "", rtc)
				else:
					await _cutscene(e.unit, e.results, "Riposte", e.hexes, str(e.element), "", {}, rtc)
		"follow_up":
			ui.feed("%s can follow up: %s" % [_name(e.unit), ", ".join(e.allow)])
		"heal":
			barks.on_heal(battle._unit(e.unit))
			_float_text(_views[e.unit], "+%d" % e.amount, Color.WHITE)
			_views[e.unit].refresh()
			ui.feed("%s heals %d" % [_name(e.unit), e.amount])
		"pulse":                                      # ---- D145: an obelisk's turn
			await _pulse(e)
		"tile_damage":
			if str(e.get("cause", "")) == "pulse":       # D145: every unit at once, no wait each
				_float_text(_views[e.unit], "-%d" % e.amount, Color(1, 1, 1))
				_views[e.unit].refresh()
				return
			_float_text(_views[e.unit], "-%d" % e.amount, Color(1, 1, 1))
			_views[e.unit].refresh()
			ui.feed("%s takes %d from %s" % [_name(e.unit), e.amount, e.cause.replace("_", " ")])
			await get_tree().create_timer(0.35).timeout
		"paint", "tiles_tick":
			board_view.on_tile_event(e)        # Phase 5 tile FX (D82): refresh + gust / ignition one-shots
		"detonate":
			board_view.on_tile_event(e)        # Phase 5 tile FX (D82): flash + ring burst
			ui.feed("[b]Detonation![/b] %d%%" % int(e.pct))
			if readability and not e.get("echo", false):
				await readability.beat(e.hex)      # ---- D163 slow beat (marked edit)
		"ko":
			ui.set_order(battle.queue.slice(maxi(battle.turn_index, 0)), battle.current(), BWTurnQueue.build(battle.units))
			var v: BWUnitView = _views[e.unit]
			barks.on_ko(battle._unit(e.unit))
			v.pose_named("fall")
			ui.feed("[b]%s is knocked out[/b]" % _name(e.unit))
			var tw := create_tween()
			tw.tween_interval(maxf(v.time_to_marker("grounded"), 0.0) + 0.5)
			tw.tween_property(v, "scale", Vector3(1, 0.05, 1), 0.3)
			tw.tween_callback(func(): v.visible = false)
			await tw.finished
		"pick":                                         # ---- D91 picks (marked edit)
			if _views.has(e.unit):
				_float_text(_views[e.unit], str(e.text).trim_prefix(_name(e.unit) + " "), BWLook.element_color(
					str(e.get("element", battle._unit(e.unit).element))), 1.0)
			ui.feed(str(e.text))
		"disobey":                                   # D129: the rogue's line, its first turn each battle
			if _views.has(e.unit):
				rig.follow(_views[e.unit].global_position)
			barks.disobey(battle._unit(e.unit), str(e.line))
			await get_tree().create_timer(1.6).timeout
		"growth":
			for g in e.events:
				if g.type == "level":
					_float_text(_views[e.unit], "LEVEL %d" % g.level, Color.WHITE, 1.2)
					ui.feed("%s reached level %d" % [_name(e.unit), g.level])
		"battle_end":
			var broke: Array = battle.objectives().filter(func(o): return not o.alive())
			if e.winner == "player" and not broke.is_empty():
				ui.banner("Victory: %s breaks" % broke[0].name, 3.0)   # D145
			else:
				ui.banner("Victory" if e.winner == "player" else "Defeat", 3.0)
			if e.winner == "player":
				barks.on_won()
			for u in battle.units:
				if u.alive() and u.team == e.winner:
					_views[u.id].pose_named("cheer")


# ---- D91 picks (marked edit) ----

## After an action resolves: every player unit that crossed a rank picks
## now, before play goes on (no banking). The unit's tile is marked, the
## camera finds it, the picker opens. Autoplay answers the AI's way.
func _resolve_picks() -> void:
	if not battle.picks_live:
		return
	while true:
		var pend := battle.pending_picks("player")
		while not _queue.is_empty():
			await _play(_queue.pop_front())         # rank-3 grants announced first
		if pend.is_empty():
			return
		var u: BWUnit = pend[0][0]
		var req: Dictionary = pend[0][1]
		if autoplay:
			battle.apply_pick(u, req, BWPicks.auto_choice(u, req))
		else:
			ranges.clear()
			board_view.clear_highlights()
			board_view.highlight([u.pos], "target")
			if _views.has(u.id):
				# aim past the unit toward the viewer so it sits above the docked panel
				var fwd := -cam.global_transform.basis.z
				fwd.y = 0.0
				rig.follow(_views[u.id].global_position - fwd.normalized() * 3.2)
			ui.set_actions_visible(false)
			ui.banner("%s ranks up" % u.name, 1.0)
			await get_tree().create_timer(0.6).timeout
			picker = BWPicker.new(u, req, "mid-fight")
			picker.dock_low()                       # the unit and its tile stay in view above
			ui.add_child(picker)
			var id: String = await picker.chosen
			picker.queue_free()
			picker = null
			board_view.clear_highlights()
			battle.apply_pick(u, req, id)
		while not _queue.is_empty():
			await _play(_queue.pop_front())

# ---- end D91 picks ----


## Daggerleap / Vault: one high arc from start to landing.
func _animate_leap(v: BWUnitView, path: Array) -> void:
	var from := _unit_pos(path[0])
	var to := _unit_pos(path[path.size() - 1])
	v.face(to)
	v.pose_named("windup")
	var h := 1.2 + from.distance_to(to) * 0.15
	var tw := create_tween()
	tw.tween_method(func(t: float): v.position = from.lerp(to, t) + Vector3(0, sin(t * PI) * h, 0),
		0.0, 1.0, 0.45).set_trans(Tween.TRANS_SINE)
	await tw.finished
	v.pose_named("kneel")
	await get_tree().create_timer(0.12).timeout
	v.idle()


## Charge (fast) and shove (pushed): a straight slide hex to hex, no hop.
func _animate_slide(v: BWUnitView, path: Array, step: float) -> void:
	var tw := create_tween()
	for i in range(1, path.size()):
		tw.tween_property(v, "position", _unit_pos(path[i]), step)
	if path.size() > 1:
		v.face(_unit_pos(path[path.size() - 1]))
	v.pose_named("strike" if step < 0.1 else "hit")
	await tw.finished
	v.idle()


func _animate_move(v: BWUnitView, path: Array) -> void:
	if path.size() > 1 and not v.plan_move(1.0, 1).is_empty():
		await _animate_walk(v, path)
		return
	var tw := create_tween()
	for i in range(1, path.size()):
		var to := _unit_pos(path[i])
		var from := _unit_pos(path[i - 1])
		tw.tween_callback(v.face.bind(to))
		# a small hop each step: up and over, so elevation changes read
		var mid := (from + to) / 2.0 + Vector3(0, 0.18 + absf(to.y - from.y) * 0.5, 0)
		tw.tween_property(v, "position", mid, 0.09).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(v, "position", to, 0.09).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tw.finished
	v.idle()
	_face_all()


## Units with clips move on the animator's plan (D62): two or more hexes
## run (the authored start, the run at ~0.4 s per hex, the authored stop
## on whichever foot is down), one hex walks, and a wounded unit limps.
## The root follows the plan's distance curve along the path, so the start
## and stop footsteps land where they were authored; the character turns
## on an s-curve at each corner (BWCharacter).
func _animate_walk(v: BWUnitView, path: Array) -> void:
	var pts: Array = []
	for h in path:
		pts.append(_unit_pos(h))
	var lens: Array = []
	var total := 0.0
	for i in range(1, pts.size()):
		var d := Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
		lens.append(d)
		total += d
	var plan := v.plan_move(total, path.size() - 1)
	var dur := float(plan.dur)
	var stop_at := float(plan.get("stop_at", -1.0))
	var s_of: Callable = plan.s
	v.face(pts[1])
	v.begin_move(plan)
	var seg := [0]
	var stopped := [false]
	var step := func(t: float) -> void:
		if stop_at >= 0.0 and t >= stop_at and not stopped[0]:
			stopped[0] = true
			v.pose_named("run_stop")
		var s := clampf(float(s_of.call(t)), 0.0, total)
		var i := 0
		var acc := 0.0
		while i < lens.size() - 1 and s > acc + float(lens[i]):
			acc += float(lens[i])
			i += 1
		if i != seg[0]:
			seg[0] = i
			v.face(pts[i + 1])
		var u := clampf((s - acc) / maxf(float(lens[i]), 1e-4), 0.0, 1.0)
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var p := a.lerp(b, u)
		if absf(b.y - a.y) > 0.01:
			p.y += sin(u * PI) * (0.12 + absf(b.y - a.y) * 0.5)   # step up / down a ledge
		v.position = p
	var tw := create_tween()
	tw.tween_method(step, 0.0, dur, dur)
	await tw.finished
	v.position = pts[pts.size() - 1]
	v.idle()
	_face_all()


## Distance fraction travelled at time t for a trapezoid speed profile
## (linear ramp up over `ramp` s, cruise, ramp down), total time `dur`.
static func _trapezoid(t: float, dur: float, ramp: float) -> float:
	var r := minf(ramp, dur * 0.5)
	var cruise := dur - r                 # area = v * (dur - r)
	t = clampf(t, 0.0, dur)
	var d := 0.0
	if t < r:
		d = 0.5 * t * t / r
	elif t > dur - r:
		var u := dur - t
		d = cruise - 0.5 * u * u / r
	else:
		d = 0.5 * r + (t - r)
	return clampf(d / cruise, 0.0, 1.0)


# ---------------------------------------------------------------- cutscene

## Brief: everything but attacker, target and their tiles fades to near
## black; the camera tightens; melee closes in; the defender reacts by
## result; then everything returns.
## D122 `tc` (BWCutsceneTier.tier_for): FULL plays the whole thing; SHORT
## the zoom and dim on quicker tweens, a ~0.3 s callout and no long holds.
func _cutscene(attacker_id: String, results: Array, skill_name: String, hexes: Array = [], element: String = "", skill_clip: String = "", call: Dictionary = {}, tc: Dictionary = {}) -> void:
	var a: BWUnitView = _views[attacker_id]
	var targets: Array = []
	for r in results:
		targets.append(_views[r.target])
	if targets.is_empty():
		return
	var d: BWUnitView = targets[0]
	var full := int(tc.get("tier", BWCutsceneTier.FULL)) == BWCutsceneTier.FULL     # ---- D122
	var zoom_t := 0.45 if full else 0.3
	var hint := full and BWSettings.take_skip_hint()                                    # ---- D123
	if hint:
		ui.skip_hint(true)
	ui.cinematic(true)                               # ---- D111: the menu fades for the cutscene
	if BWSettings.value("show_odds"):
		_odds_in(results, element)                   # ---- D113
	# Keep lit: attacker, every target, their tiles, and the skill's shape.
	var keep: Array = [a]
	keep.append_array(targets)
	keep.append_array(board_view.hex_parts(a.unit.pos))
	for t in targets:
		keep.append_array(board_view.hex_parts(t.unit.pos))
	for h in hexes:
		keep.append_array(board_view.hex_parts(h))
	var others: Array = []
	for c in board_view.get_children():
		if not c in keep:
			others.append(c)
	for id in _views:
		if not _views[id] in keep:
			others.append(_views[id])
	var saved := { "pos": rig.pivot, "yaw": rig.yaw, "pitch": rig.pitch, "dist": rig.dist, "fov": cam.fov }
	rig.following = false
	rig.input_enabled = false
	var centre := Vector3.ZERO
	for t in targets:
		centre += t.global_position
	centre /= targets.size()
	var mid: Vector3 = (a.global_position + centre) / 2.0 + Vector3(0, 0.6, 0)
	var side_yaw := atan2(centre.x - a.global_position.x, centre.z - a.global_position.z) + PI / 2.0
	var span := a.global_position.distance_to(centre)
	var tw := create_tween().set_parallel(true)
	tw.tween_method(_dim_all.bind(others), 0.0, 1.0, zoom_t * 0.78)
	tw.tween_property(rig, "yaw", _closest_angle(rig.yaw, side_yaw), zoom_t).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(cam, "fov", CINE_FOV, zoom_t).set_trans(Tween.TRANS_CUBIC)
	# Frame big units (the Giant) whole: pull back and raise the look point by their scale.
	var big := a.scale.y
	for t in targets:
		big = maxf(big, t.scale.y)
	if big > 1.0:
		mid += Vector3(0, 1.1 * big, 0)
	tw.tween_property(rig, "pivot", mid, zoom_t).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(rig, "dist", clampf(9.0 + span * 1.1, 11.0, 22.0) * maxf(1.0, big * 0.75), zoom_t).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(rig, "pitch", deg_to_rad(CINE_PITCH), zoom_t).set_trans(Tween.TRANS_CUBIC)
	await tw.finished
	var hidden := _hide_occluders(keep, [a] + targets)
	# ---- D100 skill callout: the camera has settled; name the skill, hold, then cast
	if not call.is_empty():
		var hold := BWCombatUI.CALLOUT_HOLD if full else 0.14       # D122: SHORT ~0.3 s all told
		if skipping:
			hold = 0.05
		ui.callout(str(call.word), str(call.element), str(call.name), a.unit.name, hold)
		skill_called.emit(attacker_id, str(call.text), str(call.element))
		await get_tree().create_timer(BWCombatUI.CALLOUT_IN + hold).timeout
	elif skill_name != "":
		ui.banner(skill_name, 0.7 if full else 0.4)
	# ---- end D100

	a.face(centre)
	for t in targets:
		t.face(a.global_position)
	var melee := BWHex.distance(a.unit.pos, d.unit.pos) <= 1
	var spell := str(a.unit.weapon().get("damage_type", "")) == "spell"
	var home := a.position
	# casting: staff spells, and elemental skills used at range (a skill
	# channels first); striking: every weapon style has a strike clip
	var use_cast := spell or (not melee and element != "" and skill_name != "" and not (ranged and ranged.handles(a)))   # D165: bows and thrown blades shoot
	var clip := a.has_clip("cast") if use_cast else a.has_clip("strike")
	var to_impact := 0.0
	if use_cast and clip:
		var wind: float = vfx.windup(a) if vfx else 0.0              # ---- D167: casting circle + converge
		if skill_name != "" and a.has_clip("channel"):
			a.pose_named("channel")
			await _hold(maxf(0.55 if full else 0.25, wind))
		elif wind > 0.0:
			await _hold(wind)
		a.pose_named("cast")
		await get_tree().create_timer(maxf(a.time_to_marker("release"), 0.0)).timeout
		var rel_t: float = vfx.release(a, d, bool(results[0].result.hit)) if vfx else -1.0    # ---- D167: the element's release
		to_impact = rel_t if rel_t >= 0.0 else _projectile(a, d, true, element if element != "" else a.unit.attuned, bool(results[0].result.hit))
	elif clip:
		# the anticipation is held at "coil", then the clip drives the timing:
		# melee dashes in while both feet are off the ground (launch..land);
		# bows and pistols let fly on "release"
		a.skill = skill_clip            # ---- D102: the def's clip (spin, pistol_whip, flurry ...) when this weapon has it; else the class strike
		a.pose_named("windup")
		var heavy: float = vfx.strike_windup(a) if vfx else 0.0       # ---- D169: Triumph's held gleam
		await get_tree().create_timer(maxf(a.time_to_marker("coil"), 0.0) + 0.1 + heavy).timeout
		a.pose_named("strike")
		if vfx:
			vfx.on_strike(a, targets)                           # ---- D169: spin trail ring
		var launch := a.time_to_marker("launch")
		if melee and launch >= 0.0:
			var land := maxf(a.time_to_marker("land"), launch + 0.05)
			var gap := home.distance_to(d.position)
			var engage := float(a.character.animator.clip_meta(a.character.animator.top_clip()).get("engage", gap * 0.58))
			var dash := create_tween()
			dash.tween_interval(launch)
			dash.tween_property(a, "position", home.lerp(d.position, clampf(1.0 - engage / maxf(gap, 0.01), 0.0, 0.42)), land - launch).set_trans(Tween.TRANS_SINE)
		var rel := a.time_to_marker("release")
		if rel >= 0.0:
			await get_tree().create_timer(rel).timeout
			to_impact = _projectile(a, d, element != "", element if element != "" else a.unit.attuned, bool(results[0].result.hit))
			if vfx:
				vfx.at_release(a, targets)                      # ---- D169: Empty the Chamber's fan
		elif not melee:
			# a reach weapon or a skill at range: the bolt leaves on the hit frame
			await get_tree().create_timer(maxf(a.time_to_marker("hit"), 0.0)).timeout
			to_impact = _projectile(a, d, element != "", element if element != "" else a.unit.attuned, bool(results[0].result.hit))
		else:
			to_impact = maxf(a.time_to_marker("hit"), 0.0)
	else:
		a.skill = skill_clip if skill_clip != "" else skill_name   # the def's clip (D89; Flurry, Uppercut, Palm Burst…); "" = plain strike
		a.pose_named("cast" if spell else "windup")
		var t1 := create_tween()
		if melee:
			var lunge := home.lerp(d.position, 0.42)
			t1.tween_property(a, "position", home - (d.position - home).normalized() * 0.12, 0.16).set_ease(Tween.EASE_OUT)
			t1.tween_property(a, "position", lunge, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		else:
			t1.tween_interval(0.25)
		await t1.finished
		a.pose_named("cast" if spell else "strike")
		if not melee:
			to_impact = _projectile(a, d, spell or element != "", element if element != "" else a.unit.attuned, bool(results[0].result.hit))
	# each defender reacts by its own result (brief: kneel, dodge, block,
	# fumble block), started so the reaction's impact meets the blow
	# (a clean hit picks by context: BWReactionPick, design/art/ANIMATION.md)
	var reacts: Array = []
	for k in results.size():
		reacts.append(_pick_reaction(targets[k], results[k], melee, "%s|%d" % [attacker_id, k]))
	await _react_at(a, targets, reacts, to_impact, results, str(tc.get("flash", "full")))
	ui.odds_result(results[0].result)                # ---- D113: light what happened
	var lines: PackedStringArray = []
	var biggest := 0
	for k in results.size():
		var r: Dictionary = results[k]
		var t: BWUnitView = targets[k]
		var res: Dictionary = r.result
		var label := "MISS" if not res.hit else str(res.damage)
		if res.crit: label += "  CRIT"
		if res.glance: label += "  glance"
		if res.resisted: label += "  resisted"
		if BWSettings.value("show_numbers"):           # ---- D124
			feel.float_number(t, label, res, 1.0)       # ---- D170: sized by the hit
		_float_tags(t, r)                        # D86/D87: "Spark", "Shatter", ...
		t.refresh()
		biggest = maxi(biggest, int(res.damage))
		if res.crit:
			biggest = maxi(biggest, 999)
		lines.append("%s %s" % [t.unit.name, label.strip_edges()])
	if biggest > 0:
		feel.shake_blows(targets, results)             # ---- D170: scaled to the hit's share of max HP
	ui.feed("%s%s → %s" % [a.unit.name, (" (%s)" % skill_name) if skill_name != "" else "", ", ".join(lines)])
	# the clip hops back to its stance: return home while it is airborne
	var back := 0.25
	if clip and melee and a.time_to_marker("hop_start") > 0.0:
		await get_tree().create_timer(a.time_to_marker("hop_start")).timeout
		back = maxf(a.time_to_marker("hop_end"), 0.08)
	else:
		await _hold(0.55 if full else 0.25)
	ui.odds_hide()                                   # ---- D113
	if hint:
		ui.skip_hint(false)
	var t2 := create_tween().set_parallel(true)
	t2.tween_property(a, "position", home, back).set_trans(Tween.TRANS_SINE)
	t2.tween_method(_dim_all.bind(others), 1.0, 0.0, zoom_t * 0.9)
	t2.tween_property(rig, "pivot", saved.pos, zoom_t).set_trans(Tween.TRANS_CUBIC)
	t2.tween_property(rig, "yaw", saved.yaw, zoom_t).set_trans(Tween.TRANS_CUBIC)
	t2.tween_property(cam, "fov", saved.fov, zoom_t)
	t2.tween_property(rig, "dist", saved.dist, zoom_t)
	t2.tween_property(rig, "pitch", saved.pitch, zoom_t).set_trans(Tween.TRANS_CUBIC)
	await t2.finished
	for n in hidden:
		if is_instance_valid(n):
			n.visible = true
	rig.following = true
	rig.input_enabled = true
	ui.cinematic(false)                              # ---- D111
	a.idle()
	for t in targets:
		if t.unit.alive():
			t.idle()


## D113: the primary target's odds for the strip, "+N" for the rest.
func _odds_in(results: Array, element: String) -> void:
	var r: Dictionary = results[0]
	var seen := {}
	for x in results:
		seen[str(x.target)] = true
	ui.odds_show(r.get("odds", {}), _name(str(r.target)), seen.size() - 1, element)


## Anything standing between the cutscene camera and the fighters (a pillar,
## a raised tile, a bystander) is hidden for the shot, then restored.
func _hide_occluders(keep: Array, actors: Array) -> Array:
	var eye := cam.global_position
	var hidden: Array = []
	var candidates: Array = board_view.get_children()
	for id in _views:
		candidates.append(_views[id])
	for n in candidates:
		if n in keep or not n is Node3D or not n.visible:
			continue
		var c: Vector3 = (n as Node3D).global_position
		if n is MeshInstance3D:
			c = (n as MeshInstance3D).global_transform * (n as MeshInstance3D).get_aabb().get_center()
		for act in actors:
			var target: Vector3 = act.global_position + Vector3(0, 1.1 * act.scale.y, 0)
			var seg := target - eye
			var t := clampf((c - eye).dot(seg) / seg.length_squared(), 0.0, 1.0)
			if t > 0.05 and t < 0.92 and (eye + seg * t).distance_to(c) < 1.15:
				n.visible = false
				hidden.append(n)
				break
	return hidden


func _dim_all(x: float, nodes: Array) -> void:
	for n in nodes:
		# A view can be freed mid-cutscene (a KO from a chain arc, a splash).
		if is_instance_valid(n):
			BWLook.set_dim(n, x)


## D122 MINIMAL: no zoom, no dim, no callout. The clip plays in place
## (a projectile still flies), every target reacts on the impact, the
## numbers float and the odds strip shows briefly. Basic attacks, extra
## strikes, counters, overwatch shots and riposte answers play here, and
## shorter skills in the Fast mode. A crit gets the tiny flash (`tc.flash`).
func _quick_hit(attacker_id: String, results: Array, label_text: String, element: String = "", skill_clip: String = "", tc: Dictionary = {}) -> void:
	var a: BWUnitView = _views[attacker_id]
	var targets: Array = []
	for r in results:
		targets.append(_views[r.target])
	var r0: Dictionary = results[0]
	var d: BWUnitView = targets[0]
	a.face(d.global_position)
	for t in targets:
		t.face(a.global_position)
	var res: Dictionary = r0.result
	var spell := str(a.unit.weapon().get("damage_type", "")) == "spell"
	var melee := BWHex.distance(a.unit.pos, d.unit.pos) <= 1
	var reacts: Array = []
	for k in results.size():
		reacts.append(_pick_reaction(targets[k], results[k], melee, "%s|%s|%d" % [attacker_id, label_text, k]))
	ui.cinematic(true)                               # ---- D111
	if BWSettings.value("show_odds"):
		_odds_in(results, element)                   # ---- D113
	var to_impact := 0.0
	a.skill = skill_clip                             # the def's clip, else the class strike (never a stale one)
	a.pose_named("cast" if spell else "strike")
	var rel := a.time_to_marker("release")
	var tint := element if element != "" else a.unit.attuned
	if rel >= 0.0 or (not melee and a.time_to_marker("hit") >= 0.0):
		await get_tree().create_timer(rel if rel >= 0.0 else a.time_to_marker("hit")).timeout
		to_impact = _projectile(a, d, spell or element != "", tint, bool(res.hit))
	else:
		to_impact = maxf(a.time_to_marker("hit"), 0.0)
	await _react_at(a, targets, reacts, to_impact, results, str(tc.get("flash", "tiny")))
	ui.odds_result(res)                              # ---- D113
	var lines: PackedStringArray = []
	for k in results.size():
		var t: BWUnitView = targets[k]
		var rk: Dictionary = (results[k] as Dictionary).result
		var num := "MISS" if not rk.hit else str(rk.damage)
		if rk.get("crit", false) and rk.hit:
			num += "  CRIT"
		if BWSettings.value("show_numbers"):         # ---- D124
			feel.float_number(t, num + (("  " + label_text) if label_text != "" and k == 0 else ""), rk, 0.7)   # ---- D170
		_float_tags(t, results[k])                   # D86/D87
		t.refresh()
		lines.append("%s %s" % [t.unit.name, "miss" if not rk.hit else str(rk.damage)])
	feel.shake_blows(targets, results)               # ---- D170: gentle, scaled to the hit
	ui.feed("%s%s → %s" % [a.unit.name, (" " + label_text) if label_text != "" else "", ", ".join(lines)])
	await _hold(0.45)
	ui.odds_hide()                                   # ---- D113
	ui.cinematic(false)                              # ---- D111
	a.idle()
	for t in targets:
		if t.unit.alive():
			t.idle()


## D122: a setup skill (no blows: a guard, a paint, Transfer's lift, War
## Cry) plays in place: a short channel if the unit has one, and the feed.
## The guard / status / paint events that follow show the rest.
func _setup_beat(attacker_id: String, skill_name: String) -> void:
	var a: BWUnitView = _views.get(attacker_id)
	ui.feed("%s: %s" % [_name(attacker_id), skill_name])
	if a == null:
		return
	var show: float = vfx.setup(a) if vfx else 0.0       # ---- D169: Ley Line, War Cry, Siphon in place
	if a.has_clip("channel"):
		a.pose_named("channel")
		await _hold(maxf(0.35, show))
		a.idle()
	elif show > 0.0:
		await _hold(show)


## The reaction for one blow on one target: BWReactionPick by context
## (damage as a share of max HP, crit / glance, HP left, the target's
## friendliness and vibe), seeded per blow. Stores the pick on the result
## dict ("pick") and on the view (last_reaction) for the audio lane.
func _pick_reaction(t: BWUnitView, r: Dictionary, melee: bool, salt: String) -> String:
	var res: Dictionary = r.result
	var hp_after := int(r.get("target_hp", -1))
	if hp_after < 0:
		hp_after = t.unit.hp
	var p := BWReactionPick.pick(t.unit, res, { "ko": bool(r.get("ko", false)), "melee": melee, "hp_after": hp_after, "salt": salt })
	var info := { "tier": p.tier, "why": p.why, "damage": int(res.get("damage", 0)), "crit": bool(res.get("crit", false)),
		"glance": bool(res.get("glance", false)) }
	r["pick"] = info
	t.last_reaction = str(p.reaction)
	return str(p.reaction)


## Start each target's reaction so its "impact" frame meets the blow in
## `to_impact` seconds (a block is up, a dodge already moving), move a
## dodger by its clip's shift while it is airborne, and return at impact.
func _react_at(a: BWUnitView, targets: Array, reacts: Array, to_impact: float, results: Array = [], flash: String = "full") -> void:
	var order: Array = []
	for k in targets.size():
		order.append([maxf(0.0, to_impact - (targets[k] as BWUnitView).lead_to_impact(reacts[k])), k])
	order.sort_custom(func(x, y): return x[0] < y[0])
	var t := 0.0
	for o in order:
		if float(o[0]) > t:
			await get_tree().create_timer(float(o[0]) - t).timeout
			t = float(o[0])
		var tv: BWUnitView = targets[o[1]]
		var react: String = reacts[o[1]]
		tv.pose_named(react)
		var info: Dictionary = (results[o[1]] as Dictionary).get("pick", {}) if o[1] < results.size() else {}
		reaction_chosen.emit(tv.unit.id, react, info)
		if react == "dodge" and not tv is BWObeliskView:   # D145: a stone doesn't step aside
			_dodge_shift(a, tv)
	if to_impact > t:
		await get_tree().create_timer(to_impact - t).timeout
	# ---- D101: a crit freezes on its impact frame for the white flash
	for r in results:
		var res: Dictionary = (r as Dictionary).get("result", {}) if r is Dictionary else {}
		if bool(res.get("crit", false)) and bool(res.get("hit", true)):
			if flash == "full" and not skipping:     # ---- D122: the white-out is FULL's; else a tiny flash
				await _crit_flash(a.unit.id if a and a.unit else "")
			elif flash != "none":
				crit_flashed.emit(a.unit.id if a and a.unit else "")
				ui.crit_flash_tiny()
			break
	if feel:
		await feel.impact(a, targets, results, flash)   # ---- D167-D170: impact VFX, hit-stop, final-KO slow-mo


## The dodger's root moves only while both its feet are off the ground:
## away on launch..land, home on hop_start..hop_end (the clip's markers).
func _dodge_shift(a: BWUnitView, t: BWUnitView) -> void:
	var m := t.clip_meta_of("dodge")
	var mk: Dictionary = m.get("markers", {})
	var from := t.position
	if mk.has("launch") and mk.has("hop_start"):
		var shift: Vector3 = m.get("shift", Vector3(0, 0, -0.3))
		var to := from + t.global_basis.orthonormalized() * shift
		var dt := create_tween()
		dt.tween_interval(float(mk.launch))
		dt.tween_property(t, "position", to, float(mk.land) - float(mk.launch)).set_trans(Tween.TRANS_SINE)
		dt.tween_interval(float(mk.hop_start) - float(mk.land))
		dt.tween_property(t, "position", from, float(mk.hop_end) - float(mk.hop_start)).set_trans(Tween.TRANS_SINE)
		return
	var away: Vector3 = (t.position - a.position).normalized() * 0.3
	var tw := create_tween()
	tw.tween_property(t, "position", from + away, 0.12)
	tw.tween_property(t, "position", from, 0.2).set_delay(0.25)


## Launch a projectile at the target and return its flight time (the
## caller waits that long with a timer, so a missing clip or a freed node
## can never hang the combat). The model is the weapon's own
## (BWProjectileFlight / BWProjectileView): bows loose an ARROW from the
## string (it arcs, turns along its flight and sticks in the target),
## pistols fire a BULLET with its tracer and a muzzle flash, spells and
## reach weapons send a spinning BOLT wrapped in the element aura.
func _projectile(a: BWUnitView, d: BWUnitView, spell: bool, element: String = "", hit: bool = true) -> float:
	if ranged and ranged.handles(a, spell):          # ---- D165: arrows / thrown blades (vfx_ranged.gd)
		return ranged.shoot(a, d, element, hit)
	var kind := BWProjectileFlight.kind_for(a.unit.weapon_class, spell)
	var from: Variant = a.weapon_tip()
	if (from as Vector3).distance_to(a.global_position) > 3.5 or (from as Vector3).y < a.global_position.y + 0.3:
		from = a.global_position + Vector3(0, 1.2, 0)
	if kind == "arrow" and a.character:
		var nk: Variant = a.character.nocked_arrow()
		if nk != null:
			from = nk                          # straight off the string: a seamless hand-over
	var tint := element if element != "" else a.unit.element
	var f := BWProjectileFlight.launch(self, kind, from, d, tint if (spell or element != "" or kind == "arrow") else "", hit)
	return f.duration


func _shake(strength: float) -> void:
	if not BWHitFeel.shake_on():                     # ---- D170: the "Screen shake" setting
		return
	var tw := create_tween()
	var base := cam.h_offset
	for i in 4:
		tw.tween_property(cam, "h_offset", base + randf_range(-1, 1) * strength, 0.03)
		tw.parallel().tween_property(cam, "v_offset", randf_range(-1, 1) * strength, 0.03)
	tw.tween_property(cam, "h_offset", base, 0.04)
	tw.parallel().tween_property(cam, "v_offset", 0.0, 0.04)


func _float_text(v: Node3D, text: String, col: Color, hold: float = 0.6) -> void:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0016
	l.font_size = 40
	l.outline_size = 14
	l.modulate = col
	l.outline_modulate = Color.BLACK
	l.render_priority = 20             # D102: over the board's transparent pass (it washed floaters out)
	l.outline_render_priority = 19
	add_child(l)
	l.global_position = v.global_position + Vector3(0, _label_height(v), 0)
	var tw := create_tween()
	tw.tween_property(l, "global_position", l.global_position + Vector3(0, 0.6, 0), hold).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.25)
	tw.tween_callback(l.queue_free)


# ---- D100 / D101 / D102 (presentation lane, marked edits) ----

## D100: what the callout says for a skill: the element word when the skill
## carries one ("Fire" + "Tempest"), else just the name. The name comes from
## the def (BWSkillRegistry, through BWSkills), falling back to the key.
## {} for basic attacks (no callout).
func _callout_for(key: String, element: String) -> Dictionary:
	if key == "" or key == "basic":
		return {}
	var row := BWSkills.get_skill(key)
	if bool(row.get("basic", false)):
		return {}
	var nm := str(row.get("name", ""))
	if nm == "":
		nm = key.replace("_", " ").capitalize()
	var word := element.capitalize() if element != "" else ""
	if word != "" and nm.to_lower().begins_with(word.to_lower()):
		word = ""                                  # "Fire Tempest" already says it
	return { "word": word, "element": element, "name": nm, "text": (word + " " + nm).strip_edges() }


## D101: the crit's hit-stop. The world freezes on the impact frame (a near-
## zero time scale, so springs and markers stay sane), the white flash
## collapses to a line and goes, then time resumes and the impact and the
## reaction play on. Timers here ignore the time scale; the scale is always
## restored.
const CRIT_PRE_FREEZE := 0.04
const CRIT_TIME_SCALE := 0.001

func _crit_flash(unit_id: String) -> void:
	_freezing = true
	Engine.time_scale = CRIT_TIME_SCALE
	await get_tree().create_timer(CRIT_PRE_FREEZE, true, false, true).timeout
	crit_flashed.emit(unit_id)
	var dur := ui.crit_flash()
	await get_tree().create_timer(dur, true, false, true).timeout
	_freezing = false
	Engine.time_scale = SKIP_SCALE if skipping else 1.0     # D123: a hold that began during the freeze keeps going


func _exit_tree() -> void:
	if Engine.time_scale < 0.01 or skipping or _freezing:
		Engine.time_scale = 1.0                # never leave the game frozen (or fast)
	if skipping:
		for bus in ["SFX", "Voice"]:
			BWAudio._apply(bus)


## D102: a status floats as its name (with its glyph: Pinned's nail) over a
## smaller line of its rule ("no skills", "no crit, reach 2").
func _float_status(v: BWUnitView, key: String, label: String, rule: String) -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_position = v.global_position + Vector3(0, _label_height(v), 0)
	var l := Label3D.new()
	l.text = label
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0016
	l.font_size = 24
	l.outline_size = 10
	l.modulate = Color(0.9, 0.9, 0.94)
	l.outline_modulate = Color.BLACK
	l.render_priority = 20             # D102: over the board's transparent pass (it washed floaters out)
	l.outline_render_priority = 19
	root.add_child(l)
	if rule != "":
		var r := Label3D.new()
		r.text = rule
		r.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		r.no_depth_test = true
		r.fixed_size = true
		r.pixel_size = 0.0016
		r.font_size = 16
		r.outline_size = 8
		r.modulate = Color(0.72, 0.72, 0.76)
		r.outline_modulate = Color.BLACK
		r.render_priority = 20             # D102: over the board's transparent pass (it washed floaters out)
		r.outline_render_priority = 19
		r.offset = Vector2(0, -26)
		root.add_child(r)
	var glyph := BWCombatUI.status_glyph(key)
	if glyph:
		var sp := Sprite3D.new()
		sp.texture = glyph
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.no_depth_test = true
		sp.fixed_size = true
		sp.pixel_size = 0.0016 * 0.42
		sp.render_priority = 21
		# above the word, point down: the nail is driven into it
		sp.offset = Vector2(0, 150.0)
		root.add_child(sp)
		var drop := create_tween()                  # the nail is driven in
		drop.tween_property(sp, "offset:y", 64.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var tw := create_tween()
	tw.tween_property(root, "global_position", root.global_position + Vector3(0, 0.6, 0), 1.1).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(k: float):
		for c in root.get_children():
			if c is Label3D:
				(c as Label3D).modulate.a = k
				(c as Label3D).outline_modulate.a = k
			elif c is Sprite3D:
				(c as Sprite3D).modulate.a = k, 1.0, 0.0, 0.3)
	tw.tween_callback(root.queue_free)

# ---- end D100 / D101 / D102 ----


# ---------------------------------------------------------------- helpers

## D86/D87: the named riders on one blow ("Spark", "Shatter", "Backstab" ...)
## float as small tags under the damage number, in the rider's element colour
## (Spark thunder purple, Shatter ice cyan), and tell the audio lane.
const TAG_COLOR := { "Spark": "thunder", "Shatter": "ice" }

func _float_tags(t: BWUnitView, r: Dictionary) -> void:
	var tags: Array = r.get("tags", [])
	for i in tags.size():
		var tag := str(tags[i])
		var col := BWLook.element_color(TAG_COLOR[tag]) if TAG_COLOR.has(tag) else Color(0.9, 0.9, 0.9)
		var l := Label3D.new()
		l.text = tag
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.fixed_size = true
		l.pixel_size = 0.0016
		l.font_size = 26
		l.outline_size = 10
		l.modulate = col
		l.outline_modulate = Color.BLACK
		l.render_priority = 20             # D102: over the board's transparent pass (it washed floaters out)
		l.outline_render_priority = 19
		add_child(l)
		l.global_position = t.global_position + Vector3(0, _label_height(t) - 0.35 - 0.3 * i, 0)
		var tw := create_tween()
		tw.tween_property(l, "scale", Vector3.ONE * 1.25, 0.08).from(Vector3.ONE * 0.6)
		tw.tween_property(l, "scale", Vector3.ONE, 0.1)
		tw.tween_interval(0.7)
		tw.tween_property(l, "modulate:a", 0.0, 0.25)
		tw.tween_callback(l.queue_free)
		rider_shown.emit(t.unit.id, tag)

## Floating numbers start just above the HP bar (rig figures are 2.2 tall,
## the primitive stand-in ~1.8; the boss is scaled).
func _label_height(v: Node3D) -> float:
	return (v as BWUnitView).head_height() + 1.0 if v is BWUnitView else 2.4


func _unit_pos(h: Vector2i) -> Vector3:
	return board_view.top_center(h)


func _face_all() -> void:
	# idle units face the nearest foe, so the board reads as a standoff
	for u in battle.units:
		if not u.alive():
			continue
		var foes := battle.foes_of(u)
		if foes.is_empty():
			continue
		var near: BWUnit = foes[0]
		for f in foes:
			if BWHex.distance(u.pos, f.pos) < BWHex.distance(u.pos, near.pos):
				near = f
		_views[u.id].face(_unit_pos(near.pos))


func _closest_angle(from: float, to: float) -> float:
	return from + wrapf(to - from, -PI, PI)


func _name(id: String) -> String:
	var v: BWUnitView = _views.get(id)
	return v.unit.name if v else id


# ---- D140/D145 obelisks (combat lane) ----

## The hint's tail in an obelisk fight: the next stone to pulse, how many
## turns away, and what it does (flat damage: no roll, no DEF / RES / ward).
func pulse_hint() -> String:
	if not battle.objective_mode():
		return ""
	var u := battle.current()
	var q := battle.queue
	for k in range(maxi(battle.turn_index, 0) + 1, q.size()):
		var w: BWUnit = q[k]
		if BWObelisk.is_objective(w) and w.alive():
			var o := w as BWObelisk
			var in_n := k - battle.turn_index
			return "\n%s pulses in %d turn%s: %d to every unit (no roll, ignores DEF, RES and wards), %s one hex%s" % [
				o.name, in_n, "" if in_n == 1 else "s", o.pulse_damage, "pushed" if o.pulse_kind == "push" else "pulled",
				" (%s: HP %d → %d)" % [u.name, u.hp, maxi(0, u.hp - o.pulse_damage)] if u and u.team == "player" else ""]
	var left: Array = battle.objectives().filter(func(o): return o.alive())
	return "\nNext round the stones pulse again: %s" % ", ".join(left.map(
		func(o): return "%s %d" % [o.name, (o as BWObelisk).pulse_damage]))


## An obelisk's turn on screen: the camera finds it, its glyphs flare, the
## ring runs (out for the Lantern's push, in for the Well's pull), the board
## shakes, a pitched sound from the existing set. Then the damage floats and
## the pushes / pulls play as their own events.
func _pulse(e: Dictionary) -> void:
	var v := _views.get(str(e.unit)) as BWObeliskView
	var push := str(e.get("kind", "push")) == "push"
	ui.feed("[b]%s pulses[/b]: %d to every unit, %s" % [_name(str(e.unit)), int(e.damage),
		"everyone pushed one hex away" if push else "everyone pulled one hex toward it"])
	ui.banner("%s %s" % [_name(str(e.unit)), "breathes out" if push else "breathes in"], 0.9)
	if v == null:
		return
	rig.follow(v.global_position)
	await get_tree().create_timer(0.25).timeout
	var dur := v.pulse(str(e.get("kind", "push")))
	# existing SFX, pitched: a slow low detonation for the push, a dark swell for the pull
	if push:
		BWSfx.play("tile_detonate", v, { "pitch": 0.55, "gain_db": -2.0, "stack": true, "tag": "pulse" })
		BWSfx.play("cast_whoom", v, { "pitch": 0.6, "gain_db": -4.0, "stack": true, "delay": 0.05, "tag": "pulse" })
	else:
		BWSfx.play("elem_dark", v, { "pitch": 0.5, "gain_db": -1.0, "stack": true, "tag": "pulse" })
		BWSfx.play("cast_whoom", v, { "pitch": 0.45, "gain_db": -5.0, "stack": true, "delay": 0.3, "tag": "pulse" })
	_shake(0.08)
	await get_tree().create_timer(dur * 0.7).timeout
	_shake(0.12)

# ---- end D140/D145 ----
