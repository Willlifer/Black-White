class_name BWAudio
extends RefCounted
## The audio layout (Phase 6, design/audio/AUDIO.md): buses, per-bus volume
## settings, and the director that attaches sound to the game by listening.
##
##   BWAudio.ensure(node)            buses + BWSfx + the director (idempotent)
##   BWAudio.set_volume("Music", 0.6)   0..1 per bus, saved to user://audio.cfg
##   BWAudio.get_volume("SFX")
##
## Buses (left to right; a bus only sends to the left):
##   Master        HardLimiter at -1 dB (nothing clips, whatever stacks up)
##   Music         Amplify "duck" (stings), Compressor sidechained by Voice
##                 (music dips ~4 dB under a bark)
##   MusicStretch  -> Music. PitchShift: compensates a runtime pitch_scale so a
##                 tempo change keeps its key (only used when
##                 BWMusic.runtime_tempo is on; the default cues use
##                 pre-rendered tempo sets)
##   SFX           world sounds (3D)
##   Voice         barks and grunts
##   UI            menus, stings, chimes (2D)

const BUSES: PackedStringArray = ["Master", "Music", "MusicStretch", "SFX", "Voice", "UI"]
const SEND := { "Music": "Master", "MusicStretch": "Music", "SFX": "Master", "Voice": "Master", "UI": "Master" }
## The mix: each bus's level at volume 1.0. The files are levelled to about
## -16 LUFS (SFX) and -20 (music layers); these set their place in the mix.
const BASE_DB := { "Master": 0.0, "Music": -7.0, "MusicStretch": 0.0, "SFX": -3.0, "Voice": -1.0, "UI": -6.0 }
const SETTINGS_PATH := "user://audio.cfg"
const LIMIT_CEILING_DB := -1.0
## Voice -> Music ducking: gentle. A bark at about -20 dBFS pulls the music
## down ~4 dB (ratio 2 over a -28 dB threshold), back in 0.35 s.
const DUCK := { "threshold": -28.0, "ratio": 2.0, "attack_us": 8000.0, "release_ms": 350.0 }

static var _volumes := {}          # bus -> 0..1 (user setting)
static var _loaded := false


static func ensure(parent: Node) -> void:
	ensure_buses()
	BWSfx.ensure(parent)
	BWAudioDirector.ensure(parent)


## Builds the bus layout if it isn't there. Safe to call any number of times.
static func ensure_buses() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
	for b in SEND:
		AudioServer.set_bus_send(AudioServer.get_bus_index(b), SEND[b])
	_ensure_effect("Master", "AudioEffectHardLimiter", func():
		var l := AudioEffectHardLimiter.new()
		l.ceiling_db = LIMIT_CEILING_DB
		l.pre_gain_db = 0.0
		return l)
	_ensure_effect("Music", "AudioEffectAmplify", func():
		var a := AudioEffectAmplify.new()
		a.volume_db = 0.0
		return a)
	_ensure_effect("Music", "AudioEffectCompressor", func():
		var c := AudioEffectCompressor.new()
		c.threshold = DUCK.threshold
		c.ratio = DUCK.ratio
		c.attack_us = DUCK.attack_us
		c.release_ms = DUCK.release_ms
		c.gain = 0.0
		c.sidechain = &"Voice"
		return c)
	_ensure_effect("MusicStretch", "AudioEffectPitchShift", func():
		var p := AudioEffectPitchShift.new()
		p.pitch_scale = 1.0
		p.fft_size = AudioEffectPitchShift.FFT_SIZE_2048
		p.oversampling = 4
		return p)
	AudioServer.set_bus_effect_enabled(AudioServer.get_bus_index("MusicStretch"), 0, false)
	_load()
	for b in BUSES:
		_apply(b)


static func _ensure_effect(bus: String, cls: String, make: Callable) -> void:
	var i := AudioServer.get_bus_index(bus)
	for k in AudioServer.get_bus_effect_count(i):
		if AudioServer.get_bus_effect(i, k).get_class() == cls:
			return
	AudioServer.add_bus_effect(i, make.call())


## First effect of a class on a bus (null if none).
static func effect(bus: String, cls: String) -> AudioEffect:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return null
	for k in AudioServer.get_bus_effect_count(i):
		var e := AudioServer.get_bus_effect(i, k)
		if e.get_class() == cls:
			return e
	return null


static func effect_index(bus: String, cls: String) -> int:
	var i := AudioServer.get_bus_index(bus)
	for k in AudioServer.get_bus_effect_count(i):
		if AudioServer.get_bus_effect(i, k).get_class() == cls:
			return k
	return -1


# ---------------------------------------------------------------- volume settings

## Volume of a bus, 0..1 (1 = the designed mix, 0 = silent). Saved.
static func set_volume(bus: String, v: float) -> void:
	_load()
	_volumes[bus] = clampf(v, 0.0, 1.0)
	_apply(bus)
	_save()


static func get_volume(bus: String) -> float:
	_load()
	return float(_volumes.get(bus, 1.0))


static func _apply(bus: String) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	var v := float(_volumes.get(bus, 1.0))
	AudioServer.set_bus_mute(i, v <= 0.001)
	AudioServer.set_bus_volume_db(i, float(BASE_DB.get(bus, 0.0)) + linear_to_db(maxf(v, 0.001)))


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	for b in BUSES:
		if cf.has_section_key("volume", b):
			_volumes[b] = clampf(float(cf.get_value("volume", b, 1.0)), 0.0, 1.0)


static func _save() -> void:
	var cf := ConfigFile.new()
	for b in _volumes:
		cf.set_value("volume", b, _volumes[b])
	cf.save(SETTINGS_PATH)
