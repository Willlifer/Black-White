class_name BWSquallView
extends Node3D
## D311/D313 readability and VFX for wind's Squall and ice's Overfreeze
## (rules: BWSquall, BWOverfreeze; ELEMENTS.md §17). Built in the wind and
## elements views' language: unshaded vertex-coloured meshes, ink first, the
## element's colour on top.
##
## Board marks (rebuilt when the squalls change):
##   squall front  every hex the front reaches at the next tick gets a
##                 spinning three-arm swirl in the squall's colour (light:
##                 yellow over ink; dark: deep violet over ink over a white
##                 hairline, D345) and an
##                 outward chevron that drifts out and back: a moving front.
## Event VFX:
##   squall          the origin flares in the squall's colour (feed line)
##   squall_advance  a ring of gust strokes sweeps out over the reached ring
##   overfreeze      a white burst: an expanding white ring with an ice-cyan
##                   core, white shards with cyan edges flung out over the ring,
##                   the seven hexes flashing white with a cyan rim
## Plus the blast preview's layer (preview) and the shader warm catalogue.

const INK := Color(0.02, 0.02, 0.03)
const LIFT := 0.07
const WHITE := Color(0.98, 0.99, 1.0)

var screen: BWCombatScreen
var _front: Array = []         # [MeshInstance3D swirl, MeshInstance3D chevron, Vector3 base, Vector3 out]
var _sig := ""
var _t := 0.0
var played: Array = []
var shown := {}                # probes / review: { front: [hexes] }


## D345: the dark front was a pale lavender over a white stroke and read as
## a light mark; now a deep violet over an ink outline (the dark tiles' own
## ink-and-violet), with a thin white halo outside the ink so it still reads
## on a dark tile.
const DARK_VIOLET := Color(0.37, 0.16, 0.66)

static func col_of(el: String) -> Color:
	return BWLook.glow_color(el) if el == "light" else DARK_VIOLET


static func under_of(_el: String) -> Color:
	return INK


## The outermost hairline (dark only): white, so ink on a dark tile still reads.
static func halo_of(el: String) -> Color:
	return Color(WHITE, 0.85) if el == "dark" else Color(0, 0, 0, 0)


static func ice_col() -> Color:
	return BWLook.element_color("ice")


static func material() -> StandardMaterial3D:
	return BWElementsView.material()


static func warm_catalog() -> Array:
	return []                                       # the elements view's material covers ours


func setup(s: BWCombatScreen) -> void:
	screen = s


func _process(delta: float) -> void:
	if screen == null or screen.battle == null:
		return
	_t += delta
	var sig := _signature(screen.battle)
	if sig != _sig and not screen._busy:
		_sig = sig
		rebuild()
	for f in _front:
		var sw: MeshInstance3D = f[0]
		var ch: MeshInstance3D = f[1]
		if is_instance_valid(sw):
			sw.rotation.y = -_t * 2.4
		if is_instance_valid(ch):
			ch.position = (f[2] as Vector3) + (f[3] as Vector3) * (0.12 + 0.12 * sin(_t * 4.0))


func _signature(b: BWBattle) -> String:
	var parts: PackedStringArray = []
	var all := BWSquall.squalls(b)
	var keys := all.keys()
	keys.sort()
	for id in keys:
		var s: Dictionary = all[id]
		parts.append("%s%s%d%s" % [id, s.origin, int(s.ring), s.element])
	return "|".join(parts)


func rebuild() -> void:
	for f in _front:
		for n in [f[0], f[1]]:
			if is_instance_valid(n):
				(n as Node).queue_free()
	_front.clear()
	shown = { "front": [] }
	var b := screen.battle
	var all := BWSquall.squalls(b)
	var keys := all.keys()
	keys.sort()
	for id in keys:
		var s: Dictionary = all[id]
		for h in BWSquall.next_ring(b, s):
			shown.front.append(h)
			_front_mark(h, s.origin, str(s.element))


func _top(h: Vector2i) -> Vector3:
	return screen.board_view.top_center(h) + Vector3(0, LIFT, 0)


func _node(st: SurfaceTool, at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.position = at
	return mi


## One hex of the front: a spinning swirl and an outward chevron.
func _front_mark(h: Vector2i, origin: Vector2i, el: String) -> void:
	var c := _top(h)
	var col := col_of(el)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	swirl(st, Vector3.ZERO, 0.62, under_of(el), col, halo_of(el))
	var sw := _node(st, c)
	var o := _top(origin)
	var out := Vector3(c.x - o.x, 0, c.z - o.z)
	out = out.normalized() if out.length() > 0.01 else Vector3.RIGHT
	var cs := SurfaceTool.new()
	cs.begin(Mesh.PRIMITIVE_TRIANGLES)
	chevron(cs, Vector3(0, 0.01, 0), out, 0.3, under_of(el), col, halo_of(el))
	var ch := _node(cs, c)
	_front.append([sw, ch, c, out])


## A three-arm swirl (wind's mark) in `col` over an `under` stroke.
## `halo` (alpha > 0): a wider hairline under the ink (D345, the dark front).
static func swirl(st: SurfaceTool, c: Vector3, rad: float, under: Color, col: Color, halo := Color(0, 0, 0, 0)) -> void:
	for pass_i in range(-1 if halo.a > 0.0 else 0, 2):
		var w := 0.16 if pass_i < 0 else (0.11 if pass_i == 0 else (0.07 if halo.a > 0.0 else 0.06))
		var cc := halo if pass_i < 0 else (under if pass_i == 0 else col)
		for arm in 3:
			var prev := Vector3.ZERO
			for i in 13:
				var t := float(i) / 12.0
				var a := arm * TAU / 3.0 + t * 1.3 * PI
				var r := rad * (1.0 - t) + 0.08
				var p := c + Vector3(cos(a) * r, 0.004 * pass_i, sin(a) * r)
				if i > 0:
					_flat(st, prev, p, w * (1.0 - 0.6 * t), cc)
				prev = p


## An outward chevron (two strokes meeting at the tip).
static func chevron(st: SurfaceTool, c: Vector3, out: Vector3, size: float, under: Color, col: Color, halo := Color(0, 0, 0, 0)) -> void:
	var side := Vector3(-out.z, 0, out.x)
	var tip := c + out * size
	var a := c - out * size * 0.2 + side * size
	var b := c - out * size * 0.2 - side * size
	for pass_i in range(-1 if halo.a > 0.0 else 0, 2):
		var w := 0.17 if pass_i < 0 else (0.12 if pass_i == 0 else (0.07 if halo.a > 0.0 else 0.06))
		var cc := halo if pass_i < 0 else (under if pass_i == 0 else col)
		var lift := Vector3(0, 0.004 * pass_i, 0)
		_flat(st, a + lift, tip + lift, w, cc)
		_flat(st, b + lift, tip + lift, w, cc)


static func _flat(st: SurfaceTool, a: Vector3, b: Vector3, w: float, col: Color) -> void:
	var d := b - a
	d.y = 0
	if d.length() < 0.0001:
		return
	var s := Vector3(-d.z, 0, d.x).normalized() * w * 0.5
	for p in [a - s, a + s, b + s, a - s, b + s, b - s]:
		st.set_color(col)
		st.add_vertex(p)


# ---------------------------------------------------------------- events

func on_event(e: Dictionary) -> void:
	played.append(str(e.type))
	match str(e.type):
		"squall":
			var el := str(e.element)
			_flare(e.hex, col_of(el), under_of(el), halo_of(el))
			screen.ui.feed("[b]Squall![/b] %s's wind catches the %s: it spreads a ring a tick for %d ticks%s" % [
				screen._name(str(e.unit)), el, int(e.left), " (the old squall is gone)" if bool(e.get("replaced", false)) else ""])
			_sig = ""
			await get_tree().create_timer(0.25).timeout
		"squall_advance":
			_sweep(e.hex, e.ring, str(e.element))
			screen.ui.feed("[b]Squall[/b]: the %s front advances (%d hex%s)" % [str(e.element), (e.painted as Array).size(),
				"" if (e.painted as Array).size() == 1 else "es"])
			screen.board_view.refresh_tiles()
			_sig = ""
			await get_tree().create_timer(0.3).timeout
		"squall_end":
			_sig = ""
		"overfreeze":
			burst(e.hex, e.ring)
			screen._shake(0.14)
			screen.ui.feed("[b]Overfreeze![/b] %s's ice shatters the frozen water: %d%% to every unit on and around it, a rink forms" % [
				screen._name(str(e.unit)), roundi(float(e.pct))])
			screen.board_view.refresh_tiles()
			await get_tree().create_timer(0.35).timeout


func _fade(mi: MeshInstance3D, life: float, grow: float = 1.0) -> void:
	var m := mi.material_override as StandardMaterial3D
	m.albedo_color = Color(1, 1, 1, 1)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "albedo_color", Color(1, 1, 1, 0), life).set_ease(Tween.EASE_IN)
	if grow != 1.0:
		tw.tween_property(mi, "scale", Vector3.ONE * grow, life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(mi.queue_free)


func _flare(hex: Vector2i, col: Color, under: Color, halo := Color(0, 0, 0, 0)) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	swirl(st, Vector3.ZERO, 0.9, under, col, halo)
	var mi := _node(st, _top(hex))
	_fade(mi, 0.5, 1.8)


## The front sweeps over its ring: a gust stroke per hex, pointing out.
func _sweep(origin: Vector2i, ring: Array, el: String) -> void:
	var o := _top(origin)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for h in ring:
		var c := _top(h) - o
		var out := Vector3(c.x, 0, c.z).normalized()
		chevron(st, c, out, 0.42, under_of(el), col_of(el), halo_of(el))
		_flat(st, c - out * 0.45, c + out * 0.2, 0.05, col_of(el))
	var mi := _node(st, o)
	_fade(mi, 0.55, 1.12)


## The Overfreeze burst at `hex` over `ring`.
func burst(hex: Vector2i, ring: Array) -> void:
	var c := _top(hex)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_ring(st, Vector3(0, 0.02, 0), 0.6, 0.24, INK)
	_ring(st, Vector3(0, 0.025, 0), 0.6, 0.16, WHITE)
	_ring(st, Vector3(0, 0.03, 0), 0.6, 0.05, ice_col())
	for k in 10:                                  # ice spikes
		var a := TAU * k / 10.0 + 0.15
		var d := Vector3(cos(a), 0, sin(a))
		var s := Vector3(-d.z, 0, d.x)
		var base := d * 0.55
		var tip := d * (1.15 + 0.2 * (k % 2)) + Vector3(0, 0.45 + 0.2 * (k % 3), 0)
		_tri(st, base - s * 0.16, base + s * 0.16, tip, INK)
		_tri(st, base - s * 0.11, base + s * 0.11, tip - d * 0.06, WHITE)
		_tri(st, base - s * 0.03, base + s * 0.03, tip - d * 0.1, ice_col())
	_fade(_node(st, c), 0.6, 1.9)
	var hs := SurfaceTool.new()
	hs.begin(Mesh.PRIMITIVE_TRIANGLES)
	for h in [hex] + ring:
		var p := _top(h) - c
		var outer := BWLook.hex_corners(p, BWLook.HEX_SIZE * 0.84)
		var inner := BWLook.hex_corners(p, BWLook.HEX_SIZE * 0.72)
		for e in 6:
			_tri(hs, p, outer[e], outer[(e + 1) % 6], Color(WHITE, 0.8))
			var n := (e + 1) % 6
			_tri(hs, outer[e] + Vector3(0, 0.003, 0), outer[n] + Vector3(0, 0.003, 0), inner[n] + Vector3(0, 0.003, 0), ice_col())
			_tri(hs, outer[e] + Vector3(0, 0.003, 0), inner[n] + Vector3(0, 0.003, 0), inner[e] + Vector3(0, 0.003, 0), ice_col())
	_fade(_node(hs, c), 0.7)
	_shards(c + Vector3(0, 0.3, 0), 14, 1.7)


func _shards(at: Vector3, n: int, reach: float) -> void:
	for i in n:
		var a := TAU * i / n + 0.25 * (i % 3)
		var mi := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.1, 0.3, 0.07)
		mi.mesh = pm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = WHITE if i % 3 != 0 else ice_col()
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.global_position = at
		mi.rotation = Vector3(0.5 * i, a, 0.3 * i)
		var to := at + Vector3(cos(a) * reach, 0.5 - 0.15 * (i % 4), sin(a) * reach)
		var tw := create_tween()
		tw.tween_property(mi, "global_position", to, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.parallel().tween_property(mi, "rotation", mi.rotation + Vector3(3, 2, 1), 0.5)
		tw.tween_property(mi, "scale", Vector3.ONE * 0.01, 0.2)
		tw.tween_callback(mi.queue_free)


func _ring(st: SurfaceTool, c: Vector3, r: float, w: float, col: Color) -> void:
	var seg := 28
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		_tri(st, c + d0 * (r - w * 0.5), c + d0 * (r + w * 0.5), c + d1 * (r + w * 0.5), col)
		_tri(st, c + d0 * (r - w * 0.5), c + d1 * (r + w * 0.5), c + d1 * (r - w * 0.5), col)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	for p in [a, b, c]:
		st.set_color(col)
		st.add_vertex(p)


# ---------------------------------------------------------------- the blast preview's layer

## BWBlastPreview.show_sim: a squall the action starts (its first front ring,
## swirls and "SQUALL: NEXT TICK"), an Overfreeze (the seven hexes hatched
## white, the centre's heavy ink rim, "OVERFREEZE 12%"). Squalls already on
## the board are drawn by the board marks.
static func preview(bp: BWBlastPreview, st: SurfaceTool, sim: Dictionary) -> void:
	for ev in sim.get("events", []):
		match str(ev.get("type", "")):
			"squall":
				var el := str(ev.element)
				var nxt: Array = ev.get("next", [])
				for h in nxt:
					bp._hatch(st, h, col_of(el), "sparse", 0.75)
					bp._rim(st, h, Color(BWLook.glow_color("wind"), 0.95), BWBlastPreview.RIM_W, true)
					swirl(st, bp._top(h) + Vector3(0, 0.01, 0), 0.45, under_of(el), col_of(el), halo_of(el))
				if not nxt.is_empty():
					bp._hex_tag(nxt[0], "SQUALL: NEXT TICK", BWLook.glow_color("wind"), 0.55)
				bp._hex_tag(ev.hex, "SQUALL (%s)" % el.to_upper(), col_of(el) if el == "light" else BWLook.glow_color("wind"), 0.85)
			"overfreeze":
				for h in [ev.hex] + (ev.ring as Array):
					if bp.board_view.board.exists(h):
						bp._hatch(st, h, ice_col(), "mid", 0.95)
						bp._rim(st, h, Color(ice_col(), 0.95), BWBlastPreview.RIM_W, true)
				bp._rim(st, ev.hex, INK, BWBlastPreview.RIM_W * 1.6)
				bp._hex_tag(ev.hex, "OVERFREEZE %d%%" % roundi(float(ev.pct)), ice_col(), 0.55)
