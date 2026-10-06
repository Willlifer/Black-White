class_name BWDowntimeScreen
extends Node3D
## Brief: your units in various poses, each under their own spotlight, in an
## empty marble school hall (D83). D127: each unit takes ONE of three choices
## (Specialize, Branch out, Wander), shown by name only. "Progress day" plays
## a 5 s day of units acting their choice out (Specialize: training at the
## dummy; Branch out: trying an unfamiliar weapon; Wander: walking off into
## the dark and coming back). Then the results, slowly: one unit at a time
## under its light, a card in its own words (BWRun.downtime's report), found
## items with their icons; a click goes on. Picks the unit earned open right
## after its card. Then "Day N", any key.
##
## The hall is BWHall (floor, reflection, columns, windows, spotlights).
## Each unit stands in its pool in a hold picked from its personality (the
## weapon-handling holds, D73), turned a little its own way. The selected
## unit's light comes up, the others dim, and the camera eases toward it.
##
## The flow probe drives `_plans`, `_refresh_go()`, `_progress()`, then the
## cards (`card_unit`, any key) and `picker`; the screen audio watches `_go`
## and is_processing_unhandled_input().

signal done

const RESULT_SECONDS := 5.0
const SPACING := 2.55
const MIN_CONTINUE := 1.0           # the day card ignores keys this long
const CARD_MIN := 0.6               # a result card ignores clicks this long
const FLAVOUR := "After a good night's rest, your team has a day to recover and prepare for the next fight."
## Per vibe (BWAnimClips.personality): the holds to stand in, in preference
## order, and how far the unit turns off square (toward the middle).
const VIBE_HOLDS := {
	"stoic": ["ground", "side", "guard"], "cocky": ["shoulder", "side", "guard"],
	"dreamy": ["side", "shoulder", "guard"], "fussy": ["guard", "side", "reverse"],
	"bouncy": ["shoulder", "reverse", "guard"],
}
const VIBE_TURN := { "stoic": 0.0, "cocky": 0.42, "dreamy": -0.32, "fussy": 0.18, "bouncy": 0.28 }

var run: BWRun
var _views: Array = []
var _spot_ids: Array = []
var _home: Array = []               # each view's standing position and yaw
var _plans := {}                    # unit id -> its choice ("" = none yet)
var _asked := {}                    # unit id -> the "ask" bark played today (BARKS.md: once per unit per day)
var _sel := 0
var _cam: Camera3D
var _cam_pos := Vector3(0, 3.4, 11.5)
var _cam_look := Vector3(0, 1.9, 0)
var _cam_look_now := Vector3(0, 1.9, 0)
var _hall: BWHall
var _ui_root: Control
var _plan_ui: Control               # everything that hides when the day starts
var _advice: Label
var _advice_box: PanelContainer
var _card_icon: BWWidgets.LivePortrait
var _card_bar: BWWidgets.HPBar
var _card_text: RichTextLabel
var _actions_title: Label
var _actions_count: Label
var _tiles: HBoxContainer
var _tile_btns := {}
var _go: BWDowntimeWidgets.ProgressArrow
var _tags: Array = []               # per view: { box, name, chips[] }
var _tag_layer: Control
var _rng := RandomNumberGenerator.new()
var _day := false
var _continue_t := -1.0
var _sent := false
var _sun: BWDowntimeWidgets.SunTrack
var _fov := 34.0
var picker: BWPicker                # D90: the open picker (the flow probe answers it)
var _t := 0.0
## The results (D127): the day's reports, the card on screen, its unit.
var reports: Array = []
var card: Control
var card_unit: BWUnit
var _card_t := -1.0
var _card_next := false             # a click / key asked for the next card
var _icon_slots: Array = []         # [TextureRect, item] waiting for BWItemIcons
var option_btns: Array = []         # Branch out's option cards on the open result card (D128)
var _option := -1                   # the option taken (keys 1/2 or a click)


func _ready() -> void:
	_rng.seed = run.seed_value + run.day * 101
	_hall = BWHall.new()
	add_child(_hall)
	BWItemIcons.ensure(self)
	BWPortraits.prewarm(run.squad)       # D156: the hall card and pickers
	var n := run.squad.size()
	for i in n:
		var u: BWUnit = run.squad[i]
		u.team = "player"
		var v := BWUnitView.new()
		add_child(v)
		v.setup(u)
		v.show_label(false)
		var at := _slot(i, n)
		v.position = at
		var yaw := _stand(v, u, i, n)
		_home.append({ "pos": at, "yaw": yaw })
		_views.append(v)
		_spot_ids.append(_hall.add_spot(at, 0.6))
		_plans[u.id] = ""
	_cam = Camera3D.new()
	_cam.fov = 34.0
	_cam.position = _cam_pos
	add_child(_cam)
	_cam.look_at(_cam_look)
	_cam.make_current()
	_build_ui()
	_select(0)
	_cam.position = _cam_pos
	_cam_look_now = _cam_look
	_cam.look_at(_cam_look_now)


## Where unit i of n stands: a shallow arc facing the camera.
func _slot(i: int, n: int) -> Vector3:
	var sp := minf(SPACING, 15.5 / maxf(1.0, n - 1.0))
	var x := (i - (n - 1) / 2.0) * sp
	return Vector3(x, 0, -0.035 * x * x)


## "Various poses": a hold from the unit's personality (each neighbour a
## different one where the weapon allows), turned its own way. Returns the yaw.
func _stand(v: BWUnitView, u: BWUnit, i: int, n: int) -> float:
	var vibe := BWAnimClips.vibe_of(u)
	var to_cam := Vector3(0, 0, 13) - v.position
	var yaw := atan2(to_cam.x, to_cam.z)
	var side := -signf(v.position.x) if absf(v.position.x) > 0.1 else 1.0
	yaw += float(VIBE_TURN.get(vibe, 0.2)) * side
	v.rotation.y = yaw
	if v.character and v.character.animator:
		var have: Array = BWAnimHandling.holds(v.character.weapon_style())
		var prev := str(_views[i - 1].get_meta("hold", "")) if i > 0 and _views.size() >= i else ""
		var pick := "guard"
		for h in VIBE_HOLDS.get(vibe, ["guard"]):
			if h in have and h != prev:
				pick = h
				break
		if pick != "guard":
			_after(0.35 + 0.18 * i, func():
				if is_instance_valid(v) and not _day:
					v.handle(pick))
		v.set_meta("hold", pick)
	return yaw


func _process(delta: float) -> void:
	_t += delta
	var k := 1.0 - exp(-delta * 3.2)
	_cam.position = _cam.position.lerp(_cam_pos, k)
	_cam.fov = lerpf(_cam.fov, _fov, k)
	_cam_look_now = _cam_look_now.lerp(_cam_look, k)
	_cam.look_at(_cam_look_now)
	_hall.follow(_cam)
	_place_tags()
	if _continue_t >= 0.0:
		_continue_t += delta
	if _card_t >= 0.0:
		_card_t += delta
	for slot in _icon_slots.duplicate():
		var tex := BWItemIcons.for_item(slot[1])
		if tex != null and is_instance_valid(slot[0]):
			(slot[0] as TextureRect).texture = tex
			_icon_slots.erase(slot)


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	_ui_root = Control.new()
	_ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.theme = BWStyle.theme()
	ui.add_child(_ui_root)
	_ui_root.add_child(top_scrim())
	_tag_layer = Control.new()
	_tag_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tag_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(_tag_layer)
	for i in _views.size():
		_tags.append(_make_tag(i))
	_plan_ui = Control.new()
	_plan_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_plan_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(_plan_ui)
	_build_header()
	_build_card()
	_build_actions()
	_go = BWDowntimeWidgets.ProgressArrow.new()
	_go.anchor_left = 1.0
	_go.anchor_right = 1.0
	_go.anchor_top = 1.0
	_go.anchor_bottom = 1.0
	_go.offset_left = -24 - 262
	_go.offset_right = -24
	_go.offset_top = -24 - 196
	_go.offset_bottom = -24
	_go.pressed.connect(_progress)
	_plan_ui.add_child(_go)
	_refresh_go()


## A soft black fade down from the top edge, so the header and the speech
## plate read over the bright windows.
static func top_scrim() -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.82))
	g.set_color(1, Color(0, 0, 0, 0))
	g.add_point(0.45, Color(0, 0, 0, 0.5))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 64
	var r := TextureRect.new()
	r.texture = gt
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.anchor_right = 1.0
	r.offset_bottom = 190
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func _outlined(l: Label, size: int, outline: int = 6) -> Label:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", outline)
	return l


func _build_header() -> void:
	var top := VBoxContainer.new()
	top.position = Vector2(30, 18)
	top.add_theme_constant_override("separation", -2)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plan_ui.add_child(top)
	top.add_child(BWStyle.section_label("Downtime  ·  the hall"))
	var day := _outlined(Label.new(), 46, 10)
	day.text = "Day %d" % run.day
	top.add_child(day)
	var sub := _outlined(Label.new(), BWStyle.F_SMALL)
	sub.text = ("the Giant waits" if run.is_boss() else "before fight %d" % run.fight) + "   ·   one choice each"
	sub.add_theme_color_override("font_color", BWStyle.TEXT_DIM)
	top.add_child(sub)
	var info := Button.new()
	info.text = "Info  [I]"
	info.focus_mode = Control.FOCUS_NONE
	info.anchor_left = 1.0
	info.anchor_right = 1.0
	info.offset_left = -24 - 150
	info.offset_right = -24
	info.offset_top = 24
	info.offset_bottom = 24 + 46
	info.pressed.connect(open_codex)
	_plan_ui.add_child(info)
	# the author's flavour line, top centre; the selected unit's speech plate under it
	var flav := _outlined(Label.new(), BWStyle.F_BODY - 1, 8)
	flav.text = FLAVOUR
	flav.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flav.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	flav.anchor_left = 0.5
	flav.anchor_right = 0.5
	flav.offset_left = -400
	flav.offset_right = 400
	flav.offset_top = 22
	flav.autowrap_mode = TextServer.AUTOWRAP_WORD
	_plan_ui.add_child(flav)
	_advice_box = PanelContainer.new()
	_advice_box.add_theme_stylebox_override("panel", BWStyle.prompt_style())
	_advice_box.anchor_left = 0.5
	_advice_box.anchor_right = 0.5
	_advice_box.offset_left = -330
	_advice_box.offset_right = 330
	_advice_box.offset_top = 66
	_advice_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_advice_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plan_ui.add_child(_advice_box)
	_advice = Label.new()
	_advice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_advice.autowrap_mode = TextServer.AUTOWRAP_WORD
	_advice.add_theme_font_size_override("font_size", BWStyle.F_SUB - 1)
	_advice.custom_minimum_size = Vector2(636, 0)
	_advice_box.add_child(_advice)


## The selected unit's card, in the combat card's language (BWCombatUI:
## frame weight, head icon over a ticked HP bar, name, weapon · element,
## HP / Move / Speed, the seven stats, Wander's badges).
func _build_card() -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", BWStyle.frame_style())
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.anchor_top = 1.0
	p.anchor_bottom = 1.0
	p.offset_left = 24
	p.offset_right = 24 + 440
	p.offset_top = -24 - 196
	p.offset_bottom = -24
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_plan_ui.add_child(p)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	p.add_child(h)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	h.add_child(left)
	_card_icon = BWWidgets.LivePortrait.new(null, 88.0)       # D156: live, the unit is on stage
	left.add_child(_card_icon)
	_card_bar = BWWidgets.HPBar.new(Vector2(88, 10))
	left.add_child(_card_bar)
	_card_text = RichTextLabel.new()
	_card_text.bbcode_enabled = true
	_card_text.fit_content = true
	_card_text.scroll_active = false
	_card_text.custom_minimum_size = Vector2(318, 0)
	_card_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(_card_text)


func _fill_card(u: BWUnit) -> void:
	_card_icon.set_unit(u)
	_card_icon.selected = true
	_card_bar.set_hp(u.hp, u.max_hp())
	var dim := BWStyle.TEXT_DIM.to_html(false)
	var lab := BWStyle.LABEL.to_html(false)
	var el := BWLook.element_color(u.element)
	var wname := BWText.weapon(u.weapon_class)
	var lines: PackedStringArray = []
	lines.append("[font_size=%d][b]%s[/b][/font_size]  [color=#%s]Lv %d[/color]" % [BWStyle.F_NAME - 2, u.name, dim, u.level])
	lines.append("[font_size=%d][color=#%s]%s (%s)   [/color][color=#%s]◆[/color] [color=#%s]%s[/color][/font_size]" % [
		BWStyle.F_SMALL, lab, wname, u.expertise_letter(u.weapon_class), el.to_html(false),
		BWGearText.readable(el).to_html(false), u.element.capitalize()])
	lines.append_array(BWCombatUI.badge_lines(u, BWStyle.F_SMALL - 2))     # D129/D130
	lines.append("[font_size=%d]HP %d    Move %d    Speed %d[/font_size]" % [BWStyle.F_SMALL + 1, u.max_hp(), u.move_range(), u.speed()])
	var st: PackedStringArray = []
	for s in BWUnit.STATS:
		st.append("%s [b]%d[/b]" % [s.to_upper(), u.stat(s)])
	lines.append("[font_size=%d][color=#%s]%s\n%s[/color][/font_size]" % [BWStyle.F_SMALL - 2, dim,
		"   ".join(st.slice(0, 4)), "   ".join(st.slice(4))])
	_card_text.text = "\n".join(lines)


## D127: three big tiles, the names and nothing else (no effect line, no
## tooltip); keys 1-3.
func _build_actions() -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", BWStyle.frame_style())
	p.anchor_left = 0.0
	p.anchor_right = 1.0
	p.anchor_top = 1.0
	p.anchor_bottom = 1.0
	p.offset_left = 24 + 440 + 14
	p.offset_right = -24 - 262 - 14
	p.offset_top = -24 - 196
	p.offset_bottom = -24
	_plan_ui.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	v.add_child(head)
	_actions_title = BWStyle.section_label("Today")
	_actions_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_actions_title.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	head.add_child(_actions_title)
	_actions_count = Label.new()
	_actions_count.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 1)
	_actions_count.add_theme_color_override("font_color", BWStyle.TEXT_DIM)
	head.add_child(_actions_count)
	_tiles = HBoxContainer.new()
	_tiles.add_theme_constant_override("separation", 12)
	_tiles.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_tiles)
	var key := 1
	for c in BWRun.DOWNTIME_CHOICES:
		var t := BWDowntimeWidgets.ChoiceTile.new(c, str(key))
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.size_flags_vertical = Control.SIZE_EXPAND_FILL
		t.pressed.connect(_choose.bind(c))
		_tiles.add_child(t)
		_tile_btns[c] = t
		key += 1


## A name and the chosen chip under each spotlight.
func _make_tag(i: int) -> Dictionary:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_tag_layer.add_child(box)
	var nm := _outlined(Label.new(), BWStyle.F_SMALL, 7)
	nm.text = (run.squad[i] as BWUnit).name
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(nm)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	var c := BWDowntimeWidgets.Chip.new()
	row.add_child(c)
	return { "box": box, "name": nm, "chips": [c] }


func _place_tags() -> void:
	if _cam == null:
		return
	for i in mini(_tags.size(), _views.size()):
		var v: BWUnitView = _views[i]
		var tag: Dictionary = _tags[i]
		var p := v.global_position + Vector3(0, 0, BWHall.SPOT_R * 0.95)
		if _cam.is_position_behind(p):
			tag.box.visible = false
			continue
		var s := _cam.unproject_position(p)
		var box: Control = tag.box
		box.reset_size()
		box.position = s + Vector2(-box.size.x * 0.5, 6)


func _refresh_tags() -> void:
	for i in _tags.size():
		var u: BWUnit = run.squad[i]
		var tag: Dictionary = _tags[i]
		var c: BWDowntimeWidgets.Chip = tag.chips[0]
		var ch := str(_plans.get(u.id, ""))
		c.set_action(ch, str(BWDowntimeWidgets.info(ch)[1]) if ch != "" else "")
		var sel := i == _sel and not _day
		(tag.name as Label).add_theme_color_override("font_color", Color.WHITE if sel or _day else BWStyle.TEXT_DIM)
		(tag.name as Label).text = ("▸ " if sel else "") + u.name + ("  ✓" if ch != "" and not _day else "")


func _select(i: int) -> void:
	_focus(i)
	var at: Vector3 = _home[_sel].pos
	_cam_pos = Vector3(at.x * 0.10, 3.7, 16.4)
	_cam_look = Vector3(at.x * 0.16, 1.15, at.z)
	var u: BWUnit = run.squad[_sel]
	if not _asked.has(u.id) and str(_plans[u.id]) == "":
		# BARKS.md: "ask" once per unit per day
		var b := BWBarks.pick("downtime_advice", u.friendliness, _squad_trust(u), "any", "ask", _rng)
		_asked[u.id] = b
		if not b.is_empty():
			BWVoice.say(self, str(b.voice_clip), float(u.cosmetics.get("voice_pitch", 1.0)))
	var said: Dictionary = _asked.get(u.id, {})
	_say(u, BWBarks.fill(str(said.get("line", "...")), { "speaker": u.name }) if not said.is_empty() else "")
	_fill_card(u)
	_refresh_panel()
	_refresh_tags()


## The chosen unit's light up, the others dimmed (shared with BWPrepScreen).
func _focus(i: int) -> void:
	_sel = wrapi(i, 0, _views.size())
	for k in _views.size():
		_hall.set_spot_level(_spot_ids[k], 1.0 if k == _sel else 0.42)
		var v: BWUnitView = _views[k]
		var to := 0.0 if k == _sel else 0.28
		var from := float(v.get_meta("dim", 0.0))
		if absf(from - to) > 0.001:
			create_tween().tween_method(func(x: float): v.set_meta("dim", x); BWLook.set_dim(v, x), from, to, 0.3)


## The unit nearest a click (on its body, foot to head), or -1.
func _unit_at(p: Vector2) -> int:
	var best := -1
	var best_d := 70.0
	for i in _views.size():
		var v: BWUnitView = _views[i]
		var foot := _cam.unproject_position(v.global_position)
		var head := _cam.unproject_position(v.global_position + Vector3(0, v.head_height() + 0.2, 0))
		var d := Geometry2D.get_closest_point_to_segment(p, foot, head).distance_to(p)
		if d < best_d:
			best_d = d
			best = i
	return best


func _say(u: BWUnit, line: String) -> void:
	_advice_box.visible = line != ""
	_advice.text = "%s:  “%s”" % [u.name, line]
	_advice_box.reset_size()


func _squad_trust(u: BWUnit) -> String:
	var pts: Array = []
	for o in run.squad:
		if o != u:
			pts.append(int(run.trust.get(BWRun.trust_key(u.id, o.id), 0)))
	pts.sort()
	var med: int = pts[pts.size() / 2] if not pts.is_empty() else 0
	return "trusted" if med >= 8 else ("acquainted" if med >= 3 else "strangers")


func _refresh_panel() -> void:
	var u: BWUnit = run.squad[_sel]
	var ch := str(_plans[u.id])
	_actions_title.text = ("WHAT WILL %s DO TODAY?" % u.name).to_upper()
	_actions_count.text = "←/→ next unit" if ch != "" else "pick one  ·  1 – 3"
	for c in _tile_btns:
		var t: BWDowntimeWidgets.ChoiceTile = _tile_btns[c]
		t.chosen = c == ch
		t.queue_redraw()


## A tile was pressed: that is the unit's choice for the day (another press
## changes it).
func _choose(c: String) -> void:
	var u: BWUnit = run.squad[_sel]
	if _day or not c in BWRun.DOWNTIME_CHOICES:
		return
	var first := str(_plans[u.id]) == ""
	_plans[u.id] = c
	if first or _rng.randf() < 0.5:
		var react := BWBarks.pick("downtime_advice", u.friendliness, _squad_trust(u), "any", c, _rng)
		if not react.is_empty():
			_say(u, BWBarks.fill(str(react.line), { "speaker": u.name, "element": u.element, "weapon": u.weapon_class }))
			BWVoice.say(self, str(react.voice_clip), float(u.cosmetics.get("voice_pitch", 1.0)))
	_refresh_panel()
	_refresh_tags()
	_refresh_go()


func _clear_sel() -> void:
	_plans[(run.squad[_sel] as BWUnit).id] = ""
	_refresh_panel()
	_refresh_tags()
	_refresh_go()


func _refresh_go() -> void:
	var ready := 0
	for id in _plans:
		if str(_plans[id]) != "":
			ready += 1
	_go.disabled = ready < _plans.size() or _day
	_go.set_count(ready, _plans.size())
	_refresh_tags()


func open_codex(tab: String = "elements") -> void:
	BWCodex.summon(self, tab)


func _unhandled_input(ev: InputEvent) -> void:
	var pressed: bool = (ev is InputEventKey and ev.pressed and not ev.echo) \
		or (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventJoypadButton and ev.pressed)
	if _day:
		if card != null and not option_btns.is_empty():
			if ev is InputEventKey and ev.pressed and not ev.echo:
				var n: int = ev.keycode - KEY_1
				if n >= 0 and n < option_btns.size() and _card_t >= CARD_MIN:
					_option = n
			return                                   # an option must be taken (a click on its card, or 1/2)
		if card != null and pressed and _card_t >= CARD_MIN:
			_card_next = true
		elif card == null and pressed and _continue_t >= MIN_CONTINUE and not _sent:
			_sent = true
			done.emit()
		return
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_LEFT: _select(_sel - 1)
			KEY_RIGHT: _select(_sel + 1)
			KEY_TAB: _select(_next_unready())
			KEY_I: open_codex()
			KEY_ESCAPE: BWPauseMenu.open(self, "hall")          # ---- D124
			KEY_BACKSPACE, KEY_DELETE: _clear_sel()
			KEY_ENTER, KEY_KP_ENTER:
				if not _go.disabled:
					_progress()
			_:
				var n: int = ev.keycode - KEY_1
				if n >= 0 and n < BWRun.DOWNTIME_CHOICES.size():
					_choose(BWRun.DOWNTIME_CHOICES[n])
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var best := _unit_at(ev.position)
		if best >= 0:
			_select(best)


func _next_unready() -> int:
	for k in range(1, _views.size() + 1):
		var i := wrapi(_sel + k, 0, _views.size())
		if str(_plans[(run.squad[i] as BWUnit).id]) == "":
			return i
	return _sel + 1


# ---------------------------------------------------------------- the day

func _progress() -> void:
	if _day:
		return
	_day = true
	_go.disabled = true
	set_process_unhandled_input(false)          # the screen audio's cue: the day starts
	var plan: Array = []
	for u in run.squad.slice(0, _views.size()):
		plan.append([u.id, str(_plans[u.id])])
	var before := run.squad.size()
	reports = run.progress_day(plan, false)       # Branch out's options wait for the card
	var recruits: Array = run.squad.slice(before)
	# planning UI out; every light up; the camera pulls back to the whole hall
	var tw := create_tween()
	tw.tween_property(_plan_ui, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func(): _plan_ui.visible = false)
	for k in _views.size():
		_hall.set_spot_level(_spot_ids[k], 1.0)
		var v: BWUnitView = _views[k]
		var from := float(v.get_meta("dim", 0.0))
		if from > 0.0:
			create_tween().tween_method(func(x: float): v.set_meta("dim", x); BWLook.set_dim(v, x), from, 0.0, 0.3)
	var n_all := _views.size() + recruits.size()
	var half_w := absf(_recruit_slot(recruits.size() - 1).x) if not recruits.is_empty() else absf(_slot(n_all - 1, n_all).x)
	# wider and a touch up: the windows, the beam and the rafters over the lineup
	_cam_pos = Vector3(0, 3.3, 15.8 + maxf(0.0, half_w - 6.4) * 1.3)
	_cam_look = Vector3(0, 2.15, 0)
	_fov = 39.0
	_refresh_tags()
	_build_day_ui()
	# the day: dawn to dusk over RESULT_SECONDS
	_hall.set_time(0.0)
	var sun := create_tween()
	sun.tween_method(func(f: float): _hall.set_time(f); _sun.f = f; _sun.queue_redraw(), 0.0, 1.0, RESULT_SECONDS)
	var dur := RESULT_SECONDS - 0.7
	for i in _views.size():
		var u: BWUnit = run.squad[i]
		get_tree().create_timer(0.25 + 0.09 * i).timeout.connect(_act.bind(i, str(_plans[u.id]), _report_for(u.id), dur - 0.09 * i))
	for j in recruits.size():
		get_tree().create_timer(RESULT_SECONDS * 0.55).timeout.connect(_arrive.bind(recruits[j], j))
	await get_tree().create_timer(RESULT_SECONDS).timeout
	_end_of_day()


func _report_for(id: String) -> Dictionary:
	for r in reports:
		if r.unit == id:
			return r
	return {}


func _build_day_ui() -> void:
	_sun = BWDowntimeWidgets.SunTrack.new()
	_sun.title = "Day %d" % (run.day - 1)
	_sun.anchor_left = 0.5
	_sun.anchor_right = 0.5
	_sun.offset_left = -280
	_sun.offset_right = 280
	_sun.offset_top = 22
	_sun.offset_bottom = 22 + 92
	_sun.modulate.a = 0.0
	_ui_root.add_child(_sun)
	create_tween().tween_property(_sun, "modulate:a", 1.0, 0.4)


## Unit i acts its choice out under its light for `dur` seconds (D127).
func _act(i: int, choice: String, rep: Dictionary, dur: float) -> void:
	if i >= _views.size():
		return
	var v: BWUnitView = _views[i]
	var u: BWUnit = run.squad[i]
	var home: Dictionary = _home[i]
	var tag: Dictionary = _tags[i]
	(tag.chips[0] as BWDowntimeWidgets.Chip).active = true
	(tag.chips[0] as BWDowntimeWidgets.Chip).queue_redraw()
	match choice:
		"specialize":
			# training at the dummy: windup, strike, again, then an element cast into it
			var dummy := _dummy(home.pos + _side(home.pos) * 0.95 + Vector3(0, 0, 0.75))
			v.face(dummy.global_position)
			for k in 2:
				_after(0.1 + k * 1.3, func(): if is_instance_valid(v): v.pose_named("windup"))
				_after(0.5 + k * 1.3, func(): if is_instance_valid(v): v.pose_named("strike"))
				_after(0.95 + k * 1.3, func(): if is_instance_valid(dummy): _rock(dummy))
			_after(dur * 0.62, func(): _cast(v, u.element))
			_after(dur, func(): _shrink(dummy); _home_pose(v, home))
		"branch_out":
			_try_weapon(v, u, rep, home, dur)
		"wander":
			# walks off into the dark, is gone a while, comes back
			var away: Vector3 = home.pos + Vector3(-_side(home.pos).x * 2.2, 0, -7.5)
			var t1 := dur * 0.3
			v.face(away)
			v.pose_named("walk")
			var tw := create_tween()
			tw.tween_property(v, "position", away, t1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
			tw.tween_callback(func(): v.visible = false)
			tw.tween_interval(dur * 0.32)
			tw.tween_callback(func(): v.visible = true; v.face(home.pos); v.pose_named("walk"))
			tw.tween_property(v, "position", home.pos, t1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tw.tween_callback(func():
				_home_pose(v, home)
				_burst(v.global_position + Vector3(0, 1.2, 0), "", 1.4 if rep.get("jackpot", false) else 0.5))
		_:
			v.pose_named("idle")


## Branch out: the unit holds the unfamiliar weapon it found (shown on the
## view only; the rules already put it in the inventory), turns it over,
## tries a clumsy swing, then goes back to its own.
func _try_weapon(v: BWUnitView, u: BWUnit, rep: Dictionary, home: Dictionary, dur: float) -> void:
	var found: Dictionary = {}
	for it in rep.get("items", []):
		if str(it.slot) == "main_hand":
			found = it
	if found.is_empty() and not rep.get("options", []).is_empty() and str(rep.options[0].weapon) != "":
		# the choice waits for the card: show a model of the first option's class
		var wc := str(rep.options[0].weapon)
		var models: Array = BWData.table("equipment").filter(func(r): return str(r.slot) == "main_hand" and str(r.weight) == wc)
		if not models.is_empty():
			found = { "base": str(models[0].id), "weight": wc, "slot": "main_hand", "enchant": "", "tier": "E", "stats": {} }
	var own: Dictionary = u.equipment.get("main_hand", {})
	var own_class := u.weapon_class
	var own_model := u.weapon_model
	var put_back := func():
		if found.is_empty() or not is_instance_valid(v):
			return
		u.equipment["main_hand"] = own
		u.weapon_class = own_class
		u.weapon_model = own_model
		v.refresh_equipment()
	if not found.is_empty() and v.character:
		u.equipment["main_hand"] = found
		u.weapon_class = str(found.weight)
		u.weapon_model = str(found.base)
		v.refresh_equipment()
		u.equipment["main_hand"] = own          # the sheet is untouched while the view shows it
		u.weapon_class = own_class
		u.weapon_model = own_model
	v.face(v.global_position + Vector3(0, 0, 5) + _side(home.pos) * 2.0)
	if not (v.handle("admire") or v.handle("heft")):
		v.pose_named("idle_look")
	_after(dur * 0.4, func(): if is_instance_valid(v): v.pose_named("windup"))
	_after(dur * 0.4 + 0.45, func(): if is_instance_valid(v): v.pose_named("strike"))
	_after(dur * 0.4 + 0.9, func():
		if is_instance_valid(v):
			v.pose_named("stricken" if v.has_clip("stricken") else "idle_look")
			_burst(v.weapon_tip(), "", 0.4))
	_after(dur, func(): put_back.call(); _home_pose(v, home))


## A recruit walks in out of the dark to a new spotlight at the row's end.
## Recruits stand on past the end of the row, alternating sides.
func _recruit_slot(j: int) -> Vector3:
	var right := j % 2 == 0
	var end: Vector3 = _home.back().pos if right else _home.front().pos
	var x := end.x + (SPACING * (1 + j / 2)) * (1.0 if right else -1.0)
	return Vector3(x, 0, -0.035 * x * x)


func _arrive(u: BWUnit, j: int) -> void:
	u.team = "player"
	var v := BWUnitView.new()
	add_child(v)
	v.setup(u)
	v.show_label(false)
	var at := _recruit_slot(j)
	v.position = at + Vector3(signf(at.x) * 1.5, 0, -5.0)
	var spot := _hall.add_spot(at, 0.0)
	v.face(at)
	v.pose_named("walk")
	var tw := create_tween()
	tw.tween_property(v, "position", at, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		_hall.set_spot_level(spot, 1.0)
		v.face(Vector3(0, 0, 13))
		v.pose_named("idle"))


func _home_pose(v: BWUnitView, home: Dictionary) -> void:
	if not is_instance_valid(v):
		return
	v.visible = true
	v.position = home.pos
	v.rotation.y = home.yaw
	v.pose_named("idle")


## Toward the hall's middle (the side with room for props).
func _side(at: Vector3) -> Vector3:
	return Vector3(-1.0 if at.x > 0.1 else 1.0, 0, 0)


func _after(t: float, f: Callable) -> void:
	get_tree().create_timer(t).timeout.connect(f)


# ---------------------------------------------------------------- the results (D127)

func _end_of_day() -> void:
	for i in _views.size():
		_home_pose(_views[i], _home[i])
	for t in _tags:
		(t.chips[0] as BWDowntimeWidgets.Chip).active = false
		(t.chips[0] as BWDowntimeWidgets.Chip).queue_redraw()
	create_tween().tween_property(_sun, "modulate:a", 0.0, 0.4)
	create_tween().tween_property(_tag_layer, "modulate:a", 0.0, 0.4)
	set_process_unhandled_input(true)
	for k in reports.size():
		var u := run.unit(str(reports[k].unit))
		var i := run.squad.find(u)
		if u == null or i < 0 or i >= _views.size():
			continue
		await _show_report(reports[k], i, k)
		await _resolve_picks(u)
	await _resolve_picks(null)                   # a recruit's first perk, anything left
	_day_card()


## One unit reports: its light up, the camera beside it, a card in its own
## words. Waits for a click / key (after CARD_MIN).
func _show_report(rep: Dictionary, i: int, k: int) -> void:
	var u: BWUnit = run.squad[i]
	card_unit = u
	_focus(i)
	var at: Vector3 = _home[i].pos
	_cam_pos = Vector3(at.x + 2.6, 2.0, at.z + 9.2)
	_cam_look = Vector3(at.x + 2.0, 1.05, at.z)
	_fov = 34.0
	var v: BWUnitView = _views[i]
	v.face(Vector3(at.x + 2.0, 0, at.z + 8.0))
	if rep.get("jackpot", false):
		_flash()
		v.pose_named("cheer_cool" if v.has_clip("cheer_cool") else "cheer")
	elif rep.get("levels", 0) > 0 or rep.get("choice", "") == "specialize":
		v.pose_named("cheer" if v.has_clip("cheer") else "idle")
	card = _report_card(rep, k)
	_ui_root.add_child(card)
	card.modulate.a = 0.0
	create_tween().tween_property(card, "modulate:a", 1.0, 0.35)
	_card_t = 0.0
	_card_next = false
	if rep.get("pending", false):
		# D128 Branch out: the player takes one of the (up to) two pairings
		_option = -1
		while _option < 0:
			await get_tree().process_frame
		run.branch_pick(u, rep, _option)
		option_btns = []
		card.queue_free()
		card = _report_card(rep, k)
		_ui_root.add_child(card)
		v.pose_named("cheer" if v.has_clip("cheer") else "idle")
		_card_t = 0.0
		_card_next = false
	while not _card_next:
		await get_tree().process_frame
	var c := card
	card = null
	_card_t = -1.0
	var tw := create_tween()
	tw.tween_property(c, "modulate:a", 0.0, 0.2)
	tw.tween_callback(c.queue_free)
	_home_pose(v, _home[i])


## The card: the choice, the name, the headline in quotes, one line per
## outcome (element words and enchanted item names in their colour, a found
## item with its icon), and where we are in the queue.
func _report_card(rep: Dictionary, k: int) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", BWStyle.frame_style())
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.anchor_left = 0.5
	p.anchor_right = 1.0
	p.anchor_top = 0.5
	p.anchor_bottom = 0.5
	p.offset_left = 10
	p.offset_right = -40
	p.offset_top = -250
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var u: BWUnit = run.unit(str(rep.unit))
	v.add_child(BWStyle.section_label("%s  ·  day %d" % [str(BWRun.CHOICE_NAMES.get(rep.choice, rep.choice)), run.day - 1]))
	var nm := Label.new()
	nm.text = str(rep.name)
	nm.add_theme_font_size_override("font_size", BWStyle.F_NAME + 6)
	v.add_child(nm)
	var head := RichTextLabel.new()
	head.bbcode_enabled = true
	head.fit_content = true
	head.scroll_active = false
	head.custom_minimum_size = Vector2(600, 0)
	head.add_theme_font_size_override("normal_font_size", BWStyle.F_SUB + 3)
	head.add_theme_font_size_override("bold_font_size", BWStyle.F_SUB + 3)
	head.add_theme_font_size_override("italics_font_size", BWStyle.F_SUB + 3)
	head.add_theme_font_size_override("bold_italics_font_size", BWStyle.F_SUB + 3)
	head.text = "[i]“%s”[/i]" % _rich(str(rep.headline), rep.get("items", []))
	v.add_child(head)
	var rule := ColorRect.new()
	rule.color = Color(1, 1, 1, 0.25)
	rule.custom_minimum_size = Vector2(0, 2)
	v.add_child(rule)
	option_btns = []
	if rep.get("pending", false):
		var opts := HBoxContainer.new()
		opts.add_theme_constant_override("separation", 14)
		v.add_child(opts)
		for i in rep.options.size():
			var b := _option_card(rep.options[i], i)
			opts.add_child(b)
			option_btns.append(b)
	for l in rep.get("lines", []):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		v.add_child(row)
		var it: Dictionary = l.get("item", {})
		if not it.is_empty():
			var well := PanelContainer.new()
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(1, 1, 1, 0.08)
			sb.border_color = BWLook.element_color(BWRun.item_element(it)) if BWRun.item_element(it) != "" else Color(1, 1, 1, 0.4)
			sb.set_border_width_all(2)
			sb.set_corner_radius_all(6)
			well.add_theme_stylebox_override("panel", sb)
			row.add_child(well)
			var ic := TextureRect.new()
			ic.custom_minimum_size = Vector2(64, 64)
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ic.texture = BWItemIcons.for_item(it)
			if ic.texture == null:
				_icon_slots.append([ic, it])
			well.add_child(ic)
		else:
			var dot := Label.new()
			dot.text = "◆" if str(l.get("element", "")) != "" else "·"
			dot.custom_minimum_size = Vector2(22, 0)
			dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			if str(l.get("element", "")) != "":
				dot.add_theme_color_override("font_color", BWLook.element_color(str(l.element)))
			row.add_child(dot)
		var t := RichTextLabel.new()
		t.bbcode_enabled = true
		t.fit_content = true
		t.scroll_active = false
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		t.add_theme_font_size_override("normal_font_size", BWStyle.F_BODY + (6 if rep.get("jackpot", false) else 0))
		t.add_theme_font_size_override("bold_font_size", BWStyle.F_BODY + (6 if rep.get("jackpot", false) else 0))
		t.text = _rich(str(l.text), [it] if not it.is_empty() else [])
		row.add_child(t)
	if u != null and u.rogue and rep.get("jackpot", false):
		var b := RichTextLabel.new()
		b.bbcode_enabled = true
		b.fit_content = true
		b.text = "\n".join(BWCombatUI.badge_lines(u, BWStyle.F_SMALL))
		v.add_child(b)
	var foot := Label.new()
	var owes := u != null and not BWPicks.next_request(u).is_empty()
	var what := "click to choose what you earned" if owes else "click to go on"
	if rep.get("pending", false):
		what = "pick one  ·  click a card, or %s" % ("1 / 2" if rep.options.size() > 1 else "1")
	foot.text = "%d of %d   ·   %s" % [k + 1, reports.size(), what]
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	foot.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 1)
	foot.add_theme_color_override("font_color", BWStyle.TEXT_DIM)
	v.add_child(foot)
	return p


## One Branch out option as a card: the new element (its colour, big) and the
## new weapon class, with its key. Nothing about what follows.
func _option_card(opt: Dictionary, i: int) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(270, 150)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var el := str(opt.element)
	var ec := BWLook.element_color(el) if el != "" else Color.WHITE
	for st in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.16, 0.16, 0.18, 0.96) if st == "hover" else Color(0.06, 0.06, 0.07, 0.95)
		sb.set_corner_radius_all(8)
		sb.border_color = ec if st != "normal" else Color(ec.r, ec.g, ec.b, 0.7)
		sb.set_border_width_all(3 if st != "normal" else 2)
		sb.border_width_left = 10
		b.add_theme_stylebox_override(st, sb)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 24
	col.offset_top = 12
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)
	var key := Label.new()
	key.text = str(i + 1)
	key.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	key.add_theme_font_size_override("font_size", 14)
	col.add_child(key)
	var e := Label.new()
	e.text = el.capitalize() if el != "" else "—"
	e.add_theme_font_size_override("font_size", BWStyle.F_NAME)
	e.add_theme_color_override("font_color", BWGearText.readable(ec))
	col.add_child(e)
	var w := Label.new()
	w.text = ("+ the " + BWRun.class_name_of(str(opt.weapon))) if str(opt.weapon) != "" else ""
	w.add_theme_font_size_override("font_size", BWStyle.F_SUB)
	col.add_child(w)
	b.pressed.connect(func():
		if _card_t >= CARD_MIN:
			_option = i)
	return b


## BBCode for a report line: enchanted item names bold in their element's
## colour, element words in theirs.
func _rich(text: String, items: Array) -> String:
	text = text.replace("[", "(").replace("]", ")")
	var marks := {}
	var n := 0
	for it in items:
		if it.is_empty():
			continue
		var nm := BWRun.item_name(it).replace("[", "(").replace("]", ")")
		if not text.contains(nm):
			continue
		var el := BWRun.item_element(it)
		var col := BWGearText.readable(BWLook.element_color(el)).to_html(false) if el != "" else "ffffff"
		var tok := "\u0001%d\u0002" % n
		n += 1
		text = text.replace(nm, tok)
		marks[tok] = "[b][color=#%s]%s[/color][/b]" % [col, nm]
	for el in BWFormulas.ELEMENTS:
		var re := RegEx.create_from_string("(?i)\\b%s\\b" % el)
		text = re.sub(text, "[color=#%s]%s[/color]" % [BWGearText.readable(BWLook.element_color(el)).to_html(false), el.capitalize()], true)
	for tok in marks:
		text = text.replace(tok, marks[tok])
	return text


## The jackpot: the hall whites out and comes back.
func _flash() -> void:
	var f := ColorRect.new()
	f.color = Color.WHITE
	f.set_anchors_preset(Control.PRESET_FULL_RECT)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(f)
	var tw := create_tween()
	tw.tween_property(f, "color:a", 0.0, 1.6).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(f.queue_free)


## D90/D91: every pick `u` owes (all units when null) opens a picker now,
## one at a time, its light up. Nothing is carried on.
func _resolve_picks(only: BWUnit) -> void:
	while true:
		var u: BWUnit = only
		var req: Dictionary = {}
		if only != null:
			req = BWPicks.next_request(only)
		else:
			var pend := run.pending_picks()
			if not pend.is_empty():
				u = pend[0][0]
				req = pend[0][1]
		if req.is_empty():
			return
		var i := run.squad.find(u)
		if i >= 0 and i < _spot_ids.size():
			_focus(i)
		picker = BWPicker.new(u, req, "day %d" % (run.day - 1))
		_ui_root.add_child(picker)
		var id: String = await picker.chosen
		BWPicks.apply(u, req, id)
		picker.queue_free()
		picker = null
		await get_tree().process_frame


## Day's end: the whole hall again, "Day N", any key.
func _day_card() -> void:
	card_unit = null
	for k in _spot_ids.size():
		_hall.set_spot_level(_spot_ids[k], 1.0)
	_focus_none()
	_cam_pos = Vector3(0, 3.3, 15.8)
	_cam_look = Vector3(0, 2.15, 0)
	_fov = 39.0
	var box := VBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.offset_left = -400
	box.offset_right = 400
	box.offset_top = 18
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.modulate.a = 0.0
	_ui_root.add_child(box)
	var big := _outlined(Label.new(), 64, 18)
	big.text = "Day %d" % run.day
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(big)
	var sub := _outlined(Label.new(), BWStyle.F_SUB, 10)
	sub.text = ("the Giant waits" if run.is_boss() else "fight %d is next" % run.fight) + "   ·   press any key"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", BWStyle.TEXT_DIM)
	box.add_child(sub)
	create_tween().tween_property(box, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE)
	_continue_t = 0.0


func _focus_none() -> void:
	for v in _views:
		var from := float(v.get_meta("dim", 0.0))
		if from > 0.0:
			create_tween().tween_method(func(x: float): v.set_meta("dim", x); BWLook.set_dim(v, x), from, 0.0, 0.3)


# ---------------------------------------------------------------- props

## A training dummy: a post, a stuffed body with a crossbar, a round head;
## pale grey with ink contours. Pops up out of the floor.
func _dummy(at: Vector3) -> Node3D:
	var d := Node3D.new()
	d.position = at
	add_child(d)
	var parts := [
		[_cyl(0.05, 0.05, 1.5), Vector3(0, 0.75, 0), Vector3.ZERO, Color(0.32, 0.32, 0.32)],
		[_cyl(0.24, 0.2, 0.72), Vector3(0, 1.12, 0), Vector3.ZERO, Color(0.78, 0.78, 0.78)],
		[_cyl(0.04, 0.04, 0.9), Vector3(0, 1.32, 0), Vector3(0, 0, 90), Color(0.32, 0.32, 0.32)],
		[_sphere(0.17), Vector3(0, 1.66, 0), Vector3.ZERO, Color(0.9, 0.9, 0.9)],
		[_cyl(0.32, 0.36, 0.06), Vector3(0, 0.03, 0), Vector3.ZERO, Color(0.2, 0.2, 0.2)],
	]
	for p in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = p[0]
		mi.position = p[1]
		mi.rotation_degrees = p[2]
		mi.material_override = BWLook.flat()
		mi.set_instance_shader_parameter("tint", p[3])
		d.add_child(mi)
		var ol := MeshInstance3D.new()
		ol.mesh = p[0]
		ol.material_override = BWLook.outline(0.022)
		mi.add_child(ol)
	# a rope band round the middle
	var band := MeshInstance3D.new()
	band.mesh = _cyl(0.235, 0.235, 0.05)
	band.position = Vector3(0, 1.0, 0)
	band.material_override = BWLook.flat()
	band.set_instance_shader_parameter("tint", Color(0.1, 0.1, 0.1))
	d.add_child(band)
	d.scale = Vector3(1, 0.01, 1)
	create_tween().tween_property(d, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# it rocks when struck
	_after(0.95, func():
		if is_instance_valid(d):
			_rock(d))
	return d


func _rock(d: Node3D) -> void:
	var tw := create_tween()
	tw.tween_property(d, "rotation:z", -0.16, 0.08)
	tw.tween_property(d, "rotation:z", 0.08, 0.18).set_trans(Tween.TRANS_SINE)
	tw.tween_property(d, "rotation:z", 0.0, 0.3).set_trans(Tween.TRANS_SINE)


func _shrink(n: Node3D) -> void:
	if not is_instance_valid(n):
		return
	var tw := create_tween()
	tw.tween_property(n, "scale", Vector3(1, 0.01, 1) if n.scale.y > 0.5 else Vector3.ZERO, 0.25).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(n.queue_free)


## An element sigil on the floor round a unit: two rings and ticks, turning.
func _sigil(at: Vector3, el: String) -> Node3D:
	var root := Node3D.new()
	root.position = at + Vector3(0, 0.02, 0)
	add_child(root)
	var col := BWLook.element_color(el)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in [[0.78, 0.84], [0.62, 0.64]]:
		for i in 64:
			var a0 := TAU * i / 64.0
			var a1 := TAU * (i + 1) / 64.0
			var p := [Vector3(cos(a0) * ring[0], 0, sin(a0) * ring[0]), Vector3(cos(a0) * ring[1], 0, sin(a0) * ring[1]),
				Vector3(cos(a1) * ring[1], 0, sin(a1) * ring[1]), Vector3(cos(a1) * ring[0], 0, sin(a1) * ring[0])]
			for j in [0, 1, 2, 0, 2, 3]:
				st.add_vertex(p[j])
	for i in 8:
		var a := TAU * i / 8.0
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x) * 0.025
		var p := [dir * 0.66 - side, dir * 0.66 + side, dir * 0.78 + side, dir * 0.78 - side]
		for j in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(p[j])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = BWLook.alpha()
	mi.set_instance_shader_parameter("tint", Color(col.r, col.g, col.b, 0.9))
	root.add_child(mi)
	root.scale = Vector3.ONE * 0.2
	create_tween().tween_property(root, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	create_tween().tween_property(root, "rotation:y", TAU * 0.5, 3.0)
	return root


## An element bolt from the weapon into the air (training casts).
func _cast(v: BWUnitView, el: String) -> void:
	if not is_instance_valid(v):
		return
	v.pose_named("cast")
	if v.character:
		v.character.set_aura(el, 1.3)
	_after(0.16, func():
		if not is_instance_valid(v):
			return
		var from := v.weapon_tip()
		var fwd := Vector3(sin(v.rotation.y), 0, cos(v.rotation.y))      # the way the unit faces
		_bolt(from, from + fwd * 2.4 + Vector3(0, 0.9, 0), el))


func _bolt(from: Vector3, to: Vector3, el: String) -> void:
	var col := BWLook.element_color(el)
	var mi := MeshInstance3D.new()
	mi.mesh = _sphere(0.13)
	mi.material_override = BWLook.flat()
	mi.set_instance_shader_parameter("tint", col)
	mi.position = from
	add_child(mi)
	var ol := MeshInstance3D.new()
	ol.mesh = mi.mesh
	ol.material_override = BWLook.outline(0.02)
	mi.add_child(ol)
	var tw := create_tween()
	tw.tween_property(mi, "position", to, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): _burst(to, el, 0.7); mi.queue_free())


## A ring of light that opens and fades (element colour, or white).
func _burst(at: Vector3, el: String, size: float) -> void:
	var col := BWLook.element_color(el) if el != "" else Color(1, 1, 1)
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.16
	tm.outer_radius = 0.22
	tm.rings = 24
	tm.ring_segments = 6
	mi.mesh = tm
	mi.material_override = BWLook.alpha()
	mi.set_instance_shader_parameter("tint", Color(col.r, col.g, col.b, 0.95))
	mi.position = at
	add_child(mi)
	if _cam:
		mi.look_at(_cam.global_position)
		mi.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * (4.0 * size), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(a: float): mi.set_instance_shader_parameter("tint", Color(col.r, col.g, col.b, a)), 0.95, 0.0, 0.45)
	tw.chain().tween_callback(mi.queue_free)


## White sparks off a blade being honed.
func _sparks(at: Vector3) -> void:
	for k in 6:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.025, 0.025, 0.14)
		mi.mesh = bm
		mi.material_override = BWLook.flat()
		mi.position = at
		add_child(mi)
		var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.3, 1.2), _rng.randf_range(-1, 1)).normalized()
		mi.look_at(at + dir)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(mi, "position", at + dir * _rng.randf_range(0.35, 0.7) + Vector3(0, -0.15, 0), 0.3).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "scale", Vector3.ONE * 0.1, 0.3)
		tw.chain().tween_callback(mi.queue_free)


func _cyl(r0: float, r1: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r0
	c.bottom_radius = r1
	c.height = h
	c.radial_segments = 16
	return c


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 16
	s.rings = 8
	return s
