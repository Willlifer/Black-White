class_name BWBoardView
extends Node3D
## Draws a BWBoard: white tile tops with black rims, grey walls, black jagged
## rock, a highlight overlay per hex, and the tile FX (Phase 5, D82): per hex
## an animated face + standing-card layer for each element axis and one for
## the operator marker or glaze (BWTileFX, shaders/tile_*.gdshader). Tier
## changes grow or shrink over FX_BLEND seconds; one-shot events (detonation,
## gale gust, glaze forming, grass ignition) play over the board. Picking is
## pure maths against the tile tops, so no physics bodies are needed.

const FLOOR_Y := -0.6     # walls run down to here

var board: BWBoard
var tiles: BWTiles
var _hex_nodes := {}      # Vector2i -> MeshInstance3D (the tile itself)
var _hi := {}             # Vector2i -> MeshInstance3D highlight
## Tile FX (D82). Per hex: { face_h, face_v, cards_h, cards_v, mark } nodes and
## per layer an animation record { el, t, el_to, t_to, speed } (see _fx_step).
const FX_BLEND := 0.3          # seconds for a tier change to grow / shrink
const FX_FORM := 0.7           # seconds for a glaze to spread across the tile
const FX_LIFT := { "face_h": 0.010, "face_v": 0.010, "mark": 0.020, "cards_h": 0.012, "cards_v": 0.012 }
var _fx := {}             # Vector2i -> { node name -> MeshInstance3D }
var _fx_anim := {}        # Vector2i -> { "h" | "v" | "mark" -> record }
var _fx_state := {}       # Vector2i -> BWTileFX.layers() as last applied
var _fx_active := {}      # hexes with a layer still animating
var _bursts: Array = []   # [{ node, t, dur, curve }]
## D86 chain lightning: live bolts { node, core, t, dur, a, b, next } (re-rolled jaggedness).
var _bolts: Array = []
const BOLT_DUR := 0.55
const BOLT_REROLL := 0.06
var _last_entries := {}   # Vector2i -> entry copy at the last refresh (event diffing)
## D116 static hexes: the inlaid rim per static hex (permanent, drawn above the
## element FX so it reads even under blazing fire or while the static is spent).
var _static := {}         # Vector2i -> MeshInstance3D
const STATIC_SORT := 0.45  # over faces (0.30-0.35) and marks (0.40), under highlights (0.50)
## D135 seeded hexes: a lighter inlay than a static (one thin element-colour
## ring, no ink rings or corner wedges), shown only while the seed is
## untouched (BWTiles.is_seeded). Once play changes the hex it is ordinary
## charge, so the ring goes and never comes back.
var _seed := {}           # Vector2i -> MeshInstance3D
var kanji: BWKanjiLayer   # D231
var icewater: BWIceWaterView   # D266: rinks, pillars, steam, electrified fields


func build(p_board: BWBoard, p_tiles: BWTiles = null) -> void:
	board = p_board
	tiles = p_tiles
	for c in get_children():
		c.queue_free()
	_hex_nodes.clear()
	_hi.clear()
	_fx.clear()
	_fx_anim.clear()
	_fx_state.clear()
	_fx_active.clear()
	_bursts.clear()
	_last_entries.clear()
	_static.clear()
	_seed.clear()
	for h in board.cells():
		var mi := MeshInstance3D.new()
		mi.mesh = _tile_mesh(h)
		mi.material_override = BWLook.flat()
		mi.name = "hex_%d_%d" % [h.x, h.y]
		add_child(mi)
		_hex_nodes[h] = mi
		if board.terrain(h) == BWBoard.JAGGED:
			continue
		var top := top_center(h)
		_hi[h] = _overlay(top + Vector3(0, 0.026, 0), 0.86)
		_hi[h].sorting_offset = BWTileFX.SORT_MARK + 0.1     # unit highlights over the tile FX
		_fx[h] = _fx_nodes(h, top)
		if board.statics.has(h):
			_static[h] = _static_rim(h, top)
		elif board.seeds.has(h):
			_seed[h] = _seed_rim(h, top)
	kanji = BWKanjiLayer.new()                  # D231: element kanji on the tile tops (accessibility)
	add_child(kanji)
	icewater = BWIceWaterView.new()             # D266
	add_child(icewater)
	icewater.setup(self)
	refresh_tiles(true)


func top_center(h: Vector2i) -> Vector3:
	return BWLook.world(h, board.elevation(h)) + Vector3(0, BWLook.TILE_HEIGHT, 0)


func hex_node(h: Vector2i) -> Node3D:
	return _hex_nodes.get(h)


## Every node that belongs to hex h (tile + overlays), for dimming.
func hex_parts(h: Vector2i) -> Array:
	var out: Array = []
	for d in [_hex_nodes, _hi, _static, _seed]:
		if d.has(h):
			out.append(d[h])
	if _fx.has(h):
		out.append_array(_fx[h].values())
	return out


# ---------------------------------------------------------------- overlays

## Highlight a set of hexes: kind "move" (soft grey), "path" (dark), "attack"
## (black, pulsing), "target" (black), "deploy" (grey dashed feel), or "" to clear.
func highlight(hexes: Array, kind: String) -> void:
	var col := Color(0, 0, 0, 0)
	var pulse := false
	match kind:
		"move": col = Color(0.62, 0.62, 0.66, 0.26)   # a light wash: the board must stay white
		"path": col = Color(0.15, 0.15, 0.15, 0.55)
		"attack": col = Color(0, 0, 0, 0.5); pulse = true
		"target": col = Color(0, 0, 0, 0.8)
		"deploy": col = Color(0.35, 0.35, 0.35, 0.35)
		"cursor": col = Color(0, 0, 0, 0.25)
	for h in hexes:
		if _hi.has(h):
			var mi: MeshInstance3D = _hi[h]
			mi.material_override = BWLook.alpha(pulse)
			mi.set_instance_shader_parameter("tint", col)
			mi.visible = col.a > 0.0


func clear_highlights() -> void:
	for h in _hi:
		_hi[h].visible = false


## Redraw the element layers from BWTiles (call after any paint or tick).
## Layers retarget and grow / shrink over FX_BLEND; `snap` jumps straight to
## the new state (first build). A glaze that has just formed spreads across
## the tile (the "glaze forming" one-shot), wherever it came from.
func refresh_tiles(snap: bool = false) -> void:
	if tiles == null:
		return
	for h in _fx:
		var e := tiles.at(h)
		var prev: Dictionary = _last_entries.get(h, {})
		_last_entries[h] = e.duplicate()
		var formed := int(e.get("glaze", 0)) > int(prev.get("glaze", 0)) and not snap
		_fx_apply(h, BWTileFX.layers(e), snap, formed)
		if _seed.has(h):
			_seed[h].visible = tiles.is_seeded(h)
	if icewater:
		icewater.refresh()                      # D266


## The tile FX state applied to hex h (for tests and tools).
func fx_state(h: Vector2i) -> Dictionary:
	return _fx_state.get(h, BWTileFX.layers({}))


## The animated tier of one layer ("h", "v", "mark") right now.
func fx_tier(h: Vector2i, layer: String) -> float:
	if not _fx_anim.has(h):
		return 0.0
	return float(_fx_anim[h][layer].t)


## The layer nodes of hex h (face_h, face_v, cards_h, cards_v, mark).
func fx_nodes(h: Vector2i) -> Dictionary:
	return _fx.get(h, {})


## Battle-event hook for the tile FX (combat_screen, Phase 5): refreshes the
## layers and plays the one-shot for the event.
##   paint      refresh; a gale that fired here blows a gust ring
##   detonate   purple-white flash + ring burst onto the neighbours
##   tiles_tick refresh; every grass hex the tick seeded flares
func on_tile_event(e: Dictionary) -> void:
	match str(e.get("type", "")):
		"paint":
			var before := _last_entries.duplicate()
			refresh_tiles()
			for h in _gale_origins(e, before):
				burst("gust", h)
		"detonate":
			burst("detonate", e.hex, float(e.get("radius", 1)))
		"tiles_tick":
			refresh_tiles()
			for h in e.get("seeded", []):
				burst("ignite", h)


## Hexes where a gale fired in a paint: a gale marker that caught a charge,
## or a wind cast on a charged tile (its charge unchanged, timer untouched;
## the copies it laid are fresh entries with timer 1).
func _gale_origins(e: Dictionary, before: Dictionary) -> Array:
	var out: Array = []
	if tiles == null:
		return out
	for h in e.get("hexes", []):
		var was: Dictionary = before.get(h, {})
		var now := tiles.at(h)
		if was.is_empty() or now.is_empty() or str(now.marker) != "":
			continue
		if str(was.marker) == "gale":
			out.append(h)
		elif str(e.get("element", "")) == "wind" and str(was.marker) == "" and int(was.glaze) == 0 \
				and now.h == was.h and now.v == was.v and now.timer == was.timer:
			out.append(h)
	return out


## D86: chain lightning: a purple bolt from hex `a` (the conductive unit) to
## hex `b` (the teammate it arcs to), chest high, with a flash at both ends.
## Two crossed ribbons (thick purple glow + thin white core) so it reads from
## any camera pitch; the zigzag is re-rolled every BOLT_REROLL s, then fades.
func chain_bolt(a: Vector2i, b: Vector2i) -> void:
	if board == null:
		return
	var pa := top_center(a) + Vector3(0, 1.15, 0)
	var pb := top_center(b) + Vector3(0, 1.15, 0)
	var glow := BWLook.glow_color("thunder")
	var outer := MeshInstance3D.new()
	outer.material_override = _bolt_mat(Color(glow.r, glow.g, glow.b, 0.9))
	var core := MeshInstance3D.new()
	core.material_override = _bolt_mat(Color(1.0, 0.96, 1.0, 1.0))
	for n in [outer, core]:
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.sorting_offset = 3.5
		add_child(n)
	var rec := { "node": outer, "core": core, "t": 0.0, "dur": BOLT_DUR, "a": pa, "b": pb, "next": 0.0 }
	_bolt_roll(rec)
	_bolts.append(rec)
	_spawn_burst("flash_detonate", pa, Vector3.ONE * 0.8, 0.3, true)
	_spawn_burst("flash_detonate", pb, Vector3.ONE * 1.1, 0.4, true)


func _bolt_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	m.albedo_color = c
	return m


## A fresh zigzag between rec.a and rec.b: 9 kinks, jittered sideways and up.
func _bolt_roll(rec: Dictionary) -> void:
	var a: Vector3 = rec.a
	var b: Vector3 = rec.b
	var dir := (b - a)
	var side := dir.cross(Vector3.UP).normalized()
	if side.length() < 0.01:
		side = Vector3.RIGHT
	var pts: Array = [a]
	var kinks := 9
	for i in range(1, kinks):
		var t := float(i) / kinks
		var amp := 0.32 * sin(t * PI)
		pts.append(a + dir * t + side * randf_range(-amp, amp) + Vector3.UP * randf_range(-amp, amp) * 0.8)
	pts.append(b)
	(rec.node as MeshInstance3D).mesh = _ribbon(pts, 0.16)
	(rec.core as MeshInstance3D).mesh = _ribbon(pts, 0.05)


## Two crossed flat strips along a polyline (one widened sideways, one up).
func _ribbon(pts: Array, w: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for axis in [0, 1]:
		for i in pts.size() - 1:
			var p0: Vector3 = pts[i]
			var p1: Vector3 = pts[i + 1]
			var d := (p1 - p0).normalized()
			var off: Vector3 = d.cross(Vector3.UP).normalized() if axis == 0 else Vector3.UP
			if off.length() < 0.01:
				off = Vector3.RIGHT
			off *= w * 0.5
			for v in [p0 - off, p0 + off, p1 + off, p0 - off, p1 + off, p1 - off]:
				st.add_vertex(v)
	return st.commit()


## D87: Striketwice's opposite-element reaction one-shots on hex h: steam
## (a pale gust ring + white flash), eclipse (a dark flash + ring), storm
## (a purple gust ring + flash: the ring is pushed out).
func reaction_burst(kind: String, h: Vector2i) -> void:
	if board == null or not board.exists(h):
		return
	var top := top_center(h)
	match kind:
		"steam":
			_spawn_burst("burst_steam", top + Vector3(0, 0.05, 0), Vector3.ONE, 0.8)
			_spawn_burst("flash_steam", top + Vector3(0, 0.7, 0), Vector3.ONE * 1.4, 0.5, true)
		"eclipse":
			_spawn_burst("burst_eclipse", top + Vector3(0, 0.05, 0), Vector3.ONE, 0.8)
			_spawn_burst("flash_eclipse", top + Vector3(0, 1.0, 0), Vector3.ONE * 1.8, 0.6, true)
		"storm":
			_spawn_burst("burst_storm", top + Vector3(0, 0.05, 0), Vector3.ONE * 1.2, 0.75)
			_spawn_burst("flash_detonate", top + Vector3(0, 0.8, 0), Vector3.ONE * 1.2, 0.4, true)
		"retarget":
			_spawn_burst("flash_steam", top + Vector3(0, 1.0, 0), Vector3.ONE * 0.9, 0.35, true)


## Play a one-shot on hex h: "detonate" (radius = splash rings), "gust",
## "ignite" or "frost" (frost replays the glaze-forming spread).
func burst(kind: String, h: Vector2i, radius: float = 1.0) -> void:
	if board == null or not board.exists(h):
		return
	var top := top_center(h)
	match kind:
		"detonate":
			_spawn_burst("burst_detonate", top + Vector3(0, 0.03, 0), Vector3(radius, 1, radius), 0.75)
			_spawn_burst("flash_detonate", top + Vector3(0, 0.8, 0), Vector3.ONE * 1.5, 0.45, true)
		"gust":
			_spawn_burst("burst_gust", top + Vector3(0, 0.03, 0), Vector3.ONE, 0.7)
		"ignite":
			_spawn_burst("burst_ignite", top + Vector3(0, 0.03, 0), Vector3.ONE, 0.5)
			_spawn_burst("flash_ignite", top + Vector3(0, 0.45, 0), Vector3.ONE * 0.6, 0.3, true)
			# a quick flare of flame cards: up to blazing and back down to the seed
			var mi := _fx_card_node(top + Vector3(0, FX_LIFT.cards_h, 0))
			mi.material_override = BWTileFX.material("tile_flame")
			mi.set_instance_shader_parameter("seed", BWTileFX.seed_for(h, 9))
			mi.set_instance_shader_parameter("tier", 0.0)
			mi.visible = true
			add_child(mi)
			_bursts.append({ "node": mi, "t": 0.0, "dur": 0.6, "curve": "flare" })
		"frost":
			if _fx_anim.has(h):
				_fx_anim[h].mark.form = 0.0
				_fx_active[h] = true


func _spawn_burst(mat: String, at: Vector3, scl: Vector3, dur: float, flash: bool = false) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = BWTileFX.quad_mesh() if flash else BWTileFX.disc_mesh()
	mi.material_override = BWTileFX.material(mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at
	mi.scale = scl
	mi.sorting_offset = 3.0          # over every tile layer it sweeps across
	mi.set_instance_shader_parameter("age", 0.0)
	mi.set_instance_shader_parameter("seed", randf())
	if flash:
		mi.custom_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	add_child(mi)
	_bursts.append({ "node": mi, "t": 0.0, "dur": dur, "curve": "age" })


func _process(delta: float) -> void:
	for i in range(_bolts.size() - 1, -1, -1):        # D86 chain bolts
		var bo: Dictionary = _bolts[i]
		bo.t += delta
		if not is_instance_valid(bo.node) or bo.t >= bo.dur:
			for k in ["node", "core"]:
				if is_instance_valid(bo[k]):
					bo[k].queue_free()
			_bolts.remove_at(i)
			continue
		if bo.t >= bo.next:
			bo.next = bo.t + BOLT_REROLL
			_bolt_roll(bo)
		var fade := 1.0 - pow(bo.t / bo.dur, 2.0)
		(bo.node.material_override as StandardMaterial3D).albedo_color.a = 0.9 * fade
		(bo.core.material_override as StandardMaterial3D).albedo_color.a = fade
	for h in _fx_active.keys():
		if not _fx_step(h, delta):
			_fx_active.erase(h)
	for i in range(_bursts.size() - 1, -1, -1):
		var b: Dictionary = _bursts[i]
		b.t += delta
		var k := clampf(b.t / b.dur, 0.0, 1.0)
		var node: MeshInstance3D = b.node
		if not is_instance_valid(node):
			_bursts.remove_at(i)
			continue
		if b.curve == "flare":
			node.set_instance_shader_parameter("tier", 3.0 * sin(k * PI) * (1.0 - 0.3 * k))
		else:
			node.set_instance_shader_parameter("age", k)
		if k >= 1.0:
			node.queue_free()
			_bursts.remove_at(i)


# ---------------------------------------------------------------- tile FX

func _fx_nodes(h: Vector2i, top: Vector3) -> Dictionary:
	var d := {}
	for n in ["face_h", "face_v", "mark"]:
		var mi := MeshInstance3D.new()
		mi.mesh = BWTileFX.hex_mesh()
		mi.position = top + Vector3(0, FX_LIFT[n], 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		mi.name = "fx_%s_%d_%d" % [n, h.x, h.y]
		mi.sorting_offset = BWTileFX.SORT_MARK if n == "mark" else BWTileFX.SORT_FACE
		add_child(mi)
		d[n] = mi
	for n in ["cards_h", "cards_v"]:
		var mi := _fx_card_node(top + Vector3(0, FX_LIFT[n], 0))
		mi.name = "fx_%s_%d_%d" % [n, h.x, h.y]
		add_child(mi)
		d[n] = mi
	var salt := 0
	for n in d:
		(d[n] as MeshInstance3D).set_instance_shader_parameter("seed", BWTileFX.seed_for(h, salt))
		salt += 1
	_fx_anim[h] = {
		"h": { "el": "", "t": 0.0, "el_to": "", "t_to": 0.0, "speed": 1.0 },
		"v": { "el": "", "t": 0.0, "el_to": "", "t_to": 0.0, "speed": 1.0 },
		"mark": { "el": "", "t": 0.0, "el_to": "", "t_to": 0.0, "speed": 1.0,
			"form": 1.0, "frost": 0.0, "frost_to": 0.0, "crack": 0.0, "crack_to": 0.0 },
	}
	return d


func _fx_card_node(at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = BWTileFX.card_mesh()
	mi.custom_aabb = BWTileFX.CARD_AABB
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi


## Retarget hex h's layers to `want` (BWTileFX.layers()).
func _fx_apply(h: Vector2i, want: Dictionary, snap: bool, formed: bool) -> void:
	_fx_state[h] = want
	if kanji:
		kanji.apply(h, top_center(h), want)
	var an: Dictionary = _fx_anim[h]
	for axis in ["h", "v"]:
		var w: Dictionary = want[axis]
		_fx_target(an[axis], str(w.get("el", "")), float(w.get("tier", 0)), snap)
	_fx_target(an.mark, str(want.mark), 1.0 if want.mark != "" else 0.0, snap)
	an.mark.frost_to = 1.0 if want.mark == "glaze" else 0.0
	an.mark.crack_to = 1.0 if want.crack else 0.0
	if formed:
		an.mark.form = 0.0
	if snap:
		an.mark.frost = an.mark.frost_to
		an.mark.crack = an.mark.crack_to
	# the dominant axis draws on top of the other (ties: fire / water)
	var nodes: Dictionary = _fx[h]
	var top_h: bool = want.top == "h"
	var top := BWTileFX.SORT_TOP
	(nodes.face_h as MeshInstance3D).sorting_offset = BWTileFX.SORT_FACE + (top if top_h else 0.0)
	(nodes.face_v as MeshInstance3D).sorting_offset = BWTileFX.SORT_FACE + (0.0 if top_h else top)
	(nodes.cards_h as MeshInstance3D).sorting_offset = BWTileFX.SORT_CARDS + (top if top_h else 0.0)
	(nodes.cards_v as MeshInstance3D).sorting_offset = BWTileFX.SORT_CARDS + (0.0 if top_h else top)
	_fx_active[h] = true
	_fx_step(h, 0.0)


func _fx_target(rec: Dictionary, el: String, t: float, snap: bool) -> void:
	if t <= 0.0:
		el = str(rec.el)        # fading out: keep drawing what is there
	rec.el_to = el
	rec.t_to = t
	if snap:
		rec.el = el if t > 0.0 else ""
		rec.t = t
		return
	# any change (one tier, three tiers, a fade or an element swap) takes ~FX_BLEND
	var dist: float = absf(t - float(rec.t)) if (rec.el == el or rec.el == "") else float(rec.t) + t
	rec.speed = maxf(dist, 1.0) / FX_BLEND


## Advance hex h's layer animation by dt and push the instance uniforms.
## Returns true while anything is still moving.
func _fx_step(h: Vector2i, dt: float) -> bool:
	var an: Dictionary = _fx_anim[h]
	var nodes: Dictionary = _fx[h]
	var mk: Dictionary = an.mark
	var moving := false
	for key in ["frost", "crack"]:
		if not is_equal_approx(float(mk[key]), float(mk[key + "_to"])):
			mk[key] = move_toward(float(mk[key]), float(mk[key + "_to"]), dt / 0.4)
			moving = true
	for axis in ["h", "v"]:
		var rec: Dictionary = an[axis]
		moving = _fx_advance(rec, dt) or moving
		_fx_push_axis(nodes["face_" + axis], nodes["cards_" + axis], rec, float(mk.frost))
	moving = _fx_advance(mk, dt) or moving
	if float(mk.form) < 1.0:
		mk.form = minf(1.0, float(mk.form) + dt / FX_FORM)
		moving = true
	var m: MeshInstance3D = nodes.mark
	m.visible = float(mk.t) > 0.001 and mk.el != ""
	if m.visible:
		var kind: String = mk.el
		m.material_override = BWTileFX.material(kind)
		m.position.y = top_center(h).y + (FX_LIFT.mark if kind == "glaze" else FX_LIFT.face_h + 0.004)
		m.set_instance_shader_parameter("tier", float(mk.t))
		m.set_instance_shader_parameter("age", float(mk.form) if kind == "glaze" else 1.0)
		m.set_instance_shader_parameter("crack", float(mk.crack))
	return moving


func _fx_advance(rec: Dictionary, dt: float) -> bool:
	if rec.el != rec.el_to and rec.el != "":
		# fade the old element out, then swap and grow the new one
		rec.t = move_toward(float(rec.t), 0.0, float(rec.speed) * dt)
		if float(rec.t) <= 0.0:
			rec.el = rec.el_to
		return true
	if rec.el == "":
		rec.el = rec.el_to
	if is_equal_approx(float(rec.t), float(rec.t_to)):
		rec.t = rec.t_to
		if float(rec.t_to) <= 0.0:
			rec.el = ""
			rec.el_to = ""
		return false
	rec.t = move_toward(float(rec.t), float(rec.t_to), float(rec.speed) * dt)
	return true


func _fx_push_axis(face: MeshInstance3D, cards: MeshInstance3D, rec: Dictionary, frost: float) -> void:
	var t: float = rec.t
	var el: String = rec.el
	var on := t > 0.001 and el != ""
	face.visible = on
	# standing cards only where something stands: fire smoke from tier ~0.5,
	# light motes from 1, the abyss tendrils from 2
	var floor_t: float = { "fire": 0.3, "light": 1.0, "dark": 2.0 }.get(el, 99.0)
	cards.visible = on and t > floor_t
	if not on:
		return
	face.material_override = BWTileFX.material(BWTileFX.FACE[el])
	face.set_instance_shader_parameter("tier", t)
	face.set_instance_shader_parameter("frost", frost)
	if cards.visible:
		cards.material_override = BWTileFX.material(BWTileFX.CARDS[el])
		cards.set_instance_shader_parameter("tier", t)
		cards.set_instance_shader_parameter("frost", frost)


# ---------------------------------------------------------------- picking

## The hex under a screen point, or (-1,-1). Tests every tile top plane and
## keeps the nearest hit, so raised tiles occlude the ones behind them.
func pick(cam: Camera3D, screen: Vector2) -> Vector2i:
	var origin := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	var best := Vector2i(-1, -1)
	var best_t := INF
	for h in board.cells():
		var y := top_center(h).y
		if absf(dir.y) < 1e-5:
			continue
		var t := (y - origin.y) / dir.y
		if t <= 0.0 or t >= best_t:
			continue
		var p := origin + dir * t
		var local := Vector2(p.x, p.z)
		if BWHex.from_world(local, BWLook.HEX_SIZE) == h:
			best = h
			best_t = t
	return best


# ---------------------------------------------------------------- meshes

func _tile_mesh(h: Vector2i) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := top_center(h)
	var kind := board.terrain(h)
	if kind == BWBoard.JAGGED:
		_jagged(st, c, h)
	else:
		var top_col := BWLook.WHITE
		if kind == BWBoard.MUDDY:
			top_col = BWLook.MUD
		elif kind == BWBoard.GRASSY:
			top_col = BWLook.PAPER
		_prism(st, c, BWLook.HEX_SIZE, FLOOR_Y, BWLook.INK, BWLook.SIDE)
		_cap(st, c + Vector3(0, 0.004, 0), BWLook.HEX_SIZE - BWLook.BORDER, top_col)
		if kind == BWBoard.GRASSY:
			_grass_tufts(st, c + Vector3(0, 0.006, 0), h)
		elif kind == BWBoard.MUDDY:
			_mud_dots(st, c + Vector3(0, 0.006, 0), h)
	st.generate_normals()
	return st.commit()


## A hex column from y=bottom up to the top cap at c, rimmed in `cap_col`.
func _prism(st: SurfaceTool, c: Vector3, r: float, bottom: float, cap_col: Color, side_col: Color) -> void:
	var top := BWLook.hex_corners(c, r)
	_cap(st, c, r, cap_col)
	for i in 6:
		var a := top[i]
		var b := top[(i + 1) % 6]
		var a2 := Vector3(a.x, bottom, a.z)
		var b2 := Vector3(b.x, bottom, b.z)
		# Walls: lighter near the top, so stacked elevations read as steps.
		var upper := side_col
		var lower := BWLook.SIDE_DARK
		_quad(st, b, a, a2, b2, [upper, upper, lower, lower])
	# Black seam down each wall corner, so columns separate cleanly.
	for i in 6:
		var p := top[i]
		var out := (p - c).normalized() * 0.015
		var tan := out.rotated(Vector3.UP, PI / 2)
		_quad(st, p + tan + out, p - tan + out, Vector3(p.x, bottom, p.z) - tan + out,
			Vector3(p.x, bottom, p.z) + tan + out, [BWLook.INK, BWLook.INK, BWLook.INK, BWLook.INK])


func _cap(st: SurfaceTool, c: Vector3, r: float, col: Color) -> void:
	var v := BWLook.hex_corners(c, r)
	for i in 6:
		st.set_color(col)
		st.add_vertex(c)
		st.set_color(col)
		st.add_vertex(v[i])
		st.set_color(col)
		st.add_vertex(v[(i + 1) % 6])


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, cols: Array) -> void:
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_color(cols[idx])
		st.add_vertex([a, b, c, d][idx])


## Jagged: a black rock column standing a level and a half proud of its
## cell, with a broken, faceted crown so it never reads as a floor tile.
func _jagged(st: SurfaceTool, c: Vector3, h: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(h)
	var crown := c + Vector3(0, BWLook.TILE_HEIGHT * 1.5, 0)
	var ring := BWLook.hex_corners(crown, BWLook.HEX_SIZE * 0.92)
	_prism(st, crown, BWLook.HEX_SIZE * 0.92, FLOOR_Y, BWLook.INK, Color(0.12, 0.12, 0.12))
	var peak := crown + Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(0.35, 0.6), rng.randf_range(-0.2, 0.2))
	for i in 6:
		var shade := 0.05 + 0.18 * float(i % 3) / 2.0
		var col := Color(shade, shade, shade)
		st.set_color(col)
		st.add_vertex(peak)
		st.set_color(col)
		st.add_vertex(ring[i])
		st.set_color(col)
		st.add_vertex(ring[(i + 1) % 6])


## Grassy: three black ink tufts, placed by hash so every tile differs.
func _grass_tufts(st: SurfaceTool, c: Vector3, h: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(h) ^ 0x5eed
	for i in 3:
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.15, 0.55)
		var base := c + Vector3(cos(a) * d, 0, sin(a) * d)
		for blade in [-1, 0, 1]:
			var tip := base + Vector3(blade * 0.06, 0, -0.14 + absf(blade) * 0.04)
			st.set_color(BWLook.INK)
			st.add_vertex(base + Vector3(-0.02 + blade * 0.03, 0, 0))
			st.set_color(BWLook.INK)
			st.add_vertex(base + Vector3(0.02 + blade * 0.03, 0, 0))
			st.set_color(BWLook.INK)
			st.add_vertex(tip)
			st.set_color(BWLook.INK)
			st.add_vertex(base + Vector3(0.02 + blade * 0.03, 0, 0))
			st.set_color(BWLook.INK)
			st.add_vertex(base + Vector3(-0.02 + blade * 0.03, 0, 0))
			st.set_color(BWLook.INK)
			st.add_vertex(tip)


## Muddy: a scatter of dark puddle dots on the grey top.
func _mud_dots(st: SurfaceTool, c: Vector3, h: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(h) ^ 0xd17
	for i in 5:
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.1, 0.6)
		var p := c + Vector3(cos(a) * d, 0, sin(a) * d)
		var r := rng.randf_range(0.04, 0.09)
		var v := BWLook.hex_corners(p, r)
		for j in 6:
			st.set_color(BWLook.GREY_DARK)
			st.add_vertex(p)
			st.set_color(BWLook.GREY_DARK)
			st.add_vertex(v[j])
			st.set_color(BWLook.GREY_DARK)
			st.add_vertex(v[(j + 1) % 6])


## D116: a static hex's inlay. Element colour is the accent; ink does the
## work: a carved double rim (ink / element band / ink), six ink wedges
## notched in at the corners and a small element lozenge at each wedge's
## tip, so it reads as cut into the stone rather than painted on, from any
## camera angle, whether the charge is up, stepped down or spent. A two-axis
## static draws its band in the dominant axis' colour, the other in the
## lozenges.
func _static_rim(h: Vector2i, top: Vector3) -> MeshInstance3D:
	var s: Vector2i = board.statics[h]
	var main := _static_color(s, true)
	var second := _static_color(s, false)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := top + Vector3(0, 0.03, 0)
	_ring(st, c, 0.93, 0.885, BWLook.INK)
	_ring(st, c, 0.885, 0.78, main)
	_ring(st, c, 0.78, 0.745, BWLook.INK)
	var outer := BWLook.hex_corners(c, 0.745)
	var inner := BWLook.hex_corners(c, 0.6)
	for i in 6:
		var p: Vector3 = outer[i]
		var tip: Vector3 = inner[i]
		var side := (p - c).normalized().cross(Vector3.UP) * 0.07
		for v in [p - side, p + side, tip]:
			st.set_color(BWLook.INK)
			st.add_vertex(v)
		var mid := tip.lerp(p, 0.28)
		var d := (p - c).normalized() * 0.045
		var w := side * 0.45
		for v in [mid - d, mid + w, mid + d, mid - d, mid + d, mid - w]:
			st.set_color(second)
			st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = BWLook.flat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.sorting_offset = STATIC_SORT
	mi.name = "static_%d_%d" % [h.x, h.y]
	add_child(mi)
	return mi


## D135: the seeded inlay, one thin ring in the seed's dominant element colour
## just inside the tile's edge, with a paper hairline inside it so a dark ring
## still reads on its own dark charge (same radius band as the static's colour band,
## so the two read as kin; the static adds ink rings and corner wedges).
func _seed_rim(h: Vector2i, top: Vector3) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := top + Vector3(0, 0.03, 0)
	_ring(st, c, 0.9, 0.835, _static_color(board.seeds[h], true))
	_ring(st, c, 0.835, 0.815, BWLook.WHITE)   # a hairline so it reads on its own charge
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = BWLook.flat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.sorting_offset = STATIC_SORT
	mi.name = "seed_%d_%d" % [h.x, h.y]
	add_child(mi)
	return mi


static func _static_color(s: Vector2i, dominant: bool) -> Color:
	var use_h: bool = absi(s.x) >= absi(s.y)
	if not dominant and s.x != 0 and s.y != 0:
		use_h = not use_h
	var el: String
	if use_h:
		el = "fire" if s.x > 0 else "water"
	else:
		el = "light" if s.y > 0 else "dark"
	return BWLook.element_color(el)


## A flat hex annulus between radii r_out and r_in at c.
func _ring(st: SurfaceTool, c: Vector3, r_out: float, r_in: float, col: Color) -> void:
	var o := BWLook.hex_corners(c, r_out)
	var n := BWLook.hex_corners(c, r_in)
	for i in 6:
		var j := (i + 1) % 6
		for v in [o[i], o[j], n[j], o[i], n[j], n[i]]:
			st.set_color(col)
			st.add_vertex(v)


func _overlay(at: Vector3, r: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cap(st, at, r, Color(1, 1, 1))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = BWLook.alpha()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return mi
