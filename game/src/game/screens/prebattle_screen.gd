class_name BWPrebattleScreen
extends Node3D
## Brief: review units, equip skills/armour/weapons, check stats and
## affinities; select 3; place them in the rows opposite the enemy start;
## "Begin battle". The shop (1-for-1 trades, imbuement scrolls, D203) lives here too,
## because the brief allows inventory changes at any time.
##
## Layout (1600×900 design space, BWStyle weights):
##   top left     title, status line, the squad list (tick 3; element swatch
##                and name per row; drag a row onto the map to place it)
##   top right    BWStatPanel: the selected unit's sheet
##   centre       the map under the V8 camera rig (BWCameraRig: left-drag on
##                empty ground orbits, right-drag pans, wheel zooms, Q/E
##                rotate, Space recentres), fitted so every deploy hex and
##                the enemy start sit in the free space between the panels
##   bottom       Info · Equipment · Shop · Begin battle
##   overlays     BWGearPanel (paperdoll + inventory) and BWShopPanel, over
##                the left and centre; the stat panel stays visible beside them
## Placement (author, 10/4: "click and drag to place … it defaults to swapping"):
##   drag a placed unit, or a squad row, to a ringed deploy hex; a ghost
##   shows where it lands. Dropping on a hex a unit stands on swaps the two;
##   anywhere else it is a plain move. A click selects. A click on an empty
##   deploy hex moves the selected placed unit there (never a swap).
## Hover any unit on the map for its card (stats, element, weapon, gear).

signal done(plan: Dictionary)

const DRAG_PX := 7.0
const PITCH := 60.0
const LEFT_W := 340.0
const RIGHT_W := 470.0

var run: BWRun
var rig: BWCameraRig
var _board: BWBoard
var _bv: BWBoardView
var _cam: Camera3D
var _sel: BWUnit
var _deployed: Array = []        # BWUnit, up to _need
## D320: units this fight fields: the map's deploy_count capped by the squad
## (BWRun.deploy_for): 3 on the 3v3 maps, 6 on a big map.
var _need := BWRun.DEPLOY
var _placed := {}                # unit id -> Vector2i
var _views := {}                 # unit id -> BWUnitView (placed only)
var _enemy_at: Array = []        # D211: where each enemy starts (BWBattle.enemy_layout)
var _enemies: Array = []         # BWUnit
var _enemy_views := {}           # unit id -> BWUnitView
var _ui: CanvasLayer
var _root: Control
var _list: VBoxContainer
var _list_panel: PanelContainer
var _stats: BWStatPanel
var _begin: Button
var _status: Label
var _equip: BWGearPanel
var _shop: BWShopPanel
var _hover_card: BWUnitCard
var _hover_id := ""
var _drag := {}                  # { unit, from: "map"|"row", start, active, target }
var _drop_count := 0             # successful drops (audio watcher reads it)
var _ghost: BWUnitView           # row drags of an unplaced unit
var _drag_tag: PanelContainer
var _drag_tag_label: Label
var _rings := {}                 # deploy hex -> MeshInstance3D
var _mark_to: MeshInstance3D
var _mark_from: MeshInstance3D
var _codex: BWCodex
var _mode_plate: BWModePrebattle    # D327: the 6v6 mode's additions (null otherwise)


func _ready() -> void:
	var we := WorldEnvironment.new()
	we.environment = BWLook.starfield_environment()
	add_child(we)
	BWItemIcons.ensure(self)
	_board = BWBoard.load_file("res://maps/%s.json" % run.map_for(run.fight))
	_need = run.deploy_for(run.fight)                   # D320
	_bv = BWBoardView.new()
	add_child(_bv)
	_bv.build(_board, BWTileFX.authored(_board, "res://maps/%s.json" % run.map_for(run.fight)))   # tile FX (D82)
	_build_marks()
	rig = BWCameraRig.new()
	rig.input_enabled = false          # input is routed by this screen (drags win over orbit)
	add_child(rig)
	_cam = rig.cam
	rig.clicked.connect(_on_map_click)
	rig.fit_board(_board)              # D322: big boards: wider zoom, pan clamp (edge scroll once input is the rig's)
	# Show who you're facing at their start.
	_enemies = BWModePrebattle.visible_enemies(run.enemies_for(run.fight))   # D331: a wave mode shows its first wave
	_enemy_at = BWBattle.enemy_layout(_board, _enemies, _board.spawns.player)   # D211: a Horde fans out, a Colossus fits
	for i in _enemies.size():
		var fv := BWUnitView.new()
		_enemies[i].team = "enemy"
		add_child(fv)
		fv.setup(_enemies[i])
		fv.position = _bv.top_center(_enemy_at[i])
		fv.face(_bv.top_center(_board.spawns.player[0]))
		_enemy_views[_enemies[i].id] = fv
	# D156: render every portrait the fight will show now, one per ~2 frames,
	# so the combat HUD's turn order (~12) never renders at battle start.
	BWPortraits.prewarm(run.squad + _enemies)
	_build_ui()
	_sel = run.squad[0]
	if _need > BWRun.DEPLOY:
		_auto_fill()                                   # D321: a 6v6 opens placed (3v3 unchanged: tick your three)
	_mode_plate = BWModePrebattle.attach(self)         # D327: a 6v6 mode's plate, fronts, divider, exit
	_refresh()
	_fit_camera.call_deferred()
	get_viewport().size_changed.connect(_fit_camera)


# ---------------------------------------------------------------- camera

## Frame the deploy hexes and the enemy start inside the free space between
## the panels, from behind the player side, pitched 60° so the near row is
## not foreshortened away (author: "I can't see the bottom row clearly").
func _fit_camera() -> void:
	if rig == null or not is_inside_tree():
		return
	var pts: Array = []
	var dsum := Vector3.ZERO
	for h in _board.deploy.player:
		pts.append(_bv.top_center(h))
		dsum += _bv.top_center(h)
	var esum := Vector3.ZERO
	for h in _board.spawns.enemy:
		pts.append(_bv.top_center(h))
		pts.append(_bv.top_center(h) + Vector3(0, 2.7, 0))
		esum += _bv.top_center(h)
	var dc := dsum / maxf(1.0, _board.deploy.player.size())
	var ec := esum / maxf(1.0, _board.spawns.enemy.size())
	var away := Vector2(dc.x - ec.x, dc.z - ec.z)
	rig.yaw = atan2(away.x, away.y) if away.length() > 0.1 else 0.0
	rig.pitch = deg_to_rad(PITCH)
	var c := Vector3.ZERO
	for p in pts:
		c += p
	c /= pts.size()
	rig.pivot = c
	rig.dist = 24.0
	var vr := get_viewport().get_visible_rect()
	var free := Rect2(Vector2(24 + LEFT_W + 24, 96), Vector2(vr.size.x - (24 + LEFT_W + 24) - (RIGHT_W + 40), vr.size.y - 96 - 150))
	for i in 40:
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in pts:
			var s := _cam.unproject_position(p)
			lo = Vector2(minf(lo.x, s.x), minf(lo.y, s.y))
			hi = Vector2(maxf(hi.x, s.x), maxf(hi.y, s.y))
		var box := Rect2(lo, hi - lo)
		var a := _ground(box.get_center(), c.y)
		var b := _ground(free.get_center(), c.y)
		if a != Vector3.INF and b != Vector3.INF:
			rig.pivot += (a - b) * 0.8
		var k := maxf(box.size.x / free.size.x, box.size.y / free.size.y)
		rig.dist = clampf(rig.dist * lerpf(1.0, k, 0.5), BWCameraRig.DIST_MIN, rig.dist_max)
	rig.follow(rig.pivot, true)


## The point on the horizontal plane y under a screen position.
func _ground(screen: Vector2, y: float) -> Vector3:
	var o := _cam.project_ray_origin(screen)
	var d := _cam.project_ray_normal(screen)
	if absf(d.y) < 1e-5:
		return Vector3.INF
	var t := (y - o.y) / d.y
	return o + d * t if t > 0.0 else Vector3.INF


# ---------------------------------------------------------------- deploy marks

## A bold ink ring on every deploy hex (the light grey wash alone was easy
## to lose on the near rows), plus the drag's "to" and "from" markers.
func _build_marks() -> void:
	for h in _board.deploy.player:
		var r := _hex_ring(_bv.top_center(h) + Vector3(0, 0.03, 0), 0.60, 0.80, Color(0, 0, 0, 0.78), false)
		_rings[h] = r
	_mark_to = _hex_ring(Vector3.ZERO, 0.30, 0.92, Color(0, 0, 0, 0.62), true)
	_mark_from = _hex_ring(Vector3.ZERO, 0.66, 0.80, Color(0.5, 0.5, 0.5, 0.9), false)


func _hex_ring(at: Vector3, r0: float, r1: float, col: Color, pulse: bool) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner := BWLook.hex_corners(Vector3.ZERO, r0)
	var outer := BWLook.hex_corners(Vector3.ZERO, r1)
	for i in 6:
		var j := (i + 1) % 6
		for p in [outer[i], outer[j], inner[j], outer[i], inner[j], inner[i]]:
			st.set_color(Color.WHITE)
			st.add_vertex(p)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = BWLook.alpha(pulse)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("tint", col)
	mi.position = at
	mi.visible = at != Vector3.ZERO
	add_child(mi)
	return mi


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = BWStyle.theme()
	_ui.add_child(_root)

	var title := Label.new()
	title.text = ("THE GIANT" if run.is_boss() else "THE TWINS" if run.is_twins() else "Fight %d of %d" % [run.fight, BWRun.FIGHTS]) + "  ·  " + _board.name
	title.position = Vector2(24, 14)
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 8)
	_root.add_child(title)
	_status = Label.new()
	_status.position = Vector2(26, 56)
	_status.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
	_status.add_theme_color_override("font_color", BWStyle.LABEL)
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.add_theme_constant_override("outline_size", 6)
	_root.add_child(_status)

	_list_panel = PanelContainer.new()
	_list_panel.add_theme_stylebox_override("panel", BWStyle.frame_style())
	_list_panel.position = Vector2(24, 96)
	_list_panel.custom_minimum_size = Vector2(LEFT_W, 0)
	_root.add_child(_list_panel)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list_panel.add_child(_list)

	var rp := PanelContainer.new()
	rp.add_theme_stylebox_override("panel", BWStyle.frame_style())
	rp.anchor_left = 1.0
	rp.anchor_right = 1.0
	rp.offset_left = -RIGHT_W - 16
	rp.offset_right = -16
	rp.offset_top = 14
	rp.offset_bottom = 14
	_root.add_child(rp)
	_stats = BWStatPanel.new()
	rp.add_child(_stats)

	var bar := HBoxContainer.new()
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.anchor_right = 1.0
	bar.offset_left = 24 + LEFT_W
	bar.offset_right = -RIGHT_W - 32
	bar.offset_top = -74
	bar.offset_bottom = -22
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 10)
	_root.add_child(bar)
	var info := _bar_button(bar, "Info", open_codex)
	info.tooltip_text = "The codex: stats, elements, weapons, terrain  [I]"
	_bar_button(bar, "Equipment", func(): _open_overlay(_equip))
	_bar_button(bar, "Shop", func(): _open_overlay(_shop))   # D202: re-imbue is gone; scrolls live in the shop
	_begin = _bar_button(bar, "Begin battle", _try_begin)
	_begin.custom_minimum_size = Vector2(200, 0)

	# overlays: over the left and centre, the stat panel stays beside them
	_equip = BWGearPanel.new(run)
	_shop = BWShopPanel.new(run)
	for o in [_equip, _shop]:
		o.anchor_bottom = 1.0
		o.anchor_right = 1.0
		o.offset_left = 20
		o.offset_right = -RIGHT_W - 32
		o.offset_top = 92
		o.offset_bottom = -84
		o.visible = false
		_root.add_child(o)
		o.closed.connect(_close_overlays)
		o.changed.connect(_on_gear_changed)
		BWEsc.track(o, _close_overlays, { "name": "gear" if o == _equip else "shop" })   # ---- D171
	var step := HBoxContainer.new()
	step.add_theme_constant_override("separation", 4)
	for d in [-1, 1]:
		var b := Button.new()
		b.text = "◀" if d < 0 else "▶"
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "Previous unit" if d < 0 else "Next unit"
		b.pressed.connect(func(): _step_unit(d))
		step.add_child(b)
	_equip.add_header(step)

	_hover_card = BWUnitCard.new()
	_hover_card.visible = false
	_hover_card.z_index = 5
	_root.add_child(_hover_card)
	BWEsc.track(_hover_card, _dismiss_hover, { "name": "unit card", "hover": true })   # ---- D171

	_drag_tag = PanelContainer.new()
	_drag_tag.add_theme_stylebox_override("panel", BWStyle.prompt_style())
	_drag_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_tag.visible = false
	_drag_tag.z_index = 6
	_drag_tag_label = Label.new()
	_drag_tag_label.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
	_drag_tag.add_child(_drag_tag_label)
	_root.add_child(_drag_tag)


func _bar_button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 50)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _refresh() -> void:
	_refresh_list()
	_stats.scale_max = _stat_scale()
	_stats.set_unit(_sel)
	_refresh_board()
	var placed := _deployed.filter(func(u): return _placed.has(u.id)).size()
	if _deployed.size() < _need:
		_status.text = "Tick %d more  ·  drag units onto the ringed hexes  ·  hover the enemy to read them" % (_need - _deployed.size())
	elif placed < _need:
		_status.text = "Place %d more on the ringed hexes" % (_need - placed)
	else:
		_status.text = "Ready  ·  drag to rearrange (drop on a unit to swap)  ·  Enter to begin"
	_begin.disabled = not (_deployed.size() == _need and placed == _need)
	if _mode_plate:
		_mode_plate.refresh()                          # D328: Split Front waits for three a front


## Bars share one scale across the squad: the best stat (with gear),
## rounded up to the next 10, at least 20.
func _stat_scale() -> int:
	var m := 0
	for u in run.squad:
		for s in BWUnit.STATS:
			m = maxi(m, u.stat(s))
	return maxi(20, int(ceil(float(m + 1) / 10.0)) * 10)


func _refresh_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	var head := HBoxContainer.new()
	var hl := Label.new()
	hl.text = ("Squad — all %d" % _need) if _need >= run.squad.size() and _need > BWRun.DEPLOY else ("Squad — pick %d" % _need)
	hl.add_theme_font_size_override("font_size", BWStyle.F_SUB)
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hl)
	var cnt := Label.new()
	cnt.text = "%d / %d" % [_deployed.size(), _need]
	cnt.add_theme_color_override("font_color", BWStyle.LABEL)
	head.add_child(cnt)
	if _need > BWRun.DEPLOY:                           # D321: big maps: one click fills and places the rest
		var auto := Button.new()
		auto.name = "auto_place"
		auto.text = "Auto"
		auto.focus_mode = Control.FOCUS_NONE
		auto.tooltip_text = "Fill the empty slots with the highest-level units and place everyone on the default starts"
		auto.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 2)
		auto.pressed.connect(func():
			_auto_fill(true)
			_refresh())
		head.add_child(auto)
	_list.add_child(head)
	for u in run.squad:
		_list.add_child(_squad_row(u))
	var tip := Label.new()
	tip.text = "Drag a row onto the map to place it."
	tip.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 3)
	tip.add_theme_color_override("font_color", BWStyle.FAINT)
	_list.add_child(tip)


## One squad row: deploy tick · element swatch · name / Lv · weapon ·
## element name · a drag grip. Press-and-drag places it on the map.
func _squad_row(u: BWUnit) -> Control:
	var row := _Row.new()
	row.screen = self
	row.unit = u
	row.selected = u == _sel
	row.deployed = u in _deployed
	row.placed = _placed.has(u.id)
	row.custom_minimum_size = Vector2(0, 70)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 8
	h.offset_right = -26
	row.add_child(h)
	var dep := CheckBox.new()
	dep.button_pressed = u in _deployed
	dep.focus_mode = Control.FOCUS_NONE
	dep.disabled = not dep.button_pressed and _deployed.size() >= _need
	dep.tooltip_text = "Deploy" if not dep.button_pressed else "Bench"
	dep.toggled.connect(_on_deploy.bind(u))
	h.add_child(dep)
	h.add_child(BWGearText.Swatch.new(u.element, 18.0))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -3)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(v)
	var n := Label.new()
	n.text = u.name
	n.add_theme_font_size_override("font_size", BWStyle.F_BODY)
	v.add_child(n)
	var sub := RichTextLabel.new()
	sub.bbcode_enabled = true
	sub.fit_content = true
	sub.scroll_active = false
	sub.autowrap_mode = TextServer.AUTOWRAP_OFF
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub.custom_minimum_size = Vector2(250, 0)
	sub.add_theme_font_size_override("normal_font_size", BWStyle.F_SMALL - 2)
	sub.text = _row_gear_text(u)
	v.add_child(sub)
	return row


## D491: the row names what the unit actually carries and every element it
## holds, so picking who deploys doesn't need the gear panel:
##   Lv 3 · Jagged Dagger + Short Bow
##   Light 2 · Fire 1
func _row_gear_text(u: BWUnit) -> String:
	var lab := BWGearText.hex(BWStyle.LABEL)
	var main: Dictionary = u.equipment.get("main_hand", {})
	var weap := BWRun.item_name(main) if not main.is_empty() else BWText.weapon(u.weapon_class)
	var second := u.second_weapon()
	if not second.is_empty():
		weap += " + %s" % BWRun.item_name(second)
	if weap.length() > 22:                     # keep clear of the drag grip; the card has the full name
		weap = weap.left(21).strip_edges() + "…"
	var els: Array = []
	for el in BWAutoEquip.elements(u):
		els.append("[color=#%s]%s %d[/color]" % [BWGearText.hex(BWGearText.readable(BWLook.element_color(el))),
			str(el).capitalize(), maxi(1, u.affinity_rank(el))])
	if els.is_empty() and u.element != "":
		els.append("[color=#%s]%s[/color]" % [BWGearText.hex(BWGearText.readable(BWLook.element_color(u.element))), u.element.capitalize()])
	return "[color=#%s]Lv %d · %s[/color]\n%s" % [lab, u.level, weap, " · ".join(els)]


## A squad row: selection on click, a map drag on press-and-move.
class _Row:
	extends Control
	var screen: BWPrebattleScreen
	var unit: BWUnit
	var selected := false
	var deployed := false
	var placed := false
	var _press := Vector2.INF

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				_press = ev.position
				screen._begin_drag(unit, "row", get_global_mouse_position())
			else:
				if not screen._drag_active():
					screen._select(unit)
				_press = Vector2.INF
			accept_event()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var el := BWLook.element_color(unit.element)
		draw_rect(r, Color(0.16, 0.16, 0.18, 0.95) if selected else Color(0, 0, 0, 0.55))
		draw_rect(Rect2(0, 0, 4, size.y), el if deployed else Color(el, 0.35))
		draw_rect(r.grow(-0.5), Color.WHITE if selected else Color(1, 1, 1, 0.22), false, 2.0 if selected else 1.0)
		# grip: two columns of dots
		for i in 3:
			for j in 2:
				draw_circle(Vector2(size.x - 16 + j * 6, size.y / 2.0 - 6 + i * 6), 1.6, Color(1, 1, 1, 0.45))
		if placed:
			# a small hex: on the map
			var c := Vector2(size.x - 34, size.y / 2.0)
			var pts := BWLook.hex_corners(Vector3.ZERO, 6.0)
			var p2 := PackedVector2Array()
			for p in pts:
				p2.append(c + Vector2(p.x, p.z))
			p2.append(p2[0])
			draw_polyline(p2, Color.WHITE, 1.5)


func _select(u: BWUnit) -> void:
	if u == _sel:
		return
	_sel = u
	_refresh()
	if _equip.visible:
		_equip.set_unit(u)
	if _shop.visible:
		_shop.open(u)


func _step_unit(d: int) -> void:
	var i := run.squad.find(_sel)
	_select(run.squad[posmod(i + d, run.squad.size())])


# ---------------------------------------------------------------- overlays

func _open_overlay(o: Control) -> void:
	var was := o.visible
	_close_overlays()
	if was:
		return
	o.visible = true
	_list_panel.visible = false
	_hover_card.visible = false
	if o == _equip:
		_equip.set_unit(_sel)
	else:
		_shop.open(_sel)


func _close_overlays() -> void:
	_equip.visible = false
	_shop.visible = false
	_list_panel.visible = true
	if _equip.doll.character:
		_equip.doll.refresh()


func _overlay_open() -> bool:
	return _equip.visible or _shop.visible


func _on_gear_changed() -> void:
	for id in _views:
		_views[id].refresh_equipment()
	_refresh()
	if _equip.visible:
		_equip.refresh()


## The codex (BWCodex, the rules reference) over the screen; "Info" or I.
## Opens on Stats here: this is where the sheet is read.
func open_codex(tab: String = "stats") -> void:
	if is_instance_valid(_codex):
		return
	_end_drag()
	_hover_card.visible = false
	_codex = BWCodex.summon(self, tab)


# ---------------------------------------------------------------- deploy

func _on_deploy(on: bool, u: BWUnit) -> void:
	if on and not u in _deployed and _deployed.size() < _need:
		_deployed.append(u)
		_sel = u
		var free: Array = _board.deploy.player.filter(func(h): return not h in _placed.values())
		if not free.is_empty():
			var sp: Array = _board.spawns.player
			var spawn: Vector2i = sp[_deployed.size() - 1] if _deployed.size() - 1 < sp.size() else free[0]   # D320
			_placed[u.id] = spawn if not spawn in _placed.values() else free[0]
	elif not on:
		_deployed.erase(u)
		_placed.erase(u.id)
	_refresh()


## D321: the auto-placement default. Fills the open slots with the squad's
## highest-level units (ties: squad order) and puts every unplaced deployed
## unit on the map's default starts (BWBoard.default_starts: the spawns, then
## the deploy hexes nearest them). `reseat` moves everyone back to the
## default starts in deploy order (the Auto button).
func _auto_fill(reseat: bool = false) -> void:
	var bench: Array = run.squad.filter(func(x): return not x in _deployed)
	bench.sort_custom(func(a, b): return a.level > b.level or (a.level == b.level and run.squad.find(a) < run.squad.find(b)))
	for x in bench:
		if _deployed.size() >= _need:
			break
		_deployed.append(x)
	if reseat:
		_placed.clear()
	var todo: Array = _deployed.filter(func(x): return not _placed.has(x.id))
	var starts := _board.default_starts("player", todo.size(), _placed.values())
	for i in mini(todo.size(), starts.size()):
		_placed[todo[i].id] = starts[i]


func _refresh_board() -> void:
	_bv.clear_highlights()
	_bv.highlight(_board.deploy.player, "deploy")
	for id in _views.keys():
		if not _placed.has(id):
			_views[id].queue_free()
			_views.erase(id)
	for u in _deployed:
		if not _placed.has(u.id):
			continue
		if not _views.has(u.id):
			var v := BWUnitView.new()
			u.team = "player"
			add_child(v)
			v.setup(u)
			_views[u.id] = v
		_views[u.id].position = _bv.top_center(_placed[u.id])
		_views[u.id].face(_bv.top_center(_board.spawns.enemy[mini(1, _board.spawns.enemy.size() - 1)]))
		BWLook.set_dim(_views[u.id], 0.0)
		_views[u.id].show_label(true)
		if u == _sel:
			_bv.highlight([_placed[u.id]], "target")
	_mark_to.visible = false
	_mark_from.visible = false


func _occupant(h: Vector2i) -> String:
	for id in _placed:
		if _placed[id] == h:
			return id
	return ""


func _unit_by_id(id: String) -> BWUnit:
	for u in run.squad:
		if u.id == id:
			return u
	return null


## The unit whose body is under a screen point (nearest to the camera), from
## `views` (id -> BWUnitView). Bodies stand above their hex, so the hex pick
## alone misses a click on a head or torso.
func _unit_under(p: Vector2, views: Dictionary, skip: String = "") -> String:
	var best := ""
	var best_d := INF
	for id in views:
		if id == skip or not is_instance_valid(views[id]) or not views[id].visible:
			continue
		var v: BWUnitView = views[id]
		var foot := v.global_position
		if _cam.is_position_behind(foot):
			continue
		var a := _cam.unproject_position(foot)
		var b := _cam.unproject_position(foot + Vector3(0, v.head_height() + 0.45, 0))
		var hgt := a.y - b.y
		var w := maxf(hgt * 0.45, 22.0)
		if Rect2(b.x - w / 2.0, b.y, w, hgt + w * 0.2).has_point(p):
			var d := _cam.global_position.distance_to(foot)
			if d < best_d:
				best_d = d
				best = id
	return best


# ---------------------------------------------------------------- map input

func _unhandled_input(ev: InputEvent) -> void:
	if not is_processing_unhandled_input():
		return
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.keycode == KEY_ESCAPE:
			if _drag_active():
				_cancel_drag()
			elif _overlay_open():
				_close_overlays()
			else:
				BWPauseMenu.open(self, "prebattle")       # ---- D124: nothing to close: the pause menu
			get_viewport().set_input_as_handled()
			return
		if _overlay_open():
			return
		if ev.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			_try_begin()
			return
		if ev.keycode == KEY_I:
			open_codex()
			return
	if _overlay_open():
		return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			var id := _unit_under(ev.position, _views)
			if id == "":
				var h := _bv.pick(_cam, ev.position)
				id = _occupant(h) if h in _board.deploy.player else ""
			if id != "":
				_begin_drag(_unit_by_id(id), "map", ev.position)
				get_viewport().set_input_as_handled()
				return
		elif not _drag.is_empty():
			# a press on a unit that never became a drag: a click, select it
			var u: BWUnit = _drag.unit
			_end_drag()
			_select(u)
			get_viewport().set_input_as_handled()
			return
	elif ev is InputEventMouseMotion and _drag.is_empty():
		_update_hover(ev.position)
	_rig_input(ev)


## Forward an event to the camera rig (its own handler is off, so a press on
## a unit never starts an orbit).
func _rig_input(ev: InputEvent) -> void:
	rig.input_enabled = true
	rig._unhandled_input(ev)
	rig.input_enabled = false


## A click without a drag on the map (from the rig).
func _on_map_click(p: Vector2) -> void:
	if _overlay_open():
		return
	var h := _bv.pick(_cam, p)
	if not h in _board.deploy.player:
		return
	var occ := _occupant(h)
	if occ != "":
		_select(_unit_by_id(occ))
	elif _sel in _deployed:
		_placed[_sel.id] = h          # plain move; never a swap
		_drop_count += 1
		_refresh()


# ---------------------------------------------------------------- hover card

func _update_hover(p: Vector2) -> void:
	var id := _unit_under(p, _enemy_views)
	var u: BWUnit = null
	if id != "":
		for e in _enemies:
			if e.id == id:
				u = e
	else:
		var h := _bv.pick(_cam, p)
		for i in _enemies.size():
			if i < _enemy_at.size() and (_enemy_at[i] == h or BWHex.distance(_enemy_at[i], h) < _enemies[i].size):
				u = _enemies[i]
		if u == null:
			id = _unit_under(p, _views)
			if id == "" and h in _board.deploy.player:
				id = _occupant(h)
			u = _unit_by_id(id) if id != "" else null
	if u == null:
		_hover_card.visible = false
		_hover_id = ""
		_hover_off = ""
		return
	if u.id == _hover_off:
		return
	_hover_off = ""
	if u.id != _hover_id:
		_hover_id = u.id
		_hover_card.show_unit(u)
	_hover_card.visible = true
	_place_near(_hover_card, p)


## D171: Esc, a click elsewhere or the mouse leaving: hide the card until
## the cursor reaches another unit.
var _hover_off := ""


func _dismiss_hover() -> void:
	_hover_off = _hover_id
	_hover_card.visible = false


func _place_near(c: Control, p: Vector2) -> void:
	var vr := get_viewport().get_visible_rect().size
	var s := c.get_combined_minimum_size()
	var at := p + Vector2(28, 20)
	if at.x + s.x > vr.x - RIGHT_W - 40:
		at.x = p.x - s.x - 28
	at.y = clampf(at.y, 12, vr.y - s.y - 12)
	at.x = maxf(at.x, 12)
	c.position = at
	c.size = s


func _process(_d: float) -> void:
	# the card belongs to the map: hide it once the cursor is over a panel
	if _hover_card.visible and get_viewport().has_method("gui_get_hovered_control"):
		var over: Control = get_viewport().gui_get_hovered_control()
		if over != null and over != _hover_card:
			_hover_card.visible = false
			_hover_id = ""


# ---------------------------------------------------------------- drag & drop

func _drag_active() -> bool:
	return not _drag.is_empty() and _drag.active


func _begin_drag(u: BWUnit, from: String, at: Vector2) -> void:
	if _overlay_open() or u == null:
		return
	_drag = { "unit": u, "from": from, "start": at, "active": false, "target": {} }


## Motion and release for a drag are watched here, before the GUI, so a drag
## that starts on a squad row keeps tracking over the map.
func _input(ev: InputEvent) -> void:
	if _drag.is_empty():
		return
	if ev is InputEventMouseMotion:
		var p := _vp_pos(ev)
		if not _drag.active and p.distance_to(_drag.start) > DRAG_PX:
			_activate_drag()
		if _drag.active:
			_update_drag(p)
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
		if _drag.active:
			_drop(_vp_pos(ev))
			get_viewport().set_input_as_handled()
		elif _drag.from == "row":
			_drag = {}


## Event position in the viewport's design space (input events reaching
## _input are already in it for the root viewport).
func _vp_pos(ev: InputEventMouse) -> Vector2:
	return ev.position


func _activate_drag() -> void:
	var u: BWUnit = _drag.unit
	_drag.active = true
	_hover_card.visible = false
	_sel = u
	_refresh()
	if not _views.has(u.id):
		_ghost = BWUnitView.new()
		u.team = "player"
		add_child(_ghost)
		_ghost.setup(u)
		_ghost.show_label(false)
	if _views.has(u.id):
		_views[u.id].show_label(false)
	if _placed.has(u.id):
		_mark_from.position = _bv.top_center(_placed[u.id]) + Vector3(0, 0.035, 0)
		_mark_from.visible = true
	_drag_tag.visible = true


func _drag_view() -> BWUnitView:
	var u: BWUnit = _drag.unit
	return _views[u.id] if _views.has(u.id) else _ghost


## Where a drop at p would go: { hex, ok, swap (unit id or ""), text }.
## The hex under the cursor wins: an empty deploy hex is a plain move, a
## deploy hex with a unit on it is a swap with that unit. Off the deploy
## hexes, a drop on a unit's body still swaps with it.
func _target_at(p: Vector2) -> Dictionary:
	var u: BWUnit = _drag.unit
	var h := _bv.pick(_cam, p)
	var swap := ""
	if h in _board.deploy.player:
		var occ := _occupant(h)
		if occ == u.id:
			return { "hex": h, "ok": false, "swap": "", "text": "Same place" }
		swap = occ
	else:
		swap = _unit_under(p, _views, u.id)
		if swap == "":
			return { "hex": h, "ok": false, "swap": "", "text": "Not a deploy hex — drop on a ringed hex" }
		h = _placed[swap]
	var deployed := u in _deployed
	if swap != "":
		var other := _unit_by_id(swap)
		if deployed:
			return { "hex": h, "ok": true, "swap": swap, "text": "Swap with %s" % other.name }
		return { "hex": h, "ok": true, "swap": swap, "text": "Send %s in, bench %s" % [u.name, other.name] }
	if not deployed and _deployed.size() >= _need:
		return { "hex": h, "ok": false, "swap": "", "text": "Squad full — drop onto a unit to swap them out" }
	return { "hex": h, "ok": true, "swap": "", "text": "Move here" if deployed else "Deploy %s here" % u.name }


func _update_drag(p: Vector2) -> void:
	var t := _target_at(p)
	_drag.target = t
	var v := _drag_view()
	# reset any swap preview, then show this one
	for id in _views:
		if _placed.has(id):
			_views[id].position = _bv.top_center(_placed[id])
			BWLook.set_dim(_views[id], 0.0)
	if t.ok:
		v.position = _bv.top_center(t.hex) + Vector3(0, 0.18, 0)
		BWLook.set_dim(v, 0.42)
		_mark_to.position = _bv.top_center(t.hex) + Vector3(0, 0.04, 0)
		_mark_to.visible = true
		if t.swap != "" and _views.has(t.swap):
			var u: BWUnit = _drag.unit
			if _placed.has(u.id):
				_views[t.swap].position = _bv.top_center(_placed[u.id])
				BWLook.set_dim(_views[t.swap], 0.42)
			else:
				BWLook.set_dim(_views[t.swap], 0.82)      # benched by this drop
	else:
		_mark_to.visible = false
		var g := _ground(p, _bv.top_center(_board.deploy.player[0]).y)
		if g != Vector3.INF:
			v.position = g + Vector3(0, 0.25, 0)
		BWLook.set_dim(v, 0.72)
	_drag_tag_label.text = t.text
	_drag_tag_label.add_theme_color_override("font_color", Color.WHITE if t.ok else BWStyle.TEXT_DIM)
	_drag_tag.reset_size()
	_drag_tag.position = p + Vector2(34, -96)


func _drop(p: Vector2) -> void:
	var t := _target_at(p)
	var u: BWUnit = _drag.unit
	_end_drag()
	if not t.ok:
		_refresh()
		return
	var other := _unit_by_id(t.swap) if t.swap != "" else null
	if u in _deployed:
		if other:
			if _placed.has(u.id):
				_placed[other.id] = _placed[u.id]
			else:
				_placed.erase(other.id)
		_placed[u.id] = t.hex
	else:
		if other:
			_deployed[_deployed.find(other)] = u
			_placed.erase(other.id)
		else:
			_deployed.append(u)
		_placed[u.id] = t.hex
	_sel = u
	_drop_count += 1
	_refresh()


func _cancel_drag() -> void:
	_end_drag()
	_refresh()


func _end_drag() -> void:
	_drag = {}
	_drag_tag.visible = false
	_mark_to.visible = false
	_mark_from.visible = false
	if _ghost:
		_ghost.queue_free()
		_ghost = null


func _try_begin() -> void:
	if _begin.disabled:
		return
	set_process_unhandled_input(false)
	done.emit({ "units": _deployed.duplicate(), "at": _deployed.map(func(u): return _placed[u.id]) })
