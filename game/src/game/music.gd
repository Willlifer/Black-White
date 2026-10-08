class_name BWMusic
extends Node
## Adaptive music (Phase 6, design/audio/AUDIO.md). Every layer of a tempo
## set plays at once, sample-locked in one AudioStreamSynchronized; a cue is
## a volume per layer. Cue changes land on the next bar, combat intensity on
## the next beat, each with short fades, so the drums come in on a downbeat.
##
##   BWMusic.ensure(node)          once (also builds the buses, BWSfx, the director)
##   BWMusic.play("combat")        title roster prebattle rest rooms tutorial combat boss
##   BWMusic.set_intensity(2)      0..2, combat only (BWCombatAudio drives it)
##   BWMusic.sting("victory")      a sting over ducked music (STINGS); one at a time
##   BWMusic.stop_sting()          fade the playing sting out (a picker closed)
##
## D411 (the author, 2026-10-08: "fade the existing track out, play the
## jingle, then fade it in"): a sting fades the music out (DUCK_OUT), holds it
## out until the sting has rung out (sfx.json tail_s: 30 dB under its peak),
## then fades it back in (DUCK_IN). A pure state machine (Duck) drives the
## Music bus's Amplify every frame: a sting during the fade-in turns it
## around from where it is, one during the hold extends it, and a screen
## change mid-duck starts the new track under the same bus duck, so it comes
## in with everything else. Nothing can stay silent: the duck lifts when the
## sting is gone, and BWMusic resets the bus on entering and leaving the tree.
##
## Layers (tools/audio/make_music.py; 8 bars each, all the same length):
##   full bright calm air drums drums_top drums_half voice_pad, and from the
##   author's drop 2 (make_drop2.py) low_beat and kick; plus four free-tempo
##   one-layer sets (arpeggio chillin moderato rooms), D239
## Tempo sets: main 120 BPM; slow 102 BPM (roster, rest: the docx's "slow it
## down for roster picking"); boss 132.3 BPM (+10%). Pre-rendered with
## pitch-preserving WSOLA, so the key never moves. A set change crossfades on
## the bar line and enters the new set on the same bar of the progression.
##
## runtime_tempo = true plays slow and boss on the main set instead, at
## pitch_scale 0.85 / 1.1025 through the MusicStretch bus, whose PitchShift
## (1 / rate) keeps the key: Godot-side tempo change, at a phase-vocoder
## cost on transients. The default is the pre-rendered sets (D66).

const DIR := "res://audio/music/layers/"
const MANIFEST := "res://audio/music/layers/layers.json"
const BARS := 8
const BEATS_PER_BAR := 4
const OFF_DB := -80.0
const SETS := {
	"main": ["full", "bright", "calm", "air", "drums", "drums_top", "drums_half", "voice_pad", "low_beat", "kick"],
	"slow": ["full", "bright", "calm", "voice_pad"],
	"battle": ["full", "bright", "air", "drums", "drums_top", "voice_pad", "kick"],
	"boss": ["full", "bright", "calm", "air", "drums", "drums_top", "voice_pad", "kick"],
	# D239: the author's drop 2 phrase loops, one layer each (tools/audio/make_drop2.py)
	"arpeggio": ["arpeggio"],
	"chillin": ["chillin"],
	"moderato": ["moderato"],
	"rooms": ["rooms"],
}
const SET_FOLDER := { "main": "", "slow": "slow/", "battle": "battle/", "boss": "boss/",
	"arpeggio": "drop2/", "chillin": "drop2/", "moderato": "drop2/", "rooms": "drop2/" }
## 8 bars of each set in samples (44.1 kHz): main 120, slow 102.0, battle 108.0, boss 132.3 BPM.
## The drop 2 sets are free-tempo phrase loops at their own measured length (AUDIO.md).
const SET_SAMPLES := { "main": 705600, "slow": 830000, "battle": 784000, "boss": 640000,
	"arpeggio": 579072, "chillin": 297408, "moderato": 316160, "rooms": 301899 }
## D239: free-tempo sets (played rubato, no bar grid): a cue change leaves them
## at once with the deck crossfade, and they are always entered at their start.
## Only the four re-timings of the 8-bar loop share a progression.
const FREE := ["arpeggio", "chillin", "moderato", "rooms"]
## Cue -> tempo set and layer volumes (dB; a layer not listed is off).
## "intensity" lists overrides for combat levels 0, 1, 2.
## Author 10/4: brighter ("a little depressing … up it an octave") — `bright`
## (the loop +12 st) leads the menus and rides over combat; the muffled `calm`
## low-pass is retired from the cues. Combat drops to the 108 BPM `battle`
## set ("when battle starts it's a little too fast").
## D239 (author's drop 2): title = MainTheme Arpeggio, rest (the hall) =
## chillin main theme, tutorial = moderato main loopish, rooms = Music Rooms,
## prebattle = Low Beat over the no-snare kick; the kick also joins combat at
## intensity 2 and the boss. A solo phrase loop is one quieter layer than a
## stack, so its gain is above 0 dB (levelled to the old cues' loudness).
const CUES := {
	"title": { "set": "arpeggio", "mix": { "arpeggio": 6.0 } },
	"roster": { "set": "slow", "mix": { "bright": -1.0, "full": -7.0 } },
	"prebattle": { "set": "main", "mix": { "low_beat": 6.5, "kick": 2.5 } },
	"rest": { "set": "chillin", "mix": { "chillin": 6.5 } },
	"rooms": { "set": "rooms", "mix": { "rooms": 3.0 } },
	"tutorial": { "set": "moderato", "mix": { "moderato": 4.5 } },
	"combat": { "set": "battle", "mix": { "full": -4.0, "bright": -3.0, "drums": 0.0, "drums_top": -10.0 },
		"intensity": [{}, { "full": -3.0, "bright": -2.0, "drums_top": -5.0, "air": -12.0 },
			{ "full": -2.0, "bright": -1.0, "drums_top": -2.0, "air": -8.0, "voice_pad": -11.0, "kick": -6.0 }] },
	"boss": { "set": "boss", "mix": { "full": 0.0, "bright": -4.0, "drums": 0.0, "drums_top": -3.0, "air": -7.0, "voice_pad": -7.0, "kick": -5.0 } },
}
## The highest a layer may be pushed (dB): the solo loops' make-up gain.
const MAX_DB := 8.0
## D240: the author's stings. One at a time: a new one fades out the last.
## The procedural sting_victory / sting_defeat stay in the manifest unused.
## D392: the pick cards get the 2.3 s cut ("pick": "sting_pick_reveal" switches back);
## the full 7 s take stays mapped as "pick_long".
## D411: the shop purchase is a sting too (it ducks). D412: all of them play in
## A; BWSfx.STING_KEY = "C" switches every one back to the author's C originals.
const STINGS := { "victory": "sting_good", "defeat": "sting_bad", "jackpot": "sting_good", "cursed": "sting_bad",
	"level_up": "sting_level_up", "pick": "sting_pick_short", "pick_long": "sting_pick_reveal", "room_hard": "sting_room_hard",
	"shop": "shop_purchase" }
const FADE_IN := 0.08          # a layer coming in (on the beat)
const FADE_OUT := 0.45         # a layer leaving
const DECK_IN := 0.1           # a tempo set entering on the bar line
const DECK_OUT := 0.9
const START_FADE := 1.2        # the very first cue
const DUCK_OUT := 0.3          # D411: the music fades out under a sting (s)
const DUCK_IN := 1.0           # and back in once the sting has rung out (s)
const DUCK_FLOOR_DB := -60.0   # "out"
const DUCK_LEAD := 0.1         # the sting starts this far into the fade (the music already ~7 dB down)

static var runtime_tempo := false
static var log_enabled := false
static var events: Array = []  # capture log: cue requests and the moments they were applied
static var _inst: BWMusic


class Deck:
	extends RefCounted
	var key := ""
	var set_name := ""
	var player: AudioStreamPlayer
	var stream: AudioStreamSynchronized
	var index := {}            # layer -> stream slot
	var amp := {}              # layer -> linear volume now
	var length := 16.0         # seconds of source, 8 bars
	var rate := 1.0
	var loops := 0
	var last := 0.0
	var fade: Tween

	func bar() -> float:
		return length / BARS

	func beat() -> float:
		return length / (BARS * BEATS_PER_BAR)

	## Source position (s) of what is being mixed now, counting whole loops.
	func abs_pos() -> float:
		if player == null or not player.playing:
			return loops * length + last
		var raw := player.get_playback_position()
		if raw < last - length * 0.5:
			loops += 1
		last = raw
		return loops * length + raw + AudioServer.get_time_since_last_mix() * rate

	func set_amp(layer: String, a: float) -> void:
		amp[layer] = a
		if index.has(layer):
			stream.set_sync_stream_volume(index[layer], linear_to_db(maxf(a, 0.0001)))


## D411: the sting duck. Pure: step(dt) returns the Music bus gain (dB), so
## the tests drive it without audio. `a` is the music's amplitude (0..1). Out
## it follows (1 - t)^2 over fade_out s (a fast first drop, so the sting's
## attack isn't fighting the music); back in it follows sin(t * pi/2) over
## fade_in s. Each step re-reads its curve position from `a`, so turning
## around mid-fade is continuous: no jumps either way.
class Duck:
	extends RefCounted
	enum { IDLE, DOWN, HELD, UP }
	var state := IDLE
	var a := 1.0
	var hold := 0.0            # seconds until the music may come back
	var fade_out := 0.3
	var fade_in := 1.0
	var floor_db := -60.0

	## A sting starts: fade out (or keep out) and hold `hold_s` from now. A
	## newer sting replaces the older one's hold (the older is faded out).
	func begin(hold_s: float) -> void:
		hold = maxf(hold_s, 0.0)
		if state != HELD:
			state = DOWN if a > 0.0 else HELD

	## The sting is going (stopped, or gone): come back in `after` s at most.
	func release(after: float = 0.0) -> void:
		if state == DOWN or state == HELD:
			hold = minf(hold, maxf(after, 0.0))

	func reset() -> void:
		state = IDLE
		a = 1.0
		hold = 0.0

	func active() -> bool:
		return state != IDLE

	func step(dt: float) -> float:
		match state:
			DOWN:
				var g := maxf(sqrt(a) - dt / fade_out, 0.0)
				a = g * g
				hold -= dt
				if hold <= 0.0:
					state = UP
				elif a <= 0.0:
					state = HELD
			HELD:
				hold -= dt
				if hold <= 0.0:
					state = UP
			UP:
				var u := minf(asin(clampf(a, 0.0, 1.0)) / (PI * 0.5) + dt / fade_in, 1.0)
				a = 1.0 if u >= 1.0 else sin(u * PI * 0.5)
				if u >= 1.0:
					state = IDLE
		return level_db()

	func level_db() -> float:
		return floor_db if a <= db_to_linear(floor_db) else minf(linear_to_db(a), 0.0)


var _decks := {}               # key -> Deck
var _active: Deck
var _cue := ""
var _intensity := 0
var _queue: Array = []         # { deck, at, fn, what }
var _sting_player: Node        # D240: the sting playing now (one at a time)
var _sting_kind := ""
var duck := Duck.new()         # D411
var lead := DUCK_LEAD          # the tests set 0 (no timer)
var _sting_token := 0          # a sting asked for; a newer one (or a stop) cancels a pending start
var _sting_pending := false
var _duck_db := 0.0


func _init() -> void:
	duck.fade_out = DUCK_OUT
	duck.fade_in = DUCK_IN
	duck.floor_db = DUCK_FLOOR_DB


## D411: a fresh instance (or one leaving) never inherits a ducked bus.
func _enter_tree() -> void:
	_set_duck_db(0.0)


func _exit_tree() -> void:
	duck.reset()
	_set_duck_db(0.0)


func _set_duck_db(db: float) -> void:
	_duck_db = db
	var amp := BWAudio.effect("Music", "AudioEffectAmplify") as AudioEffectAmplify
	if amp:
		amp.volume_db = db


## The Music bus's sting duck now (dB; 0 = none). The tests and the capture read it.
static func duck_db() -> float:
	return _inst._duck_db if _inst else 0.0


static func ensure(parent: Node) -> void:
	BWAudio.ensure(parent)
	if _inst == null or not is_instance_valid(_inst):
		_inst = BWMusic.new()
		_inst.name = "BWMusic"
		parent.add_child(_inst)


static func play(cue: String) -> void:
	if _inst:
		_inst._play(cue)


static func set_intensity(level: int) -> void:
	if _inst:
		_inst._set_intensity(level)


static func sting(kind: String) -> void:
	if _inst:
		_inst._sting(kind)
	elif STINGS.has(kind):
		BWSfx.ui(STINGS[kind])


static func current_cue() -> String:
	return _inst._cue if _inst else ""


static func instance() -> BWMusic:
	return _inst


## The full layer table of a cue at an intensity: every layer of its set ->
## dB (OFF_DB when off). Pure; the tests read it.
static func cue_mix(cue: String, intensity: int = 0) -> Dictionary:
	var c: Dictionary = CUES.get(cue, {})
	var out := {}
	for l in SETS.get(str(c.get("set", "main")), []):
		out[l] = OFF_DB
	var m: Dictionary = c.get("mix", {})
	for l in m:
		out[l] = float(m[l])
	var steps: Array = c.get("intensity", [])
	if not steps.is_empty():
		var o: Dictionary = steps[clampi(intensity, 0, steps.size() - 1)]
		for l in o:
			out[l] = float(o[l])
	return out


static func layer_path(set_name: String, layer: String) -> String:
	return DIR + str(SET_FOLDER.get(set_name, "")) + layer + ".wav"


static func runtime_rate(set_name: String) -> float:
	return float(SET_SAMPLES.main) / float(SET_SAMPLES.get(set_name, SET_SAMPLES.main))


# ---------------------------------------------------------------- decks

func _deck(set_name: String, rate: float) -> Deck:
	var stretch := absf(rate - 1.0) > 0.001
	var key := set_name + ("/stretch" if stretch else "")
	if _decks.has(key):
		return _decks[key]
	var d := Deck.new()
	d.key = key
	d.set_name = set_name
	d.rate = rate
	d.stream = AudioStreamSynchronized.new()
	var layers: Array = SETS[set_name]
	d.stream.stream_count = layers.size()
	var length := 0.0
	for i in layers.size():
		var w: AudioStream = load(layer_path(set_name, layers[i])) if ResourceLoader.exists(layer_path(set_name, layers[i])) else null
		if w is AudioStreamWAV:
			var wav := w as AudioStreamWAV
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = int(SET_SAMPLES[set_name])
			length = float(SET_SAMPLES[set_name]) / wav.mix_rate
		d.stream.set_sync_stream(i, w)
		d.stream.set_sync_stream_volume(i, OFF_DB)
		d.index[layers[i]] = i
		d.amp[layers[i]] = 0.0
	d.length = length if length > 0.0 else 16.0
	d.player = AudioStreamPlayer.new()
	d.player.name = "Deck_" + key.replace("/", "_")
	d.player.stream = d.stream
	d.player.bus = "MusicStretch" if stretch else "Music"
	d.player.pitch_scale = rate
	add_child(d.player)
	_decks[key] = d
	return d


func _start(d: Deck, mix: Dictionary, from: float, fade: float) -> void:
	for l in d.index:
		d.set_amp(l, db_to_linear(float(mix.get(l, OFF_DB))) if float(mix.get(l, OFF_DB)) > OFF_DB else 0.0)
	_stretch_fx(d)
	d.player.volume_db = -50.0
	d.loops = 0
	d.last = fmod(from, d.length)
	d.player.play(fmod(from, d.length))
	var tw := create_tween()
	tw.tween_property(d.player, "volume_db", 0.0, fade).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_active = d


func _stop(d: Deck, fade: float) -> void:
	if d == null or not d.player.playing:
		return
	var tw := create_tween()
	tw.tween_property(d.player, "volume_db", -60.0, fade).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(d.player.stop)


## The compensating pitch shift for a deck playing off its native tempo.
func _stretch_fx(d: Deck) -> void:
	var bus := AudioServer.get_bus_index("MusicStretch")
	var k := BWAudio.effect_index("MusicStretch", "AudioEffectPitchShift")
	if bus < 0 or k < 0:
		return
	var on := d.player.bus == "MusicStretch"
	if on:
		(AudioServer.get_bus_effect(bus, k) as AudioEffectPitchShift).pitch_scale = 1.0 / d.rate
	AudioServer.set_bus_effect_enabled(bus, k, on)


func _fade_layers(d: Deck, mix: Dictionary) -> void:
	if d.fade and d.fade.is_valid():
		d.fade.kill()
	var from := d.amp.duplicate()
	var to := {}
	for l in d.index:
		var db := float(mix.get(l, OFF_DB))
		to[l] = db_to_linear(db) if db > OFF_DB else 0.0
	var total := maxf(FADE_IN, FADE_OUT)
	d.fade = create_tween()
	d.fade.tween_method(_fade_step.bind(d, from, to, total), 0.0, 1.0, total)


## Rising layers reach full in FADE_IN, falling ones leave over FADE_OUT.
func _fade_step(t: float, d: Deck, from: Dictionary, to: Dictionary, total: float) -> void:
	for l in to:
		var a: float = from.get(l, 0.0)
		var b: float = to[l]
		var u := clampf(t * total / (FADE_IN if b > a else FADE_OUT), 0.0, 1.0)
		d.set_amp(l, lerpf(a, b, u))


# ---------------------------------------------------------------- cues

func _play(cue: String) -> void:
	if cue == _cue or not CUES.has(cue):
		return
	_cue = cue
	_intensity = 0
	var c: Dictionary = CUES[cue]
	var set_name := str(c.set)
	var rate := 1.0
	if runtime_tempo and set_name != "main" and not set_name in FREE:
		rate = runtime_rate(set_name)
		set_name = "main"
	var mix := cue_mix(cue, 0)
	_log({ "type": "cue", "cue": cue })
	_queue = _queue.filter(func(q): return q.what != "cue" and q.what != "intensity")
	if _active == null or not _active.player.playing:
		var d := _deck(set_name, rate)
		_start(d, mix, 0.0, START_FADE)
		_log({ "type": "start", "cue": cue, "deck": d.key, "from": 0.0 })
		return
	var target := _deck(set_name, rate)
	if target == _active:
		if absf(target.rate - rate) > 0.001:
			_schedule(_active, "bar", "cue", _retime_and_fade.bind(target, rate, mix))
		else:
			_schedule(_active, "bar", "cue", func(): _fade_layers(target, mix))
	else:
		_schedule(_active, "bar", "cue", func(): _switch(target, mix))


## Crossfade to another tempo set on the bar line, entering it on the same
## bar of the progression.
func _switch(to: Deck, mix: Dictionary) -> void:
	var from_deck := _active
	var bar_i := int(round(from_deck.abs_pos() / from_deck.bar())) % BARS
	if from_deck.set_name in FREE or to.set_name in FREE:
		bar_i = 0                                    # D239: a phrase loop has no shared progression
	_stop(from_deck, DECK_OUT)
	_start(to, mix, bar_i * to.bar(), DECK_IN)
	_log({ "type": "start", "cue": _cue, "deck": to.key, "from": bar_i * to.bar(), "bar": bar_i })


## Runtime tempo change on the stretch deck: pitch_scale and its
## compensating pitch shift glide together over one bar.
func _retime(d: Deck, rate: float) -> void:
	var r0 := d.rate
	d.rate = rate
	var k := BWAudio.effect_index("MusicStretch", "AudioEffectPitchShift")
	var fx: AudioEffectPitchShift = AudioServer.get_bus_effect(AudioServer.get_bus_index("MusicStretch"), k) if k >= 0 else null
	var tw := create_tween()
	tw.tween_method(_retime_step.bind(d, fx), r0, rate, d.bar() / rate)


func _retime_step(r: float, d: Deck, fx: AudioEffectPitchShift) -> void:
	d.player.pitch_scale = r
	if fx:
		fx.pitch_scale = 1.0 / r


func _retime_and_fade(d: Deck, rate: float, mix: Dictionary) -> void:
	_retime(d, rate)
	_fade_layers(d, mix)


func _set_intensity(level: int) -> void:
	var c: Dictionary = CUES.get(_cue, {})
	if not c.has("intensity") or level == _intensity or _active == null:
		return
	_intensity = level
	var mix := cue_mix(_cue, level)
	var d := _active
	_queue = _queue.filter(func(q): return q.what != "intensity")
	_schedule(d, "beat", "intensity", func(): _fade_layers(d, mix))
	_log({ "type": "intensity", "cue": _cue, "level": level })


func _sting(kind: String) -> void:
	if not STINGS.has(kind):
		return
	_stop_sting(0.3, false)                          # D240: one sting at a time, never stacked
	var name: String = STINGS[kind]
	_sting_kind = kind
	_sting_token += 1
	var hold := sting_hold(name) + lead
	duck.begin(hold)                                 # D411: out, hold until it has rung out, back in
	_log({ "type": "sting", "kind": kind, "sfx": BWSfx.resolve(name), "hold_s": hold, "lead_s": lead })
	if lead > 0.0 and is_inside_tree():
		_sting_pending = true                        # "fade the existing track out, play the jingle"
		get_tree().create_timer(lead).timeout.connect(_sting_start.bind(_sting_token, name))
	else:
		_sting_start(_sting_token, name)


func _sting_start(token: int, name: String) -> void:
	if token != _sting_token:
		return                                       # replaced or stopped while the music faded
	_sting_pending = false
	_sting_player = BWSfx.ui(name, { "tag": "sting", "stack": true })
	_log({ "type": "sting_start", "kind": _sting_kind, "sfx": BWSfx.resolve(name) })


## D411: how long the music stays out under a sting, from its start: until
## it falls 30 dB under its peak (sfx.json tail_s), so the fade-in rises over
## the last of its reverb. Older manifests: body_s + 1 s, else length - 1 s.
static func sting_hold(name: String) -> float:
	var lv: Array = BWSfx.info(name).get("levels", [])
	if not lv.is_empty():
		var l0: Dictionary = lv[0]
		if l0.has("tail_s"):
			return float(l0.tail_s)
		if l0.has("body_s"):
			return float(l0.body_s) + 1.0
		if l0.has("seconds"):
			return maxf(float(l0.seconds) - 1.0, 0.5)
	return 2.0


## Fade the playing sting out (a picker closed, a newer sting); `release`
## also brings the music back in (D411: over DUCK_IN, starting while the
## sting fades) instead of waiting out its hold.
static func stop_sting(fade: float = 0.6, kind: String = "") -> void:
	if _inst and (kind == "" or kind == _inst._sting_kind):
		_inst._stop_sting(fade, true)


func _stop_sting(fade: float, release: bool) -> void:
	var p := _sting_player
	_sting_player = null
	_sting_kind = ""
	_sting_token += 1                                # a pending start never plays
	_sting_pending = false
	if p != null and is_instance_valid(p) and p.is_inside_tree():
		BWSfx.loop_stop(p, fade)
	if release:
		duck.release(fade * 0.5)


## D411: drive the bus duck. A sting that is gone (freed, or never started:
## no manifest entry, a skipped play) can't hold the music out.
func _step_duck(delta: float) -> void:
	if not duck.active():
		if _duck_db != 0.0:
			_set_duck_db(0.0)
		return
	var gone := _sting_player != null and not is_instance_valid(_sting_player)      # freed under us
	var never := _sting_player == null and _sting_kind != "" and not _sting_pending  # asked for, never played
	if duck.state != Duck.UP and (gone or never):
		duck.release(0.0)
	var was := duck.state
	_set_duck_db(duck.step(delta))
	if duck.state != was:
		_log({ "type": "duck", "state": ["idle", "down", "held", "up"][duck.state], "db": _duck_db })


# ---------------------------------------------------------------- the grid

func _schedule(d: Deck, quant: String, what: String, fn: Callable) -> void:
	var q := d.bar() if quant == "bar" else d.beat()
	var now := d.abs_pos()
	var at := (floorf(now / q) + 1.0) * q
	if at - now < 0.02:
		at += q
	if d.set_name in FREE:
		at = now + 0.02                              # D239: no grid to wait for: leave on the next frame
	_queue.append({ "deck": d, "at": at, "fn": fn, "what": what, "quant": quant })


func _process(delta: float) -> void:
	_step_duck(delta)
	var i := 0
	while i < _queue.size():
		var q: Dictionary = _queue[i]
		var d: Deck = q.deck
		var pos := d.abs_pos()
		# apply on the frame nearest the boundary: the change reaches the next mix
		if not d.player.playing or pos + delta * d.rate * 0.5 >= float(q.at):
			_queue.remove_at(i)
			q.fn.call()
			_log({ "type": "applied", "what": q.what, "quant": q.quant, "deck": d.key, "cue": _cue,
				"target_s": q.at, "pos_s": pos, "err_ms": (pos - float(q.at)) * 1000.0 / d.rate,
				"grid_s": d.bar() if q.quant == "bar" else d.beat() })
			continue
		i += 1


func _log(e: Dictionary) -> void:
	if log_enabled:
		e["usec"] = Time.get_ticks_usec()
		e["frame"] = Engine.get_process_frames()
		if _active:
			e["deck_pos_s"] = _active.abs_pos()
			e["active"] = _active.key
		events.append(e)
