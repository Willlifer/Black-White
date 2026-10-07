class_name BWBlastPreview
extends Node3D
## D160 blast preview: an action's ground consequences drawn on the board
## while it is being aimed, before Confirm. Fed by BWBattle.simulate (the
## real resolution on a clone, expected rolls), drawn in the range
## overlay's language (BWRangeOverlay, D59): flat hex fills become
## diagonal HATCHING in the consequence's colour, each hex rimmed, plus small
## billboard tags.
##
##   detonate   dense thunder hatch, a heavy ink rim, tag "BLAST 52%"
##   splash     sparse thunder hatch on the blast's ring (the reach of the
##              half-damage splash, even where nobody stands)
##   glaze      ice hatch            gale (origin)  wind hatch, tag "GALE"
##   spread     sparse wind hatch (a gale copy)
##   arm        the operator's colour, sparse (a marker laid)
##   paint      the element's colour, sparse; erase: grey, sparse
##   ignite     a dashed fire rim (fire 2+ on grass catches at cycle end)
##   D266 pools  the pool that reacts: steam (grey hatch, dashed rim, "STEAM"),
##              electrified (thunder hatch, dashed rim, "ELECTRIFIED"), rink
##              glaze; a pillar that rises: ice hatch, heavy ink rim, "PILLAR"
##   slides     D266: an ink arrow along the slide, a dashed ghost ring on the
##              end hex, "SLIDE" there or "SLAM 8%" where it slams
##   arcs       a purple dashed arch from the conductive unit to the one
##              it would jump to, an arrow head over the receiver
##   units      a tag over every unit whose HP would change: "−31" exact,
##              "≈14" an expected value (a roll decides it; D171: one sign,
##              never "~−14"), "KO"; on a friendly (allies and the actor
##              itself) the tag is red with a warning mark. Heals read "+6".
##   layout     D171: the tags are laid out greedily in screen space every
##              frame (front units first): each takes the first of a few
##              nearby slots (as is, up, sideways, further up) that overlaps
##              no other tag and no unit's HP bar, HP number or name.

const LIFT := 0.045                 # above the range overlay's fill (0.03)
const INSET := 0.90
const STRIPE_GAP := { "dense": 0.17, "mid": 0.24, "sparse": 0.34 }
const STRIPE_W := { "dense": 0.075, "mid": 0.06, "sparse": 0.05 }
const RIM_W := 0.06
const WARN := Color(0.86, 0.10, 0.10)
const INK := Color(0.02, 0.02, 0.03)
const ARC_H := 1.6                  # how high the chain arc rises at its middle
const TAG_Y := 0.3                  # tags sit at the unit's feet

var board_view: BWBoardView
var _mesh: MeshInstance3D
var _tags: Array = []
var _groups: Array = []             # D171: [{ main, sub, w, top, bottom }], sizes in label pixels
## D171: screen rects the tags must avoid (the units' HP bars and labels);
## set by BWReadability. Returns Array[Rect2] in viewport coordinates.
var obstacles: Callable
var last: Dictionary = {}           # the simulation last shown (probes, review)


func _init(bv: BWBoardView = null) -> void:
	board_view = bv
	_mesh = MeshInstance3D.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = 2
	_mesh.material_override = m
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


func clear() -> void:
	_mesh.mesh = null
	for t in _tags:
		if is_instance_valid(t):
			t.queue_free()
	_tags.clear()
	_groups.clear()
	last = {}


func shown() -> bool:
	return not last.is_empty()


## Draw one simulation (BWBattle.simulate). `units` maps id -> BWUnit for
## the live positions (tags ride where the unit stands now).
func show_sim(sim: Dictionary, element: String = "") -> void:
	clear()
	if sim.is_empty() or board_view == null:
		return
	last = sim
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var drawn := {}
	# the blast's splash ring first, so the hexes' own kinds draw over it
	for d in sim.detonations:
		for h in board_view.board.area(d.hex, int(d.radius)):
			if h != d.hex and board_view.board.exists(h) and not sim.hexes.has(h):
				_hatch(st, h, BWLook.glow_color("thunder"), "sparse", 0.55)
				_rim(st, h, Color(BWLook.glow_color("thunder"), 0.55), RIM_W * 0.6)
	for h in sim.hexes:
		var rec: Dictionary = sim.hexes[h]
		var kinds: Array = rec.kinds
		var k := _main_kind(kinds)
		var col := _kind_color(k, rec, element)
		_hatch(st, h, col, "dense" if k in ["detonate", "pillar"] else ("mid" if k in ["glaze", "gale", "shock"] else "sparse"), 0.95)
		_rim(st, h, INK if k in ["detonate", "pillar"] else Color(col, 0.95), RIM_W * (1.6 if k in ["detonate", "pillar"] else 1.0),
			k in ["steam", "shock"])                   # D266: a reacting pool's outline is dashed
		if "ignite" in kinds:
			_rim(st, h, BWLook.glow_color("fire"), RIM_W * 0.8, true)
		drawn[h] = true
		var occupied := false
		for id in sim.units:
			if sim.units[id].pos == h:
				occupied = true
		if occupied:
			pass
		elif k == "detonate":
			var pct := 0.0
			for d in sim.detonations:
				if d.hex == h:
					pct = float(d.pct)
			_hex_tag(h, "BLAST %d%%" % roundi(pct), BWLook.glow_color("thunder"), 0.3)
		elif k == "gale":
			var gm := str((rec.get("after", {}) as Dictionary).get("mode", ""))    # D270: the field's mode
			_hex_tag(h, "GALE" if gm == "" else "%s GALE" % gm.to_upper(), BWLook.glow_color("wind"), 0.3)
		elif k == "glaze":
			_hex_tag(h, "GLAZE", BWLook.glow_color("ice"), 0.3)
		elif k == "pillar":
			_hex_tag(h, "PILLAR", BWLook.element_color("ice"), 0.3)
		elif k in ["steam", "shock"] and not drawn.has(k):
			drawn[k] = true                            # D266: one tag per reacting pool
			_hex_tag(h, "STEAM" if k == "steam" else "ELECTRIFIED", Color(0.5, 0.52, 0.56) if k == "steam" else BWLook.glow_color("thunder"), 0.3)
	for c in sim.chains:
		_arc(st, c.hex, c.to_hex)
	var slam_at := {}
	for sl in sim.get("slams", []):
		slam_at[str(sl.unit)] = sl
	for mv in sim.get("moves", []):
		var path: Array = mv.path
		if path.size() >= 2 and str(mv.kind) != "leap":
			_shove(st, path[0], path[path.size() - 1])
		if str(mv.kind) == "slide" and path.size() >= 2:  # D266: the slide's ghost and its slam
			var end: Vector2i = path[path.size() - 1]
			_rim(st, end, INK, RIM_W * 1.3, true)
			var sl: Dictionary = slam_at.get(str(mv.unit), {})
			_hex_tag(end, "SLAM %d%%" % int(BWSlides.SLAM_PCT) if not sl.is_empty() else "SLIDE", BWLook.element_color("ice"), 0.75)
	for ev in sim.get("events", []):                # D270: Becalm marks (still ink rings + a tag)
		if str(ev.get("type", "")) == "becalm":
			var bh: Vector2i = ev.hex
			for k2 in 2:
				_ring(st, bh, 0.42 + 0.2 * k2, 0.06)
			_hex_tag(bh, "BECALM", BWLook.glow_color("wind"), 0.55)
	BWElementsView.preview(self, st, sim)          # D285-D292: Overheat rings, beams + Empowered, Static fuse, launch, Magnify
	BWSquallView.preview(self, st, sim)            # D311/D313: a squall's first front, an Overfreeze burst
	_mesh.mesh = st.commit()
	for id in sim.units:
		_unit_tag(sim.units[id])


## Which kind a hex reads as when it has several (the strongest consequence).
static func _main_kind(kinds: Array) -> String:
	for k in ["detonate", "pillar", "shock", "glaze", "steam", "gale", "spread", "arm", "paint", "erase"]:
		if k in kinds:
			return k
	return "paint"


static func _kind_color(k: String, rec: Dictionary, element: String) -> Color:
	match k:
		"detonate", "shock": return BWLook.glow_color("thunder")
		"glaze": return BWLook.glow_color("ice")
		"pillar": return BWLook.element_color("ice")
		"steam": return Color(0.55, 0.58, 0.62)
		"gale", "spread": return BWLook.glow_color("wind")
		"arm":
			var mk := str((rec.after as Dictionary).get("marker", ""))
			return BWLook.glow_color(str(BWTiles.MARKER_ELEMENT.get(mk, element if element != "" else "thunder")))
		"erase": return Color(0.45, 0.45, 0.48)
	if element != "":
		return BWLook.glow_color(element)
	var a: Dictionary = rec.after
	if not a.is_empty():
		var hv := int(a.get("h", 0))
		var vv := int(a.get("v", 0))
		if absi(hv) >= absi(vv) and hv != 0:
			return BWLook.glow_color("fire" if hv > 0 else "water")
		if vv != 0:
			return BWLook.glow_color("light" if vv > 0 else "dark")
	return INK


# ---------------------------------------------------------------- geometry

func _top(h: Vector2i) -> Vector3:
	return board_view.top_center(h) + Vector3(0, LIFT, 0)


## Diagonal stripes clipped to the hex (Geometry2D on the hex's flat plane).
func _hatch(st: SurfaceTool, h: Vector2i, col: Color, density: String, alpha: float) -> void:
	var c := _top(h)
	var r := BWLook.HEX_SIZE * INSET
	var corners := BWLook.hex_corners(Vector3.ZERO, r)
	var hexp := PackedVector2Array()
	for p in corners:
		hexp.append(Vector2(p.x, p.z))
	var gap: float = STRIPE_GAP[density]
	var w: float = STRIPE_W[density]
	var dir := Vector2(1, -1).normalized()          # stripes run up-right
	var nrm := Vector2(dir.y, -dir.x)
	var k := -r * 1.5
	var cc := Color(col, alpha)
	while k <= r * 1.5:
		var a := nrm * k - dir * r * 2.0
		var b := nrm * k + dir * r * 2.0
		var strip := PackedVector2Array([a - nrm * w * 0.5, b - nrm * w * 0.5, b + nrm * w * 0.5, a + nrm * w * 0.5])
		for poly in Geometry2D.intersect_polygons(strip, hexp):
			var tri := Geometry2D.triangulate_polygon(poly)
			for i in tri:
				st.set_color(cc)
				st.add_vertex(c + Vector3(poly[i].x, 0, poly[i].y))
		k += gap


## A flat band just inside the hex edge; `dashed` skips every other piece.
func _rim(st: SurfaceTool, h: Vector2i, col: Color, w: float, dashed: bool = false) -> void:
	var c := _top(h) + Vector3(0, 0.002, 0)
	var outer := BWLook.hex_corners(c, BWLook.HEX_SIZE * INSET)
	var inner := BWLook.hex_corners(c, BWLook.HEX_SIZE * INSET - w)
	for e in 6:
		var n := (e + 1) % 6
		if dashed:
			for s in 3:
				if s == 1:
					continue
				var t0 := s / 3.0
				var t1 := (s + 1) / 3.0
				_quad(st, outer[e].lerp(outer[n], t0), outer[e].lerp(outer[n], t1), inner[e].lerp(inner[n], t1), inner[e].lerp(inner[n], t0), col)
		else:
			_quad(st, outer[e], outer[n], inner[n], inner[e], col)


## The chain arc: a dashed purple arch from hex a to hex b, an arrow head
## pointing down onto b. Flat ribbons facing up and sideways (readable from
## any orbit).
func _arc(st: SurfaceTool, a: Vector2i, b: Vector2i) -> void:
	var pa := _top(a) + Vector3(0, 1.0, 0)
	var pb := _top(b) + Vector3(0, 1.0, 0)
	var col := BWLook.glow_color("thunder")
	var n := 18
	var rise := ARC_H * clampf(pa.distance_to(pb) / 3.0, 0.6, 1.6)
	var pts: Array = []
	for i in n + 1:
		var t := float(i) / n
		pts.append(pa.lerp(pb, t) + Vector3(0, rise * 4.0 * t * (1.0 - t), 0))
	for i in n:
		if i % 3 == 2:
			continue
		_ribbon_seg(st, pts[i], pts[i + 1], 0.13, INK)
		_ribbon_seg(st, pts[i], pts[i + 1], 0.08, col)
	var tip: Vector3 = pts[n]
	var back: Vector3 = pts[n - 2]
	var d := (tip - back).normalized()
	var side := d.cross(Vector3.UP).normalized() * 0.32
	if side.length() < 0.01:
		side = Vector3.RIGHT * 0.32
	for p in [tip, back + side, back - side]:
		st.set_color(col)
		st.add_vertex(p)


## D270: a still ink ring round a Becalmed unit's hex.
func _ring(st: SurfaceTool, h: Vector2i, r: float, w: float) -> void:
	var c := _top(h) + Vector3(0, 0.03, 0)
	var seg := 24
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		_quad(st, c + d0 * (r - w * 0.5), c + d0 * (r + w * 0.5), c + d1 * (r + w * 0.5), c + d1 * (r - w * 0.5), INK)


## A knockback / push: an ink arrow on the ground from where the unit stands
## to where it would end.
func _shove(st: SurfaceTool, a: Vector2i, b: Vector2i) -> void:
	var pa := _top(a) + Vector3(0, 0.02, 0)
	var pb := _top(b) + Vector3(0, 0.02, 0)
	var d := pb - pa
	d.y = 0
	if d.length() < 0.01:
		return
	var dn := d.normalized()
	var side := Vector3(-dn.z, 0, dn.x)
	var end := pb - dn * 0.35
	_quad(st, pa - side * 0.08, pa + side * 0.08, end + side * 0.08, end - side * 0.08, INK)
	for p in [pb, end + side * 0.28, end - side * 0.28]:
		st.set_color(INK)
		st.add_vertex(p)


func _ribbon_seg(st: SurfaceTool, p0: Vector3, p1: Vector3, w: float, col: Color) -> void:
	var d := (p1 - p0).normalized()
	var s1 := d.cross(Vector3.UP).normalized() * w
	if s1.length() < 0.001:
		s1 = Vector3.RIGHT * w
	var s2 := d.cross(s1).normalized() * w
	_quad(st, p0 - s1, p0 + s1, p1 + s1, p1 - s1, col)
	_quad(st, p0 - s2, p0 + s2, p1 + s2, p1 - s2, col)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	for p in [a, b, c, a, c, d]:
		st.set_color(col)
		st.add_vertex(p)


# ---------------------------------------------------------------- tags

func _label(text: String, col: Color, size: int, outline: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0009
	l.font_size = size
	l.outline_size = 12
	l.modulate = col
	l.outline_modulate = outline
	l.render_priority = 18
	l.outline_render_priority = 17
	add_child(l)
	_tags.append(l)
	return l


func _hex_tag(h: Vector2i, text: String, col: Color, y: float) -> void:
	var l := _label(text, Color.WHITE, 22, col.darkened(0.35))
	l.position = _top(h) + Vector3(0, y, 0)
	_add_group(l, null)


## One unit's consequence, a sticker at its feet (its name and HP bar ride
## above its head): the total ("≈" when a roll decides part of it, KO), the
## sources small under it. Red with a "!" on a friendly; heals read "+6".
func _unit_tag(rec: Dictionary) -> void:
	var friendly: bool = rec.friendly
	var dmg := int(rec.damage)
	var heal := int(rec.get("heal", 0))
	var bits: PackedStringArray = []
	if dmg > 0:
		bits.append(damage_text(dmg, bool(rec.approx)))
	if heal > 0:
		bits.append("+%d" % heal)
	if bits.is_empty():
		return
	var text := " ".join(bits)
	if bool(rec.ko):
		text += " KO"
	var warn := friendly and dmg > 0
	if warn:
		text = "! " + text
	var l := _label(text, WARN if warn else Color.WHITE, 30, Color.BLACK)
	l.position = _top(rec.pos) + Vector3(0, TAG_Y, 0)
	var sub := _label(_sources_text(rec).get_slice("   ", 0), Color(1.0, 0.80, 0.80) if warn else Color(1, 1, 1, 0.9), 19, Color.BLACK)
	sub.outline_size = 8
	sub.position = l.position
	sub.offset = Vector2(0, -SUB_DY)
	_add_group(l, sub)


## D171: one sign per number. Exact damage "−31"; an expected value "≈31"
## (≈ replaces the minus instead of stacking on it: "~−31" read as a double
## sign). The confirm box, the arcs and the tags all use it.
static func damage_text(n: int, approx: bool) -> String:
	return ("≈%d" if approx else "−%d") % n


# ---------------------------------------------------------------- D171 tag layout

const SUB_DY := 26.0                # the sources line sits this far under the total (label px)
const LINE_H := 1.22                # a label's height per font pixel (outline included)
const PAD := 3.0                    # screen px kept between tags


func _add_group(main: Label3D, sub: Label3D) -> void:
	var f := ThemeDB.fallback_font
	var wm := f.get_string_size(main.text, HORIZONTAL_ALIGNMENT_LEFT, -1, main.font_size).x + main.outline_size
	var hm := main.font_size * LINE_H
	var g := { "main": main, "sub": sub, "w": wm, "top": hm * 0.5, "bottom": hm * 0.5 }
	if sub:
		var ws := f.get_string_size(sub.text, HORIZONTAL_ALIGNMENT_LEFT, -1, sub.font_size).x + sub.outline_size
		g.w = maxf(wm, ws)
		g.bottom = SUB_DY + sub.font_size * LINE_H * 0.5
	_groups.append(g)


func _process(_delta: float) -> void:
	if not _groups.is_empty():
		layout_tags()


## Screen pixels per label pixel for a fixed-size Label3D (constant at any depth).
static func px_scale(cam: Camera3D, pixel_size: float) -> float:
	var vh := cam.get_viewport().get_visible_rect().size.y
	if cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return vh * pixel_size / maxf(cam.size, 0.001)
	return vh * pixel_size / (2.0 * tan(deg_to_rad(cam.fov) * 0.5))


## A fixed-size Label3D's rect on screen (its text, outline and offset).
static func label_rect(cam: Camera3D, l: Label3D) -> Rect2:
	if l == null or not l.is_visible_in_tree() or l.text == "" or cam.is_position_behind(l.global_position):
		return Rect2()
	var k := px_scale(cam, l.pixel_size)
	var sz := Vector2(ThemeDB.fallback_font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size).x + l.outline_size,
		l.font_size * LINE_H) * k
	var c := cam.unproject_position(l.global_position) + Vector2(l.offset.x, -l.offset.y) * k
	return Rect2(c - sz * 0.5, sz)


## Greedy: tags in front (lower on screen) first; each takes the first free
## slot of a short list, else the one overlapping least. Returns the screen
## rects used (review / tests).
func layout_tags() -> Array:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return []
	var k := px_scale(cam, 0.0009)
	var placed: Array = []
	if obstacles.is_valid():
		placed.append_array(obstacles.call())
	var items: Array = []
	for g in _groups:
		if not is_instance_valid(g.main):
			continue
		var at: Vector3 = (g.main as Label3D).global_position
		if cam.is_position_behind(at):
			continue
		items.append({ "g": g, "at": cam.unproject_position(at) })
	items.sort_custom(func(a, b): return a.at.y > b.at.y)
	var used: Array = []
	for it in items:
		var g: Dictionary = it.g
		var w: float = g.w * k + PAD
		var h: float = (g.top + g.bottom) * k + PAD
		var base := Rect2(it.at.x - w * 0.5, it.at.y - g.top * k - PAD * 0.5, w, h)
		var best := Vector2.ZERO
		var best_hit := INF
		for d in [Vector2(0, 0), Vector2(0, -h), Vector2(w * 0.55, 0), Vector2(-w * 0.55, 0),
				Vector2(w * 0.55, -h * 0.6), Vector2(-w * 0.55, -h * 0.6), Vector2(0, -2.0 * h),
				Vector2(w + PAD, 0), Vector2(-w - PAD, 0), Vector2(0, h), Vector2(0, -3.0 * h)]:
			var r := Rect2(base.position + d, base.size)
			var hit := 0.0
			for p in placed:
				var q: Rect2 = p
				if q.has_area() and r.intersects(q):
					hit += r.intersection(q).get_area()
			if hit < best_hit - 0.5:
				best_hit = hit
				best = d
			if hit <= 0.0:
				break
		var off := Vector2(best.x, -best.y) / k
		(g.main as Label3D).offset = off
		if g.sub and is_instance_valid(g.sub):
			(g.sub as Label3D).offset = off + Vector2(0, -SUB_DY)
		var r2 := Rect2(base.position + best, base.size)
		placed.append(r2)
		used.append(r2)
	return used


static func _sources_text(rec: Dictionary) -> String:
	var parts: PackedStringArray = []
	var by := {}
	var order: Array = []
	for s in rec.sources:
		var k := str(s.kind)
		if not by.has(k):
			by[k] = 0
			order.append(k)
		by[k] += absi(int(s.amount))
	for k in order:
		if int(by[k]) <= 0:
			continue
		parts.append("%s %d" % [str(k).replace("_", " "), int(by[k])])
	return " · ".join(parts) + ("   HP %d → %d" % [int(rec.hp), int(rec.hp_after)] if int(rec.damage) > 0 else "")
