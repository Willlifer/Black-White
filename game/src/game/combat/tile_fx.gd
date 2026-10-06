class_name BWTileFX
extends RefCounted
## Tile FX (Phase 5, D82): the shared materials and meshes behind the element
## layers BWBoardView draws on every hex, and the pure mapping from a BWTiles
## entry to those layers (ELEMENTS §4).
##
## Per hex there are five layer nodes, created once and swapped between the
## shared materials below (one material per element, never per tile; per-tile
## values are instance uniforms, slots fixed by D55):
##   face_h / face_v   flat hex, the axis element's face shader
##   cards_h / cards_v billboard card cluster for what stands up off the tile
##                     (fire flames, the light column, abyss tendrils)
##   mark              operator marker (fuse / gale / stasis) or the glaze
## Draw order: the board itself is in the transparent pass (BWLook.flat writes
## ALPHA) at render_priority 0, painter-sorted by depth with no depth writes.
## The FX join that same pass at priority 0 and win against their own tile by
## SORT_* offsets (faces < marker/glaze < highlight), so a raised tile in front
## still covers them; BWRangeOverlay's priority 1 draws above all of it.
## Within a hex the dominant axis gets SORT_TOP extra (ties: fire/water).
const SORT_FACE := 0.30
const SORT_TOP := 0.05
const SORT_MARK := 0.40
const SORT_CARDS := 0.30

## Which layer material each element uses, per slot.
const FACE := { "fire": "tile_fire", "water": "tile_water", "light": "tile_light", "dark": "tile_dark" }
const CARDS := { "fire": "tile_flame", "light": "tile_beam", "dark": "tile_tendril" }   # water hugs the tile
const MARKER_MODE := { "fuse": 0, "gale": 1, "gale2": 1, "stasis": 2 }

## Card cluster: [radius, angle deg, width, height scale, ring]
const CARD_LAYOUT := [
	[0.0, 0.0, 0.62, 1.2, 0],
	[0.36, 30.0, 0.5, 1.0, 1], [0.36, 150.0, 0.5, 1.0, 1], [0.36, 270.0, 0.5, 1.0, 1],
	[0.66, 0.0, 0.42, 0.8, 2], [0.66, 60.0, 0.42, 0.8, 2], [0.66, 120.0, 0.42, 0.8, 2],
	[0.66, 180.0, 0.42, 0.8, 2], [0.66, 240.0, 0.42, 0.8, 2], [0.66, 300.0, 0.42, 0.8, 2],
]
## Culling box for a card cluster (the light column is the tallest at 3.2).
const CARD_AABB := AABB(Vector3(-1.1, -0.05, -1.1), Vector3(2.2, 3.4, 2.2))

static var _mats := {}
static var _hex_mesh: ArrayMesh
static var _card_mesh: ArrayMesh
static var _disc_mesh: PlaneMesh
static var _quad_mesh: QuadMesh


# ------------------------------------------------------------------ mapping

## The layers one tile entry draws. Pure: reads only the entry.
##   h / v: { el, tier } or {} ; top: "h" | "v" (dominant axis, drawn on top)
##   mark: "" | "fuse" | "gale" | "stasis" | "glaze" ; crack: glaze's last cycle
static func layers(e: Dictionary) -> Dictionary:
	var out := { "h": {}, "v": {}, "top": "h", "mark": "", "crack": false }
	if e.is_empty():
		return out
	if str(e.get("marker", "")) != "":
		out.mark = str(e.marker)
		if out.mark in ["gale2", "gale_2"] or (out.mark == "gale" and gale_level(e) >= 2):
			out.mark = "gale2"                    # D102: gale 2 draws the bigger swirl
		return out
	var h := int(e.get("h", 0))
	var v := int(e.get("v", 0))
	if h != 0:
		out.h = { "el": "fire" if h > 0 else "water", "tier": absi(h) }
	if v != 0:
		out.v = { "el": "light" if v > 0 else "dark", "tier": absi(v) }
	out.top = "v" if absi(v) > absi(h) else "h"
	var g := int(e.get("glaze", 0))
	if g > 0:
		out.mark = "glaze"
		out.crack = g == 1
	return out


## Authored starting charges and markers of a map file (ELEMENTS §5.4), for
## the screens that show a board with no battle behind it (title, loading,
## pre-battle): `bv.build(board, BWTileFX.authored(board, path))`. Reads the
## V8 form, a top-level `effects` array of { q, r, effect } and/or a per-cell
## `effect` key, with effect `charge_<h>_<v>` or `mark_fuse|stasis|gale`.
## Unknown kinds are skipped with a warning. Returns an empty BWTiles when the
## map authors nothing, so the FX layers are live either way.
static func authored(board: BWBoard, map_path: String) -> BWTiles:
	var t := BWTiles.new(board)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(map_path)) if FileAccess.file_exists(map_path) else null
	if not parsed is Dictionary:
		return t
	var list: Array = (parsed as Dictionary).get("effects", []).duplicate()
	for c in (parsed as Dictionary).get("cells", []):
		if c is Dictionary and c.has("effect"):
			list.append(c)
	for fx in list:
		if not fx is Dictionary:
			continue
		var hex := Vector2i(int(fx.get("q", -1)), int(fx.get("r", -1)))
		var kind := str(fx.get("effect", ""))
		if kind.begins_with("charge_"):
			var parts := kind.trim_prefix("charge_").split("_")
			if parts.size() == 2:
				t.author(hex, clampi(int(parts[0]), -3, 3), clampi(int(parts[1]), -3, 3))
				continue
		elif kind in ["mark_fuse", "mark_stasis", "mark_gale"]:
			t.author(hex, 0, 0, kind.trim_prefix("mark_"))
			continue
		push_warning("BWTileFX: %s: ignoring authored effect '%s'" % [map_path, kind])
	return t


## D102: the level of a gale marker (1 when the entry doesn't say). Read
## defensively: the rules lane may store it under any of these keys.
static func gale_level(e: Dictionary) -> int:
	for k in ["gale_level", "level", "gale", "tier", "power", "strength"]:
		var v: Variant = e.get(k)
		if v is int or v is float:
			return int(v)
	return 1


## A stable per-hex seed in 0..1 (shader time offset and noise origin).
static func seed_for(h: Vector2i, salt: int = 0) -> float:
	return float(absi(hash(Vector3i(h.x, h.y, salt))) % 997) / 997.0


# ------------------------------------------------------------------ materials

static func material(kind: String) -> ShaderMaterial:
	if _mats.has(kind):
		return _mats[kind]
	var m := ShaderMaterial.new()
	match kind:
		"tile_fire", "tile_flame":
			m.shader = load("res://shaders/%s.gdshader" % kind)
			m.set_shader_parameter("glow", BWLook.glow_color("fire"))
		"tile_water":
			m.shader = load("res://shaders/tile_water.gdshader")
			m.set_shader_parameter("glow", BWLook.glow_color("water"))
		"tile_light", "tile_beam":
			m.shader = load("res://shaders/%s.gdshader" % kind)
			m.set_shader_parameter("glow", BWLook.glow_color("light"))
		"tile_dark", "tile_tendril":
			m.shader = load("res://shaders/%s.gdshader" % kind)
			m.set_shader_parameter("glow", BWLook.glow_color("dark"))
		"fuse":
			m.shader = load("res://shaders/tile_marker.gdshader")
			m.set_shader_parameter("mode", 0)
			m.set_shader_parameter("glow", BWLook.glow_color("thunder"))
			m.set_shader_parameter("ink", Color(0.2, 0.04, 0.38))
		"gale", "gale2":
			m.shader = load("res://shaders/tile_marker.gdshader")
			m.set_shader_parameter("mode", 1)
			m.set_shader_parameter("glow", BWLook.glow_color("wind"))
			m.set_shader_parameter("ink", Color(0.02, 0.24, 0.08))
			m.set_shader_parameter("gale_size", 1.0 if kind == "gale2" else 0.0)   # D102
		"stasis":
			m.shader = load("res://shaders/tile_marker.gdshader")
			m.set_shader_parameter("mode", 2)
			# the hair hue, not the pale tile glow: pale cyan vanishes on white
			m.set_shader_parameter("glow", BWLook.element_color("ice"))
			m.set_shader_parameter("ink", Color(0.04, 0.38, 0.5))
		"glaze":
			m.shader = load("res://shaders/tile_glaze.gdshader")
			m.set_shader_parameter("glow", BWLook.glow_color("ice"))
			m.set_shader_parameter("ink", Color(0.04, 0.38, 0.5))
		"burst_detonate", "burst_gust", "burst_ignite", "flash_detonate", "flash_ignite":
			m.shader = load("res://shaders/tile_burst.gdshader")
			var mode: int = { "burst_detonate": 0, "burst_gust": 1, "flash_detonate": 2, "flash_ignite": 2, "burst_ignite": 3 }[kind]
			m.set_shader_parameter("mode", mode)
			var el := "thunder" if kind.ends_with("detonate") else ("wind" if kind == "burst_gust" else "fire")
			m.set_shader_parameter("glow", BWLook.glow_color(el))
		# D87 Striketwice reactions, the same burst shader re-tinted
		"burst_steam", "flash_steam", "burst_eclipse", "flash_eclipse", "burst_storm":
			m.shader = load("res://shaders/tile_burst.gdshader")
			var mode: int = { "burst_steam": 1, "flash_steam": 2, "burst_eclipse": 3, "flash_eclipse": 2, "burst_storm": 1 }[kind]
			m.set_shader_parameter("mode", mode)
			var col: Color = {
				"burst_steam": Color(0.78, 0.86, 0.92), "flash_steam": Color(0.9, 0.95, 1.0),
				"burst_eclipse": BWLook.glow_color("dark"), "flash_eclipse": BWLook.glow_color("dark"),
				"burst_storm": BWLook.glow_color("thunder"),
			}[kind]
			m.set_shader_parameter("glow", col)
		_:
			push_error("BWTileFX: unknown material '%s'" % kind)
			return null
	_mats[kind] = m
	return m


# ------------------------------------------------------------------ meshes

## Flat pointy-top hex of circumradius 1 on XZ (the face shaders' canvas).
static func hex_mesh() -> ArrayMesh:
	if _hex_mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var v := BWLook.hex_corners(Vector3.ZERO, 1.0)
		for i in 6:
			st.add_vertex(Vector3.ZERO)
			st.add_vertex(v[i])
			st.add_vertex(v[(i + 1) % 6])
		_hex_mesh = st.commit()
	return _hex_mesh


## The billboard card cluster (see tile_cards.gdshaderinc).
static func card_mesh() -> ArrayMesh:
	if _card_mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
		var k := 0
		for c in CARD_LAYOUT:
			var a := deg_to_rad(float(c[1]))
			var pivot := Vector3(cos(a) * float(c[0]), 0.0, sin(a) * float(c[0]))
			var data := Color(float(c[2]), float(c[3]), float(k) * 0.137 + 0.05, float(c[4]))
			var corners := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]
			for uv in corners:
				st.set_uv(uv)
				st.set_custom(0, data)
				st.add_vertex(pivot)
			k += 1
		_card_mesh = st.commit()
	return _card_mesh


static func disc_mesh() -> PlaneMesh:
	if _disc_mesh == null:
		_disc_mesh = PlaneMesh.new()
		_disc_mesh.size = Vector2(5.4, 5.4)
	return _disc_mesh


static func quad_mesh() -> QuadMesh:
	if _quad_mesh == null:
		_quad_mesh = QuadMesh.new()
		_quad_mesh.size = Vector2(2, 2)
	return _quad_mesh
