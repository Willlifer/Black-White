class_name BWModePrebattle
extends Node3D
## D327-D333: the pre-battle screen for a 6v6 mode (BWPrebattleScreen keeps
## its own flow; this adds to it). Inert for any other fight.
##   the plate     top centre: the mode's name, its objective and its rule in
##                 a line or two: Split Front telegraphs the divider's element
##                 and counter; the Horde its waves and the exit
##   the board     Split Front: each arena's deploy zone is tagged WEST FRONT /
##                 EAST FRONT with how many stand there (3 / 3 is the rule:
##                 Begin waits for it), the divider's hexes washed in its
##                 element with its name. The Horde: the exit row washed and
##                 ringed, EXIT tags, the north edge where the waves land.
##   enemies       the Horde shows its first wave only (the rest come later).

var screen: BWPrebattleScreen
var mode := ""
var element := ""
var shown := {}                  # probes / review: { title, lines, west, east }
var _front_tags := {}            # "west" / "east" -> Label3D
var _layer: CanvasLayer
var _lines: Label


## Enemies the pre-battle shows: a wave mode's first wave.
static func visible_enemies(list: Array) -> Array:
	return list.filter(func(u): return not u.has_meta("wave") or int(u.get_meta("wave")) <= 1)


static func attach(s: BWPrebattleScreen) -> BWModePrebattle:
	var m := s.run.mode_for(s.run.fight)
	if m == "" or BWRun.mode_map(m) != str(BWRun.MODE_MAPS.get(m, "")):
		return null
	if not m in ["splitfront", "horde"]:
		return null                                  # the castle modes dress their own
	var p := BWModePrebattle.new()
	p.screen = s
	p.mode = m
	s.add_child(p)
	p._build()
	return p


func _build() -> void:
	var title := str(BWRun.MODE_NAMES.get(mode, mode))
	var lines: PackedStringArray = []
	match mode:
		"splitfront":
			element = str(BWRooms.battle_opts(screen.run, screen.run.fight).get("divider", BWSplitFront.element_for_seed(screen.run.seed_value * 31 + screen.run.fight)))   # D354: the card's divider
			lines.append("Two fronts, one wall: three of your six fight in each arena. Defeat every enemy.")
			lines.append("Divider: %s. %s." % [BWSplitFront.NAMES[element], BWSplitFront.counter_text(element)])
			lines.append("The enemy breaks through at round %d if it is losing a front." % BWSplitFront.ENEMY_BREAK_ROUND)
			_dress_split()
		"horde":
			var waves: PackedStringArray = []
			for w in BWHordeMode.WAVES:
				waves.append("%d%s" % [int(w[1]), " + %d elite%s" % [int(w[2]), "" if int(w[2]) == 1 else "s"] if int(w[2]) > 0 else ""])
			lines.append("Keep the little one alive: %d waves hunt the Lil Fella, who joins behind your line (half your best HP; only the enemy can hurt it)." % BWHordeMode.WAVES.size())
			lines.append("Waves: %s. Each is rung on the north edge a round before it lands." % ", ".join(waves))
			_dress_horde()
	_layer = CanvasLayer.new()
	_layer.layer = 2
	add_child(_layer)
	var panel := PanelContainer.new()
	panel.theme = BWStyle.theme()
	panel.add_theme_stylebox_override("panel", BWStyle.frame_style())
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.offset_left = -300
	panel.offset_right = 330
	panel.offset_top = 6
	_layer.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	panel.add_child(v)
	var t := Label.new()
	t.text = title.to_upper()
	t.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
	v.add_child(t)
	_lines = Label.new()
	_lines.text = "\n".join(lines)
	_lines.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lines.custom_minimum_size = Vector2(610, 0)
	_lines.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 2)
	_lines.add_theme_color_override("font_color", BWStyle.LABEL)
	v.add_child(_lines)
	shown = { "title": t.text, "lines": Array(lines), "element": element }


# ---------------------------------------------------------------- Split Front

func _dress_split() -> void:
	var bd: BWBoard = screen._board
	var bv: BWBoardView = screen._bv
	var hexes := Array(bd.objective.get("divider", [])).map(func(p): return Vector2i(int(p[0]), int(p[1])))
	var col := BWLook.element_color(element)
	_hex_mesh(bv, hexes, 0.0, 0.93, Color(col, 0.55))
	_hex_mesh(bv, hexes, 0.70, 0.90, Color(0, 0, 0, 0.8))
	if not hexes.is_empty():
		var c := Vector3.ZERO
		for h in hexes:
			c += bv.top_center(h)
		c /= hexes.size()
		var l := _tag(str(BWSplitFront.NAMES[element]).to_upper(), 26)
		l.position = c + Vector3(0, 3.0, 0)
		var pillar_h := 1.2 if element == "ice" else 0.9
		for h in hexes:
			var mi := MeshInstance3D.new()
			if element == "ice":
				var pm := PrismMesh.new()
				pm.size = Vector3(0.7, pillar_h, 0.7)
				mi.mesh = pm
			else:
				var bm := BoxMesh.new()
				bm.size = Vector3(0.9, pillar_h, 0.12)
				mi.mesh = bm
			mi.material_override = BWLook.alpha(false)
			mi.set_instance_shader_parameter("tint", Color(col.lerp(Color.WHITE, 0.35), 0.75))
			mi.position = bv.top_center(h) + Vector3(0, pillar_h * 0.5, 0)
			add_child(mi)
	var q := int(bd.objective.get("split_q", bd.cols / 2))
	for side in ["west", "east"]:
		var zone: Array = bd.deploy.player.filter(func(h): return (h.x < q) == (side == "west"))
		if zone.is_empty():
			continue
		var back := 0
		for h in zone:
			back = maxi(back, h.y)
		var row: Array = zone.filter(func(h): return h.y == back)
		var c := Vector3.ZERO
		for h in row:
			c += bv.top_center(h)
		c /= row.size()
		var l := _tag("", 22)
		l.position = c + Vector3(0, 0.1, 1.2)          # in front of the back row, under the units
		_front_tags[side] = l


## Split Front: the squad's count per front; Begin waits for 3 / 3 (a smaller
## squad: as even as it can be). Called from BWPrebattleScreen._refresh.
func refresh() -> void:
	if mode != "splitfront":
		return
	var q := int(screen._board.objective.get("split_q", screen._board.cols / 2))
	var west := 0
	var east := 0
	for u in screen._deployed:
		if screen._placed.has(u.id):
			if (screen._placed[u.id] as Vector2i).x < q:
				west += 1
			else:
				east += 1
	var need := screen._need
	var half := need / 2
	var ok := west + east < need or (west == half and east == need - half) or (west == need - half and east == half)
	for side in _front_tags:
		var n := west if side == "west" else east
		(_front_tags[side] as Label3D).text = "%s FRONT  %d" % [side.to_upper(), n]
	shown["west"] = west
	shown["east"] = east
	if not ok:
		screen._status.text = "Split your squad: %d on each front (west %d · east %d)" % [half, west, east]
		screen._begin.disabled = true
	elif not screen._begin.disabled:
		screen._status.text = "Ready  ·  west %d · east %d  ·  drag to rearrange  ·  Enter to begin" % [west, east]


# ---------------------------------------------------------------- the Horde

func _dress_horde() -> void:
	var bd: BWBoard = screen._board
	var bv: BWBoardView = screen._bv
	var ex := Array(bd.objective.get("exit", [])).map(func(p): return Vector2i(int(p[0]), int(p[1])))
	_hex_mesh(bv, ex, 0.0, 0.93, Color(0, 0, 0, 0.45))
	_hex_mesh(bv, ex, 0.62, 0.86, Color(0, 0, 0, 0.9))
	ex.sort()
	if not ex.is_empty():
		for h in [ex[0], ex[ex.size() / 2], ex[-1]]:
			var l := _tag("EXIT", 28)
			l.position = bv.top_center(h) + Vector3(0, 1.0, 0)
	var edge := Array(bd.objective.get("spawn_edge", [])).map(func(p): return Vector2i(int(p[0]), int(p[1])))
	_hex_mesh(bv, edge.filter(func(h): return h.y == 0), 0.78, 0.9, Color(0, 0, 0, 0.45))


# ---------------------------------------------------------------- bits

func _tag(text: String, size: int) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0011
	l.font_size = size
	l.outline_size = 9
	l.modulate = Color.WHITE
	l.outline_modulate = Color.BLACK
	add_child(l)
	return l


func _hex_mesh(bv: BWBoardView, hexes: Array, r0: float, r1: float, col: Color) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for h in hexes:
		var c: Vector3 = bv.top_center(h) + Vector3(0, 0.035, 0)
		var outer := BWLook.hex_corners(c, r1)
		var inner := BWLook.hex_corners(c, maxf(r0, 0.0))
		for i in 6:
			var j := (i + 1) % 6
			if r0 <= 0.0:
				for p in [c, outer[i], outer[j]]:
					st.set_color(Color.WHITE)
					st.add_vertex(p)
			else:
				for p in [outer[i], outer[j], inner[j], outer[i], inner[j], inner[i]]:
					st.set_color(Color.WHITE)
					st.add_vertex(p)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = BWLook.alpha(false)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("tint", col)
	add_child(mi)
	return mi
