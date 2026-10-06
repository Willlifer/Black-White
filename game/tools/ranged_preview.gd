extends SceneTree
## D164 review: the bow clips as a clean contact sheet (no overlays), two
## views per clip (side, from the bow side; and 3/4 front), every 2nd frame.
##
##   godot --path . --resolution 1600x900 -s res://tools/ranged_preview.gd -- [--clips strike,shot_sky] [--out <png>] [--every 2] [--unit gail]
##
## Default: every bow clip -> design/art/ranged_bow_sheet.png

const DT := 1.0 / 60.0
const CELL := Vector2i(150, 210)


func _initialize() -> void:
	_run.call_deferred()


func _arg(k: String, d: String) -> String:
	var a := OS.get_cmdline_user_args()
	var i := a.find(k)
	return a[i + 1] if i >= 0 and i + 1 < a.size() else d


func _run() -> void:
	var clips := _arg("--clips", "strike,shot_quick,shot_aimed,shot_sky,shot_volley,shot_fan").split(",")
	var out := _arg("--out", ProjectSettings.globalize_path("res://../design/art/ranged_bow_sheet.png"))
	var every := int(_arg("--every", "2"))
	var uid := _arg("--unit", "gail")
	var views := [[PI / 2.0, -0.12, "side"], [PI * 0.22, -0.2, "3/4"]]
	var rows: Array = []      # [label, [Image...]]
	var vp := SubViewport.new()
	vp.size = CELL * 2
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	root.add_child(vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.62, 0.62)
	we.environment = env
	vp.add_child(we)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6, 6)
	floor.mesh = pm
	floor.material_override = BWLook.flat()
	floor.set_instance_shader_parameter("tint", BWLook.PAPER)
	vp.add_child(floor)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 3.3
	vp.add_child(cam)
	cam.make_current()
	for clip in clips:
		for v in views:
			var u := BWRosterKits.unit(uid)
			var c := BWCharacter.create(u)
			vp.add_child(c)
			c.set_process(false)
			c.pose("idle", 0.0)
			c.animator.rotate_idles = false
			for i in 30:
				c._process(DT)
			var b := Basis.from_euler(Vector3(float(v[1]), float(v[0]), 0))
			cam.global_transform = Transform3D(b, Vector3(0, 1.35, 0) + b.z * 12.0)
			var an := c.animator
			if not an.library.has_animation(StringName(clip)):
				push_error("no clip " + clip)
				c.queue_free()
				continue
			var top: Dictionary = an.layers.back()
			an._push(an._clip_layer(clip), 0.08, top)
			an.current = clip
			var frames := int(round(an.library.get_animation(StringName(clip)).length * 24.0))
			var imgs: Array = []
			var marks: Dictionary = an.clip_meta(clip).get("markers", {})
			var f := 0
			var tsec := 0.0
			while f <= frames:
				var want := f / 24.0
				while tsec < want - 1e-6:
					c._process(DT)
					tsec += DT
				await RenderingServer.frame_post_draw
				var img := vp.get_texture().get_image()
				img.resize(CELL.x, CELL.y, Image.INTERPOLATE_LANCZOS)
				img.convert(Image.FORMAT_RGBA8)
				var lab := "f%d" % f
				for m in marks:
					if absf(float(marks[m]) * 24.0 - f) < 0.6:
						lab += " " + str(m).to_upper()
				imgs.append([img, lab])
				f += every
			rows.append(["%s  (%s)  %d f" % [clip, v[2], frames], imgs])
			vp.remove_child(c)
			c.free()
	# compose
	var per := 0
	for r in rows:
		per = maxi(per, (r[1] as Array).size())
	var lab_h := 16
	var sheet := Image.create(per * CELL.x, rows.size() * (CELL.y + lab_h * 2), false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.95, 0.95, 0.95))
	var font := ThemeDB.fallback_font
	var y := 0
	var labels: Array = []
	for r in rows:
		labels.append([Vector2(4, y + 13), str(r[0])])
		var x := 0
		for e in r[1]:
			sheet.blit_rect(e[0], Rect2i(Vector2i.ZERO, CELL), Vector2i(x, y + lab_h))
			labels.append([Vector2(x + 4, y + lab_h + CELL.y + 12), str(e[1])])
			x += CELL.x
		y += CELL.y + lab_h * 2
	# labels via a 2D viewport pass
	var vp2 := SubViewport.new()
	vp2.size = Vector2i(sheet.get_width(), sheet.get_height())
	vp2.transparent_bg = false
	vp2.render_target_update_mode = SubViewport.UPDATE_ONCE
	root.add_child(vp2)
	var tr := TextureRect.new()
	tr.texture = ImageTexture.create_from_image(sheet)
	vp2.add_child(tr)
	var lay := Control.new()
	lay.draw.connect(func():
		for l in labels:
			lay.draw_string(font, l[0], l[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.BLACK))
	lay.size = Vector2(sheet.get_width(), sheet.get_height())
	vp2.add_child(lay)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	vp2.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit(0)
