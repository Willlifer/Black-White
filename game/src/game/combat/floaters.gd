class_name BWFloaters
extends RefCounted
## D344 floater declutter (polish pass 3). The word floaters over a unit
## ("Chain", "immune", "SLAM", statuses, keystone words, riders) were 24-40 px
## at the damage numbers' pixel size: in a 6v6 crowd they overlapped each
## other and the turn order. Now:
##   * every floater now uses the names' pixel size (PIXEL); tags are small
##     (TAG_FONT, half the smallest damage number, BWHitFeel.NUM_MIN), in
##     their colour over a black outline;
##   * tags on one unit STACK: each live tag takes the next slot up
##     (STACK_PX label pixels) over the number's line, clear of the name and
##     the bar, so two words never print on top of each other;
##   * they rise a little and fade fast (TAG_HOLD_MAX, TAG_FADE);
##   * every floater (tags and damage numbers) stays below the turn-order bar
##     (BWHPBar3D.hud_rect), like the HP bars (D217).
## Damage numbers keep their hit-size scaling (D170, BWHitFeel.number_size).

## The pixel size of every floater: the names' (BWUnitView, 0.0011). At the old
## 0.0016 a 40-font word was ~60 px tall at 1080p and a capped crit ~150 px.
const PIXEL := 0.0011
const TAG_FONT := 15               # ~21 px at 1080p, a little over a name
const TAG_RULE_FONT := 11
const STACK_PX := 19.0             # one tag line, in label pixels
const FIRST_PX := 58.0             # the first tag sits over the damage number's line (clear of the name and bar)
## Rises are in SCREEN (label) pixels, not world units: 0.6 world was ~20 px
## on the 6v6 camera and ~150 px zoomed in, where a rising number ran through
## the tags spawned after it.
const NUM_RISE_PX := 26.0
const TAG_RISE_PX := 14.0
const TAG_HOLD_MAX := 0.55
const TAG_FADE := 0.18
const HUD_GAP := 6.0               # screen px kept under the turn-order bar

static var _stacks := {}           # view instance id -> Array[Node3D] (live tags)


## Per unit view, the push-down its floaters need this frame and the one
## applied (last frame's max): all floaters of one unit move TOGETHER, so a
## clamped stack keeps its order (number, then tags above it).
static var _need := {}             # group id -> [frame, px]
static var _applied := {}          # group id -> px


## A floating label that stays below the turn-order bar: each frame its
## screen rect is measured and, if its top would sit above the bar's bottom
## edge, its group (`group`, the unit view) is pushed down by the largest
## need among its floaters (`base_offset` is the unclamped offset).
class Floater extends Label3D:
	var base_offset := Vector2.ZERO
	var group := 0

	func _process(_d: float) -> void:
		offset = base_offset
		if not BWHPBar3D.hud_rect.has_area() or not is_inside_tree():
			return
		var cam := get_viewport().get_camera_3d()
		if cam == null or cam.is_position_behind(global_position):
			return
		var r := BWBlastPreview.label_rect(cam, self)
		if not r.has_area():
			return
		var limit := BWHPBar3D.hud_rect.end.y + HUD_GAP
		var need := maxf(0.0, limit - r.position.y)
		var f := Engine.get_process_frames()
		var key := group if group != 0 else get_instance_id()
		var rec: Array = BWFloaters._need.get(key, [-1, 0.0])
		if int(rec[0]) != f:
			BWFloaters._applied[key] = float(rec[1]) if int(rec[0]) == f - 1 else need
			rec = [f, 0.0]
		rec[1] = maxf(float(rec[1]), need)
		BWFloaters._need[key] = rec
		var px := maxf(float(BWFloaters._applied.get(key, 0.0)), need)
		if px > 0.0:
			var k := BWBlastPreview.px_scale(cam, pixel_size)
			if k > 0.0:
				offset = base_offset - Vector2(0, px / k)


## A number's rise (a fixed screen distance, see NUM_RISE_PX).
static func rise(tw: Tween, l: Floater, hold: float) -> void:
	tw.tween_property(l, "base_offset:y", NUM_RISE_PX, hold).set_ease(Tween.EASE_OUT)


static func label(text: String, col: Color, size: int, outline: int, owner: Node3D = null) -> Floater:
	var l := Floater.new()
	l.group = owner.get_instance_id() if owner != null else 0
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = PIXEL
	l.font_size = size
	l.outline_size = outline
	l.modulate = col
	l.outline_modulate = Color.BLACK
	l.render_priority = 20             # D102: over the board's transparent pass
	l.outline_render_priority = 19
	return l


## The first free run of `span` stack slots on a view (registers `n` in it
## until it is freed).
static func _slot(v: Node3D, n: Node3D, span: int = 1) -> int:
	var k := v.get_instance_id()
	var arr: Array = (_stacks.get(k, []) as Array).filter(func(x): return is_instance_valid(x) and not (x as Node).is_queued_for_deletion())
	var used := {}
	for x in arr:
		for j in int((x as Node).get_meta("span", 1)):
			used[int((x as Node).get_meta("slot", 0)) + j] = true
	var s := 0
	while used.has(s) or (span > 1 and used.has(s + 1)):
		s += 1
	n.set_meta("slot", s)
	n.set_meta("span", span)
	arr.append(n)
	_stacks[k] = arr
	return s


## A word tag over a unit view: small, stacked, quick. `rule` adds a smaller
## second line (statuses: "no skills").
static func tag(screen: Node3D, v: Node3D, text: String, col: Color, hold: float = 0.6, rule: String = "",
		height: float = 2.4) -> Node3D:
	var root := Node3D.new()
	screen.add_child(root)
	root.global_position = v.global_position + Vector3(0, height, 0)
	var slot := _slot(v, root, 2 if rule != "" else 1)
	var y := FIRST_PX + STACK_PX * (slot + (1 if rule != "" else 0))   # stacks UP (the clamp keeps it under the turn order); a rule line sits in the lower slot
	var l := label(text, col, TAG_FONT, 6, v)
	l.base_offset = Vector2(0, y)
	root.add_child(l)
	if rule != "":
		var r := label(rule, Color(0.78, 0.78, 0.82), TAG_RULE_FONT, 4, v)
		r.base_offset = Vector2(0, y - 14.0)
		root.add_child(r)
	var tw := root.create_tween()
	var bases: Array = root.get_children().map(func(c): return (c as Floater).base_offset if c is Floater else Vector2.ZERO)
	tw.tween_method(func(k: float):
		var kids := root.get_children()
		for i in mini(kids.size(), bases.size()):
			if kids[i] is Floater:
				(kids[i] as Floater).base_offset = bases[i] + Vector2(0, TAG_RISE_PX * k), 0.0, 1.0, minf(hold, TAG_HOLD_MAX)).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(a: float):
		for c in root.get_children():
			if c is Label3D:
				(c as Label3D).modulate.a = a
				(c as Label3D).outline_modulate.a = a
			elif c is Sprite3D:
				(c as Sprite3D).modulate.a = a, 1.0, 0.0, TAG_FADE)
	tw.tween_callback(root.queue_free)
	return root


## Live tags on a view (probes / review).
static func live(v: Node3D) -> int:
	var arr: Array = _stacks.get(v.get_instance_id(), [])
	return arr.filter(func(x): return is_instance_valid(x) and not (x as Node).is_queued_for_deletion()).size()
