class_name BWKit2View
extends Node3D
## D425-D432 readability for the weapon kit pass 2 (rules: BWKit2 and the
## defs riposte, lance_charge, consume, daggerleap, fan_of_knives).
##
## Standing marks, read from the battle when it changes (a signature):
##   Lance Charge   a set charge's line, for both sides: an inked ribbon in
##                  the element down the line, chevrons pointing the way and
##                  a barb at the end (D428: "telegraphed")
##   Riposte        a standing guard previews its release: a small inked
##                  element dot on each of the 18 release hexes (D425)
##   Barrier        Consume's barrier: a dashed white ring at the unit's feet
##                  (D429b)
##   Bellow         D436: a held Bellow (the next Cleave / Sunder doubles):
##                  six inked spikes bursting out round the feet, and a card
##                  line (`card_lines`)
## One-shots (on_event, from BWCombatScreen._play): the release (the lines
## flare out from the duelist), the charge being set / running, Blade Dance,
## the barrier going up and soaking.

const INK := Color(0.02, 0.02, 0.03)
const LIFT := 0.06

var screen: BWCombatScreen
var _mesh: MeshInstance3D
var _sig := ""
var shown := {}            # probes / review: { charges: {id: [hexes]}, guards: {id: [hexes]}, barriers: [ids] }


func setup(s: BWCombatScreen) -> void:
	screen = s
	_mesh = MeshInstance3D.new()
	_mesh.material_override = BWKeystoneView.material()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.sorting_offset = 2.0
	add_child(_mesh)


func _process(_delta: float) -> void:
	if screen == null or screen.battle == null:
		return
	var sig := _signature(screen.battle)
	if sig != _sig and not screen._busy:
		_sig = sig
		rebuild()


func _signature(b: BWBattle) -> String:
	var parts: PackedStringArray = []
	for u in b.units:
		if not u.alive():
			continue
		if u.fx.has("lance_charge"):
			parts.append("c%s%s" % [u.id, var_to_str(u.fx.lance_charge.get("line", []))])
		if not u.riposte.is_empty() and not u.fx.get("riposte_answered", false):
			parts.append("r%s%s%s" % [u.id, u.pos, str(u.riposte.get("element", ""))])
		if BWKit2.barrier_hp(u) > 0:
			parts.append("b%s%s" % [u.id, u.pos])
		if u.fx.get("bellow", false):
			parts.append("w%s%s" % [u.id, u.pos])
	return "|".join(parts)


func rebuild() -> void:
	var b := screen.battle
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 0
	shown = { "charges": {}, "guards": {}, "barriers": [], "bellows": [] }
	var rd = BWSkillRegistry.get_def("riposte")
	for u in b.units:
		if not u.alive():
			continue
		if u.fx.has("lance_charge"):
			var line: Array = u.fx.lance_charge.get("line", [])
			shown.charges[u.id] = line.duplicate()
			_charge_line(st, u.pos, line, str(u.fx.lance_charge.get("element", "")))
			n += 1
		if not u.riposte.is_empty() and not u.fx.get("riposte_answered", false) and rd != null:
			var el := str(u.riposte.get("element", ""))
			var hexes: Array = rd.release_hexes(b, u)
			shown.guards[u.id] = hexes
			for h in hexes:
				_dot(st, _top(h), el)
				n += 1
		if BWKit2.barrier_hp(u) > 0:
			shown.barriers.append(u.id)
			_dashed_ring(st, _top(u.pos) + Vector3(0, 0.01, 0), 0.62, 0.05)
			n += 1
		if u.fx.get("bellow", false):
			shown.bellows.append(u.id)
			_bellow_burst(st, _top(u.pos) + Vector3(0, 0.012, 0), BWLook.element_color(u.element))
			n += 1
	_mesh.mesh = st.commit() if n > 0 else null


func _top(h: Vector2i) -> Vector3:
	return screen.board_view.top_center(h) + Vector3(0, LIFT, 0)


## The set charge: an element ribbon with ink rails from the lancer down the
## line, a chevron on every hex, a barb past the last.
func _charge_line(st: SurfaceTool, from: Vector2i, line: Array, el: String) -> void:
	if line.is_empty():
		return
	var col := BWLook.element_color(el) if el != "" else Color(0.55, 0.55, 0.58)
	col.a = 0.85
	var pts: Array = [_top(from)] + line.map(func(h): return _top(h))
	for i in range(1, pts.size()):
		var a: Vector3 = pts[i - 1]
		var c: Vector3 = pts[i]
		var d := c - a
		d.y = 0.0
		if d.length() < 0.01:
			continue
		var f := d.normalized()
		var s := Vector3(-f.z, 0, f.x)
		var a0 := a + f * (0.45 if i == 1 else 0.0)
		_quad(st, a0 - s * 0.11, c - s * 0.11, c + s * 0.11, a0 + s * 0.11, col)
		_quad(st, a0 - s * 0.15, c - s * 0.15, c - s * 0.11, a0 - s * 0.11, INK)
		_quad(st, a0 + s * 0.11, c + s * 0.11, c + s * 0.15, a0 + s * 0.15, INK)
		# a chevron on the hex, pointing on
		var m := c - f * 0.1 + Vector3(0, 0.004, 0)
		_ribbon(st, m - f * 0.24 - s * 0.26, m, 0.07, INK)
		_ribbon(st, m - f * 0.24 + s * 0.26, m, 0.07, INK)
	# the barb past the end
	var last: Vector3 = pts[-1]
	var prev: Vector3 = pts[-2]
	var fd := last - prev
	fd.y = 0.0
	var ff := fd.normalized() if fd.length() > 0.01 else Vector3.FORWARD
	var sd := Vector3(-ff.z, 0, ff.x)
	var tip := last + ff * 0.62
	_tri(st, last + ff * 0.18 - sd * 0.34, tip, last + ff * 0.18 + sd * 0.34, INK)
	_tri(st, last + ff * 0.24 - sd * 0.22 + Vector3(0, 0.003, 0), tip - ff * 0.1 + Vector3(0, 0.003, 0),
		last + ff * 0.24 + sd * 0.22 + Vector3(0, 0.003, 0), col)


## The release preview: a small element dot with an ink rim.
func _dot(st: SurfaceTool, c: Vector3, el: String) -> void:
	var col := BWLook.element_color(el) if el != "" else Color(0.6, 0.6, 0.6)
	col.a = 0.75
	_disc(st, c, 0.15, Color(INK, 0.8))
	_disc(st, c + Vector3(0, 0.003, 0), 0.11, col)


## D436: a held Bellow: six inked wedge spikes bursting out round the feet,
## each with a sliver of the roarer's hair colour.
func _bellow_burst(st: SurfaceTool, c: Vector3, col: Color) -> void:
	col.a = 0.95
	for i in 6:
		var a := TAU * (i + 0.5) / 6.0
		var d := Vector3(cos(a), 0, sin(a))
		var s := Vector3(-d.z, 0, d.x)
		_tri(st, c + d * 0.52 - s * 0.13, c + d * 0.98, c + d * 0.52 + s * 0.13, INK)
		_tri(st, c + d * 0.6 - s * 0.06 + Vector3(0, 0.003, 0), c + d * 0.86 + Vector3(0, 0.003, 0), c + d * 0.6 + s * 0.06 + Vector3(0, 0.003, 0), col)


## D436: the unit card's line for a held Bellow.
static func card_lines(u: BWUnit, fs: int) -> PackedStringArray:
	var out: PackedStringArray = []
	if u != null and u.fx.get("bellow", false):
		out.append("[font_size=%d][b]Bellow[/b] [color=#%s]its next Cleave or Sunder doubles in size[/color][/font_size]" % [
			fs, BWStyle.TEXT_DIM.to_html(false)])
	return out


func _dashed_ring(st: SurfaceTool, c: Vector3, r: float, w: float) -> void:
	var seg := 24
	for i in seg:
		if i % 2 == 1:
			continue
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		_quad(st, c + d0 * (r - w), c + d0 * (r + w), c + d1 * (r + w), c + d1 * (r - w), INK)
		_quad(st, c + d0 * (r - w * 0.5) + Vector3(0, 0.002, 0), c + d0 * (r + w * 0.5) + Vector3(0, 0.002, 0),
			c + d1 * (r + w * 0.5) + Vector3(0, 0.002, 0), c + d1 * (r - w * 0.5) + Vector3(0, 0.002, 0), Color(1, 1, 1, 0.95))


# ---------------------------------------------------------------- one-shots

func on_event(e: Dictionary) -> void:
	var v: Node3D = screen._views.get(str(e.get("unit", "")))
	match str(e.type):
		"riposte_release":
			if v:
				screen._float_text(v, "Riposte released", BWGearText.readable(BWLook.element_color(str(e.element))), 0.9)
			screen.ui.feed("[b]%s's guard releases[/b]: six lines of %s" % [screen._name(str(e.unit)), str(e.element)])
			rebuild()                      # the preview dots give way to the paint
			_sig = "#dirty"
			await _flare(e.get("hexes", []), str(e.element), screen.battle._unit(str(e.unit)))
			screen.board_view.refresh_tiles()
		"lance_charge_set":
			if v:
				screen._float_text(v, "Charge set", Color.WHITE, 0.8)
			screen.ui.feed("[b]%s sets a Lance Charge[/b]: %d tiles, at its next turn" % [screen._name(str(e.unit)), (e.hexes as Array).size()])
			_sig = "#dirty"
		"lance_charge_run":
			_sig = "#dirty"
			rebuild()                      # the line goes as the run starts
			if e.get("fizzled", false):
				if v:
					screen._float_text(v, "Charge held", Color.WHITE, 0.7)
				return
			screen.ui.banner("Lance Charge", 0.7)
			screen.ui.feed("[b]%s charges[/b] %d tiles%s" % [screen._name(str(e.unit)), maxi((e.path as Array).size() - 1, 0),
				(", piercing %d" % (e.get("struck", []) as Array).size()) if not (e.get("struck", []) as Array).is_empty() else ""])
			await get_tree().create_timer(0.25).timeout
		"blade_dance":
			if v:
				screen._float_text(v, "Blade Dance", Color.WHITE, 0.7)
		"barrier":
			if v:
				screen._float_text(v, "Barrier %d" % int(e.hp), Color.WHITE, 0.8)
			screen.ui.feed("%s raises a barrier (%d)" % [screen._name(str(e.unit)), int(e.hp)])
			_sig = "#dirty"
		"barrier_hit":
			if v:
				screen._float_text(v, "barrier -%d" % int(e.absorbed), Color(0.9, 0.9, 0.95), 0.6)
			_sig = "#dirty"
		"barrier_end":
			_sig = "#dirty"


## The release: each line's hexes flare in turn, out from the duelist.
func _flare(hexes: Array, el: String, u: BWUnit) -> void:
	if hexes.is_empty():
		return
	var col := BWLook.element_color(el)
	var origin: Vector2i = u.pos if u != null else hexes[0]
	for h in hexes:
		var d := BWHex.distance(origin, h)
		var at: Vector3 = screen.board_view.top_center(h)
		get_tree().create_timer(0.07 * (d - 1)).timeout.connect(_pop.bind(at, col))
	await get_tree().create_timer(0.07 * 3 + 0.25).timeout


func _pop(at: Vector3, col: Color) -> void:
	if not is_inside_tree():
		return
	var mi := MeshInstance3D.new()
	mi.material_override = BWKeystoneView.material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.sorting_offset = 3.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_disc(st, Vector3(0, 0.09, 0), 0.62, Color(INK, 0.9))
	_disc(st, Vector3(0, 0.095, 0), 0.52, Color(col, 0.95))
	mi.mesh = st.commit()
	add_child(mi)
	mi.global_position = at
	mi.scale = Vector3.ONE * 0.3
	var tw := create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE, 0.16).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(mi, "transparency", 1.0, 0.3)
	tw.tween_callback(mi.queue_free)


# ---------------------------------------------------------------- mesh bits

static func _disc(st: SurfaceTool, c: Vector3, r: float, col: Color) -> void:
	var seg := 18
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		_tri(st, c, c + Vector3(cos(a0), 0, sin(a0)) * r, c + Vector3(cos(a1), 0, sin(a1)) * r, col)


static func _ribbon(st: SurfaceTool, a: Vector3, b: Vector3, w: float, col: Color) -> void:
	var d := b - a
	d.y = 0.0
	if d.length() < 0.0001:
		return
	var s := Vector3(-d.z, 0, d.x).normalized() * w * 0.5
	_quad(st, a - s, a + s, b + s, b - s, col)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	_tri(st, a, b, c, col)
	_tri(st, a, c, d, col)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	for p in [a, b, c]:
		st.set_color(col)
		st.add_vertex(p)
