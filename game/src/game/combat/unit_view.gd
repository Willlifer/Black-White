class_name BWUnitView
extends Node3D
## A unit on the board, on the roster stage, in the downtime hall: the
## dressed character (BWCharacter: rig, hair, clothes, armour, weapon, poses),
## its team disc, a floating HP bar and a name label.
##
## Public API (combat, screens and probes depend on it; keep it stable):
##   setup(u), refresh(), show_label(v), face(target), idle(), pose_named(name)
##   pose names: idle windup strike cast hit kneel dodge block fumble fall cheer
## Additive: refresh_equipment(), head_height(), character.
## Animation (additive): pose_named("walk" | "run" | "run_stop" | "channel"),
##   has_clip(pose), time_to_marker(name), walk_speed(), plan_move(dist, hexes),
##   begin_move(plan), lead_to_impact(pose), clip_meta_of(pose), weapon_tip().
##   Every weapon style has a clip set (BWAnimClips), so every pose name plays
##   a clip; the static key poses stay as the safety fallback. Below 35% HP
##   refresh() switches the unit to its wounded idle and limp.
## Reactions (additive): pose_named("stricken_flinch" | "stricken_shrug" |
##   "stricken_stumble" | "stricken_knockback" | "stricken_rage"), the hit
##   variants the cutscene picks (BWReactionPick); `last_reaction` holds the
##   reaction name last picked for this unit (the audio lane's grunt key).
## Weapon handling (additive, D80): standing, the unit rotates how it holds
##   its weapon (side, shoulder, planted, daggers reversed) and handles it
##   (heft, admire, tricks). `showcase = true` (the roster stage) shows more
##   of it; hold(), grip() ("forward" | "reverse"), handle(hold or action).
##
## `use_rig = false` builds the old primitive stand-in instead (capsules and
## spheres at the reference proportions), for fallback and tests. Poses there
## are a few hand-set joint angles.

const HEAD_R := 0.34
const LIMB := 0.035

## false = the primitive stand-in (fallback, tests). Read at setup().
static var use_rig := true

var unit: BWUnit
var character: BWCharacter       ## null in the primitive fallback
var last_reaction := ""          ## the reaction last picked for this unit (BWReactionPick)
## The skill the next windup / strike performs (a key such as "flurry" or
## its display name, "Palm Burst"): weapons with a clip for it (fists:
## flurry, uppercut, palm_burst) play that instead of the plain strike.
## Cleared once its strike starts. (The combat lane sets it per cutscene.)
var skill := ""
## The roster stage: more weapon-handling variety than in combat. Set it
## before or after setup().
var showcase := false:
	set(v):
		showcase = v
		if character:
			character.showcase = v
var _equip_sig := ""
var _hip: Node3D
var _chest: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _head: Node3D
var _label: Label3D
var _bar_bg: MeshInstance3D
var _bar_fill: MeshInstance3D
var _bar_ghost: MeshInstance3D     # the chunk just lost, lingering grey before it drains
var _hp_label: Label3D             # current HP, printed on the bar (author 10/4: "hard to see what the current HP is")
var _shown_f := 1.0
## Bigger than v1 (0.9 × 0.075): the HP has to read at combat distance.
const BAR_W := 1.25
const BAR_H := 0.13
var _t := 0.0


func setup(u: BWUnit) -> void:
	unit = u
	name = "unit_" + u.id
	register(self)
	_build()
	if u.size > 1:
		# The boss: a giant standing over its whole 7-hex footprint.
		scale = Vector3.ONE * 2.6
		_label.pixel_size *= 1.0 / 2.6
	refresh()


func _build() -> void:
	_build_disc()
	if use_rig:
		character = BWCharacter.create(unit)
		character.showcase = showcase
		add_child(character)
		_equip_sig = _signature()
	else:
		_build_primitive()
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0011
	_label.outline_size = 7
	_label.modulate = Color.WHITE
	_label.outline_modulate = Color.BLACK
	_label.font_size = 13
	add_child(_label)
	# V8-style floating HP bar: ink well, white fill (grey for enemies)
	_bar_bg = _bar_quad(BAR_W + 0.04, BAR_H + 0.04, Color(0, 0, 0, 0.9), 0)
	add_child(_bar_bg)
	_bar_ghost = _bar_quad(BAR_W, BAR_H, Color(0.62, 0.62, 0.66), 1)
	add_child(_bar_ghost)
	_bar_fill = _bar_quad(BAR_W, BAR_H, Color(0.45, 0.45, 0.47) if unit.team == "enemy" else Color(0.97, 0.97, 0.97), 2)
	add_child(_bar_fill)
	_hp_label = Label3D.new()
	_hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_label.no_depth_test = true
	_hp_label.fixed_size = true
	_hp_label.pixel_size = 0.0011
	_hp_label.font_size = 17
	_hp_label.outline_size = 9
	_hp_label.modulate = Color.BLACK
	_hp_label.outline_modulate = Color.WHITE
	_hp_label.render_priority = 14
	_hp_label.outline_render_priority = 13
	add_child(_hp_label)
	_place_bar()
	idle()


## The bar floats above the tallest thing on the head (hair, hat, helm).
func _place_bar() -> void:
	var bar := 2.2                     # primitive stand-in: unchanged
	if character:
		bar = 2.62 if character.part("head") == null else 2.80
	_bar_bg.position.y = bar
	_bar_fill.position.y = bar
	_bar_ghost.position.y = bar
	_hp_label.position.y = bar
	_label.position.y = bar + 0.18


## D156: which view shows a unit right now (BWWidgets.LivePortrait follows it).
## Every setup() registers; view_for() returns the newest view of `u` that is
## still in the tree and visible (a drag ghost freed, the board's view again).
static var _by_unit := {}        # unit instance id -> Array[WeakRef]


static func register(v: BWUnitView) -> void:
	if v.unit == null:
		return
	var k := v.unit.get_instance_id()
	var arr: Array = _by_unit.get(k, [])
	arr = arr.filter(func(w): return w.get_ref() != null and w.get_ref() != v)
	arr.append(weakref(v))
	_by_unit[k] = arr


static func view_for(u: BWUnit) -> BWUnitView:
	if u == null or not _by_unit.has(u.get_instance_id()):
		return null
	var arr: Array = _by_unit[u.get_instance_id()]
	for i in range(arr.size() - 1, -1, -1):
		var v: BWUnitView = arr[i].get_ref()
		if v != null and v.is_inside_tree() and v.is_visible_in_tree() and v.unit == u:
			return v
	return null


## Height of the head centre in this view's space (camera framing, barks).
func head_height() -> float:
	return (1.92 if character else 0.62 + 0.55 + HEAD_R * 0.95) * scale.y


func _signature() -> String:
	var parts: PackedStringArray = [unit.weapon_model]
	for slot in ["main_hand", "head", "chest", "legs"]:
		var it: Dictionary = unit.equipment.get(slot, {})
		parts.append("%s:%s" % [it.get("base", ""), it.get("enchant", "")])
	return "|".join(parts)


## Re-dress after the unit's gear changed (refresh() does this on its own
## when it notices a change).
func refresh_equipment() -> void:
	if character:
		character.refresh_equipment()
		_equip_sig = _signature()
		_place_bar()


func _build_disc() -> void:
	# team disc: player = white ring on black, enemy = solid black
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.42
	cm.bottom_radius = 0.42
	cm.height = 0.02
	disc.mesh = cm
	disc.material_override = BWLook.flat()
	disc.set_instance_shader_parameter("tint", Color(0.08, 0.08, 0.08) if unit.team == "enemy" else Color(0.85, 0.85, 0.85))
	disc.position.y = 0.012
	add_child(disc)
	if unit.team == "player":
		var inner := MeshInstance3D.new()
		var im := CylinderMesh.new()
		im.top_radius = 0.34
		im.bottom_radius = 0.34
		im.height = 0.024
		inner.mesh = im
		inner.material_override = BWLook.flat()
		inner.set_instance_shader_parameter("tint", BWLook.INK)
		inner.position.y = 0.014
		add_child(inner)


func _build_primitive() -> void:
	var col_cloth := BWLook.shade(str(unit.cosmetics.get("clothing_shade", "mid")))
	var hair := BWLook.element_color(unit.element)
	_hip = Node3D.new()
	_hip.position.y = 0.62
	add_child(_hip)
	_leg_l = _limb(_hip, Vector3(-0.07, 0, 0), 0.62, BWLook.INK)
	_leg_r = _limb(_hip, Vector3(0.07, 0, 0), 0.62, BWLook.INK)
	_chest = Node3D.new()
	_hip.add_child(_chest)
	var spine := _segment(Vector3.ZERO, Vector3(0, 0.55, 0), LIMB * 1.25, BWLook.INK)
	_chest.add_child(spine)
	# shirt: a short grey tube on the spine, so clothing tier reads already
	var shirt := _segment(Vector3(0, 0.12, 0), Vector3(0, 0.5, 0), 0.085, col_cloth)
	_chest.add_child(shirt)
	_arm_l = _limb(_chest, Vector3(-0.05, 0.5, 0), 0.5, BWLook.INK)
	_arm_r = _limb(_chest, Vector3(0.05, 0.5, 0), 0.5, BWLook.INK)
	_head = Node3D.new()
	_head.position.y = 0.55 + HEAD_R * 0.95
	_chest.add_child(_head)
	var head := _sphere(HEAD_R, BWLook.WHITE)
	_head.add_child(head)
	var hair_mi := _sphere(HEAD_R * 1.08, hair)
	# Hair frames the face from behind and above (reference panels): the
	# white face stays visible from the front, the colour reads from above.
	hair_mi.scale = Vector3(1.12, 0.8, 1.12)
	hair_mi.position = Vector3(0, HEAD_R * 0.46, -HEAD_R * 0.04)
	_head.add_child(hair_mi)


func show_label(v: bool) -> void:
	_label.visible = v
	if _bar_bg:
		_bar_bg.visible = v
		_bar_fill.visible = v
		_bar_ghost.visible = v
		_hp_label.visible = v


## A billboarded quad that always faces the camera and draws over the scene.
## The fill is left-anchored so scaling x empties it from the right.
func _bar_quad(w: float, h: float, col: Color, priority: int) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.no_depth_test = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	m.render_priority = 10 + priority
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("dim_alpha", col.a)      # BWLook.set_dim fades it
	return mi


func refresh() -> void:
	if character and _signature() != _equip_sig:
		refresh_equipment()
	if character:
		character.set_wounded(unit.alive() and float(unit.hp) < BWAnimator.WOUNDED_HP * maxf(unit.max_hp(), 1))
	_label.text = unit.name
	if _bar_fill:
		# billboards rotate around the node, so the fill is cut in the mesh
		# itself: width f·W, shifted to stay flush with the left of the well
		var f := clampf(float(unit.hp) / maxf(unit.max_hp(), 1), 0.0, 1.0)
		_set_bar(_bar_fill, f)
		if f < _shown_f - 0.001:
			# the lost chunk lingers grey, then drains: you see how much it was
			var tw := create_tween()
			tw.tween_interval(0.35)
			tw.tween_method(func(x: float): _set_bar(_bar_ghost, x), _shown_f, f, 0.45).set_trans(Tween.TRANS_SINE)
		else:
			_set_bar(_bar_ghost, f)
		_shown_f = f
		_hp_label.text = "%d / %d" % [unit.hp, unit.max_hp()]
	visible = unit.alive() or visible
	if has_ward(unit) != (_ward != null):        # ---- D102: the Frost Ward follows the data
		if has_ward(unit):
			set_ward(true)
		elif is_inside_tree():
			ward_break()
		else:
			set_ward(false)


func _set_bar(mi: MeshInstance3D, f: float) -> void:
	# billboards rotate around the node, so a fill is cut in the mesh itself:
	# width f·W, shifted to stay flush with the left of the well
	var q: QuadMesh = mi.mesh
	q.size = Vector2(maxf(BAR_W * f, 0.001), BAR_H)
	q.center_offset = Vector3(-(BAR_W - BAR_W * f) * 0.5, 0, 0)


func _bar() -> String:
	var n := int(round(10.0 * unit.hp / maxf(unit.max_hp(), 1)))
	return "■".repeat(n) + "□".repeat(10 - n)


func _process(delta: float) -> void:
	_t += delta
	if character and unit:
		character.breathing = unit.alive()      # the rig breathes in BWCharacterPose
	elif _hip and unit and unit.alive():
		# idle breathing bob, small, so the figures feel alive between beats
		_chest.position.y = 0.012 * sin(_t * 2.4 + hash(unit.id) % 7)


# ---------------------------------------------------------------- poses
# Angles are radians around X (forward swing) unless noted.

## Element shown on the weapon while it is being used.
const AURA_POSES := { "windup": 0.7, "strike": 1.0, "cast": 1.2, "channel": 1.2 }


func idle() -> void:
	if character:
		pose_named("idle")
		return
	_pose({ "leg_l": 0.05, "leg_r": -0.05, "arm_l": 0.15, "arm_r": -0.1, "lean": 0.0 }, Vector3.ZERO)


func pose_named(p: String) -> void:
	if character:
		var play := p
		if skill != "" and p in ["windup", "strike"]:
			var key := skill.to_lower().replace(" ", "_")
			var sp := ("windup_" + key) if p == "windup" else key
			if character.has_clip(sp):
				play = sp
			if p == "strike":
				skill = ""
		var ok := play in BWCharacterPose.POSE_NAMES or character.has_clip(play)
		character.pose(play if ok else "idle")
		var el := unit.attuned if unit.attuned != "" else unit.element
		if AURA_POSES.has(p) and el != "":
			character.set_aura(el, AURA_POSES[p])
		else:
			character.set_aura("", 0.0)
		return
	if p.begins_with("stricken"):
		p = "hit"                         # the stand-in has one hit pose
	match p:
		"windup": _pose({ "leg_l": 0.3, "leg_r": -0.35, "arm_l": 0.2, "arm_r": 2.4, "lean": -0.18 }, Vector3.ZERO)
		"strike": _pose({ "leg_l": -0.45, "leg_r": 0.4, "arm_l": -0.4, "arm_r": -1.3, "lean": 0.28 }, Vector3.ZERO)
		"cast": _pose({ "leg_l": 0.1, "leg_r": -0.1, "arm_l": 1.6, "arm_r": 1.6, "lean": -0.1 }, Vector3.ZERO)
		"hit": _pose({ "leg_l": 0.25, "leg_r": -0.1, "arm_l": 0.9, "arm_r": 0.7, "lean": -0.35 }, Vector3(0, 0, -0.12))
		"kneel": _pose({ "leg_l": 1.4, "leg_r": -0.2, "arm_l": 0.4, "arm_r": 0.3, "lean": 0.35 }, Vector3(0, -0.25, 0))
		"dodge": _pose({ "leg_l": -0.5, "leg_r": 0.6, "arm_l": 0.6, "arm_r": -0.6, "lean": -0.2 }, Vector3(0.35, 0, -0.1))
		"block": _pose({ "leg_l": 0.25, "leg_r": -0.25, "arm_l": 1.3, "arm_r": 1.5, "lean": -0.12 }, Vector3.ZERO)
		"fumble": _pose({ "leg_l": 0.4, "leg_r": -0.2, "arm_l": 2.0, "arm_r": 0.2, "lean": -0.4 }, Vector3(0, 0, -0.18))
		"fall": _pose({ "leg_l": 0.2, "leg_r": -0.2, "arm_l": 2.4, "arm_r": 2.2, "lean": -1.45 }, Vector3(0, -0.45, -0.3))
		"cheer": _pose({ "leg_l": 0.1, "leg_r": -0.1, "arm_l": 2.9, "arm_r": 2.7, "lean": -0.05 }, Vector3(0, 0.1, 0))
		_: idle()


func _pose(a: Dictionary, offset: Vector3) -> void:
	_leg_l.rotation.x = a.leg_l
	_leg_r.rotation.x = a.leg_r
	_arm_l.rotation.x = -a.arm_l
	_arm_r.rotation.x = -a.arm_r
	_arm_l.rotation.z = -0.12
	_arm_r.rotation.z = 0.12
	_chest.rotation.x = a.lean
	_hip.position = Vector3(0, 0.62, 0) + offset


## True when this unit's weapon has an animation clip for the pose.
func has_clip(p: String) -> bool:
	return character != null and character.has_clip(p)


## Seconds until a named marker (e.g. "hit") of the clip playing now; -1 when
## no clip is playing or the marker is behind the playhead.
func time_to_marker(marker_name: String) -> float:
	if character == null or character.animator == null:
		return -1.0
	return character.animator.time_to(marker_name)


## Root speed (u/s) the walk clip was authored for; 0 = no walk clip.
func walk_speed() -> float:
	if character == null or character.animator == null or not character.has_clip("walk"):
		return 0.0
	return character.animator.walk_speed()


## How this unit moves `distance` (u) over `hexes` hexes: see
## BWAnimator.plan_move (run with start / stop, walk, limp). {} = no clips.
func plan_move(distance: float, hexes: int) -> Dictionary:
	if character == null or character.animator == null:
		return {}
	return character.animator.plan_move(distance, hexes)


## Start a planned move (the gait's pose and the run's step-aligned rate).
func begin_move(plan: Dictionary) -> void:
	if character and character.animator:
		character.animator.begin_move(plan)


## Seconds from the start of a reaction (block, dodge, fumble, ...) to the
## frame its blow lands ("impact"); 0 when it has none.
func lead_to_impact(p: String) -> float:
	if character == null or character.animator == null:
		return 0.0
	var clip := character.animator.clip_of(p)
	return maxf(character.animator.marker_time(clip, "impact"), 0.0) if clip != "" else 0.0


## The meta (markers, engage, shift, ...) of the clip a pose name plays.
func clip_meta_of(p: String) -> Dictionary:
	if character == null or character.animator == null:
		return {}
	var clip := character.animator.clip_of(p)
	return character.animator.clip_meta(clip) if clip != "" else {}


## World position of the weapon's tip (blade tip, staff head, muzzle, bow
## centre): where projectiles leave from. Falls back to chest height.
func weapon_tip() -> Vector3:
	if character and character.weapon and character.poser and not character.poser.globals.is_empty():
		var hk := "hand_l" if character.poser.hold_hand == "l" else "hand_r"
		var sock := character.poser.socket_l if hk == "hand_l" else character.poser.socket_r
		var g: Transform3D = character.rig.skeleton.global_transform * (character.poser.globals[hk] as Transform3D) * sock
		return g * BWWeaponView.v3(character.weapon.meta.get("tip", [0, 1, 0]))
	return global_position + Vector3(0, 1.2 * scale.y, 0)


## The weapon hold standing in ("guard", "side", "shoulder", "ground",
## "reverse"); "guard" without clips.
func hold() -> String:
	if character == null or character.animator == null:
		return "guard"
	return character.animator.hold


## Daggers: "forward" or "reverse" (the icepick grip).
func grip() -> String:
	if character == null or character.animator == null:
		return "forward"
	return character.animator.grip()


## Change to a hold or play a handling action now (tools, tests).
func handle(what: String) -> bool:
	return character != null and character.animator != null and character.animator.handle(what)


func face(world_target: Vector3) -> void:
	var d := world_target - global_position
	d.y = 0
	if d.length() > 0.01:
		rotation.y = atan2(d.x, d.z)


# ---------------------------------------------------------------- builders

func _limb(parent: Node3D, at: Vector3, length: float, col: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = at
	parent.add_child(pivot)
	pivot.add_child(_segment(Vector3.ZERO, Vector3(0, -length, 0), LIMB, col))
	return pivot


func _segment(a: Vector3, b: Vector3, r: float, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = r
	cap.height = (b - a).length() + 2 * r
	cap.radial_segments = 8
	cap.rings = 2
	mi.mesh = cap
	mi.position = (a + b) / 2.0
	mi.material_override = BWLook.flat()
	mi.set_instance_shader_parameter("tint", col)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ol := MeshInstance3D.new()
	ol.mesh = cap
	ol.material_override = BWLook.outline(0.014, Color.WHITE if col.v < 0.3 else Color.BLACK)
	mi.add_child(ol)
	return mi


func _sphere(r: float, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2
	sm.radial_segments = 20
	sm.rings = 10
	mi.mesh = sm
	mi.material_override = BWLook.flat()
	mi.set_instance_shader_parameter("tint", col)
	var ol := MeshInstance3D.new()
	ol.mesh = sm
	ol.material_override = BWLook.outline(0.022)
	mi.add_child(ol)
	return mi


# ---- D102 Frost Ward (presentation lane, marked edit) ----

## A faint white hex shield on a warded unit: a crisp hex ring at the feet
## (white over an ink under-stroke, so it reads on the white tiles), six
## faint walls rising and fading, bright corner seams, and a slow glint
## climbing them. `ward_break()` shatters it: the walls go, shards fly out
## and fall, a ring flashes outward. The ward follows the unit's data on
## every refresh() (read defensively: the rules lane may keep it as a status,
## a field or an effect), so a missed event cannot leave it stale.
var _ward: MeshInstance3D
static var _ward_mat: ShaderMaterial
static var _shard_mat: ShaderMaterial
const WARD_R := 0.66
const WARD_H := 1.9


static func has_ward(u: BWUnit) -> bool:
	if u == null or not u.alive():
		return false
	for k in ["frost_ward", "ward"]:
		if u.statuses.has(k):
			return true
	var w: Variant = u.get("ward")
	# (not `fx`: the Frost Ward perk sits there for the whole fight, the ward itself breaks)
	return (w is bool and w) or ((w is int or w is float) and w > 0) or (w is Dictionary and not (w as Dictionary).is_empty())


func set_ward(on: bool) -> void:
	if on and _ward == null:
		_ward = MeshInstance3D.new()
		_ward.name = "frost_ward"
		_ward.mesh = _ward_mesh()
		_ward.material_override = _ward_material()
		_ward.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ward.set_instance_shader_parameter("grow", 0.0)
		add_child(_ward)
		var w := _ward
		var tw := create_tween()
		tw.tween_method(func(g: float):
			if is_instance_valid(w):
				w.set_instance_shader_parameter("grow", g), 0.0, 1.0, 0.35)
	elif not on and _ward != null:
		_ward.queue_free()
		_ward = null


func warded() -> bool:
	return _ward != null


## The ward shatters: shards burst out from the walls, tumble and fall;
## a hex ring flashes outward at chest height; the shield is gone.
func ward_break() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(unit.id + "|ward") if unit else 7
	set_ward(false)
	var s := maxf(scale.y, 0.01)
	var burst := Node3D.new()
	burst.name = "ward_burst"
	add_child(burst)
	# the flash ring
	var ring := MeshInstance3D.new()
	ring.mesh = _ward_mesh(true)
	ring.material_override = _ward_material()
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.set_instance_shader_parameter("grow", 1.0)
	ring.set_instance_shader_parameter("flash", 1.0)
	burst.add_child(ring)
	var rt := create_tween().set_parallel(true)
	rt.tween_property(ring, "scale", Vector3(1.9, 0.6, 1.9), 0.3).from(Vector3.ONE).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	rt.tween_method(func(a: float):
		if is_instance_valid(ring):
			ring.set_instance_shader_parameter("flash", a), 1.0, 0.0, 0.3)
	# shards: thin glass slivers from the walls, out and up, then falling
	for i in 22:
		var sh := MeshInstance3D.new()
		var a := TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / 22.0
		var y := rng.randf_range(0.15, WARD_H * 0.9)
		var size := rng.randf_range(0.12, 0.28)
		sh.mesh = _shard_mesh(size, rng.randf_range(0.5, 1.6))
		sh.material_override = _shard_material()
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var from := Vector3(cos(a) * WARD_R, y, sin(a) * WARD_R)
		sh.position = from
		sh.rotation = Vector3(rng.randf_range(-PI, PI), -a, rng.randf_range(-PI, PI))
		burst.add_child(sh)
		var out := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.9, 1.8) / s
		var up := rng.randf_range(0.6, 1.6) / s
		var spin := Vector3(rng.randf_range(-12, 12), rng.randf_range(-8, 8), rng.randf_range(-12, 12))
		var life := rng.randf_range(0.5, 0.75)
		var r0 := sh.rotation
		var tw := create_tween()
		tw.tween_method(func(t: float):
			if not is_instance_valid(sh):
				return
			# ballistic: out, up, gravity; the floor stops the fall
			var p := from + out * t + Vector3(0, up * t - 4.9 / s * t * t, 0)
			p.y = maxf(p.y, 0.03)
			sh.position = p
			sh.rotation = r0 + spin * t
			sh.set_instance_shader_parameter("fade", clampf((t - life * 0.55) / (life * 0.45), 0.0, 1.0)), 0.0, life, life)
	var done := create_tween()
	done.tween_interval(0.8)
	done.tween_callback(burst.queue_free)


## The shield: six walls (UV.x around 0..6, UV.y up 0..1). `ring_only`:
## a short band (the break flash).
static func _ward_mesh(ring_only: bool = false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := 0.35 if ring_only else WARD_H
	var y0 := 0.9 if ring_only else 0.02
	for i in 6:
		var a0 := deg_to_rad(60.0 * i + 30.0)
		var a1 := deg_to_rad(60.0 * (i + 1) + 30.0)
		var p0 := Vector3(cos(a0) * WARD_R, y0, sin(a0) * WARD_R)
		var p1 := Vector3(cos(a1) * WARD_R, y0, sin(a1) * WARD_R)
		var q0 := p0 + Vector3(0, h, 0)
		var q1 := p1 + Vector3(0, h, 0)
		var u0 := float(i)
		var u1 := float(i + 1)
		for v in [[p0, Vector2(u0, 0)], [p1, Vector2(u1, 0)], [q1, Vector2(u1, 1)], [p0, Vector2(u0, 0)], [q1, Vector2(u1, 1)], [q0, Vector2(u0, 1)]]:
			st.set_uv(v[1])
			st.add_vertex(v[0])
	return st.commit()


static func _shard_mesh(size: float, stretch: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_uv(Vector2(0, 0))
	st.add_vertex(Vector3(-size * 0.5, 0, 0))
	st.set_uv(Vector2(1, 0))
	st.add_vertex(Vector3(size * 0.5, 0, 0))
	st.set_uv(Vector2(0, 1))
	st.add_vertex(Vector3(size * 0.1, size * stretch, 0))
	return st.commit()


static func _ward_material() -> ShaderMaterial:
	if _ward_mat == null:
		var sh := Shader.new()
		sh.code = WARD_SHADER
		_ward_mat = ShaderMaterial.new()
		_ward_mat.shader = sh
	return _ward_mat


static func _shard_material() -> ShaderMaterial:
	if _shard_mat == null:
		var sh := Shader.new()
		sh.code = SHARD_SHADER
		_shard_mat = ShaderMaterial.new()
		_shard_mat.shader = sh
	return _shard_mat


const WARD_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;
instance uniform float dim = 0.0;
instance uniform float grow = 1.0;
instance uniform float flash = 0.0;
void fragment() {
	float x = UV.x;
	float y = UV.y;
	float seam = 1.0 - smoothstep(0.0, 0.035, abs(x - round(x)));
	float rim = 1.0 - smoothstep(0.0, 0.035, y);
	float top = (1.0 - smoothstep(0.0, 0.02, abs(y - 0.985))) * 0.55;
	float wall = 0.15 * pow(1.0 - y, 1.4);
	float g = fract(TIME * 0.35 + x * 0.04);
	float glint = (1.0 - smoothstep(0.0, 0.05, abs(y - g))) * 0.25 * (1.0 - y);
	float a = max(max(rim, wall + glint), max(seam * 0.7 * (1.0 - y * 0.6), top));
	float ink = (1.0 - smoothstep(0.03, 0.06, y)) * (1.0 - rim);
	vec3 col = mix(vec3(0.97, 0.99, 1.0), vec3(0.03, 0.05, 0.08), ink);
	a = max(a, ink * 0.8);
	a = max(a * (0.85 + 0.15 * sin(TIME * 2.4)), flash * (0.9 - 0.5 * y));
	a *= step(y, grow * 1.05) * (1.0 - dim);
	if (a < 0.003) { discard; }
	ALBEDO = mix(col, vec3(1.0), flash);
	ALPHA = clamp(a, 0.0, 1.0);
}
"""

const SHARD_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;
instance uniform float dim = 0.0;
instance uniform float fade = 0.0;
void fragment() {
	float e = min(min(UV.x, UV.y), 1.0 - UV.x - UV.y);
	float ink = 1.0 - smoothstep(0.06, 0.11, e);
	ALBEDO = mix(vec3(0.96, 0.98, 1.0), vec3(0.03, 0.05, 0.08), ink);
	ALPHA = (1.0 - fade) * (1.0 - dim) * (0.95 - 0.25 * (1.0 - ink));
}
"""

# ---- end D102 ----
