class_name BWTutorial
extends Node
## D223-D226: the guided practice fight (title screen: T, or "tutorial").
## A scripted fight on the yard (BWTutorialScript: a fixed squad, three
## enemies who hold still, a fixed seed), one prompt at a time in the coach
## panel (BWCoach), each pointing at the board or the HUD and waiting for the
## player to do the thing; then the summary with its level up, a perk pick
## and a skill pick, and a closing card on downtime, rooms and the shop.
##
## It never touches the player's run or save: the squad lives in its own
## BWRun, built here and dropped at the end; settings it leans on (the odds
## strip, full cutscenes) are set in memory for its length and put back.
##
## The combat screen is the real one. Two marked hooks there (D223) let the
## tutorial steer it: `gate` (may this click / key / menu choice go through?)
## and `turn_hook` (pass the turns it doesn't want played).

signal finished(completed: bool)

var run: BWRun
var screen: BWCombatScreen
var coach: BWCoach
var steps: Array = []
var index := -1
var want: BWUnit = null
var rear := Vector2i(-1, -1)
var done_ids: Array = []              # steps finished, in order (probes)
var history: Array = []               # the fight's events, kept once the screen is gone (probes)
var results: BWResultsScreen
var picker: BWPicker
var card: ClosingCard
var _ui: CanvasLayer
var _next := false
var _abort := false
var _skip_to := -1
var _exiting := false
var _hist0 := 0
var _hover_t := 0.0
var _saved := {}
var _report := {}
var ready_for_input := false           # the current step is up and waiting (probes)


func _ready() -> void:
	for k in ["show_odds", "cutscenes", "skip_hold"]:            # in memory only, put back on exit
		_saved[k] = BWSettings._v.get(k, BWSettings.DEFAULTS.get(k))
	BWSettings._v["show_odds"] = true
	BWSettings._v["cutscenes"] = "default"
	steps = BWTutorialScript.steps()
	run = BWTutorialScript.make_run()
	screen = BWCombatScreen.new()
	screen.configure(BWTutorialScript.MAP, run.squad.duplicate(), BWTutorialScript.make_enemies(), [], BWTutorialScript.SEED)
	screen.gate = _gate
	screen.turn_hook = _turn_hook
	add_child(screen)
	_ui = CanvasLayer.new()
	_ui.layer = 20
	add_child(_ui)
	coach = BWCoach.new()
	coach.targets = _targets
	coach.esc_passes = _esc_passes
	add_child(coach)
	coach.next_pressed.connect(func(): _next = true)
	coach.skip_pressed.connect(_skip_lesson)
	coach.exit_pressed.connect(exit)
	_run.call_deferred()


func _exit_tree() -> void:
	for k in _saved:
		BWSettings._v[k] = _saved[k]


func battle() -> BWBattle:
	return screen.battle if screen and is_instance_valid(screen) else null


func step() -> Dictionary:
	return steps[index] if index >= 0 and index < steps.size() else {}


func unit(id: String) -> BWUnit:
	var b := battle()
	return b._unit(id) if b else null


# ---------------------------------------------------------------- the script

func _run() -> void:
	await _idle()
	index = 0
	while index < steps.size() and not _exiting:
		var s: Dictionary = steps[index]
		_abort = false
		var lesson := int(s.get("lesson", 0))
		if lesson > 0 and (index == 0 or int(steps[index - 1].get("lesson", 0)) != lesson) and battle() and not battle().over:
			screen.ui.banner(BWTutorialScript.lesson_name(lesson), 1.1)
		await _do_step(s)
		if _exiting:
			return
		if _skip_to >= 0:
			index = _skip_to
			_skip_to = -1
			continue
		done_ids.append(str(s.id))
		index += 1
	if not _exiting:
		finished.emit(true)


func _do_step(s: Dictionary) -> void:
	ready_for_input = false
	var w := str(s.get("wait", "next"))
	var b := battle()
	var in_fight := b != null and not b.over and not w in ["results", "pick", "card"]
	if w == "over" and (b == null or b.over):
		return                                   # the Surge already won it
	coach.dock_low(w in ["results", "pick", "card"])
	if in_fight:
		await _idle()
		var actor := str(s.get("actor", ""))
		if actor != "":
			await _give_turn(unit(actor), bool(s.get("fresh", false)))
		if str(s.get("stage", "")) != "":
			await _stage(str(s.stage))
		if _abort:
			return
		_hist0 = b.history.size()
	coach.show_step(int(s.get("lesson", 0)), BWTutorialScript.LESSONS.size() - 1,
		BWTutorialScript.lesson_name(int(s.get("lesson", 0))), str(s.text), index, steps.size(), w in ["next", "hover", "results"])
	_next = false
	_hover_t = 0.0
	if in_fight and battle() and not battle().over:
		screen._show_options()
	match w:
		"results":
			await _results()
			return
		"pick":
			await _pick(s.get("pick", {}))
			return
		"card":
			await _card()
			return
	ready_for_input = true
	while not _abort and not _exiting:
		if _step_done(s):
			break
		await get_tree().process_frame
	ready_for_input = false
	if _abort or _exiting:
		return
	if w in ["move", "undo", "act", "over"]:
		await _idle()


## Has the player done what the step asks?
func _step_done(s: Dictionary) -> bool:
	var w := str(s.get("wait", "next"))
	if _next and w in ["next", "hover"]:
		return true
	var b := battle()
	if b == null:
		return false
	var act: Dictionary = s.get("act", {})
	match w:
		"move":
			var to: Vector2i = rear if str(act.get("hex", "")) == "rear" else act.hex
			return _new_events().any(func(e): return e.type == "move" and str(e.get("kind", "")) != "place" \
				and e.unit == want.id and (e.path as Array).back() == to)
		"undo":
			return _new_events().any(func(e): return e.type == "undo_move")
		"forecast":
			return screen.ui.forecast_open() and screen._pending_target != null and screen._pending_target.id == str(act.target)
		"aim":
			return str(screen._skill.get("key", "")) == str(act.key) and str(screen._skill.get("element", "")) == str(act.element)
		"act":
			var k := str(act.get("kind", ""))
			var hit := _new_events().any(func(e):
				if k == "swap":
					return e.type == "swap"
				if k == "attack":
					return e.type == "attack" and e.unit == want.id
				return e.type == "skill" and str(e.skill) == str(act.key))
			if hit and not BWTutorialScript.keep_actor(b, want):
				want = null                   # D223: let the turn order run on to the next player
			return hit
		"hover":
			var h: Vector2i = s.get("hex", Vector2i(-9, -9))
			var seen: bool = screen._hover == h and (screen.readability.card_shown() or screen.readability.preview.shown())
			_hover_t = _hover_t + get_process_delta_time() if seen else 0.0
			return _hover_t > 0.7
		"over":
			return b.over
	return false


func _new_events() -> Array:
	var b := battle()
	return b.history.slice(_hist0) if b else []


## Wait until the screen has played everything out.
func _idle() -> void:
	var guard := 0
	while screen and is_instance_valid(screen) and (screen.battle == null or screen._busy) and guard < 6000:
		guard += 1
		await get_tree().process_frame
	await get_tree().process_frame


## Give the turn to `u` (D223): end the waiting player's turn and pass the
## rest until it's `u`'s; the same rule as BWTutorialScript.give_turn.
func _give_turn(u: BWUnit, fresh: bool) -> void:
	var b := battle()
	if b == null or b.over or u == null or not u.alive():
		return
	want = u
	var cur := b.current()
	if cur == u and not (fresh and (u.acted or u.moved)):
		return
	_clear_aim()
	if cur != null and cur.team == "player":
		b.end_turn()
	screen._after_events()
	await _idle()


func _clear_aim() -> void:
	if screen.ui.forecast_open():
		screen.ui.hide_forecast()
	screen._pending_target = null
	screen._pending_skill = {}
	screen._skill = {}


## Staging (BWTutorialScript.stage_rules), then play what it emitted.
func _stage(name: String) -> void:
	var b := battle()
	var r := BWTutorialScript.stage_rules(b, name, run)
	if r.has("rear"):
		rear = r.rear
	if not screen._queue.is_empty():
		screen._after_events()
	await _idle()
	if name == "worn":
		for id in screen._views:
			screen._views[id].refresh()


# ---------------------------------------------------------------- the hooks (D223)

## BWCombatScreen.turn_hook: pass every turn that isn't the wanted unit's.
func _turn_hook(u: BWUnit) -> bool:
	var b := battle()
	if b == null or b.over or not BWTutorialScript.passes(u, want):
		return false
	b.end_turn()
	return true


## BWCombatScreen.gate: may this input go through? Only what the step asks
## for (camera and hovering are never gated); the last step is free play.
func _gate(kind: String, arg: Variant) -> bool:
	var s := step()
	if s.is_empty() or coach.dialog_open() or not ready_for_input:
		return false
	var w := str(s.get("wait", ""))
	var act: Dictionary = s.get("act", {})
	if w == "over":
		return kind != "wait" and (kind != "cancel" or screen.ui.forecast_open() or not screen._skill.is_empty())
	match kind:
		"click":
			var h: Vector2i = arg
			match w:
				"move":
					return h == (rear if str(act.get("hex", "")) == "rear" else act.hex)
				"forecast":
					return unit(str(act.target)) != null and h == unit(str(act.target)).pos
				"act":
					if act.has("hex"):
						return h == act.hex
					if act.has("target") and unit(str(act.target)) != null:
						return h == unit(str(act.target)).pos
			return false
		"confirm":
			return w == "act" and str(act.get("kind", "")) in ["attack", "skill"]
		"cancel":
			return w == "undo"
		"swap":
			return w == "act" and str(act.get("kind", "")) == "swap"
		"skill":
			return w == "aim" and str(arg) == "%s|%s" % [act.key, act.element]
	return false


## Esc goes to the game (not the coach's dialog) on the undo step, and in
## free play while there's an aim or a forecast to back out of.
func _esc_passes() -> bool:
	var s := step()
	var w := str(s.get("wait", ""))
	if w == "undo":
		return true
	return w == "over" and screen and is_instance_valid(screen) and (screen.ui.forecast_open() or not screen._skill.is_empty())


# ---------------------------------------------------------------- highlights

## What the coach outlines this frame, from the step's `hl`.
func _targets() -> Array:
	var s := step()
	var hl: Dictionary = s.get("hl", {})
	var out: Array = []
	if hl.is_empty() or not ready_for_input and not str(s.get("wait", "")) in ["results"]:
		return out
	var b := battle()
	if hl.has("ui"):
		var c := ui_target(str(hl.ui), s)
		if c != null and c.is_visible_in_tree():
			out.append({ "rect": c.get_global_rect() })
		elif str(hl.ui) == "level_up" and results:
			for l in results.find_children("*", "Label", true, false):
				if (l as Label).text.begins_with("Level up"):
					out.append({ "rect": (l as Label).get_global_rect() })
		return out
	if b == null or screen == null or screen._busy:
		return out
	if hl.has("hex"):
		var h: Vector2i = rear if str(hl.hex) == "rear" else hl.hex
		out.append(_hex_target(h))
	for h in hl.get("hexes", []):
		out.append(_hex_target(h))
	if hl.has("unit"):
		var u := unit(str(hl.unit))
		if u and u.alive() and screen._views.has(u.id):
			var v: Node3D = screen._views[u.id]
			out.append({ "point": screen.cam.unproject_position(screen.board_view.top_center(u.pos)), "ring": 30.0,
				"arrow": screen.cam.unproject_position(v.global_position + Vector3(0, 2.3, 0)) })
	return out


func _hex_target(h: Vector2i) -> Dictionary:
	return { "point": screen.cam.unproject_position(screen.board_view.top_center(h)), "ring": 26.0 }


## The HUD control a step points at ("forecast", "confirm", "order", "menu",
## "swap", "skill", "notes", "hit_row"), or null.
func ui_target(what: String, s: Dictionary = {}) -> Control:
	if screen == null or not is_instance_valid(screen):
		return null
	var ui := screen.ui
	match what:
		"forecast":
			return ui._forecast
		"order":
			return ui._order_panel
		"menu":
			return ui._menu
		"swap":
			return ui.find_child("swap_weapon", true, false) as Control
		"confirm":
			for c in ui._forecast.find_children("*", "Button", true, false):
				if (c as Button).text.begins_with("Confirm"):
					return c
		"notes":
			for c in ui._fc_rows.find_children("*", "RichTextLabel", true, false):
				var t := (c as RichTextLabel).get_parsed_text()
				if t.contains("Shatter") or t.contains("arcs to"):
					return c
			return ui._forecast
		"hit_row":
			for row in ui._fc_rows.get_children():
				if row is HBoxContainer and row.get_child_count() > 0 and row.get_child(0) is Label \
						and (row.get_child(0) as Label).text == "Hit chance":
					return row
			return ui._forecast
		"skill":
			var act: Dictionary = s.get("act", {})
			var key := str(s.get("hl", {}).get("key", act.get("key", "")))
			return menu_button(key, str(act.get("element", "")) if key == str(act.get("key", "")) else "")
	return null


## The menu row to press for a skill in an element: the row itself, or its
## accordion header while the group is shut (BWCombatUI.set_skills).
func menu_button(key: String, element: String) -> Button:
	var name := str(BWSkills.get_skill(key).get("name", key))
	var rows: Array = screen.ui._menu_list.get_children().filter(func(c): return c is Button)
	for i in rows.size():
		var t: String = (rows[i] as Button).text
		if t == name or t == name + " +" or t.begins_with(name + "  ·  ") or t.begins_with(name + " +  ·  "):
			return rows[i]
		if t in ["▸ " + name, "▾ " + name, "▸ " + name + " +", "▾ " + name + " +"]:
			if t.begins_with("▸"):
				return rows[i]                   # shut: open the group first
			for j in range(i + 1, rows.size()):
				var tj: String = (rows[j] as Button).text
				if not tj.begins_with("      "):
					break
				if tj.strip_edges() == element.capitalize():
					return rows[j]
			return rows[i]
	return null


# ---------------------------------------------------------------- after the fight

## The summary with the level up, from the tutorial's own run (D225).
func _results() -> void:
	var b := battle()
	var enemies: Array = b.units.filter(func(x): return x.team == "enemy") if b else []
	history = b.history.duplicate() if b else []
	_report = run.after_fight(true, run.squad, enemies.filter(func(e): return not e.alive()), enemies, history)
	if screen and is_instance_valid(screen):
		screen.queue_free()
		screen = null
		await get_tree().process_frame
	BWMusic.play("rest")
	results = BWResultsScreen.new()
	results.run = run
	results.report = _report
	add_child(results)
	ready_for_input = true
	_next = false
	while not _abort and not _exiting and not _next and not results._sent:
		await get_tree().process_frame
	ready_for_input = false
	if is_instance_valid(results):
		results.queue_free()
	results = null


## One pick over a dark backdrop (D225): the real picker, two cards.
func _pick(p: Dictionary) -> void:
	var u := run.unit(str(p.get("unit", "")))
	if u == null:
		return
	var req := { "kind": str(p.kind) }
	if req.kind == "perk":
		req["element"] = str(p.element)
	else:
		req["weapon"] = str(p.weapon)
		if BWPicks.skill_picks_owed(u, req.weapon) <= 0:
			u.bonus_skills[req.weapon] = int(u.bonus_skills.get(req.weapon, 0)) + 1
	var back := _backdrop()
	picker = BWPicker.new(u, req, "tutorial")
	back.add_child(picker)
	ready_for_input = true
	var got := [""]
	picker.chosen.connect(func(id): got[0] = id)
	while got[0] == "" and not _abort and not _exiting:
		await get_tree().process_frame
	ready_for_input = false
	if got[0] != "":
		BWPicks.apply(u, req, got[0])
	back.queue_free()
	picker = null


func _backdrop() -> Control:
	var back := ColorRect.new()
	back.color = Color(0.02, 0.02, 0.025)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(back)
	return back


## The closing card (D226), then back to the title.
func _card() -> void:
	if screen and is_instance_valid(screen):
		screen.queue_free()
		screen = null
	var back := _backdrop()
	card = ClosingCard.new()
	back.add_child(card)
	ready_for_input = true
	var go := [false]
	card.back.connect(func(): go[0] = true)
	while not go[0] and not _abort and not _exiting:
		await get_tree().process_frame
	ready_for_input = false


# ---------------------------------------------------------------- skip / exit

func _skip_lesson() -> void:
	var s := step()
	_skip_to = BWTutorialScript.lesson_start(steps, int(s.get("lesson", 0)) + 1)
	if _skip_to >= steps.size():
		exit()
		return
	# a skipped fight goes straight to the summary
	if int(steps[_skip_to].get("lesson", 0)) == 10 and str(steps[_skip_to].get("wait", "")) != "results" and battle() and battle().over:
		_skip_to = BWTutorialScript.lesson_start(steps, 10)
	if screen and is_instance_valid(screen) and not screen._busy and battle() and not battle().over:
		_clear_aim()
	_abort = true


func exit() -> void:
	if _exiting:
		return
	_exiting = true
	_abort = true
	finished.emit(false)


## The closing card: three screenshot-style mini panels, then back.
class ClosingCard:
	extends Control
	signal back

	func _init() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		theme = BWStyle.theme()

	func _ready() -> void:
		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(center)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 18)
		center.add_child(v)
		var t := Label.new()
		t.text = "Between fights"
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.add_theme_font_size_override("font_size", 40)
		v.add_child(t)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 22)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_child(row)
		row.add_child(_panel("Downtime", "downtime",
			"Each unit spends the day on one of two activities. Specialize trains what it has, Branch out adds an element and a weapon, Wander is a gamble."))
		row.add_child(_panel("Rooms", "rooms",
			"From fight 3 you pick a room: Standard, or Hard for better spoils. Some Hard rooms are special encounters."))
		row.add_child(_panel("The shop", "shop",
			"Trade gear one for one. An imbuement scroll costs two spare items and adds an element's enchantment to any item."))
		var b := Button.new()
		b.name = "card_back"
		b.text = "Back to the title  [Enter]"
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(320, 46)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.add_theme_font_size_override("font_size", BWStyle.F_BODY)
		b.pressed.connect(func(): back.emit())
		v.add_child(b)

	func _panel(title: String, kind: String, text: String) -> Control:
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", BWStyle.box_style())
		p.custom_minimum_size = Vector2(440, 0)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 10)
		p.add_child(v)
		v.add_child(BWStyle.section_label(title))
		var shot := MiniShot.new()
		shot.kind = kind
		shot.custom_minimum_size = Vector2(404, 196)
		v.add_child(shot)
		var rt := BWGlossary.Rich.new()
		rt.fit_content = true
		rt.scroll_active = false
		rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rt.custom_minimum_size = Vector2(404, 0)
		rt.add_theme_font_size_override("normal_font_size", BWStyle.F_SMALL)
		rt.add_theme_color_override("default_color", BWStyle.LABEL)
		rt.set_glossed(text)
		v.add_child(rt)
		return p

	func _unhandled_input(ev: InputEvent) -> void:
		if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			back.emit()
			get_viewport().set_input_as_handled()


## A small drawn "screenshot" of a screen, in the game's own pieces: the
## downtime tiles (BWDowntimeWidgets glyphs), two room cards with the
## encounters, the shop's scroll row (BWItemIcons.draw_scroll).
class MiniShot:
	extends Control
	var kind := ""

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.02, 0.02, 0.025))
		draw_rect(r, Color(1, 1, 1, 0.35), false, 1.0)
		var f := get_theme_font("font", "Label")
		match kind:
			"downtime":
				var names := ["specialize", "branch_out", "wander"]
				var w := (size.x - 48.0) / 3.0
				for i in 3:
					var tr := Rect2(Vector2(12 + i * (w + 12), 22), Vector2(w, size.y - 44))
					_tile(tr, i == 1)
					var ink := Color.BLACK if i == 1 else Color.WHITE
					var g := minf(tr.size.y * 0.45, 54.0)
					BWDowntimeWidgets.draw_icon(self, names[i], Rect2(tr.position + Vector2((tr.size.x - g) * 0.5, 16), Vector2(g, g)), ink)
					draw_string(f, Vector2(tr.position.x, tr.end.y - 18), str(BWRun.CHOICE_NAMES[names[i]]), HORIZONTAL_ALIGNMENT_CENTER, tr.size.x, 17, ink)
			"rooms":
				var w := (size.x - 36.0) / 2.0
				for i in 2:
					var cr := Rect2(Vector2(12 + i * (w + 12), 14), Vector2(w, size.y - 64))
					_tile(cr, false)
					var hard := i == 1
					draw_rect(Rect2(cr.position + Vector2(10, 10), Vector2(cr.size.x - 20, cr.size.y * 0.42)), Color(0.12, 0.12, 0.13))
					for k in 5:
						var c := cr.position + Vector2(26 + k * 28, 24 + (k % 2) * 12)
						draw_circle(c, 8, Color(0.3, 0.3, 0.32))
					draw_string(f, Vector2(cr.position.x, cr.end.y - 38), "Hard" if hard else "Standard", HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, 19, Color.WHITE)
					draw_string(f, Vector2(cr.position.x, cr.end.y - 14), "a tier up, +1 item" if hard else "the usual spoils", HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, 14, BWStyle.TEXT_DIM)
				draw_string(f, Vector2(0, size.y - 16), "Horde  ·  Colossus  ·  Blanks  ·  Elemental Beings", HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, BWStyle.LABEL)
			"shop":
				var els := ["fire", "water", "ice", "thunder", "wind", "light", "dark"]
				var s := (size.x - 24.0) / els.size()
				for i in els.size():
					BWItemIcons.draw_scroll(self, Rect2(Vector2(12 + i * s + 4, 24), Vector2(s - 8, s - 8)), els[i])
				var y := 24.0 + s + 14.0
				for i in 2:
					var ir := Rect2(Vector2(size.x * 0.5 - 116 + i * 62, y), Vector2(52, 52))
					_tile(ir, false)
					draw_line(ir.position + Vector2(14, 38), ir.position + Vector2(38, 14), Color(1, 1, 1, 0.7), 3.0)
				draw_string(f, Vector2(size.x * 0.5 + 16, y + 34), "=  1 scroll", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)

	func _tile(r: Rect2, lit: bool) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.97, 0.97, 0.97) if lit else Color(0.07, 0.07, 0.08)
		sb.set_corner_radius_all(6)
		sb.border_color = Color.WHITE if lit else Color(1, 1, 1, 0.55)
		sb.set_border_width_all(2 if lit else 1)
		sb.anti_aliasing = true
		draw_style_box(sb, r)
