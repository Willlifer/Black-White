class_name BWElementsView
extends Node3D
## D285-D292 readability and VFX for fire, light and thunder (rules:
## BWOverheat, BWBeams, BWThunderKeys; design/ELEMENTS-v3.md §11 and the
## author's rulings). Built in the wind view's language: one unshaded,
## vertex-coloured mesh per layer, ink first, the element's colour on top.
##
## Board marks (rebuilt when the battle's signature changes):
##   beam        a thin dashed light-yellow line between the ends (through a
##               Prism bend), over an ink under-stroke, at chest height
##   Overheat    every fire 3 hex gets a pulsing rim (fire glow over ink)
##   Static fuse a holder's fuse gets two crossed ink blades with a thunder edge
##   Empowered   a small "EMPOWERED +15%" tag over the unit, with a glint
##   Ward        "WARD 9" under it while a Ward of Light holds
## Event VFX (on_event, cheap: a mesh that fades on a tween):
##   overheat    a fire ring bursting outward over the ring hexes
##   light_beams a wide light ribbon along each beam, fading
##   empowered   a four-point glint on the unit
##   blade_burst two crossing slashes in the thunder colour
##   launch      an arc from the hex up and out, with an arrow head
## Plus the blast preview's layer (preview), the unit card's lines
## (card_lines) and the shader warm catalogue (warm_catalog).

const INK := Color(0.02, 0.02, 0.03)
const LIFT := 0.06
const BEAM_Y := 0.75

var screen: BWCombatScreen
var _marks: MeshInstance3D
var _pulse: MeshInstance3D
var _sig := ""
var _tags := {}               # unit id -> Label3D
var _t := 0.0
var played: Array = []         # event types replayed so far (probes, review)
var shown := {}               # what is drawn (probes, review): { beams, overheat, fuses, empowered }


static func light_col() -> Color:
	return BWLook.glow_color("light")


static func fire_col() -> Color:
	return BWLook.glow_color("fire")


static func thunder_col() -> Color:
	return BWLook.glow_color("thunder")


static func material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = 1
	return m


## BWShaderWarm: the one material every mark and burst uses.
static func warm_catalog() -> Array:
	var mi := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)]:
		st.set_color(Color(1, 1, 1, 0.5))
		st.add_vertex(p)
	mi.mesh = st.commit()
	mi.material_override = material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return [["elements_marks", mi]]


func setup(s: BWCombatScreen) -> void:
	screen = s
	_marks = _mesh_node()
	_pulse = _mesh_node()


func _mesh_node() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.material_override = material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _process(delta: float) -> void:
	if screen == null or screen.battle == null:
		return
	_t += delta
	var b := screen.battle
	var sig := _signature(b)
	if sig != _sig and not screen._busy:
		_sig = sig
		rebuild()
	var m := _pulse.material_override as StandardMaterial3D
	m.albedo_color = Color(1, 1, 1, 0.45 + 0.55 * (0.5 + 0.5 * sin(_t * 4.2)))   # the Overheat telegraph pulses
	_place_tags(b)


func _signature(b: BWBattle) -> String:
	var parts: PackedStringArray = []
	for bm in BWBeams.beams(b):
		parts.append(var_to_str(bm.points))
	for h in _hot(b):
		parts.append("o%s" % h)
	for h in _fuses(b):
		parts.append("s%s" % h)
	return "|".join(parts)


func _hot(b: BWBattle) -> Array:
	var out: Array = []
	for h in b.tiles.entries:
		if b.tiles.intensity(h, "fire") >= 3 and not b.tiles.is_glazed(h):
			out.append(h)
	out.sort()
	return out


## Fuses laid by a Static Blades holder (and any flagged static).
func _fuses(b: BWBattle) -> Array:
	var out: Array = []
	for h in b.tiles.entries:
		var e: Dictionary = b.tiles.entries[h]
		if str(e.get("marker", "")) != "fuse":
			continue
		var src := b._unit(str(e.get("source", "")))
		if bool(e.get("static", false)) or (src != null and BWThunderKeys.ks(src, "static_blades")):
			out.append(h)
	out.sort()
	return out


func rebuild() -> void:
	var b := screen.battle
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 0
	var all := BWBeams.beams(b)
	shown = { "beams": all.size(), "overheat": _hot(b), "fuses": _fuses(b), "empowered": [] }
	for bm in all:
		beam_line(st, bm.points, 1.0)
		n += 1
	for h in shown.fuses:
		_blades(st, h)
		n += 1
	_marks.mesh = st.commit() if n > 0 else null
	var ps := SurfaceTool.new()
	ps.begin(Mesh.PRIMITIVE_TRIANGLES)
	for h in shown.overheat:
		_rim(ps, _top(h), BWLook.HEX_SIZE * 0.86, 0.11, INK)
		_rim(ps, _top(h) + Vector3(0, 0.004, 0), BWLook.HEX_SIZE * 0.8, 0.08, fire_col())
	_pulse.mesh = ps.commit() if not shown.overheat.is_empty() else null


func _top(h: Vector2i) -> Vector3:
	return screen.board_view.top_center(h) + Vector3(0, LIFT, 0)


## A dashed light line through `pts` (hexes) at chest height, ink beneath.
func beam_line(st: SurfaceTool, pts: Array, alpha: float, y: float = BEAM_Y) -> void:
	for i in pts.size() - 1:
		var a := _top(pts[i]) + Vector3(0, y, 0)
		var c := _top(pts[i + 1]) + Vector3(0, y, 0)
		var segs := maxi(4, int(a.distance_to(c) / 0.32))
		for k in segs:
			if k % 2 == 1:
				continue
			var p0 := a.lerp(c, float(k) / segs)
			var p1 := a.lerp(c, float(k + 1) / segs)
			_ribbon3(st, p0, p1, 0.12, Color(INK, 0.85 * alpha))
			_ribbon3(st, p0, p1, 0.075, Color(light_col(), alpha))


## Two crossed blades on a Static fuse.
func _blades(st: SurfaceTool, h: Vector2i) -> void:
	var c := _top(h) + Vector3(0, 0.01, 0)
	for s in [1.0, -1.0]:
		var d := Vector3(0.42, 0, 0.42 * s)
		_ribbon(st, c - d, c + d, 0.13, INK)
		_ribbon(st, c - d * 0.92, c + d * 0.92, 0.05, thunder_col())
	_ring(st, c, 0.2, 0.05, INK)


# ---------------------------------------------------------------- tags over units

func _place_tags(b: BWBattle) -> void:
	var want := {}
	for u in b.units:
		if not u.alive() or not screen._views.has(u.id):
			continue
		var bits: PackedStringArray = []
		if BWBeams.empowered(u) > 0:
			bits.append("EMPOWERED +%d%%" % BWBeams.empowered(u))
		var w: Dictionary = u.fx.get("light_ward", {})
		if not w.is_empty():
			bits.append("WARD %d" % int(w.hp))
		if not bits.is_empty():
			want[u.id] = " · ".join(bits)
	shown.empowered = want.keys()
	for id in _tags.keys():
		if not want.has(id):
			(_tags[id] as Label3D).queue_free()
			_tags.erase(id)
	for id in want:
		var l: Label3D = _tags.get(id)
		if l == null:
			l = Label3D.new()
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.no_depth_test = true
			l.fixed_size = true
			l.pixel_size = 0.0009
			l.font_size = 22
			l.outline_size = 9
			l.modulate = light_col().lightened(0.3)
			l.outline_modulate = INK
			l.render_priority = 16
			l.outline_render_priority = 15
			add_child(l)
			_tags[id] = l
		l.text = str(want[id])
		var v: Node3D = screen._views[id]
		l.global_position = v.global_position + Vector3(0, screen._label_height(v) + 0.55, 0)
		l.visible = v.visible
		l.scale = Vector3.ONE * (1.0 + 0.06 * sin(_t * 5.0))


## The tag over a unit (probes, review).
func tag_text(id: String) -> String:
	var l: Label3D = _tags.get(id)
	return l.text if l != null else ""


# ---------------------------------------------------------------- events

## The screen replays an event of ours. Short, never blocking long.
func on_event(e: Dictionary) -> void:
	var b := screen.battle
	played.append(str(e.type))
	match str(e.type):
		"overheat":
			_fx_overheat(e.hex, e.ring)
			screen._shake(0.1 + 0.04 * int(e.get("depth", 1)))
			screen.ui.feed("[b]Overheat![/b] %s's fire erupts: the ring to fire +2, %d%%%s" % [
				screen._name(str(e.unit)), int(e.pct), " (chained)" if int(e.get("depth", 1)) > 1 else ""])
			screen.board_view.refresh_tiles()
			await get_tree().create_timer(0.32).timeout
		"light_beams":
			for bm in e.beams:
				_fx_beam(bm.points)
			screen.ui.feed("[b]Beams[/b]: %d resolve%s" % [(e.beams as Array).size(), "s" if (e.beams as Array).size() == 1 else ""])
			await get_tree().create_timer(0.35).timeout
		"empowered":
			var v: Node3D = screen._views.get(str(e.unit))
			if v:
				_fx_glint(v.global_position + Vector3(0, screen._label_height(v) * 0.6, 0))
				screen._float_text(v, "Empowered +%d%%" % int(e.pct), light_col().lightened(0.2), 0.5)
		"blade_burst":
			_fx_blades(e.hex)
			screen._shake(0.1)
			screen.ui.feed("[b]Blade burst![/b] %s's Static fuse, %d%%" % [screen._name(str(e.unit)), int(e.pct)])
			await get_tree().create_timer(0.2).timeout
		"launch":
			var lv: Node3D = screen._views.get(str(e.unit))
			_fx_launch(e.hex, lv)
			screen.ui.feed("[b]Blast Rider[/b]: %s is launched (move %d)" % [screen._name(str(e.unit)), int(e.move)])
		"static_arm":
			_fx_flash(e.hex, thunder_col())
			screen.ui.feed("%s arms a Static fuse" % screen._name(str(e.unit)))
		"daisy":
			screen.ui.feed("[b]Daisy Chain[/b]: another of %s's fuses blows" % screen._name(str(e.unit)))
			screen.board_view.chain_bolt(e.from, e.hex)
		"magnify":
			var mv: Node3D = screen._views.get(str(e.unit))
			if mv:
				screen._float_text(mv, "Magnified", light_col().lightened(0.2), 0.5)
			screen.ui.feed("[b]Magnify[/b] (%s's light): %s" % [screen._name(str(e.by)), "+1 radius" if str(e.kind) == "radius" else "+1 charge step"])
		"dawn":
			screen.ui.feed("Dawn: %s's %s cooldown -1" % [screen._name(str(e.unit)), str(BWSkills.get_skill(str(e.skill).get_slice(":", 0)).get("name", e.skill))])
		"phoenix":
			var pv: Node3D = screen._views.get(str(e.unit))
			if str(e.what) == "rise" and pv:
				screen._float_text(pv, "Phoenix Heart", fire_col(), 0.8)
				screen.ui.feed("[b]Phoenix Heart[/b]: %s holds at 1 HP, and the fire erupts" % screen._name(str(e.unit)))
			elif str(e.what) == "heal" and pv:
				screen._float_text(pv, "Phoenix", fire_col(), 0.4)
		"light_ward":
			var wv: Node3D = screen._views.get(str(e.unit))
			if wv:
				screen._float_text(wv, "Ward of Light %d" % int(e.hp), light_col().lightened(0.2), 0.5)
		"light_ward_break":
			screen.ui.feed("%s's Ward of Light absorbs %d" % [screen._name(str(e.unit)), int(e.absorbed)])
		"rider_immune":
			var rv: Node3D = screen._views.get(str(e.unit))
			if rv:
				screen._float_text(rv, "immune", Color.WHITE, 0.4)
		"trailblaze":
			screen.board_view.refresh_tiles()
	if b != null:
		_sig = ""                                    # redraw the marks once the replay catches up


# ---------------------------------------------------------------- VFX (one-shots)

func _fade(mi: MeshInstance3D, life: float, grow: float = 1.0) -> void:
	var m := mi.material_override as StandardMaterial3D
	m.albedo_color = Color(1, 1, 1, 1)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "albedo_color", Color(1, 1, 1, 0), life).set_ease(Tween.EASE_IN)
	if grow != 1.0:
		tw.tween_property(mi, "scale", Vector3.ONE * grow, life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(mi.queue_free)


func _shot(st: SurfaceTool, at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at
	return mi


## The eruption: the centre flares, a fire ring bursts out over the ring.
func _fx_overheat(hex: Vector2i, ring: Array) -> void:
	var c := _top(hex)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_ring(st, Vector3.ZERO, 0.55, 0.22, INK)
	_ring(st, Vector3.ZERO, 0.55, 0.13, fire_col())
	for k in 8:                                   # flame tongues
		var a := TAU * k / 8.0
		var d := Vector3(cos(a), 0, sin(a))
		var s := Vector3(-d.z, 0, d.x)
		var base := d * 0.62
		var tip := d * 1.25 + Vector3(0, 0.5, 0)
		_tri(st, base - s * 0.14, base + s * 0.14, tip, fire_col().lightened(0.2))
	_fade(_shot(st, c), 0.55, 1.9)
	var hs := SurfaceTool.new()
	hs.begin(Mesh.PRIMITIVE_TRIANGLES)
	for h in ring:
		var p := _top(h) - c
		var corners := BWLook.hex_corners(p, BWLook.HEX_SIZE * 0.8)
		for e in 6:
			_tri(hs, p, corners[e], corners[(e + 1) % 6], Color(fire_col(), 0.55))
	_fade(_shot(hs, c), 0.6)


## A beam resolves: a wide light ribbon along it.
func _fx_beam(pts: Array) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in (pts as Array).size() - 1:
		var a := _top(pts[i]) + Vector3(0, BEAM_Y, 0)
		var c := _top(pts[i + 1]) + Vector3(0, BEAM_Y, 0)
		_ribbon3(st, a, c, 0.34, Color(INK, 0.6))
		_ribbon3(st, a, c, 0.26, light_col())
		_ribbon3(st, a, c, 0.1, Color(1, 1, 0.95))
	_fade(_shot(st, Vector3.ZERO), 0.6)


## A four-point glint (Empowered).
func _fx_glint(at: Vector3) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var right := cam.global_transform.basis.x if cam else Vector3.RIGHT
	var up := cam.global_transform.basis.y if cam else Vector3.UP
	for k in 4:
		var a := TAU * k / 4.0
		var d := right * cos(a) + up * sin(a)
		var s := right * -sin(a) + up * cos(a)
		_tri(st, -s * 0.09, s * 0.09, d * 0.62, light_col().lightened(0.3))
		_tri(st, -s * 0.13, s * 0.13, -d * 0.0 + d * 0.3, INK)
	_fade(_shot(st, at), 0.5, 1.6)


## Two crossing slashes (the blade burst).
func _fx_blades(hex: Vector2i) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in [1.0, -1.0]:
		var a := Vector3(-0.8, 0.3, -0.8 * s)
		var c := Vector3(0.8, 1.5, 0.8 * s)
		_ribbon3(st, a, c, 0.22, INK)
		_ribbon3(st, a, c, 0.12, thunder_col())
	_ring(st, Vector3(0, 0.02, 0), 0.7, 0.12, thunder_col())
	_fade(_shot(st, _top(hex)), 0.4, 1.3)


## The launch: an arc up out of the hex, with an arrow head.
func _fx_launch(hex: Vector2i, v: Node3D) -> void:
	var a := _top(hex)
	var dir := Vector3(1, 0, 0)
	if v != null:
		dir = -v.global_transform.basis.z
		dir.y = 0
		dir = dir.normalized() if dir.length() > 0.1 else Vector3.RIGHT
	var c := a + dir * 2.2
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array = []
	for i in 17:
		var t := float(i) / 16.0
		pts.append(a.lerp(c, t) + Vector3(0, 2.2 * 4.0 * t * (1.0 - t) + 0.2, 0) - a)
	for i in 16:
		_ribbon3(st, pts[i], pts[i + 1], 0.16, INK)
		_ribbon3(st, pts[i], pts[i + 1], 0.09, thunder_col())
	var tip: Vector3 = pts[16]
	var back: Vector3 = pts[14]
	var d := (tip - back).normalized()
	var side := d.cross(Vector3.UP).normalized() * 0.3
	_tri(st, tip + d * 0.1, back + side, back - side, INK)
	_fade(_shot(st, a), 0.7)


func _fx_flash(hex: Vector2i, col: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_ring(st, Vector3.ZERO, 0.45, 0.1, col)
	_fade(_shot(st, _top(hex)), 0.35, 1.5)


# ---------------------------------------------------------------- the blast preview's layer

## BWBlastPreview.show_sim: eruption rings, the beams after the action with
## their Empowered ends, the Static fuse it arms, the blade burst, the launch
## arrow and the Magnify tag. `bp` is the preview (its hatch, rim and tag tools).
static func preview(bp: BWBlastPreview, st: SurfaceTool, sim: Dictionary) -> void:
	var tagged := {}
	for ev in sim.get("events", []):
		match str(ev.get("type", "")):
			"overheat":
				for h in ev.ring:
					if bp.board_view.board.exists(h):
						bp._hatch(st, h, fire_col(), "mid", 0.85)
						bp._rim(st, h, Color(fire_col(), 0.95), BWBlastPreview.RIM_W, true)
				bp._rim(st, ev.hex, INK, BWBlastPreview.RIM_W * 1.6)
				bp._hex_tag(ev.hex, "OVERHEAT %d%%" % int(ev.pct) + (" ×2" if int(ev.get("depth", 1)) > 1 else ""), fire_col(), 0.55)
			"static_arm":
				bp._rim(st, ev.hex, thunder_col(), BWBlastPreview.RIM_W * 1.2, true)
				bp._hex_tag(ev.hex, "STATIC FUSE", thunder_col(), 0.75)
			"blade_burst":
				bp._hex_tag(ev.hex, "BLADE BURST %d%%" % int(ev.pct), thunder_col(), 0.75)
			"launch":
				_launch_arrow(bp, st, ev.hex, int(ev.move))
			"magnify":
				for h in ev.get("ring", []):
					bp._rim(st, h, Color(light_col(), 0.9), BWBlastPreview.RIM_W * 0.8, true)
				if not tagged.has("magnify"):
					tagged["magnify"] = true
					var ring: Array = ev.get("ring", [])
					var keys: Array = (sim.get("hexes", {}) as Dictionary).keys()
					keys.sort()
					var at: Vector2i = ring[0] if not ring.is_empty() else (keys[0] if not keys.is_empty() else BWBattle.NOWHERE)
					if at != BWBattle.NOWHERE:
						bp._hex_tag(at, "MAGNIFY " + ("+1 RADIUS" if str(ev.kind) == "radius" else "+1 STEP"), light_col(), 0.95)
			"empowered":
				pass
	for bm in sim.get("beams", []):
		var pts: Array = bm.points
		for i in pts.size() - 1:
			var a := bp._top(pts[i]) + Vector3(0, BEAM_Y, 0)
			var c := bp._top(pts[i + 1]) + Vector3(0, BEAM_Y, 0)
			var segs := maxi(4, int(a.distance_to(c) / 0.32))
			for k in segs:
				if k % 2 == 1:
					continue
				bp._ribbon_seg(st, a.lerp(c, float(k) / segs), a.lerp(c, float(k + 1) / segs), 0.07, INK)
				bp._ribbon_seg(st, a.lerp(c, float(k) / segs), a.lerp(c, float(k + 1) / segs), 0.045, light_col())
		for h in bm.hexes:
			bp._hatch(st, h, light_col(), "sparse", 0.7)
		bp._hex_tag(pts[0], "EMPOWERED +%d%%" % int(bm.empower), light_col(), 1.05)
		bp._hex_tag(pts[pts.size() - 1], "EMPOWERED +%d%%" % int(bm.empower), light_col(), 1.05)


static func _launch_arrow(bp: BWBlastPreview, st: SurfaceTool, hex: Vector2i, move: int) -> void:
	var a := bp._top(hex) + Vector3(0, 0.3, 0)
	var n := 12
	var pts: Array = []
	for i in n + 1:
		var t := float(i) / n
		pts.append(a + Vector3(1.4 * t, 1.1 * 4.0 * t * (1.0 - t) + 0.3 * t, 0.5 * t))
	for i in n:
		bp._ribbon_seg(st, pts[i], pts[i + 1], 0.09, INK)
		bp._ribbon_seg(st, pts[i], pts[i + 1], 0.05, thunder_col())
	var tip: Vector3 = pts[n]
	var back: Vector3 = pts[n - 2]
	var d := (tip - back).normalized()
	var side := d.cross(Vector3.FORWARD).normalized() * 0.25
	for p in [tip + d * 0.15, back + side, back - side]:
		st.set_color(INK)
		st.add_vertex(p)
	bp._hex_tag(hex, "LAUNCH: MOVE %d" % move, thunder_col(), 1.35)


# ---------------------------------------------------------------- the unit card (BWCombatUI)

static func card_lines(u: BWUnit, fs: int) -> PackedStringArray:
	var out: PackedStringArray = []
	var dim := BWStyle.TEXT_DIM.to_html(false)
	if BWBeams.empowered(u) > 0:
		out.append("[font_size=%d][b]%s[/b] [color=#%s]+%d%% on its next attack, until its turn ends[/color][/font_size]" % [
			fs, BWGlossary.markup("Empowered"), dim, BWBeams.empowered(u)])
	var w: Dictionary = u.fx.get("light_ward", {})
	if not w.is_empty():
		out.append("[font_size=%d][b]Ward of Light[/b] [color=#%s]absorbs %d, until hit[/color][/font_size]" % [fs, dim, int(w.hp)])
	return out


# ---------------------------------------------------------------- geometry

func _ribbon(st: SurfaceTool, a: Vector3, b: Vector3, w: float, col: Color) -> void:
	var d := b - a
	d.y = 0
	if d.length() < 0.0001:
		return
	var s := Vector3(-d.z, 0, d.x).normalized() * w * 0.5
	_quad(st, a - s, a + s, b + s, b - s, col)


## A ribbon readable from any orbit: two crossed strips.
func _ribbon3(st: SurfaceTool, p0: Vector3, p1: Vector3, w: float, col: Color) -> void:
	var d := (p1 - p0).normalized()
	var s1 := d.cross(Vector3.UP).normalized() * w * 0.5
	if s1.length() < 0.001:
		s1 = Vector3.RIGHT * w * 0.5
	var s2 := d.cross(s1).normalized() * w * 0.5
	_quad(st, p0 - s1, p0 + s1, p1 + s1, p1 - s1, col)
	_quad(st, p0 - s2, p0 + s2, p1 + s2, p1 - s2, col)


func _ring(st: SurfaceTool, c: Vector3, r: float, w: float, col: Color) -> void:
	var seg := 28
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		_quad(st, c + d0 * (r - w * 0.5), c + d0 * (r + w * 0.5), c + d1 * (r + w * 0.5), c + d1 * (r - w * 0.5), col)


func _rim(st: SurfaceTool, c: Vector3, r: float, w: float, col: Color) -> void:
	var outer := BWLook.hex_corners(c, r)
	var inner := BWLook.hex_corners(c, r - w)
	for e in 6:
		var n := (e + 1) % 6
		_quad(st, outer[e], outer[n], inner[n], inner[e], col)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	for p in [a, b, c]:
		st.set_color(col)
		st.add_vertex(p)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	for p in [a, b, c, a, c, d]:
		st.set_color(col)
		st.add_vertex(p)
