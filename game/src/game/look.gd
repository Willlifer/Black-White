class_name BWLook
## The controlled palette and the shared materials. Everything visible is
## built from these, so the black/white hierarchy lives in one place:
##   white  = what you stand on and what you are (tile tops, faces)
##   black  = contour and structure (borders, limbs, outlines, sky)
##   greys  = depth and cloth (tile sides, clothing tiers)
##   colour = element only (hair, tile glows, auras)

const WHITE := Color(1, 1, 1)
const PAPER := Color(0.95, 0.95, 0.95)       # grassy top: a hair off white
const MUD := Color(0.74, 0.74, 0.74)         # muddy top
const SIDE := Color(0.62, 0.62, 0.62)        # tile walls
const SIDE_DARK := Color(0.42, 0.42, 0.42)   # lower walls, for depth
const INK := Color(0.0, 0.0, 0.0)
const GREY_DARK := Color(0.28, 0.28, 0.28)
const GREY_MID := Color(0.55, 0.55, 0.55)
const GREY_LIGHT := Color(0.82, 0.82, 0.82)

const TILE_HEIGHT := 0.35      # world units per elevation level
const HEX_SIZE := 1.0          # circumradius
const BORDER := 0.07           # black rim width on each tile top

static var _flat: ShaderMaterial
static var _alpha: ShaderMaterial
static var _pulse: ShaderMaterial
static var _outlines := {}


static func flat() -> ShaderMaterial:
	if _flat == null:
		_flat = ShaderMaterial.new()
		_flat.shader = load("res://shaders/flat.gdshader")
	return _flat


static func alpha(pulse: bool = false) -> ShaderMaterial:
	if pulse:
		if _pulse == null:
			_pulse = ShaderMaterial.new()
			_pulse.shader = load("res://shaders/flat_alpha.gdshader")
			_pulse.set_shader_parameter("pulse_speed", 4.0)
		return _pulse
	if _alpha == null:
		_alpha = ShaderMaterial.new()
		_alpha.shader = load("res://shaders/flat_alpha.gdshader")
	return _alpha


## Inverted-hull contour. Black around white shapes (heads, weapons);
## white around black limbs (D42) so stick figures stay readable against the
## black sky — on white tiles the white contour simply vanishes.
static func outline(width: float = 0.025, color: Color = Color.BLACK) -> ShaderMaterial:
	var key := "%.4f|%s" % [width, color.to_html()]
	if _outlines.has(key):
		return _outlines[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/outline.gdshader")
	m.set_shader_parameter("width", width)
	m.set_shader_parameter("color", color)
	_outlines[key] = m
	return m


static func element_color(element: String) -> Color:
	var row := BWData.row("elements", element)
	return Color(str(row.get("hair_hex", "#888888")))


# ------------------------------------------------- hair from affinity (D146)
## Hair colour follows affinity rank (design/art/HAIR.md, "Rank colour").
## The element colour is always the majority; rank shows as how many
## CONTRAST STREAKS run through it (fewer streaks = more mastery):
##   rank 0        unaligned: plain mid grey
##   rank 1        the element colour with ~30% of locks in contrast streaks
##   rank 2        ~12% contrast streaks
##   rank 3+       solid element colour
##   2+ elements   an ombre over the element colours, weakest at the root,
##                 strongest at the tips; band length follows rank; each
##                 band keeps half its own streak share (sparing)
## Streak colour by the element colour's relative luminance (linear,
## Rec. 709): below HAIR_STREAK_LUM -> light streaks (dark, thunder, water),
## at or above -> black streaks (fire, wind, ice, light).
## hair_gradient() is the one pure function; BWHair turns it into a ramp
## texture (cached by hair_key) that hair.gdshader reads along each
## vertex's root->tip coordinate.

## Contrast-streak share of the locks by rank (index = min(rank, 3)).
const HAIR_STREAKS: Array[float] = [0.0, 0.3, 0.12, 0.0]
## Inside an ombre each band keeps this fraction of its streak share.
const HAIR_MIX_STREAKS := 0.5
## Half-width of the soft transition between ombre bands (root->tip units).
const HAIR_BLEND := 0.2
## Relative luminance below which a colour takes light streaks. Fire
## (#E8432E, 0.21) is the lightest that keeps black; water (#2E6FE8, 0.18)
## the darkest that goes light.
const HAIR_STREAK_LUM := 0.19
## The two streak colours (sRGB): very light grey, and ink.
const HAIR_STREAK_LIGHT := Color(0.9, 0.9, 0.9)
const HAIR_STREAK_DARK := Color(0.0, 0.0, 0.0)
## Rank 0 (no element): a neutral that reads on the white head and the sky.
const HAIR_NONE := Color(0.55, 0.55, 0.55)


## [[element, rank], ...] with rank >= 1, strongest first. Ties: the focus
## element first, then BWFormulas.ELEMENTS order. `affinity` holds points
## (BWUnit.affinity: rank = points / POINTS_PER_RANK).
static func hair_ranks(affinity: Dictionary, focus: String = "") -> Array:
	var out: Array = []
	for el in affinity:
		var r := mini(int(affinity[el]) / BWUnit.POINTS_PER_RANK, BWUnit.MAX_AFFINITY_RANK)
		if r >= 1 and str(el) != "":
			out.append([str(el), r])
	var order := BWFormulas.ELEMENTS
	out.sort_custom(func(a: Array, b: Array) -> bool:
		if a[1] != b[1]:
			return a[1] > b[1]
		if (a[0] == focus) != (b[0] == focus):
			return a[0] == focus
		var ia := order.find(a[0])
		var ib := order.find(b[0])
		ia = ia if ia >= 0 else 99
		ib = ib if ib >= 0 else 99
		return ia < ib if ia != ib else a[0] < b[0])
	return out


## Cache key for a hair look: "" for unaligned, else "fire3,water1"
## (strongest first). Same key, same gradient.
static func hair_key(affinity: Dictionary, focus: String = "") -> String:
	var parts := PackedStringArray()
	for e in hair_ranks(affinity, focus):
		parts.append("%s%d" % [e[0], e[1]])
	return ",".join(parts)


## Relative luminance (linear Rec. 709) of an sRGB colour.
static func luminance(c: Color) -> float:
	var l := c.srgb_to_linear()
	return 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b


## True when this element colour takes light (white) contrast streaks.
static func light_streaks(c: Color) -> bool:
	return luminance(c) < HAIR_STREAK_LUM


## The streak encoding in a gradient alpha: 0.5 = no streaks; above 0.5 =
## light streaks on (a - 0.5) * 2 of the locks; below = black streaks on
## (0.5 - a) * 2. Interpolating between bands fades through "none".
static func streak_alpha(c: Color, share: float) -> float:
	return 0.5 + (0.5 if light_streaks(c) else -0.5) * clampf(share, 0.0, 1.0)


## The hair look as a Gradient over the root (0) -> tip (1) coordinate:
## rgb = the hair colour there, alpha = the contrast streaks (streak_alpha;
## hair.gdshader decodes it).
static func hair_gradient(affinity: Dictionary, focus: String = "") -> Gradient:
	var g := Gradient.new()
	var ranks := hair_ranks(affinity, focus)
	if ranks.is_empty():
		g.offsets = PackedFloat32Array([0.0, 1.0])
		g.colors = PackedColorArray([Color(HAIR_NONE, 0.5), Color(HAIR_NONE, 0.5)])
		return g
	ranks.reverse()                       # root -> tip: weakest first
	var total := 0
	for e in ranks:
		total += int(e[1])
	var multi := ranks.size() > 1
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	var start := 0.0
	for i in ranks.size():
		var c := element_color(str(ranks[i][0]))
		var r: int = ranks[i][1]
		var share: float = HAIR_STREAKS[mini(r, HAIR_STREAKS.size() - 1)] * (HAIR_MIX_STREAKS if multi else 1.0)
		var col := Color(c, streak_alpha(c, share))
		var w := float(r) / float(total)
		var hb := minf(HAIR_BLEND, w * 0.4) if multi else 0.0
		offs.append(0.0 if i == 0 else start + hb)
		cols.append(col)
		offs.append(1.0 if i == ranks.size() - 1 else start + w - hb)
		cols.append(col)
		start += w
	# drop any non-increasing offset (a narrow band squeezed by the blends)
	var o2 := PackedFloat32Array()
	var c2 := PackedColorArray()
	for k in offs.size():
		var o := clampf(offs[k], 0.0, 1.0)
		if o2.is_empty() or o > o2[o2.size() - 1] + 0.0001:
			o2.append(o)
			c2.append(cols[k])
		else:
			c2[c2.size() - 1] = cols[k]
	g.offsets = o2
	g.colors = c2
	return g


static func glow_color(element: String) -> Color:
	var row := BWData.row("elements", element)
	return Color(str(row.get("tile_glow_hex", row.get("hair_hex", "#888888"))))


static func shade(name: String) -> Color:
	match name:
		"dark": return GREY_DARK
		"light": return GREY_LIGHT
	return GREY_MID


static func world(h: Vector2i, elevation: int = 0) -> Vector3:
	var p := BWHex.to_world(h, HEX_SIZE)
	return Vector3(p.x, elevation * TILE_HEIGHT, p.y)


## Pointy-top hexagon corners on the XZ plane, radius r, at height y.
static func hex_corners(center: Vector3, r: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in 6:
		var a := deg_to_rad(60.0 * i - 30.0)
		out.append(center + Vector3(cos(a) * r, 0.0, sin(a) * r))
	return out


static func set_dim(node: Node, value: float) -> void:
	if node is Label3D:
		(node as Label3D).modulate.a = 1.0 - value
		(node as Label3D).outline_modulate.a = 1.0 - value
	elif node is GeometryInstance3D:
		(node as GeometryInstance3D).set_instance_shader_parameter("dim", value)
		# Per-node StandardMaterials (unit HP bars) have no `dim`: fade their
		# alpha from the value stored at creation (meta "dim_alpha").
		if node.has_meta("dim_alpha") and (node as GeometryInstance3D).material_override is StandardMaterial3D:
			var m := (node as GeometryInstance3D).material_override as StandardMaterial3D
			m.albedo_color.a = float(node.get_meta("dim_alpha")) * (1.0 - value)
	for c in node.get_children():
		set_dim(c, value)


static func starfield_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/starfield.gdshader")
	sky.sky_material = mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	return env
