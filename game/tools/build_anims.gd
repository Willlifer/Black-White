extends SceneTree
## Bakes every animation clip set from its source (src/game/character/anim_clips.gd)
## into art/animations/<set>.res. Deterministic: same source, same samples.
##
##   godot --headless --path game -s res://tools/build_anims.gd
##   godot --headless --path game -s res://tools/build_anims.gd -- --dump   # also print foot/roll + clip stats


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BWAnimClips.DIR))
	if "--dump" in args:
		var prof := BWAnimClips.foot_profile()
		print("FOOT hull %d pts: %s" % [prof.size(), prof])
		for p in [-0.3, -0.15, 0.0, 0.2, 0.4, 0.7]:
			print("ROLL p=%.2f -> %s  low=%s" % [p, BWAnimClips.roll(p), BWAnimClips.sole_low(p)])
	var failed := 0
	for set_id in BWAnimClips.SETS:
		var t0 := Time.get_ticks_msec()
		var lib := BWAnimClips.build_library(set_id)
		var path := BWAnimClips.path_for(set_id)
		var err := ResourceSaver.save(lib, path, ResourceSaver.FLAG_COMPRESS)
		if err != OK:
			push_error("build_anims: cannot save %s (%d)" % [path, err])
			failed += 1
			continue
		for n in lib.get_animation_list():
			var a := lib.get_animation(n)
			var m: Dictionary = a.get_meta("bw")
			print("CLIP %s/%s  %.3f s  %d frames @%d  loop=%s  tracks=%d  markers=%s %s" % [set_id, n, a.length, m.frames,
				int(m.fps), m.loop, a.get_track_count(), m.markers, ("speed=%.3f u/s" % m.speed) if m.has("speed") else ""])
		print("SET %s -> %s (v%d, %d ms)" % [set_id, path, BWAnimClips.ANIM_VERSION, Time.get_ticks_msec() - t0])
	quit(failed)
