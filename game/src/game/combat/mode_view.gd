class_name BWModeView
extends Node3D
## D327-D333: the 6v6 modes on the combat screen (BWObjectives). Inert when
## the fight has no mode.
##   intro()       the banner names the mode and its objective; the feed says
##                 the rules (the divider's element and counter; the waves)
##   the plate     top left (the obelisks' corner): the mode's title and its
##                 hud_lines (Wave 2 of 4 · next in 1 round / Lil Fella 31 / 62 /
##                 Ice Wall: 3 of 3 standing), refreshed after every event
##   exit          a mode's exit row (BWObjectives.set_exit) washed and ringed
##                 in ink, EXIT tags (no shipped mode uses one since D349)
##   telegraphs    a wave_incoming event rings its hexes (pulsing) with a WAVE
##                 n tag until the wave lands
##   events        spawn (the unit view drops in), escape (it walks off,
##                 ESCAPED), divider_break / divider_open / divider_breach
##                 (feed, banner, the board refreshed)

var screen: BWCombatScreen
var battle: BWBattle
var _layer: CanvasLayer
var _panel: PanelContainer
var _title: Label
var _lines: Label
var _tele := {}                  # wave index -> [Node3D]
var _exit_nodes: Array = []
var shown := {}                  # probes / review: { title, lines, telegraphs, exit }


func setup(s: BWCombatScreen) -> void:
	screen = s
	battle = s.battle
	if not BWObjectives.active(battle):
		return
	_build_plate()
	if not BWObjectives.exit_hexes(battle).is_empty():
		_build_exit(BWObjectives.exit_hexes(battle))
	refresh()


func active() -> bool:
	return battle != null and BWObjectives.active(battle) and BWObjectives.title(battle) != ""


## The opening: the banner names the mode and the objective (in place of
## "Battle start"), the feed spells out the rules.
func intro() -> void:
	var t := BWObjectives.title(battle)
	screen.ui.banner("%s  ·  %s" % [t, _short_goal()], 3.2)
	screen.ui.feed("[b]%s[/b]  %s" % [t, BWObjectives.objective_text(battle)])
	match BWObjectives.mode_of(battle):
		"splitfront":
			var el := BWSplitFront.element(battle)
			screen.ui.feed("[b]Divider: %s.[/b] %s. The enemy may break through at round %d if it is losing a front." % [
				BWSplitFront.NAMES.get(el, "Wall"), BWSplitFront.counter_text(el), BWSplitFront.ENEMY_BREAK_ROUND])
		"horde":
			screen.ui.feed("[b]Keep the little one alive.[/b] The Lil Fella (the ringed one with the lantern) is not yours to command, and nothing of yours can hurt it. It runs from the horde on its own turn. Waves land on the north edge, rung a round ahead; the grunts all move at once (one group turn) and go for the little one, striking whoever is in their way. Elites hunt you too.")
		"defend", "storm":
			for line in BWCastleView.intro_lines(battle):     # D340
				screen.ui.feed(line)


func _short_goal() -> String:
	match BWObjectives.mode_of(battle):
		"splitfront":
			var nm := str(BWSplitFront.NAMES.get(BWSplitFront.element(battle), "wall")).to_lower()
			return "two fronts, %s %s between" % ["an" if nm.begins_with("i") else "a", nm]
		"horde":
			return "Keep the little one alive"
	return BWObjectives.objective_text(battle)


func _build_plate() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 2
	add_child(_layer)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", BWStyle.frame_style())
	_panel.position = Vector2(16, 10)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.theme = BWStyle.theme()
	_layer.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	_panel.add_child(v)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
	_title.add_theme_color_override("font_color", BWStyle.LABEL)
	v.add_child(_title)
	_lines = Label.new()
	_lines.add_theme_font_size_override("font_size", BWStyle.F_BODY)
	v.add_child(_lines)


func refresh() -> void:
	if _panel == null:
		return
	_title.text = BWObjectives.title(battle).to_upper()
	var ls := BWObjectives.hud_lines(battle)
	_lines.text = "\n".join(ls)
	_panel.reset_size()
	shown["title"] = _title.text
	shown["lines"] = ls
	shown["telegraphs"] = _tele.keys()
	shown["exit"] = _exit_nodes.size()


# ---------------------------------------------------------------- the exit

func _build_exit(hexes: Array) -> void:
	var wash := _hex_mesh(hexes, 0.0, 0.93, Color(0, 0, 0, 0.45))
	_exit_nodes.append(wash)
	var ink := _hex_mesh(hexes, 0.62, 0.86, Color(0, 0, 0, 0.9))
	_exit_nodes.append(ink)
	var sorted := hexes.duplicate()
	sorted.sort()
	for h in [sorted[0], sorted[sorted.size() / 2], sorted[-1]]:
		var l := _tag("EXIT", 28)
		l.position = screen.board_view.top_center(h) + Vector3(0, 1.1, 0)
		_exit_nodes.append(l)


# ---------------------------------------------------------------- events

func on_event(e: Dictionary) -> void:
	match str(e.type):
		"wave_incoming":
			_telegraph(int(e.wave), e.hexes)
			screen.ui.feed("[b]Wave %d of %d incoming[/b]: %d on the north edge next round" % [int(e.wave) + _first_offset(), _total_waves(), int(e.count)])
			screen.ui.toast("Wave %d next round" % (int(e.wave) + _first_offset()))
		"spawn":
			_spawn(str(e.unit))
		"wave":
			_clear_tele(int(e.wave))
			screen.ui.banner("Wave %d of %d" % [int(e.wave) + _first_offset(), _total_waves()], 1.4)
			screen.ui.set_order(battle.queue.slice(maxi(battle.turn_index, 0)), battle.current(), BWTurnQueue.build(battle.units))
			await get_tree().create_timer(0.5).timeout
		"escape":
			await _escape(str(e.unit), int(e.escaped), int(e.limit))
		"divider_break":
			screen.board_view.refresh_tiles()
			screen.ui.feed("The %s gives way at %s (%d left)" % [str(BWSplitFront.NAMES.get(str(e.element), "wall")).to_lower(), str(e.hex), int(e.left)])
		"divider_open":
			screen.board_view.refresh_tiles()
			if str(e.by) == "enemy":
				screen.ui.banner("The enemy breaks through: the fronts merge", 2.4)
			else:
				screen.ui.banner("The divider is open: the fronts can merge", 2.0)
			screen.ui.feed("[b]The divider is open.[/b]")
			if screen.readability and not (e.hexes as Array).is_empty():
				await screen.readability.beat(e.hexes[0])
		"divider_breach":
			screen.ui.feed("[b]Round %d:[/b] the enemy is losing a front and tears the divider down." % BWSplitFront.ENEMY_BREAK_ROUND)
		"divider_gust":
			screen.ui.feed("A Gust blows the wind wall apart")
	refresh()


## The Horde counts its first wave (on the board from the start) as wave 1;
## the spawner numbers the scheduled ones from 1.
## D339: a castle mode keeps its own count (Defend: the opening six are wave 1).
func _total_waves() -> int:
	return int(battle.objective_state.get("waves_total", BWHordeMode.total_waves(battle)))


func _first_offset() -> int:
	if battle.objective_state.has("waves_total"):
		return int(battle.objective_state.get("waves_first", 0))      # D339: the castles
	return 1 if BWObjectives.mode_of(battle) == "horde" and int(battle.objective_state.get("horde", {}).get("first", 0)) > 0 else 0


func _telegraph(w: int, hexes: Array) -> void:
	_clear_tele(w)
	var nodes: Array = []
	nodes.append(_hex_mesh(hexes, 0.30, 0.92, Color(0, 0, 0, 0.7), true))
	nodes.append(_hex_mesh(hexes, 0.0, 0.3, Color(1, 1, 1, 0.5), true))
	if not hexes.is_empty():
		var c := Vector3.ZERO
		for h in hexes:
			c += screen.board_view.top_center(h)
		c /= hexes.size()
		var l := _tag("WAVE %d" % (w + _first_offset()), 26)
		l.position = c + Vector3(0, 1.1, 0)
		nodes.append(l)
	_tele[w] = nodes


func _clear_tele(w: int) -> void:
	for n in _tele.get(w, []):
		if is_instance_valid(n):
			n.queue_free()
	_tele.erase(w)


func _spawn(id: String) -> void:
	var u := battle._unit(id)
	if u == null or screen._views.has(id):
		return
	var v := BWUnitView.new()
	screen.add_child(v)
	v.setup(u)
	var to := screen._unit_pos(u.pos)
	v.position = to + Vector3(0, 3.0, 0)
	screen._views[id] = v
	var near: BWUnit = null
	for f in battle.foes_of(u):
		if near == null or BWHex.distance(u.pos, f.pos) < BWHex.distance(u.pos, near.pos):
			near = f
	if near != null:
		v.face(screen._unit_pos(near.pos))
	var tw := create_tween()
	tw.tween_property(v, "position", to, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _escape(id: String, n: int, limit: int) -> void:
	var v: Node3D = screen._views.get(id)
	screen.ui.feed("[b]%s escapes[/b]  (%d / %d)" % [screen._name(id), n, limit])
	if v == null:
		return
	screen._float_text(v, "ESCAPED", Color.WHITE, 0.9)
	var tw := create_tween()
	tw.tween_property(v, "position", v.position + Vector3(0, 0, 1.6), 0.45)
	tw.parallel().tween_property(v, "scale", Vector3(0.05, 0.05, 0.05), 0.45)
	tw.tween_callback(func(): v.visible = false)
	await tw.finished
	screen.ui.set_order(battle.queue.slice(maxi(battle.turn_index, 0)), battle.current(), BWTurnQueue.build(battle.units))


## The end banner for a mode fight ("" = the default).
func end_text(winner: String) -> String:
	if not active():
		return ""
	match BWObjectives.mode_of(battle):
		"horde":
			if winner == "player":
				return "Victory: the little one is safe"
			var lf := BWHordeMode.fella(battle)
			if lf != null and not lf.alive():
				return "Defeat: the Lil Fella fell"
		"splitfront":
			if winner == "player":
				return "Victory: both fronts won"
		"defend", "storm":
			return BWCastleView.end_text(battle, winner)      # D340
	return ""


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


## One mesh of hex rings (r0..r1 of the hex radius) over `hexes`.
func _hex_mesh(hexes: Array, r0: float, r1: float, col: Color, pulse: bool = false) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for h in hexes:
		var c: Vector3 = screen.board_view.top_center(h) + Vector3(0, 0.035, 0)
		var outer := BWLook.hex_corners(c, r1)
		if r0 <= 0.0:
			for i in 6:
				for p in [c, outer[i], outer[(i + 1) % 6]]:
					st.set_color(Color.WHITE)
					st.add_vertex(p)
			continue
		var inner := BWLook.hex_corners(c, r0)
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
	add_child(mi)
	return mi
