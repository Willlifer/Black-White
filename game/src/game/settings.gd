class_name BWSettings
extends RefCounted
## Player settings (D124): volumes, display, cutscenes, combat readouts.
## Saved to user://settings.cfg and applied on boot (boot.gd calls init()).
##
##   BWSettings.value("cutscenes")            -> "default" | "fast" | "minimal"
##   BWSettings.put("show_odds", false)       sets, applies, saves
##
## Isolation: until init(false) runs, every value is its default and nothing
## is read or written. Probes, self-test, review tools (--script) and
## `-- --defaults` all stay isolated, so a player's saved file never changes
## what they test, and they never overwrite it.

const DEFAULTS := {
	"vol_master": 1.0, "vol_music": 1.0, "vol_sfx": 1.0, "vol_voice": 1.0, "vol_ui": 1.0,
	"fullscreen": false,
	"window": "",                 # "" = maximized (project default), else "WxH"
	"scale_ui": 1.0,
	"cutscenes": "default",       # BWCutsceneTier.MODES
	"skip_hold": true,            # hold Space / right mouse to fast-forward playback
	"show_odds": true,            # D113 odds strip
	"show_numbers": true,         # floating damage numbers
	"screen_shake": true,         # D170: camera shake on hits (BWHitFeel, every BWCombatScreen._shake)
	"skip_hints": 0,              # how many times the "hold Space to skip" hint has shown
}
const BUS_KEYS := { "vol_master": "Master", "vol_music": "Music", "vol_sfx": "SFX", "vol_voice": "Voice", "vol_ui": "UI" }
const WINDOW_PRESETS := ["", "1280x720", "1600x900", "1920x1080", "2560x1440"]
const UI_SCALES := [0.9, 1.0, 1.1, 1.25]
const SKIP_HINT_TIMES := 4

static var path := "user://settings.cfg"
static var isolated := true
static var _v := {}


## Boot: load the saved file (or stay on defaults when `use_defaults`).
static func init(use_defaults: bool) -> void:
	_v = {}
	isolated = use_defaults
	if isolated:
		return
	var cf := ConfigFile.new()
	if cf.load(path) == OK:
		for k in DEFAULTS:
			if cf.has_section_key("settings", k):
				_v[k] = _clean(k, cf.get_value("settings", k))
	else:
		# first run with this file: carry over the older audio.cfg volumes
		for k in BUS_KEYS:
			var v := BWAudio.get_volume(BUS_KEYS[k])
			if not is_equal_approx(v, 1.0):
				_v[k] = v


static func value(key: String) -> Variant:
	return _v.get(key, DEFAULTS.get(key))


## Set, apply and save one setting.
static func put(key: String, v: Variant) -> void:
	if not DEFAULTS.has(key):
		push_warning("BWSettings: unknown key " + key)
		return
	_v[key] = _clean(key, v)
	_apply_one(key)
	save()


static func reset() -> void:
	var keep := int(value("skip_hints"))
	_v = { "skip_hints": keep }
	apply_all()
	save()


static func save() -> void:
	if isolated:
		return
	var cf := ConfigFile.new()
	for k in DEFAULTS:
		cf.set_value("settings", k, value(k))
	cf.save(path)


static func _clean(key: String, v: Variant) -> Variant:
	var d: Variant = DEFAULTS[key]
	match typeof(d):
		TYPE_FLOAT:
			return clampf(float(v), 0.0, 4.0)
		TYPE_BOOL:
			return bool(v)
		TYPE_INT:
			return int(v)
		_:
			var s := str(v)
			if key == "cutscenes" and not s in BWCutsceneTier.MODES:
				return d
			if key == "window" and not s in WINDOW_PRESETS:
				return d
			return s


# ---------------------------------------------------------------- applying

static func apply_all() -> void:
	apply_audio()
	apply_display()


## Bus volumes. Isolated runs set the levels in memory only (BWAudio's own
## setter would save audio.cfg).
static func apply_audio() -> void:
	for k in BUS_KEYS:
		_apply_one(k)


static func apply_display() -> void:
	_apply_one("scale_ui")
	_apply_one("window")
	_apply_one("fullscreen")


static func _apply_one(key: String) -> void:
	if BUS_KEYS.has(key):
		var bus: String = BUS_KEYS[key]
		if AudioServer.get_bus_index(bus) < 0:
			return
		if isolated:
			BWAudio._load()
			BWAudio._volumes[bus] = float(value(key))
			BWAudio._apply(bus)
		else:
			BWAudio.set_volume(bus, float(value(key)))
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var w := tree.root
	if DisplayServer.get_name() == "headless":
		return
	match key:
		"scale_ui":
			w.content_scale_factor = float(value("scale_ui"))
		"fullscreen":
			if bool(value("fullscreen")):
				w.mode = Window.MODE_FULLSCREEN
			elif w.mode == Window.MODE_FULLSCREEN:
				_apply_window(w)
		"window":
			if not bool(value("fullscreen")):
				_apply_window(w)


static func _apply_window(w: Window) -> void:
	var s := str(value("window"))
	if s == "":
		w.mode = Window.MODE_MAXIMIZED
		return
	w.mode = Window.MODE_WINDOWED
	var size := Vector2i(int(s.get_slice("x", 0)), int(s.get_slice("x", 1)))
	var screen := DisplayServer.screen_get_usable_rect(w.current_screen)
	size = Vector2i(mini(size.x, screen.size.x), mini(size.y, screen.size.y))
	w.size = size
	w.position = screen.position + (screen.size - size) / 2


## F11 / Alt+Enter: flip fullscreen and remember it.
static func toggle_fullscreen() -> void:
	put("fullscreen", not bool(value("fullscreen")))


## The "hold Space to skip" hint: true the first few FULL cutscenes (counts
## and saves each time it answers true).
static func take_skip_hint() -> bool:
	if not bool(value("skip_hold")):
		return false
	var n := int(value("skip_hints"))
	if n >= SKIP_HINT_TIMES:
		return false
	_v["skip_hints"] = n + 1
	save()
	return true
