extends SceneTree
## Review renders for the clip matrix, from the real Godot renderer and the
## game's shaders. Needs a window (not --headless):
##
##   godot --path game --resolution 1600x900 -s res://tools/anim_preview.gd -- --only <what> [--style s] [--clip c]
##     sheets     design/art/anim_<style>_sheet_<n>.png: every clip of a style,
##                every 2nd frame, 3/4 row and side row per clip
##     strip      design/art/anim_<style>_<clip>_strip.png: one clip, big cells (review)
##     gifs       PNG frames for anim_<clip>.gif: all eight styles side by side
##     showcase   PNG frames for anim_showcase_<style>.gif: run in, strike, the
##                opponent reacts, both settle, an idle variant
##     stricken   PNG frames for anim_stricken_variants.gif (the five hit
##                variants side by side, two styles) and
##                design/art/anim_stricken_variants_strip.png (every 2nd frame)
##     idle_calm  PNG frames for anim_idle_calm.gif: eight characters (one per
##                style) standing in their home idle for 10 s, variants on (D65)
##     handling   PNG frames for anim_handling_<style>.gif (D80): every hold
##                in and out, every handling action, then a hold -> strike
##                (the hands lead back to the guard) and a hit
##     shots      PNG frames for anim_bow_shot.gif and anim_pistol_shot.gif
##                (draw with the nocked arrow -> release -> flight -> stick;
##                the pistol's muzzle flash and tracer) and projectiles.png
##   ... --frames <dir> (GIF frames), --out <dir> (PNGs)
##   python game/tools/anim_gif.py <frames dir> design/art          # PNG frames -> GIFs
##
## Overlays (sheets, strips): cyan dots = head path, blue = weapon fist,
## orange = weapon tip, violet = the other hand; one dot per authoring frame
## (1/24 s), so dot spacing is the timing; the current frame is ringed.
## Dashed line = floor, ticks every 0.25 u; green bar = a locked foot (red mm
## = its slide, shown when >= 2 mm).

const DT := 1.0 / 60.0
## One roster character per style; axe clips use an axe user of the style.
const REPS := { "one": "stryker", "heavy": "della", "polearm": "rui", "spear": "bob",
	"staff": "jericho", "pair": "rem", "bow": "gail", "pistol": "sala", "fists": "will" }
## No roster character starts with fists (D76): the fists rep wears hand wraps.
const REP_WEAPON := { "fists": "hand_wraps" }
const AXE_REPS := { "one": "kai", "heavy": "burt" }
## Showcase: the opponent and the reaction each style's strike gets.
const SHOW := {
	"one": ["apollyon", "fumble"], "heavy": ["demeter", "kneel"], "polearm": ["stryker", "block"],
	"spear": ["will", "dodge"], "staff": ["aureli", "hit"], "pair": ["alexandra", "fumble"],
	"bow": ["burt", "hit"], "pistol": ["dragtol", "dodge"],
}

var out_dir := ""
var frames_dir := ""
var only := ""
var style_only := ""
var clip_only := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = _arg(args, "--out", ProjectSettings.globalize_path("res://").path_join("../design/art").simplify_path())
	frames_dir = _arg(args, "--frames", ProjectSettings.globalize_path("user://anim_frames"))
	only = _arg(args, "--only", "sheets")
	style_only = _arg(args, "--style", "")
	clip_only = _arg(args, "--clip", "")
	DirAccess.make_dir_recursive_absolute(out_dir)
	DirAccess.make_dir_recursive_absolute(frames_dir)
	_run.call_deferred()


func _arg(args: PackedStringArray, k: String, d: String) -> String:
	var i := args.find(k)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else d


func _styles() -> Array:
	return [style_only] if style_only != "" else Array(BWAnimClips.SETS)


func _clips(st: String) -> Array:
	var lib := BWAnimClips.load_set(st)
	var out: Array = []
	for n in lib.get_animation_list():
		if clip_only == "" or str(n) == clip_only:
			out.append(str(n))
	return out


func _run() -> void:
	match only:
		"sheets":
			for st in _styles():
				await _sheet(st)
		"strip":
			for st in _styles():
				for clip in _clips(st):
					await _strip(st, clip)
		"gifs":
			var names: Array = []
			for n in BWAnimClips.load_set("heavy").get_animation_list():
				if clip_only == "" or str(n) == clip_only:
					names.append(str(n))
			for n in names:
				await _lineup(n)
		"showcase":
			for st in _styles():
				await _showcase(st)
		"clipgif":
			# D510: one character, one clip (or several, comma-separated), two
			# cameras (cutscene-like 3/4 and side): frames for anim_gif.py
			for clip in clip_only.split(","):
				await _clip_gif(style_only, clip, _arg(OS.get_cmdline_user_args(), "--rep", ""), _arg(OS.get_cmdline_user_args(), "--name", ""))
		"stricken":
			await _variants_gif()
			await _variants_strip(style_only if style_only != "" else "one")
		"idle_calm":
			await _idle_calm()
		"handling":
			for st in _styles():
				await _handling(st)
		"shots":
			if clip_only != "lineup":
				await _shot_gif("bow")
				await _shot_gif("pistol")
			await _projectile_lineup()
	quit(0)


func _unit_for(st: String, clip: String) -> BWUnit:
	var id: String = REPS[st]
	if clip in ["strike_axe", "walk_heavy", "run_heavy", "strike_hook", "strike_axe_jab", "strike_sweep_under", "strike_throw_under"] and AXE_REPS.has(st) \
			or (clip.begins_with("strike_smash") and st == "one"):   # D510: the axe alternates
		id = AXE_REPS[st]
	var u := BWRosterKits.unit(id)
	if REP_WEAPON.has(st):
		u.weapon_model = REP_WEAPON[st]
		u.equipment.erase("main_hand")
	return u


# ------------------------------------------------------------------ staging

func _tile(parent: Node, at: Vector3, tint: Color = BWLook.PAPER) -> void:
	var tile := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.97
	cm.bottom_radius = 0.97
	cm.height = 0.35
	cm.radial_segments = 6
	tile.mesh = cm
	tile.material_override = BWLook.flat()
	tile.set_instance_shader_parameter("tint", tint)
	tile.position = at + Vector3(0, -0.175, 0)
	tile.rotation.y = PI / 6
	parent.add_child(tile)
	var rim := MeshInstance3D.new()
	rim.mesh = cm
	rim.material_override = BWLook.outline(0.03, Color.BLACK)
	tile.add_child(rim)


func _viewport(size: Vector2i, sky: bool, grey := 0.6) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	root.add_child(vp)
	var we := WorldEnvironment.new()
	if sky:
		we.environment = BWLook.starfield_environment()
	else:
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(grey, grey, grey)
		we.environment = e
	vp.add_child(we)
	return vp


func _character(parent: Node, u: BWUnit) -> BWCharacter:
	var c := BWCharacter.create(u)
	parent.add_child(c)
	c.set_process(false)          # stepped by hand, deterministic
	c.pose("idle", 0.0)
	if c.animator:
		c.animator.rotate_idles = false
	return c


func _step(c: BWCharacter, n: int = 1) -> void:
	for i in n:
		c._process(DT)


func _ortho(vp: SubViewport, yaw: float, pitch: float, size: float) -> Camera3D:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = size
	cam.near = 0.05
	cam.far = 60.0
	vp.add_child(cam)
	cam.set_meta("yaw", yaw)
	cam.set_meta("pitch", pitch)
	cam.make_current()
	return cam


func _aim_cam(cam: Camera3D, focus: Vector3, dist: float = 20.0) -> void:
	var b := Basis.from_euler(Vector3(float(cam.get_meta("pitch")), float(cam.get_meta("yaw")), 0))
	cam.global_transform = Transform3D(b, focus + b.z * dist)


func _frame() -> void:
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw


# --------------------------------------------------------------- scenarios

## Push a clip directly (tools): the animator's own blend; one-shots return
## to idle at their end.
func _play_clip(c: BWCharacter, clip: String, pending: String = "") -> void:
	var an := c.animator
	var top: Dictionary = an.layers.back() if not an.layers.is_empty() else {}
	an._push(an._clip_layer(clip), -1.0, top)
	an.current = "idle" if clip.begins_with("idle") else clip
	an.pending = pending


## What to play and how the root moves for one clip, replayed exactly in
## every pass. setup(c) runs after a settled idle; drive(c, i) before step i.
func _scenario(c0: BWCharacter, clip: String) -> Dictionary:
	var an := c0.animator
	var a := an.library.get_animation(clip)
	var m: Dictionary = a.get_meta("bw", {})
	var mk: Dictionary = m.get("markers", {})
	var sc := { "steps": int(round((a.length + (0.0 if a.loop_mode != Animation.LOOP_NONE else 0.5)) / DT)), "moving": false, "wide": false,
		"turn": 0.0 }
	sc.setup = func(c: BWCharacter) -> void: _play_clip(c, clip)
	sc.drive = func(_c: BWCharacter, _i: int) -> void: pass
	if m.has("gait"):
		var sp := float(m.speed)
		sc.moving = true
		sc.setup = func(c: BWCharacter) -> void:
			c.animator.walk_rate = 1.0
			c.animator.layers = [c.animator._clip_layer(clip)]
			c.animator.current = "walk"
			for k in int(round(2.0 * a.length / DT)):
				c.position.z += sp * DT
				_step(c)
		sc.drive = func(c: BWCharacter, _i: int) -> void: c.position.z += sp * DT
	elif m.has("root_s"):
		var curve: Array = m.root_s
		var hz := float(m.get("root_hz", BWAnimClips.FPS))
		var run_clip := "run"
		var run_a := an.library.get_animation(run_clip)
		var V := float(run_a.get_meta("bw").speed)
		sc.moving = true
		if clip == "run_start":
			sc.steps = int(round((a.length + 0.45) / DT))
			sc.setup = func(c: BWCharacter) -> void:
				c.animator.walk_rate = 1.0
				_play_clip(c, clip, "run")
			sc.drive = func(c: BWCharacter, i: int) -> void:
				var t := i * DT
				c.position.z = BWAnimator._curve(curve, t * hz) if t <= a.length else float(curve.back()) + V * (t - a.length)
		else:
			sc.steps = int(round((a.length + 0.5) / DT))
			var half := clip == "run_stop_r"
			sc.setup = func(c: BWCharacter) -> void:
				c.animator.walk_rate = 1.0
				c.animator.layers = [c.animator._clip_layer(run_clip)]
				c.animator.current = "run"
				var pre := 2.0 * run_a.length + (run_a.length * 0.5 if half else 0.0)
				for k in int(round(pre / DT)):
					c.position.z += V * DT
					_step(c)
				c.animator.layers.back().t = run_a.length * (0.5 if half else 0.0)
				sc["z0"] = c.position.z
				_play_clip(c, clip)
			sc.drive = func(c: BWCharacter, i: int) -> void:
				c.position.z = float(sc.z0) + BWAnimator._curve(curve, minf(i * DT, a.length) * hz)
	elif clip.begins_with("turn_"):
		sc.setup = func(c: BWCharacter) -> void:
			c.rotation.y += PI / 2 * (1.0 if clip == "turn_l" else -1.0)
	elif mk.has("launch") and mk.has("hop_start"):
		# airborne windows: the dash (strikes) or the dodge shift
		sc.wide = mk.has("hit")
		var shift: Vector3 = m.get("shift", Vector3.ZERO)
		var gap := BWAnimClips.HEX_STEP
		var dash := Vector3(0, 0, gap * clampf(1.0 - float(m.get("engage", gap)) / gap, 0.0, 0.42)) if shift == Vector3.ZERO else shift
		sc.moving = dash.length() > 0.01
		sc.drive = func(c: BWCharacter, i: int) -> void:
			var t := i * DT
			var out := 0.0
			if t >= float(mk.launch):
				out = smoothstep(float(mk.launch), float(mk.land), t)
			if t >= float(mk.hop_start):
				out = 1.0 - smoothstep(float(mk.hop_start), float(mk.hop_end), t)
			c.position = dash * out
	elif mk.has("release"):
		sc.wide = true
	return sc


func _record(c: BWCharacter, i: int) -> Dictionary:
	var sk := c.rig.skeleton
	var W := sk.global_transform
	var G := c.poser.globals
	var hk := "hand_l" if c.poser.hold_hand == "l" else "hand_r"
	var other := "hand_r" if hk == "hand_l" else "hand_l"
	var sock: Transform3D = (G[hk] as Transform3D) * (c.poser.socket_l if hk == "hand_l" else c.poser.socket_r)
	var tip := BWWeaponView.v3(c.weapon.meta.get("tip", [0, 1, 0])) if c.weapon else Vector3.UP
	var r := {
		"t": i * DT,
		"head": W * ((G.head as Transform3D) * Vector3(0, 0.26, 0)),
		"fist": W * sock.origin,
		"tip": W * (sock * tip),
		"hand_l": W * ((G[other] as Transform3D) * Vector3(0, 0.03, 0)),
		"foot_l": W * (G.foot_l as Transform3D).origin,
		"foot_r": W * (G.foot_r as Transform3D).origin,
		"root": c.global_position,
		"lock_l": (c.animator._lock.l as Dictionary).duplicate(),
		"lock_r": (c.animator._lock.r as Dictionary).duplicate(),
		"clip": c.animator.top_clip(),
	}
	for sd in ["l", "r"]:
		var fl: Dictionary = c.animator.last_pose["foot_" + sd]
		r["g_" + sd] = W * BWAnimator.ground_point(fl.pos, fl.rot)
		r["contact_" + sd] = float(c.animator.last_pose.get("contact_" + sd, 1.0))
	return r


# ------------------------------------------------------------------- shots

class Overlay:
	extends Node2D
	var cmds: Array = []

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		for c in cmds:
			match c[0]:
				"dot": draw_circle(c[1], c[2], c[3])
				"ring": draw_arc(c[1], c[2], 0, TAU, 16, c[3], 2.0)
				"line": draw_line(c[1], c[2], c[3], c[4])
				"dash": draw_dashed_line(c[1], c[2], c[3], c[4], 6.0)
				"rect": draw_rect(c[1], c[2])
				"text": draw_string(font, c[1], c[2], HORIZONTAL_ALIGNMENT_LEFT, -1, c[4], c[3])


## Render one clip as cells (every 2nd authoring frame) from two
## orthographic cameras. Returns {shots: [[img_a, img_b, proj_a, proj_b, label]], meta}.
func _shots(st: String, clip: String, cell: Vector2i, size: float) -> Dictionary:
	var u := _unit_for(st, clip)
	var vp_a := _viewport(cell, false)
	var vp_b := SubViewport.new()
	vp_b.size = cell
	vp_b.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp_b.msaa_3d = Viewport.MSAA_4X
	root.add_child(vp_b)
	vp_b.world_3d = vp_a.find_world_3d()
	var stage := Node3D.new()
	vp_a.add_child(stage)
	for k in range(-3, 6):
		_tile(stage, Vector3(0, 0, k * BWAnimClips.HEX_STEP))
	var cam_a := _ortho(vp_a, deg_to_rad(-45.0), deg_to_rad(-12.0), size)
	var cam_b := _ortho(vp_b, deg_to_rad(-90.0), 0.0, size)
	# pass 1: the paths
	var c := _character(stage, u)
	_step(c, int(0.5 / DT))
	var sc := _scenario(c, clip)
	sc.setup.call(c)
	var recs: Array = [_record(c, 0)]
	for i in range(1, int(sc.steps) + 1):
		sc.drive.call(c, i)
		_step(c)
		recs.append(_record(c, i))
	c.free()
	# pass 2: the same run, a render every 2nd authoring frame
	c = _character(stage, u)
	_step(c, int(0.5 / DT))
	sc = _scenario(c, clip)
	sc.setup.call(c)
	var moving: bool = sc.moving
	var focus_off := Vector3(0, 1.15, 0.35 if sc.wide else 0.05)
	var every := int(round((2.0 / BWAnimClips.FPS) / DT))
	var shots: Array = []
	var meta: Dictionary = c.animator.clip_meta(clip).duplicate()
	var marks: Dictionary = meta.get("markers", {})
	for i in int(sc.steps) + 1:
		if i > 0:
			sc.drive.call(c, i)
			_step(c)
		if i % every != 0:
			continue
		var focus := (c.global_position if moving else Vector3.ZERO) + focus_off
		_aim_cam(cam_a, focus)
		_aim_cam(cam_b, focus)
		await _frame()
		var r: Dictionary = recs[i]
		var pj := []
		for cam in [cam_a, cam_b]:
			var pts := {}
			for key in ["head", "fist", "tip", "hand_l"]:
				var arr: Array = []
				for f in int(floor(float(recs.back().t) * BWAnimClips.FPS)) + 1:
					var j := mini(int(round(f / BWAnimClips.FPS / DT)), recs.size() - 1)
					var p: Vector3 = recs[j][key]
					if moving:
						p += c.global_position - (recs[j].root as Vector3)
					arr.append((cam as Camera3D).unproject_position(p))
				pts[key] = arr
			var feet := {}
			for s in ["l", "r"]:
				var L: Dictionary = r["lock_" + s]
				var fp: Vector3 = r["foot_" + s]
				var slide := -1.0
				if L.get("on", false):
					var lw: Vector3 = L.world
					var gw: Vector3 = r["g_" + s]
					slide = Vector2(gw.x - lw.x, gw.z - lw.z).length() * 1000.0
				feet[s] = [(cam as Camera3D).unproject_position(Vector3(fp.x, 0, fp.z)), L.get("on", false), slide, float(r["contact_" + s])]
			var floor_pts := [(cam as Camera3D).unproject_position(c.global_position + Vector3(0, 0, -4)), (cam as Camera3D).unproject_position(c.global_position + Vector3(0, 0, 4))]
			var ticks: Array = []
			var z0 := floorf(c.global_position.z / 0.25) * 0.25
			for k in range(-10, 11):
				ticks.append((cam as Camera3D).unproject_position(Vector3(c.global_position.x, 0, z0 + k * 0.25)))
			pj.append({ "pts": pts, "feet": feet, "floor": floor_pts, "ticks": ticks, "now": int(round(float(r.t) * BWAnimClips.FPS)) })
		var f := int(round(float(r.t) * BWAnimClips.FPS))
		var label := "f%d" % f
		for mname in marks:
			if mname != "pose" and absi(int(round(float(marks[mname]) * BWAnimClips.FPS)) - f) <= 0:
				label += " " + str(mname).to_upper()
		if str(r.clip) != clip:
			label += " [%s]" % str(r.clip)
		shots.append([vp_a.get_texture().get_image(), vp_b.get_texture().get_image(), pj[0], pj[1], label])
	c.free()
	vp_a.queue_free()
	vp_b.queue_free()
	meta["unit"] = u.name
	return { "shots": shots, "meta": meta }


func _overlay_cell(ov: Overlay, at: Vector2, cell: Vector2i, pj: Dictionary, small: bool) -> void:
	var clipr := Rect2(at, Vector2(cell))
	ov.cmds.append(["dash", at + pj.floor[0], at + pj.floor[1], Color(0, 0, 0, 0.7), 1.5])
	for t in pj.ticks:
		var p: Vector2 = at + (t as Vector2)
		if clipr.has_point(p):
			ov.cmds.append(["line", p + Vector2(0, -3), p + Vector2(0, 4), Color(0, 0, 0, 0.45), 1.0])
	var cols := { "head": Color(0.0, 0.85, 0.95), "fist": Color(0.1, 0.3, 0.95), "tip": Color(1.0, 0.55, 0.0), "hand_l": Color(0.6, 0.2, 0.8) }
	var now := int(pj.now)
	var r := 1.4 if small else 1.8
	for k in cols:
		var arr: Array = pj.pts[k]
		for i in arr.size():
			var p: Vector2 = at + (arr[i] as Vector2)
			if not clipr.grow(-2).has_point(p):
				continue
			ov.cmds.append(["dot", p, r + 0.8, Color(0, 0, 0, 0.8)])
			ov.cmds.append(["dot", p, r, cols[k]])
		if now < arr.size():
			var p: Vector2 = at + (arr[now] as Vector2)
			if clipr.has_point(p):
				ov.cmds.append(["ring", p, 4.5, Color.BLACK])
	for s in ["l", "r"]:
		var fe: Array = pj.feet[s]
		var p: Vector2 = at + (fe[0] as Vector2)
		if fe[1]:
			ov.cmds.append(["rect", Rect2(p + Vector2(-8, 3), Vector2(16, 4)), Color(0.0, 0.75, 0.2)])
			if float(fe[2]) >= 2.0:
				ov.cmds.append(["text", p + Vector2(9, 15), "%d" % int(fe[2]), Color(0.75, 0, 0), 11])


## Compose rows of shots into one image and save it.
func _compose(path: String, title: String, rows: Array, cell: Vector2i, per_row: int, small: bool) -> void:
	var head_h := 30
	var lab_h := 18
	var h := head_h
	for r in rows:
		var n: int = (r.shots as Array).size()
		h += int(ceil(n / float(per_row))) * (cell.y * 2 + lab_h) + 22
	var size := Vector2i(cell.x * per_row, h)
	var vp := SubViewport.new()
	vp.size = size
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color(0.6, 0.6, 0.6)
	bg.size = Vector2(size)
	vp.add_child(bg)
	var ov := Overlay.new()
	ov.cmds.append(["text", Vector2(8, 21), title, Color.BLACK, 17])
	var y := head_h
	for r in rows:
		var meta: Dictionary = r.meta
		var marks: Dictionary = meta.get("markers", {})
		var ms := PackedStringArray()
		for k in marks:
			if k != "pose":
				ms.append("%s@f%d" % [k, int(round(float(marks[k]) * BWAnimClips.FPS))])
		ov.cmds.append(["text", Vector2(6, y + 16), "%s   %d f (%.2f s)%s   %s   %s" % [r.clip, int(meta.get("frames", 0)),
			float(meta.get("frames", 0)) / BWAnimClips.FPS, "  loop" if meta.get("loop", false) else "", ", ".join(ms), meta.get("unit", "")], Color(0.05, 0.05, 0.3), 14])
		y += 22
		var shots: Array = r.shots
		for n in shots.size():
			var band := n / per_row
			var col := n % per_row
			for v in 2:
				var tr := TextureRect.new()
				tr.texture = ImageTexture.create_from_image(shots[n][v])
				var at := Vector2(col * cell.x, y + band * (cell.y * 2 + lab_h) + v * cell.y)
				tr.position = at
				vp.add_child(tr)
				_overlay_cell(ov, at, cell, shots[n][2 + v], small)
			ov.cmds.append(["text", Vector2(col * cell.x + 4, y + band * (cell.y * 2 + lab_h) + cell.y * 2 + 13), shots[n][4], Color.BLACK, 12])
		y += int(ceil(shots.size() / float(per_row))) * (cell.y * 2 + lab_h)
	vp.add_child(ov)
	await _frame()
	vp.get_texture().get_image().save_png(path)
	print("saved ", path)
	vp.queue_free()


## Every clip of a style on pages of 5 clips: 3/4 and side rows per clip.
func _sheet(st: String) -> void:
	var cell := Vector2i(150, 170)
	var clips := _clips(st)
	var page := 0
	var rows: Array = []
	for i in clips.size():
		var r := await _shots(st, clips[i], cell, 3.4)
		r["clip"] = clips[i]
		rows.append(r)
		if rows.size() == 5 or i == clips.size() - 1:
			page += 1
			await _compose(out_dir.path_join("anim_%s_sheet_%d.png" % [st, page]),
				"%s set: page %d   (cells every 2 f; rows 3/4 and side; cyan head, blue fist, orange tip, violet other hand)" % [st, page], rows, cell, 26, true)
			rows.clear()


func _strip(st: String, clip: String) -> void:
	var cell := Vector2i(240, 300)
	var r := await _shots(st, clip, cell, 3.1)
	r["clip"] = clip
	await _compose(out_dir.path_join("anim_%s_%s_strip.png" % [st, clip]), "%s / %s" % [st, clip], [r], cell, 14, false)


# --------------------------------------------------------------------- GIFs

## One clip on all eight styles at once: 8 viewports tiled 4 x 2.
func _lineup(clip: String) -> void:
	var dir := frames_dir.path_join("anim_" + clip)
	_clean(dir)
	var cell := Vector2i(300, 300)
	var entries: Array = []
	for st in BWAnimClips.SETS:
		var lib := BWAnimClips.load_set(st)
		if not lib.has_animation(clip):
			continue
		var vp := _viewport(cell, true)
		var stage := Node3D.new()
		vp.add_child(stage)
		for k in range(-2, 9):
			_tile(stage, Vector3(0, 0, k * BWAnimClips.HEX_STEP))
		var c := _character(stage, _unit_for(st, clip))
		var cam := Camera3D.new()
		cam.fov = 30.0
		vp.add_child(cam)
		cam.make_current()
		var lbl := Label.new()
		lbl.text = "%s  %s" % [st, c.unit.name]
		lbl.position = Vector2(8, 4)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		vp.add_child(lbl)
		_step(c, 30)
		entries.append({ "vp": vp, "c": c, "cam": cam, "sc": _scenario(c, clip) })
	var steps := 0
	for e in entries:
		e.sc.setup.call(e.c)
		steps = maxi(steps, int(e.sc.steps))
	var lib0 := BWAnimClips.load_set("heavy").get_animation(clip) if BWAnimClips.load_set("heavy").has_animation(clip) else null
	if lib0 and lib0.loop_mode != Animation.LOOP_NONE:
		steps = maxi(steps, int(round(maxf(lib0.length * 2.0, 1.6) / DT)))
	var cols := 4
	var rows := int(ceil(entries.size() / float(cols)))
	var frame := 0
	for i in steps + 1:
		for e in entries:
			if i > 0:
				e.sc.drive.call(e.c, i)
				_step(e.c)
		if i % 2 != 0:
			continue
		for e in entries:
			var c: BWCharacter = e.c
			var focus := c.global_position + Vector3(0, 1.05, 0.2)
			var b := Basis.from_euler(Vector3(deg_to_rad(-10.0), deg_to_rad(-62.0), 0))
			(e.cam as Camera3D).global_transform = Transform3D(b, focus + b.z * 8.6)
		await _frame()
		var img := Image.create(cell.x * cols, cell.y * rows, false, Image.FORMAT_RGB8)
		for k in entries.size():
			var im: Image = (entries[k].vp as SubViewport).get_texture().get_image()
			im.convert(Image.FORMAT_RGB8)
			img.blit_rect(im, Rect2i(Vector2i.ZERO, cell), Vector2i((k % cols) * cell.x, (k / cols) * cell.y))
		img.save_png(dir.path_join("%04d.png" % frame))
		frame += 1
	print("frames ", dir, " ", frame)
	for e in entries:
		e.c.free()
		e.vp.queue_free()


## D510: one clip on one character from two cameras (the cutscene's 3/4
## and a side view), the root driven as in combat (the dash and hop home),
## a beat of idle before and after. Frames -> <frames>/anim_<name>/.
func _clip_gif(st: String, clip: String, rep: String, gif_name: String) -> void:
	var nm := gif_name if gif_name != "" else "%s_%s" % [st, clip]
	if "," in clip_only and gif_name != "":
		nm = "%s_%s" % [gif_name, clip]
	var dir := frames_dir.path_join("anim_" + nm)
	_clean(dir)
	var cell := Vector2i(360, 360)
	var cams: Array = []
	var chars: Array = []
	for k in 2:
		var vp := _viewport(cell, true)
		var stage := Node3D.new()
		vp.add_child(stage)
		for z in range(-2, 4):
			_tile(stage, Vector3(0, 0, z * BWAnimClips.HEX_STEP))
		var c := _character(stage, BWRosterKits.unit(rep) if rep != "" else _unit_for(st, clip))
		var cam := Camera3D.new()
		cam.fov = 30.0
		vp.add_child(cam)
		cam.make_current()
		_step(c, 30)
		chars.append(c)
		cams.append([vp, cam, deg_to_rad(-62.0) if k == 0 else deg_to_rad(40.0)])   # the cutscene side, and her left (the off hand)
	var lib: AnimationLibrary = chars[0].animator.library
	if not lib.has_animation(clip):
		print("no clip ", st, " ", clip)
		return
	var scs: Array = []
	for c in chars:
		scs.append(_scenario(c, clip))
	var pre := 12
	var steps := int(scs[0].steps) + 24
	var frame := 0
	for i in range(-pre, steps + 1):
		for k in 2:
			var c: BWCharacter = chars[k]
			if i == 0:
				scs[k].setup.call(c)
			elif i > 0:
				scs[k].drive.call(c, i)
			_step(c)
		if i % 2 != 0:
			continue
		for k in 2:
			var c: BWCharacter = chars[k]
			var focus := c.global_position + Vector3(0, 1.1, 0.4)
			var b := Basis.from_euler(Vector3(deg_to_rad(-8.0), float(cams[k][2]), 0))
			(cams[k][1] as Camera3D).global_transform = Transform3D(b, focus + b.z * 9.0)
		await _frame()
		var img := Image.create(cell.x * 2, cell.y, false, Image.FORMAT_RGB8)
		for k in 2:
			var im: Image = (cams[k][0] as SubViewport).get_texture().get_image()
			im.convert(Image.FORMAT_RGB8)
			img.blit_rect(im, Rect2i(Vector2i.ZERO, cell), Vector2i(k * cell.x, 0))
		img.save_png(dir.path_join("%04d.png" % frame))
		frame += 1
	print("frames ", dir, " ", frame)
	for c in chars:
		c.free()
	for e in cams:
		(e[0] as SubViewport).queue_free()


## The cutscene choreography for one style: run three hexes in (the move
## plan), wind up, strike (melee dashes on launch..land and hops home;
## shots and casts fire a projectile on release), the opponent reacts with
## its impact on the blow, both settle, then the attacker plays an idle
## variant. The root moves exactly as in combat.
func _showcase(st: String) -> void:
	var dir := frames_dir.path_join("anim_showcase_" + st)
	_clean(dir)
	var vp := _viewport(Vector2i(760, 460), true)
	var stage := Node3D.new()
	vp.add_child(stage)
	for k in range(-1, 7):
		_tile(stage, Vector3(0, 0, k * BWAnimClips.HEX_STEP))
	var a := _character(stage, _unit_for(st, ""))
	var d := _character(stage, BWRosterKits.unit(SHOW[st][0]))
	var react: String = SHOW[st][1]
	var ranged := st in ["bow", "pistol", "staff"]
	var gap_hexes := 3 if ranged else 1
	d.position = Vector3(0, 0, (3 + gap_hexes) * BWAnimClips.HEX_STEP)
	d.rotation.y = PI
	var cam := Camera3D.new()
	cam.fov = 30.0
	vp.add_child(cam)
	cam.make_current()
	_step(a, 30)
	_step(d, 30)
	var dist := 3.0 * BWAnimClips.HEX_STEP
	var plan := a.animator.plan_move(dist, 3)
	var s_of: Callable = plan.s
	var events: Array = []         # [time, callable]
	var t := 0.0
	var phase := "idle0"
	var pt := 0.0
	var home := Vector3.ZERO
	var dash_to := Vector3.ZERO
	var dash := [-1.0, 0.0]
	var back := [-1.0, 0.0]
	var proj: MeshInstance3D = null
	var proj_from := Vector3.ZERO
	var proj_t := [-1.0, 0.0]
	var impact_at := -1.0
	var reacted := false
	var stopped := false
	var spell := st == "staff"
	var frame := 0
	var i := 0
	var cam_d := -1.0
	var cam_m := Vector3.INF
	while t < 16.0:
		t += DT
		pt += DT
		match phase:
			"idle0":
				if pt >= 0.5:
					a.animator.begin_move(plan)
					phase = "move"
					pt = 0.0
			"move":
				if not stopped and float(plan.stop_at) >= 0.0 and pt >= float(plan.stop_at):
					a.pose("run_stop")
					stopped = true
				a.position = Vector3(0, 0, float(s_of.call(minf(pt, float(plan.dur)))))
				if pt >= float(plan.dur):
					a.pose("idle")
					phase = "settle"
					pt = 0.0
			"settle":
				if pt >= 0.55:
					a.pose("cast" if spell else "windup")
					phase = "windup"
					pt = 0.0
			"windup":
				var go := spell or (a.animator.time_to("coil") <= 0.0 and pt > 0.1 and pt >= a.animator.marker_time(a.animator.top_clip(), "coil") + 0.1)
				if go:
					if not spell:
						a.pose("strike")
					home = a.position
					var an := a.animator
					var mk: Dictionary = an.clip_meta(an.top_clip()).get("markers", {})
					if mk.has("launch") and not ranged:
						var gap := home.distance_to(d.position)
						dash_to = home.lerp(d.position, clampf(1.0 - float(an.clip_meta(an.top_clip()).get("engage", 1.0)) / gap, 0.0, 0.42))
						dash = [pt + an.time_to("launch"), an.time_to("land") - an.time_to("launch")]
						impact_at = t + an.time_to("hit")
					var rel := an.time_to("release")
					if rel >= 0.0:
						proj_t = [t + rel, 0.18 + (dist * 0.0 + d.position.distance_to(home)) * 0.03]
						impact_at = float(proj_t[0]) + float(proj_t[1])
					phase = "strike"
					pt = 0.0
			"strike":
				var an := a.animator
				if float(dash[0]) >= 0.0 and pt >= float(dash[0]):
					var u := clampf((pt - float(dash[0])) / maxf(float(dash[1]), 0.01), 0.0, 1.0)
					a.position = home.lerp(dash_to, 0.5 - 0.5 * cos(PI * u))
				if float(proj_t[0]) >= 0.0 and t >= float(proj_t[0]):
					if proj == null:
						proj = MeshInstance3D.new()
						var sm := SphereMesh.new()
						sm.radius = 0.08 if spell else 0.05
						sm.height = sm.radius * 2
						proj.mesh = sm
						proj.material_override = BWLook.flat()
						proj.set_instance_shader_parameter("tint", BWLook.element_color(a.unit.element) if spell else BWLook.INK)
						stage.add_child(proj)
						var hk := "hand_l" if a.poser.hold_hand == "l" else "hand_r"
						var sock: Transform3D = a.rig.skeleton.global_transform * (a.poser.globals[hk] as Transform3D) * (a.poser.socket_l if hk == "hand_l" else a.poser.socket_r)
						proj_from = sock * BWWeaponView.v3(a.weapon.meta.get("tip", [0, 1, 0]))
					var u := clampf((t - float(proj_t[0])) / float(proj_t[1]), 0.0, 1.0)
					var to := d.global_position + Vector3(0, 1.1, 0)
					proj.global_position = proj_from.lerp(to, u) + Vector3(0, sin(u * PI) * 0.5, 0)
					proj.visible = u < 1.0
				var lead := maxf(d.animator.marker_time(d.animator.clip_of(react), "impact"), 0.0)
				if not reacted and impact_at > 0.0 and t >= impact_at - lead:
					d.pose(react)
					reacted = true
					if react == "dodge":
						d.set_meta("dodge_t0", t)
				if reacted and react == "dodge":
					var m: Dictionary = d.animator.clip_meta("dodge")
					var mk: Dictionary = m.markers
					var tt := t - float(d.get_meta("dodge_t0"))
					var o := 0.0
					if tt >= float(mk.launch):
						o = smoothstep(float(mk.launch), float(mk.land), tt)
					if tt >= float(mk.hop_start):
						o = 1.0 - smoothstep(float(mk.hop_start), float(mk.hop_end), tt)
					d.position = Vector3(0, 0, (3 + gap_hexes) * BWAnimClips.HEX_STEP) + Basis(Vector3.UP, PI) * (m.shift as Vector3) * o
				if float(back[0]) < 0.0 and reacted and float(dash[0]) >= 0.0 and an.time_to("hop_start") < 0.0 and pt > float(dash[0]) + 0.1:
					back = [pt, maxf(an.clip_meta(an.top_clip()).markers.hop_end - an.clip_meta(an.top_clip()).markers.hop_start, 0.08)]
				if float(back[0]) >= 0.0:
					var u := clampf((pt - float(back[0])) / float(back[1]), 0.0, 1.0)
					a.position = dash_to.lerp(home, 0.5 - 0.5 * cos(PI * u))
				if reacted and not an.is_busy() and pt > 1.2:
					a.pose("idle")
					phase = "after"
					pt = 0.0
			"after":
				if pt >= 0.5 and not d.animator.is_busy():
					d.pose("idle")
				if pt >= 0.9 and a.animator.top_clip() == a.animator.actions.idle.clip:
					var vs: Array = a.animator.personality.variants
					_play_clip(a, str(vs[0]), "idle")
					phase = "variant"
					pt = 0.0
			"variant":
				if pt >= a.animator.library.get_animation(a.animator.top_clip() if a.animator.top_clip() != "" else "idle").length + 0.6 and pt > 2.6:
					break
		_step(a)
		_step(d)
		if i % 2 == 0:
			var span := a.global_position.distance_to(d.global_position)
			var mid := a.global_position.lerp(d.global_position, 0.5) + Vector3(0, 1.1, 0)
			var want := clampf(5.5 + span * 1.5, 7.5, 14.0)
			cam_d = lerpf(cam_d, want, 0.06) if cam_d > 0.0 else want
			cam_m = cam_m.lerp(mid, 0.12) if cam_m != Vector3.INF else mid
			var b := Basis.from_euler(Vector3(deg_to_rad(-9.0), deg_to_rad(-90.0 + 16.0), 0))
			cam.global_transform = Transform3D(b, cam_m + b.z * cam_d)
			await _frame()
			vp.get_texture().get_image().save_png(dir.path_join("%04d.png" % frame))
			frame += 1
		i += 1
	print("frames ", dir, " ", frame)
	a.free()
	d.free()
	vp.queue_free()


func _clean(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))


# ------------------------------------------------------- hit-reaction variety

## The five stricken variants side by side (columns) for two styles (rows),
## all starting on the same frame: anim_stricken_variants.gif.
const VARIANT_STYLES := ["heavy", "pair"]


func _variants_gif() -> void:
	var dir := frames_dir.path_join("anim_stricken_variants")
	_clean(dir)
	var cell := Vector2i(300, 320)
	var entries: Array = []
	for st in VARIANT_STYLES:
		for v in BWAnimStricken.VARIANTS:
			var vp := _viewport(cell, true)
			var stage := Node3D.new()
			vp.add_child(stage)
			for k in range(-3, 6):
				_tile(stage, Vector3(0, 0, k * BWAnimClips.HEX_STEP))
			var c := _character(stage, _unit_for(st, ""))
			var cam := Camera3D.new()
			cam.fov = 30.0
			vp.add_child(cam)
			cam.make_current()
			var lbl := Label.new()
			lbl.text = "%s  (%s, %s)" % [v.trim_prefix("stricken_"), st, c.unit.name]
			lbl.position = Vector2(8, 4)
			lbl.add_theme_color_override("font_color", Color.WHITE)
			vp.add_child(lbl)
			_step(c, 30)
			entries.append({ "vp": vp, "c": c, "cam": cam, "clip": v })
	var longest := 0.0
	for e in entries:
		longest = maxf(longest, (e.c as BWCharacter).animator.library.get_animation(e.clip).length)
	var lead := 0.3
	var steps := int(round((lead + longest + 0.5) / DT))
	var cols := BWAnimStricken.VARIANTS.size()
	var frame := 0
	for i in steps + 1:
		for e in entries:
			if i == int(round(lead / DT)):
				_play_clip(e.c, e.clip)
			if i > 0:
				_step(e.c)
		if i % 2 != 0:
			continue
		for e in entries:
			var c: BWCharacter = e.c
			var focus := c.global_position + Vector3(0, 1.05, -0.4)
			var b := Basis.from_euler(Vector3(deg_to_rad(-8.0), deg_to_rad(-84.0), 0))
			(e.cam as Camera3D).global_transform = Transform3D(b, focus + b.z * 7.4)
		await _frame()
		var img := Image.create(cell.x * cols, cell.y * VARIANT_STYLES.size(), false, Image.FORMAT_RGB8)
		for k in entries.size():
			var im: Image = (entries[k].vp as SubViewport).get_texture().get_image()
			im.convert(Image.FORMAT_RGB8)
			img.blit_rect(im, Rect2i(Vector2i.ZERO, cell), Vector2i((k % cols) * cell.x, (k / cols) * cell.y))
		img.save_png(dir.path_join("%04d.png" % frame))
		frame += 1
	print("frames ", dir, " ", frame)
	for e in entries:
		e.c.free()
		e.vp.queue_free()


## Every variant of one style as sheet rows (every 2nd frame, 3/4 + side).
func _variants_strip(st: String) -> void:
	var cell := Vector2i(150, 170)
	var rows: Array = []
	for v in BWAnimStricken.VARIANTS:
		var r := await _shots(st, v, cell, 3.6)
		r["clip"] = v
		rows.append(r)
	await _compose(out_dir.path_join("anim_stricken_variants_strip.png"),
		"%s set: the five stricken variants   (cells every 2 f; rows 3/4 and side; cyan head, blue fist, orange tip, violet other hand)" % st, rows, cell, 26, true)



# ------------------------------------------------------------- projectiles

## A shot from draw to impact: the archer (or gunslinger) winds up and
## fires at an opponent three hexes away; the camera starts close on the
## shooter (the nocked arrow, the bent string) and pulls out to frame the
## flight; the opponent's reaction meets the arrival (its impact marker);
## an arrow sticks and rides the chest through a knockback.
func _shot_gif(st: String) -> void:
	var name := "anim_bow_shot" if st == "bow" else "anim_pistol_shot"
	var dir := frames_dir.path_join(name)
	_clean(dir)
	var vp := _viewport(Vector2i(760, 440), true)
	var stage := Node3D.new()
	vp.add_child(stage)
	for k in range(-1, 5):
		_tile(stage, Vector3(0, 0, k * BWAnimClips.HEX_STEP))
	var a := _character(stage, _unit_for(st, ""))
	var foe := "burt" if st == "bow" else "dragtol"
	var react := "stricken_knockback" if st == "bow" else "stricken_flinch"
	var d := _character(stage, BWRosterKits.unit(foe))
	d.position = Vector3(0, 0, 3 * BWAnimClips.HEX_STEP)
	d.rotation.y = PI
	var cam := Camera3D.new()
	cam.fov = 30.0
	vp.add_child(cam)
	cam.make_current()
	_step(a, 30)
	_step(d, 30)
	var t := 0.0
	var fired := false
	var flight: BWProjectileFlight = null
	var impact_at := -1.0
	var reacted := false
	var released_at := -1.0
	a.pose("windup")
	var released_strike := false
	var frame := 0
	var i := 0
	var el := a.unit.element
	while t < 4.2:
		t += DT
		var an := a.animator
		if not released_strike and t > an.marker_time("strike", "coil") + 0.35:
			a.pose("strike")
			released_strike = true
		if released_strike and not fired and an.time_to("release") < 0.0 and an.top_clip() == "strike":
			var from: Variant = a.nocked_arrow() if st == "bow" else null
			if from == null:
				var sock: Transform3D = a.rig.skeleton.global_transform * (a.poser.globals["hand_l" if st == "bow" else "hand_r"] as Transform3D) * (a.poser.socket_l if st == "bow" else a.poser.socket_r)
				from = sock * BWWeaponView.v3(a.weapon.meta.get("tip", [0, 1, 0]))
			flight = BWProjectileFlight.launch(stage, "arrow" if st == "bow" else "bullet", from, d, el, true)
			flight.manual = true
			impact_at = t + flight.duration
			released_at = t
			fired = true
		var lead := maxf(d.animator.marker_time(react, "impact"), 0.0)
		if fired and not reacted and t >= impact_at - lead:
			_play_clip(d, react)
			reacted = true
		if flight and is_instance_valid(flight):
			flight.advance(DT)
		_step(a)
		_step(d)
		if i % 2 == 0:
			# close on the shooter through the draw, then out to frame the flight
			var near := a.global_position + Vector3(0, 1.35, 0.25)
			var wide := a.global_position.lerp(d.global_position, 0.5) + Vector3(0, 1.1, 0)
			var u := 0.0 if released_at < 0.0 else smoothstep(0.0, 0.35, t - released_at)
			var focus := near.lerp(wide, u)
			var dist := lerpf(3.6, 9.6, u)
			var b := Basis.from_euler(Vector3(deg_to_rad(-8.0), deg_to_rad(-90.0 + 22.0 * (1.0 - u) + 12.0 * u), 0))
			cam.global_transform = Transform3D(b, focus + b.z * dist)
			await _frame()
			vp.get_texture().get_image().save_png(dir.path_join("%04d.png" % frame))
			frame += 1
		i += 1
	print("frames ", dir, " ", frame)
	a.free()
	d.free()
	vp.queue_free()


## projectiles.png: arrow, bullet and bolt, each in three elements, side on
## (flying right) on a mid-grey ground and on the night sky.
func _projectile_lineup() -> void:
	var size := Vector2i(1500, 760)
	var vp := _viewport(size, false, 0.55)
	var stage := Node3D.new()
	vp.add_child(stage)
	var sky := Node3D.new()
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 3.9
	vp.add_child(cam)
	var cb := Basis.from_euler(Vector3(deg_to_rad(-14.0), deg_to_rad(-90.0 + 16.0), 0))
	cam.global_transform = Transform3D(cb, Vector3(0, 0.0, 0.35) + cb.z * 20.0)
	cam.make_current()
	var els := ["fire", "ice", "thunder"]
	var kinds := ["arrow", "bullet", "bolt"]
	var made: Array = []
	for r in kinds.size():
		for k in els.size():
			var p := BWProjectileView.create_projectile(kinds[r])
			stage.add_child(p)
			p.scale = Vector3.ONE * 1.9
			# flying "right" on screen: +Z of the model to the camera's right
			p.basis = Basis.looking_at(Vector3(0, 0, 1), Vector3.UP, true).scaled(Vector3.ONE * 1.9)
			var z := (k - 1) * 2.1 + (0.75 if kinds[r] == "arrow" else (0.35 if kinds[r] == "bullet" else 0.0))
			p.position = Vector3(0, (1 - r) * 1.15, z)
			if kinds[r] == "bolt":
				p.set_aura(els[k], 1.3)
			else:
				p.set_accent(els[k])
			made.append(p)
	for k in els.size():
		var l := Label.new()
		l.text = els[k]
		l.add_theme_font_size_override("font_size", 22)
		l.add_theme_color_override("font_color", Color.BLACK)
		l.position = Vector2(230 + k * 393, 12)
		vp.add_child(l)
	for r in kinds.size():
		var l := Label.new()
		l.text = kinds[r]
		l.add_theme_font_size_override("font_size", 22)
		l.add_theme_color_override("font_color", Color.BLACK)
		l.position = Vector2(12, 120 + r * 225)
		vp.add_child(l)
	for n in 40:
		await process_frame
	await _frame()
	vp.get_texture().get_image().save_png(out_dir.path_join("projectiles.png"))
	print("saved ", out_dir.path_join("projectiles.png"))
	for p in made:
		p.free()
	vp.queue_free()



## D65 review: eight characters standing in their (calm) home idle with
## their idle variants rotating, 10 s, side by side.
func _idle_calm() -> void:
	var dir := frames_dir.path_join("anim_idle_calm")
	_clean(dir)
	var cell := Vector2i(300, 320)
	var entries: Array = []
	for st in BWAnimClips.SETS:
		var vp := _viewport(cell, true)
		var stage := Node3D.new()
		vp.add_child(stage)
		for k in range(-2, 4):
			_tile(stage, Vector3(0, 0, k * BWAnimClips.HEX_STEP))
		var c := _character(stage, _unit_for(st, ""))
		c.animator.rotate_idles = true
		var cam := Camera3D.new()
		cam.fov = 30.0
		vp.add_child(cam)
		cam.make_current()
		var lbl := Label.new()
		lbl.text = "%s  (%s, %s)" % [c.unit.name, st, c.animator.personality.vibe]
		lbl.position = Vector2(8, 4)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		vp.add_child(lbl)
		var focus := Vector3(0, 1.05, 0.1)
		var b := Basis.from_euler(Vector3(deg_to_rad(-9.0), deg_to_rad(-50.0), 0))
		cam.global_transform = Transform3D(b, focus + b.z * 6.8)
		entries.append({ "vp": vp, "c": c })
	var frame := 0
	for i in int(10.0 / DT):
		for e in entries:
			_step(e.c)
		if i % 2 != 0:
			continue
		await _frame()
		var img := Image.create(cell.x * 4, cell.y * 2, false, Image.FORMAT_RGB8)
		for k in entries.size():
			var im: Image = (entries[k].vp as SubViewport).get_texture().get_image()
			im.convert(Image.FORMAT_RGB8)
			img.blit_rect(im, Rect2i(Vector2i.ZERO, cell), Vector2i((k % 4) * cell.x, (k / 4) * cell.y))
		img.save_png(dir.path_join("%04d.png" % frame))
		frame += 1
	print("frames ", dir, " ", frame)
	for e in entries:
		e.c.free()
		e.vp.queue_free()


# ---------------------------------------------------------- weapon handling

## D80 review: one character per style works through every hold (in, the
## hold's actions, out) and the guard's actions, then from a hold straight
## into a strike (the hands lead back) and a hit. Two cameras: 3/4 front
## and the other 3/4. anim_handling_<style>.gif.
func _handling(st: String) -> void:
	var dir := frames_dir.path_join("anim_handling_" + st)
	_clean(dir)
	var cell := Vector2i(400, 420)
	var vps: Array = []
	var cs: Array = []
	var u := _unit_for(st, "")
	for k in 2:
		var vp := _viewport(cell, false, 0.62)
		var stage := Node3D.new()
		vp.add_child(stage)
		for z in range(-1, 2):
			_tile(stage, Vector3(0, 0, z * BWAnimClips.HEX_STEP))
		var c := _character(stage, _unit_for(st, ""))
		var cam := Camera3D.new()
		cam.fov = 32.0
		vp.add_child(cam)
		cam.make_current()
		var focus := Vector3(0, 1.15, 0.2)
		var b := Basis.from_euler(Vector3(deg_to_rad(-8.0), deg_to_rad(-38.0 if k == 0 else 42.0), 0))
		cam.global_transform = Transform3D(b, focus + b.z * 5.6)
		var lbl := Label.new()
		lbl.position = Vector2(8, 4)
		lbl.add_theme_color_override("font_color", Color.BLACK)
		lbl.add_theme_font_size_override("font_size", 15)
		vp.add_child(lbl)
		vps.append({ "vp": vp, "lbl": lbl })
		cs.append(c)
	# the script: [what, seconds after it starts]
	var steps: Array = []
	var an: BWAnimator = cs[0].animator
	steps.append(["", 0.6])
	for a in BWAnimHandling.actions(st, "guard"):
		steps.append([str(a[1]), 0.5])
	for h in an.holds():
		if h == "guard":
			continue
		steps.append([h, 0.9])
		for a in BWAnimHandling.actions(st, h):
			steps.append([str(a[1]), 0.5])
	var last_hold := ""
	for h in an.holds():
		if h != "guard":
			last_hold = h
	steps.append(["guard", 0.6])
	if last_hold != "":
		steps.append([last_hold, 0.8])
	steps.append(["!windup", 0.5])
	steps.append(["!strike", 0.9])
	if st == "fists":
		for sk in ["flurry", "uppercut", "palm_burst"]:
			steps.append(["!windup_" + sk, 0.5])
			steps.append(["!" + sk, 0.9])
		steps.append(["!run", 0.0])
		steps.append(["!run_stop", 0.8])
	steps.append(["!hit", 1.2])
	var frame := 0
	var i := 0
	for s in steps:
		var what := str(s[0])
		for c in cs:
			var ca: BWAnimator = (c as BWCharacter).animator
			if what.begins_with("!"):
				(c as BWCharacter).pose(what.substr(1))
			elif what != "":
				ca.handle(what)
		var title := "%s (%s)  %s" % [u.name, st, what.trim_prefix("!")]
		# run until the one-shot (and any queued transition) is over, then hold a beat
		var t := 0.0
		var settle := 0.0
		while settle < float(s[1]) and t < 12.0:
			for c in cs:
				_step(c)
			t += DT
			var top: Dictionary = an.layers.back()
			var busy: bool = top.kind == "clip" and not top.loop and not top.ended
			if what.begins_with("!windup"):
				busy = t < 0.55
			if what == "!run":
				busy = t < 1.2
			settle = 0.0 if busy else settle + DT
			if i % 2 == 0:
				for v in vps:
					(v.lbl as Label).text = "%s\nhold: %s   clip: %s" % [title, an.hold, an.top_clip()]
				await _frame()
				var img := Image.create(cell.x * 2, cell.y, false, Image.FORMAT_RGB8)
				for k in vps.size():
					var im: Image = (vps[k].vp as SubViewport).get_texture().get_image()
					im.convert(Image.FORMAT_RGB8)
					img.blit_rect(im, Rect2i(Vector2i.ZERO, cell), Vector2i(k * cell.x, 0))
				img.save_png(dir.path_join("%04d.png" % frame))
				frame += 1
			i += 1
	print("frames ", dir, " ", frame)
	for c in cs:
		c.free()
	for v in vps:
		v.vp.queue_free()
