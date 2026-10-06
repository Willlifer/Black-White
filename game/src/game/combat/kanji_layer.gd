class_name BWKanjiLayer
extends Node3D
## D231: the element kanji drawn flat on the tile tops, over the element FX
## (BWBoardView owns one; it is fed every tile change through apply()).
##
##   charged tile   the axis element's kanji, weight by level: 1 thin (wght
##                  250), 2 regular (500), 3 heavy (900), with a white halo
##                  that thickens with it. Two axes (h + v) sit side by side,
##                  the dominant axis first (left).
##   marker         fuse 雷, stasis 氷, gale 風: smaller, heavy, with a thick halo,
##                  low on the hex so a unit standing there hides less of it.
## Ink-black glyphs with a white halo read on the white board and over every
## element colour. Each hex's pair turns with the camera's yaw so the glyphs
## stay upright from wherever the player looks (Q/E rotate 60°).
## Hidden while BWKanji.enabled() is false; toggling the setting mid-fight
## shows or hides it on the next frame.

const LIFT := 0.035
const SIZE_ONE := 0.92          ## world units, one glyph alone on a hex
const SIZE_TWO := 0.64          ## each of a pair
const SIZE_MARK := 0.58
const PAIR_GAP := 0.34          ## half the distance between a pair's centres
const MARK_DROP := 0.0          ## markers sit at the centre (they are alone on a hex)
const FONT_PX := 96
const INK := Color(0.03, 0.03, 0.04)
const HALO := Color(1, 1, 1)
const SORT := 0.47              ## over faces, marks and static rims; under highlights (0.50)

var _hex := {}                  # Vector2i -> { pivot, a, b, m }
var _want := {}                 # Vector2i -> BWTileFX.layers()
var _on := false
var _yaw := INF


func _ready() -> void:
	name = "kanji"
	_on = BWKanji.enabled()
	visible = _on


## Hex h's layers changed (BWBoardView._fx_apply).
func apply(h: Vector2i, top: Vector3, want: Dictionary) -> void:
	_want[h] = want
	if not _hex.has(h) and _needs(want):
		_hex[h] = _make(top)
		if is_finite(_yaw):
			_hex[h].pivot.rotation.y = _yaw
	if _hex.has(h):
		_hex[h].pivot.position = top + Vector3(0, LIFT, 0)
		_fill(_hex[h], want)


static func _needs(want: Dictionary) -> bool:
	return not (want.get("h", {}) as Dictionary).is_empty() or not (want.get("v", {}) as Dictionary).is_empty() \
		or str(want.get("mark", "")) in ["fuse", "stasis", "gale", "gale2"]


## What hex h shows now, for tests: [[glyph, level], …] in draw order (left first).
func shown(h: Vector2i) -> Array:
	var out: Array = []
	if not _hex.has(h):
		return out
	for k in ["a", "b", "m"]:
		var l: Label3D = _hex[h][k]
		if l.visible:
			out.append([l.text, int(l.get_meta("level", 0))])
	return out


func _make(top: Vector3) -> Dictionary:
	var pivot := Node3D.new()
	pivot.position = top + Vector3(0, LIFT, 0)
	add_child(pivot)
	var d := { "pivot": pivot }
	for k in ["a", "b", "m"]:
		var l := Label3D.new()
		l.name = k
		l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		l.rotation_degrees.x = -90.0                 # flat on the tile, text facing up
		l.double_sided = false
		l.shaded = false
		l.font_size = FONT_PX
		l.modulate = INK
		l.outline_modulate = HALO
		l.sorting_offset = SORT
		l.render_priority = 2
		l.outline_render_priority = 1
		l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		l.visible = false
		pivot.add_child(l)
		d[k] = l
	return d


func _fill(d: Dictionary, want: Dictionary) -> void:
	var axes: Array = []
	var hv: Array = ["h", "v"] if str(want.get("top", "h")) == "h" else ["v", "h"]
	for axis in hv:
		var w: Dictionary = want.get(axis, {})
		if not w.is_empty():
			axes.append([str(w.el), clampi(int(round(float(w.get("tier", 1)))), 1, 3)])
	var a: Label3D = d.a
	var b: Label3D = d.b
	var m: Label3D = d.m
	a.visible = false
	b.visible = false
	m.visible = false
	if axes.size() == 1:
		_glyph(a, axes[0][0], axes[0][1], SIZE_ONE, Vector3.ZERO)
	elif axes.size() == 2:
		_glyph(a, axes[0][0], axes[0][1], SIZE_TWO, Vector3(-PAIR_GAP, 0, 0))
		_glyph(b, axes[1][0], axes[1][1], SIZE_TWO, Vector3(PAIR_GAP, 0, 0))
	var mark := str(want.get("mark", ""))
	var mel: String = { "fuse": "thunder", "stasis": "ice", "gale": "wind", "gale2": "wind" }.get(mark, "")
	if mel != "":
		_glyph(m, mel, 0, SIZE_MARK, Vector3(0, 0, MARK_DROP))
		m.outline_size = 26
		m.font = BWKanji.font(3)                    # heavy: a small glyph must not thin out


func _glyph(l: Label3D, el: String, level: int, size_u: float, at: Vector3) -> void:
	l.text = BWKanji.glyph(el)
	l.visible = l.text != ""
	l.set_meta("level", level)
	l.font = BWKanji.font(level)
	l.outline_size = int(BWKanji.OUTLINES.get(level, 18))
	l.pixel_size = size_u / float(FONT_PX)
	l.position = at


func _process(_delta: float) -> void:
	var on := BWKanji.enabled()
	if on != _on:
		_on = on
		visible = on
	if not on or _hex.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var f := -cam.global_basis.z
	f.y = 0.0
	if f.length_squared() < 1e-6:
		f = cam.global_basis.y              # straight down: the camera's up is "away"
		f.y = 0.0
	if f.length_squared() < 1e-6:
		return
	f = f.normalized()
	var yaw := atan2(-f.x, -f.z)
	if is_equal_approx(yaw, _yaw):
		return
	_yaw = yaw
	for h in _hex:
		(_hex[h].pivot as Node3D).rotation.y = yaw
