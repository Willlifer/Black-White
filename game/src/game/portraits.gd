class_name BWPortraits
extends Node
## D156: unit portraits rendered from the real character, head and shoulders,
## once per look, then cached (the BWItemIcons pattern). The small icons
## (turn order, results, roster slots, picks, codex, end card) use these
## snapshots (BWWidgets.Portrait); the big unit panels show a live camera
## feed of the same framing instead (BWWidgets.LivePortrait) when the unit is
## on stage, and fall back to the snapshot otherwise.
##   memory  a static dictionary, for the rest of the session
##   disk    user://portraits/v<VERSION>/<key>.png, for later runs
## Bump VERSION when the rig, hair, clothes, outlines or the framing change.
##
##   var tex := BWPortraits.portrait(unit)     # null until rendered (a render is queued)
##   BWPortraits.prewarm(units)                # queue the lot ahead of time (pre-battle)
##   BWPortraits.instance().portrait_ready     # (key) a requested portrait landed
##
## What it shows: the blank white face, the hair style + variant in its current
## affinity gradient (D146: streaks, ombre), the top's collar in its shade,
## head and chest armour when worn. The weapon is hidden. A three-quarter view,
## the same orthographic framing for everyone, transparent background (the
## widget draws the panel and the element frame, BWWidgets.Portrait).
## Obelisks render their own stone (key "obelisk_<kind>"); the Giant is a
## character like any other (BWCharacter.BOSS_LOOK).
##
## The key is the look, not the unit: style, variant, hair_key (ranks), top,
## shade, head + chest armour (base:element). A rank-up or a new helmet makes a
## new key, so the next portrait() call queues a fresh render; the old texture
## stays up until it lands.
##
## Cost (measured, design/DECISIONS.md D156): building a dressed character is
## the expensive part (first one pays the glb loads); the render itself is two
## GPU frames. Renders run one at a time, one per ~2 frames, never all at once.
## Headless runs never render (the self-test, sims): portrait() returns null.

signal portrait_ready(key: String)

const VERSION := 1
const SIZE := 256                    ## 104 design px at 4K is ~208 physical: 256 + mipmaps
const DIR := "user://portraits/v%d/" % VERSION
## Framing (rig space, metres; the head centre is at 1.92, BWUnitView.head_height).
const VIEW_YAW := 24.0               ## degrees off front, to the character's left
const VIEW_PITCH := 6.0              ## degrees above level
const FRAME_CENTRE := Vector3(0.0, 1.83, 0.0)
const FRAME_SIZE := 1.22             ## orthographic vertical extent: hair top to the shoulders

static var _cache := {}              # key -> Texture2D
static var _inst: BWPortraits
## First-render timings, ms (tools/portrait_shots.gd prints them).
static var timings: Array = []       # [{key, build, total}]

var _queue: Array = []               # [key, BWUnit]
var _busy := false
var _vp: SubViewport
var _cam: Camera3D
var _stage: Node3D


static func enabled() -> bool:
	return DisplayServer.get_name() != "headless"


## The cache key for a unit's current look.
static func key_for(u: BWUnit) -> String:
	if u == null:
		return ""
	if BWObelisk.is_objective(u) and not u is BWLilFella:    # D348: the Lil Fella is a figure
		return "obelisk_" + (u as BWObelisk).kind
	var lk := BWCharacter.look_for(u)
	var hk := BWLook.hair_key(u.affinity, u.focus())
	if hk == "":                                    # mirrors BWCharacter.refresh_hair
		hk = ("solid-" + str(lk.element)) if str(lk.get("element", "")) != "" else "none"
	var parts: PackedStringArray = [str(lk.hair_style), str(lk.get("hair_variant", 0)), hk,
		str(lk.top), str(lk.clothing_shade)]
	for slot in ["head", "chest"]:
		var it: Dictionary = u.equipment.get(slot, {})
		var base := str(it.get("base", ""))
		if base != "" and BWEquipmentView.has_model(base):
			parts.append("%s-%s" % [base, BWRun.item_element(it)])
		elif (lk.armour as Dictionary).has(slot):
			parts.append("%s-%s" % [lk.armour[slot], lk.armour_element])
		else:
			parts.append("")
	if u.encounter != "":
		parts.append("enc-%s-%s" % [u.encounter, u.element])   # D213: the Blank's wash, the Being's glow
	return "_".join(parts).replace(",", "+").replace("#", "").replace(":", "-").replace(" ", "")


## Make sure one renderer lives in the tree (under the root, so it survives
## screen changes). Safe to call from _ready / _init of any node.
static func ensure(from: Node = null) -> BWPortraits:
	if _inst != null and is_instance_valid(_inst):
		return _inst
	var tree := from.get_tree() if from != null and from.is_inside_tree() else Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	_inst = BWPortraits.new()
	_inst.name = "Portraits"
	tree.root.add_child.call_deferred(_inst)
	return _inst


static func instance() -> BWPortraits:
	return _inst if _inst != null and is_instance_valid(_inst) else null


## The cached portrait for `u`'s current look, or null (a render is queued).
static func portrait(u: BWUnit) -> Texture2D:
	var key := key_for(u)
	if key == "":
		return null
	var hit := cached(key)
	if hit:
		return hit
	if enabled():
		var r := ensure()
		if r:
			r._request(key, u)
	return null


## Memory, then disk. No render.
static func cached(key: String) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	var path := DIR + key + ".png"
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img and not img.is_empty():
			_cache[key] = _texture(img)
			return _cache[key]
	return null


## Queue every unit's portrait (pre-battle: the deployed squad and the enemy).
static func prewarm(units: Array) -> void:
	for u in units:
		if u is BWUnit:
			portrait(u)


## Renders still queued or in progress.
static func pending() -> int:
	var r := instance()
	return 0 if r == null else r._queue.size() + (1 if r._busy else 0)


static func _texture(img: Image) -> ImageTexture:
	if not img.has_mipmaps():
		img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_8X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	_vp.add_child(we)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.current = true
	_vp.add_child(_cam)
	_stage = Node3D.new()
	_vp.add_child(_stage)
	if not _queue.is_empty():
		_pump.call_deferred()


var _log_t := 0.0
var _log_n := 0
var _log_max := 0.0
var _bench: CanvasLayer


func _bench_feed() -> void:
	var views := get_tree().root.find_children("*", "BWUnitView", true, false)
	if views.size() < 2:
		return
	_bench = CanvasLayer.new()
	add_child(_bench)
	var p := BWWidgets.LivePortrait.new((views[1] as BWUnitView).unit, 104.0)
	p.position = Vector2(700, 300)
	_bench.add_child(p)


## BW_FRAME_LOG=1: every 5 s, the average and worst frame time and the live
## feed count (the D156 A/B: run once with BW_LIVE=0, once without).
func _process(delta: float) -> void:
	if not OS.has_environment("BW_FRAME_LOG"):
		set_process(false)
		return
	if OS.has_environment("BW_LIVE_BENCH") and (_bench == null or not is_instance_valid(_bench)):
		_bench_feed()                              # a second feed, so both card slots run
	_log_t += delta
	_log_n += 1
	_log_max = maxf(_log_max, delta)
	if _log_t >= 5.0:
		print("frame log %s: avg %.2f ms  worst %.1f ms  (%d frames)  live feeds %d" % [DisplayServer.window_get_size(), _log_t * 1000.0 / _log_n, _log_max * 1000.0, _log_n, BWWidgets.LivePortrait.live])
		_log_t = 0.0
		_log_n = 0
		_log_max = 0.0


func _request(key: String, u: BWUnit) -> void:
	for q in _queue:
		if q[0] == key:
			return
	_queue.append([key, u])
	if not _busy and is_inside_tree():
		_pump.call_deferred()


func _pump() -> void:
	if _busy or not is_inside_tree():
		return
	_busy = true
	while not _queue.is_empty() and is_inside_tree():
		var q: Array = _queue.pop_front()
		var key: String = q[0]
		if _cache.has(key):
			continue
		var tex := await _render(key, q[1])
		if tex:
			_cache[key] = tex
		portrait_ready.emit(key)
	_busy = false


func _render(key: String, u: BWUnit) -> Texture2D:
	for c in _stage.get_children():
		c.free()
	var t0 := Time.get_ticks_usec()
	var centre := FRAME_CENTRE
	var size := FRAME_SIZE
	var yaw := VIEW_YAW
	if BWObelisk.is_objective(u) and not u is BWLilFella:
		var ov := BWObeliskView.new()
		_stage.add_child(ov)
		ov.setup(u)
		for n in ["_label", "_hp_label", "_bar_bg", "_bar_fill", "_bar_ghost"]:
			var v: Variant = ov.get(n)
			if v is Node3D:
				(v as Node3D).visible = false
		var ring := ov.get_node_or_null("base_ring") as Node3D
		if ring:
			ring.visible = false
		ov.set_process(false)
		# the carved head of the stone: its upper part, glyphs and cap
		var h := float(BWObeliskView.load_meta().get((u as BWObelisk).kind, {}).get("height", 3.2))
		centre = Vector3(0.0, h * 0.66, 0.0)
		size = h * 0.72
		yaw = 18.0
	else:
		var was := BWCharacter.animate
		BWCharacter.animate = false              # a still: the static idle key, no clip player
		var c := BWCharacter.new()
		var ok := c.build(u)
		BWCharacter.animate = was
		if not ok:
			c.free()
			return null
		c.breathing = false
		_stage.add_child(c)
		c.pose("idle", 0.0)
		if c.weapon:
			c.weapon.visible = false
		c.set_process(false)
		if u.size > 1 and u.encounter == "":     # the Giant: framed close, it fills the plate (the Colossus is a figure)
			centre = Vector3(0.0, 1.70, 0.0)
			size = 0.98
			yaw = 32.0
	var t_build := Time.get_ticks_usec()
	var dir := Vector3(sin(deg_to_rad(yaw)), sin(deg_to_rad(VIEW_PITCH)), cos(deg_to_rad(yaw))).normalized()
	_cam.size = size
	_cam.position = centre + dir * 6.0
	_cam.look_at(centre, Vector3.UP)
	_cam.near = 0.5
	_cam.far = 12.0
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return null
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var img := _vp.get_texture().get_image()
	for c in _stage.get_children():
		c.queue_free()
	if img == null or img.is_empty():
		return null
	img.save_png(ProjectSettings.globalize_path(DIR + key + ".png"))
	timings.append({ "key": key, "build": (t_build - t0) / 1000.0, "total": (Time.get_ticks_usec() - t0) / 1000.0 })
	return _texture(img)
