class_name BWSfx
extends Node
## Sound effects: picks a variation, places it in the world (3D, gentle
## attenuation) or on the UI (2D), and keeps the mix. The files come from
## tools/audio/make_sfx.py and are listed in res://audio/sfx/sfx.json.
##
##   BWSfx.play("hit_flesh", node_or_position)   world sound (AudioStreamPlayer3D, bus SFX)
##   BWSfx.ui("ui_confirm")                       2D (bus from the manifest, usually UI)
##   BWSfx.play("swing_heavy", v, { "delay": 0.05, "offset": 0.02, "gain_db": -3, "pitch": 0.8 })
##   var p := BWSfx.loop_start("channel_loop", node)  ...  BWSfx.loop_stop(p)
##
## Every variation is <name>_<n>.wav. Drop a real recording in under one of
## those names (any rate, mono or stereo WAV) and it plays instead; add more
## variations by raising "variants" in sfx.json. See design/audio/AUDIO.md.

const DIR := "res://audio/sfx/"
const MANIFEST := "res://audio/sfx/sfx.json"
## Per-sound mix (dB) on top of the file's -16 LUFS-ish level.
const MIX := {
	"swing_light": -8.0, "swing_heavy": -6.0, "swing_axe": -6.0,
	"hit_flesh": -3.0, "hit_crit": 0.0, "hit_glance": -6.0, "hit_block": -4.0, "hit_miss": -9.0,
	"bow_draw": -11.0, "bow_release": -6.0, "arrow_thunk": -5.0,
	"pistol_shot": -2.0, "flintlock_shot": -2.0,
	"cast_whoom": -6.0, "bolt_fizz": -9.0, "channel_loop": -15.0,
	"elem_fire": -8.0, "elem_water": -8.0, "elem_ice": -8.0, "elem_thunder": -9.0, "elem_wind": -8.0,
	"elem_dark": -7.0, "elem_light": -9.0, "heal": -6.0,
	"tile_detonate": -1.0, "tile_glaze": -6.0, "tile_gale": -7.0,
	"step_stone": -18.0, "ko_thud": -3.0,
	"ui_hover": -15.0, "ui_click": -10.0, "ui_confirm": -8.0, "ui_cancel": -9.0, "ui_pick": -8.0,
	"ui_turn": -9.0, "ui_levelup": -5.0, "sting_victory": -2.0, "sting_defeat": -2.0, "progress_day": -4.0,
	# D240: the author's drop 2 (tools/audio/make_drop2.py), files at -16 like the rest
	# levelled in the drop-2 capture: a sting's body ~ the music it ducks (momentary max)
	"sting_good": 0.5, "sting_bad": 0.5, "sting_level_up": 1.0, "sting_room_hard": 0.0,
	"sting_pick_reveal": -7.0, "shop_purchase": -6.0,
	# D392: the pick reveal's first 2.3 s (the pick cards); the 7 s take stays as "pick_long"
	"sting_pick_short": -7.0,
	# D393: placeholders (ph_*, tools/audio/make_placeholders.py), files at -16 like the rest;
	# each set against the sound it replaces (swap: the old whoosh / clink; pulse: the old
	# detonation; Colossus step: the Giant's step; casts a little over the element hits)
	"ph_swap_holster": -12.0, "ph_swap_draw": -12.0,
	"ph_proc_onkill": -7.0, "ph_proc_heal": -8.0, "ph_proc_pity": -10.0, "ph_immune": -5.0,
	"ph_obelisk_push": -3.0, "ph_obelisk_pull": -3.0,
	"ph_colossus_step": -9.0, "ph_colossus_thrust": -4.0, "ph_horde_shuffle": -20.0, "ph_being_hum": -23.0,
	"ph_blank_step": -16.0, "ph_fan_knives": -7.0,
	"ph_cast_fire": -5.0, "ph_cast_water": -5.0, "ph_cast_ice": -5.0, "ph_cast_thunder": -6.0,
	"ph_cast_wind": -5.0, "ph_cast_light": -6.0, "ph_cast_dark": -4.0,
}
## D412: the drop-2 stings, the short pick reveal and the three procs cut from
## them are retuned -3 st into the loops' key (A major / F# minor; the author,
## 2026-10-08). The author's C originals ship beside them as <name>_c
## (sfx.json "alt_of"). The one-line switch: "C" plays the originals everywhere.
const STING_KEY := "A"
## Pitch jitter per play (± fraction) so repeats don't machine-gun. 0 in captures.
static var jitter := 0.035
## Two plays of the same sound closer than this are merged (except steps).
const MIN_GAP := 0.035
## 3D: unit_size 12 puts the combat camera (11-22 u away) at about 0..-5 dB.
const UNIT_SIZE := 12.0
const MAX_DB := 3.0
const PANNING := 0.5

static var _inst: BWSfx
static var log_enabled := false
static var events: Array = []        # capture log: { name, file, usec, frame, tag }

var _manifest := {}
var _streams := {}                   # path -> AudioStream
var _last_variant := {}              # name -> n
var _last_time := {}                 # name -> seconds
var _rng := RandomNumberGenerator.new()


static func ensure(parent: Node = null) -> BWSfx:
	if _inst != null and is_instance_valid(_inst):
		return _inst
	_inst = BWSfx.new()
	_inst.name = "BWSfx"
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		tree.root.add_child.call_deferred(_inst)
	elif parent:
		parent.add_child.call_deferred(_inst)
	return _inst


func _init() -> void:
	_rng.seed = 0x5fd
	if FileAccess.file_exists(MANIFEST):
		var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if m is Dictionary:
			_manifest = m.get("sounds", {})


## Names in the manifest (the tests check every one the code uses is here).
static func names() -> Array:
	return ensure()._manifest.keys()


static func info(name: String) -> Dictionary:
	return ensure()._manifest.get(resolve(name), {})


## D412: the file set a name plays under STING_KEY: `name`, or its C original
## `name_c` when STING_KEY is "C" and one exists.
static func resolve(name: String) -> String:
	if STING_KEY == "C" and ensure()._manifest.has(name + "_c"):
		return name + "_c"
	return name


static func variants(name: String) -> int:
	return int(info(name).get("variants", 0))


static func path_of(name: String, n: int) -> String:
	return "%s%s_%d.wav" % [DIR, name, n]


## Seconds from the start of a variation to its loudest 10 ms (whooshes are
## lined up on the hit frame with it).
static func peak_s(name: String, n: int) -> float:
	var lv: Array = info(name).get("levels", [])
	return float((lv[n - 1] as Dictionary).get("peak_s", 0.0)) if n >= 1 and n <= lv.size() else 0.0


## World sound at a Node3D (follows nothing; placed where the node is now)
## or a Vector3. `where` null = 2D. Returns the player (or null if skipped).
static func play(name: String, where: Variant = null, opts: Dictionary = {}) -> Node:
	var s := ensure()
	return s._play(name, where, opts)


static func ui(name: String, opts: Dictionary = {}) -> Node:
	return play(name, null, opts)


## Picks the variation now (so a caller can line it up), returns its number.
static func pick(name: String) -> int:
	return ensure()._pick(name)


static func loop_start(name: String, follow: Node3D, opts: Dictionary = {}) -> Node:
	var s := ensure()
	var o := opts.duplicate()
	o["loop"] = true
	o["parent"] = follow
	return s._play(name, Vector3.ZERO, o)


static func loop_stop(p: Node, fade: float = 0.15) -> void:
	if p == null or not is_instance_valid(p):
		return
	var tw := p.create_tween()
	tw.tween_property(p, "volume_db", -60.0, fade)
	tw.tween_callback(p.queue_free)


func _pick(name: String) -> int:
	var n := maxi(1, int(_manifest.get(name, {}).get("variants", 1)))
	var v := _rng.randi_range(1, n)
	if n > 1 and v == int(_last_variant.get(name, -1)):
		v = v % n + 1
	_last_variant[name] = v
	return v


func _stream(path: String, loop: bool) -> AudioStream:
	if _streams.has(path):
		return _streams[path]
	if not ResourceLoader.exists(path):
		_streams[path] = null
		return null
	var st: AudioStream = load(path)
	if loop and st is AudioStreamWAV:
		var w := st as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(round(w.get_length() * w.mix_rate))
	_streams[path] = st
	return st


func _play(name: String, where: Variant, opts: Dictionary) -> Node:
	name = resolve(name)
	if not _manifest.has(name):
		push_warning("BWSfx: no sound '%s'" % name)
		return null
	var now := Time.get_ticks_msec() / 1000.0
	if not opts.get("stack", false) and now - float(_last_time.get(name, -1.0)) < MIN_GAP:
		return null
	_last_time[name] = now
	var v := int(opts.get("variant", 0))
	if v <= 0:
		v = _pick(name)
	var path := path_of(name, v)
	var loop := bool(opts.get("loop", false)) or bool(_manifest[name].get("loop", false))
	var st := _stream(path, loop)
	if st == null:
		return null
	var delay := float(opts.get("delay", 0.0))
	if delay > 0.0 and where != null:
		# a 3D player starts on the next physics tick: start the wait half a tick early
		delay = maxf(delay - 0.5 / Engine.physics_ticks_per_second, 0.0)
	if delay > 0.0 and is_inside_tree():
		var args := opts.duplicate()
		args.erase("delay")
		args["variant"] = v
		args["stack"] = true
		args["_delayed"] = delay
		var pos: Variant = where.global_position if where is Node3D and is_instance_valid(where) else where
		get_tree().create_timer(delay).timeout.connect(func(): _play(name, pos, args))
		return null
	# a C alternate (D412) mixes like the sound it stands in for
	var gain := float(MIX.get(str(_manifest[name].get("alt_of", name)), -6.0)) + float(opts.get("gain_db", 0.0))
	var pitch := float(opts.get("pitch", 1.0)) * (1.0 + _rng.randf_range(-jitter, jitter))
	var bus := str(opts.get("bus", _manifest[name].get("bus", "SFX")))
	var p: Node
	if where == null:
		var p2 := AudioStreamPlayer.new()
		p2.stream = st
		p2.volume_db = gain
		p2.pitch_scale = pitch
		p2.bus = bus
		p = p2
	else:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = st
		p3.volume_db = gain
		p3.pitch_scale = pitch
		p3.bus = bus
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.unit_size = UNIT_SIZE
		p3.max_db = MAX_DB
		p3.panning_strength = PANNING
		p3.attenuation_filter_db = 0.0          # no distance muffling: the board is small
		p3.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		p = p3
	var parent: Node = opts.get("parent", null)
	if parent != null and is_instance_valid(parent) and parent.is_inside_tree():
		parent.add_child(p)
		if p is Node3D:
			(p as Node3D).position = Vector3(0, 1.0, 0)
	elif is_inside_tree():
		add_child(p)
		if p is Node3D:
			var at: Vector3 = (where as Node3D).global_position if where is Node3D and is_instance_valid(where) else (where if where is Vector3 else Vector3.ZERO)
			(p as Node3D).global_position = at + Vector3(0, 1.0, 0)
	else:
		p.free()
		return null
	var from := float(opts.get("offset", 0.0))
	p.call("play", maxf(from, 0.0))
	if not loop:
		p.connect("finished", p.queue_free)
	if log_enabled:
		events.append({ "name": name, "file": path.get_file(), "usec": Time.get_ticks_usec(), "frame": Engine.get_process_frames(),
			"offset": from, "tag": str(opts.get("tag", "")), "unit": str(opts.get("unit", "")),
			"delay": float(opts.get("_delayed", 0.0)) })
	return p
