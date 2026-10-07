class_name BWUnitAudio
extends Node
## Sound for one BWUnitView, driven only by its animation: it listens to the
## animator's markers (BWAnimator.marker) and watches the clip on top and the
## foot lock. Never edits clips or poses. BWAudioDirector adds one to every
## unit view that enters the tree.
##
## Markers -> sound (design/art/ANIMATION.md clip table):
##   strike / strike_axe  launch   swing whoosh (light / heavy / axe), its
##                                 loudest moment lined up on `hit`
##                        hit2     second light whoosh (paired daggers)
##                        release  bow twang / pistol shot / flintlock
##   strike (bow)         clip start  draw creak
##   cast                 clip start  cast whoom, its peak on `release`
##                        release  bolt fizz
##   channel              clip on top  a hum loop while it lasts
##   any reaction         impact   the blow as the battle resolved it (see
##                                 expect()): flesh / crit ring / glance
##                                 scrape / blocked clank / whiff, + arrow
##                                 thunk, + the element's hit, + a grunt
##   stricken_rage        shout    "No" / "Hiyah" (the shout of the clip)
##   stricken_shrug       catch    "Hmm"
##   stricken_knockback   slide_end  a skid of scuffs
##   fall                 grounded KO thud
##   gaits                a foot lock engaging while the root moves: a step
##
## D393 placeholders (ph_*, tools/audio/make_placeholders.py):
##   cast (a big cast)    release  ph_cast_<element> instead of the bolt fizz
##                                 (combat_audio flags it with expect_cast)
##   strike_spin (Fan of Knives)  launch  ph_fan_knives, peak on `hit`
##   strike_colossus      launch   ph_colossus_thrust, peak on `hit`
##   stomp_colossus       stomp    ph_colossus_step, louder
##   gaits by encounter   Colossus ph_colossus_step, Blank ph_blank_step
##   an Elemental Being   alive    ph_being_hum, a quiet loop on the view
##
## Grunts: hits make the defender grunt ("Oof", "Ouch grunt", "Oogh") at its
## voice_pitch, and strikes sometimes get a "Hiyah"/"Yah", with a per-unit
## cooldown and a global gap so it never chatters.

## Reaction variant (BWReactionPick, exposed as BWUnitView.last_reaction and
## the reaction clip's name) -> bark clip and the marker it speaks on.
const VARIANT_BARKS := {
	"stricken_rage": { "clips": ["no", "hiyah"], "marker": "shout" },
	"stricken_shrug": { "clips": ["hmm"], "marker": "catch" },
	"stricken_stumble": { "clips": ["oogh"], "marker": "impact" },
	"stricken_flinch": { "clips": ["ouch_grunt"], "marker": "impact" },
	"stricken_knockback": { "clips": ["oof"], "marker": "impact" },
}
const HIT_GRUNTS: PackedStringArray = ["oof", "ouch_grunt", "oogh"]
const STRIKE_SHOUTS: PackedStringArray = ["hiyah", "yah"]
const REACTIONS: PackedStringArray = ["stricken", "fumble", "block", "dodge", "kneel", "fall",
	"stricken_flinch", "stricken_shrug", "stricken_stumble", "stricken_knockback", "stricken_rage"]
const HEAVY_SETS: PackedStringArray = ["heavy", "polearm"]
const GRUNT_CHANCE := 0.75
const SHOUT_CHANCE := 0.3
const GRUNT_COOLDOWN := 3.5          # per unit, seconds
const GRUNT_GAP := 0.9               # between any two grunts
const STEP_MIN := 0.14               # same foot, seconds
const MOVING := 0.35                 # root speed (u/s) that counts as walking
const EXPECT_TTL := 4.0
## Markers worth leading. A 3D player only starts on the next physics tick,
## and a marker is only reported on the frame after it is crossed: a marker
## known to be within 1.5 frames is played now instead, which centres the
## sound on the marker (within half a frame). Markers at frame 0 (most
## impacts) can't be foreseen and play when reported.
const LEAD := ["launch", "hit2", "release", "impact", "grounded", "shout", "catch", "slide_end"]
const LEAD_FRAMES := 1.5

static var _last_grunt_any := -10.0
static var log_enabled := false
static var events: Array = []        # capture log: marker crossings { unit, clip, marker, usec, frame }

var view: BWUnitView
var _an: BWAnimator
var _top := ""
var _expect := {}                    # the blow this unit is about to take
var _channel: Node
var _locked := { "l": false, "r": false }
var _step_at := { "l": -1.0, "r": -1.0 }
var _last_grunt := -10.0
var _rng := RandomNumberGenerator.new()
var _layer: Variant = null           # the animator's top layer (identity: a new play of a clip)
var _serial := 0
var _cast := {}                      # D393: the big cast / fan this unit is about to make
var _hum: Node                       # D393: an Elemental Being's idle hum
var _led := {}                       # "serial:marker" already played ahead of its report


func _ready() -> void:
	view = get_parent() as BWUnitView
	_rng.seed = hash(view.name if view else name)


## The battle's verdict for the next blow on `v`: { result, element, set,
## model, ko }. Consumed by the reaction's `impact` marker.
static func expect(v: Node, info: Dictionary) -> void:
	var ua := of(v)
	if ua:
		var e := info.duplicate()
		e["at"] = Time.get_ticks_msec() / 1000.0
		ua._expect = e


## D393: the caster's next cast release (or spin) is a big one: { kind
## "cast", element } or { kind "fan" }. Consumed by the marker; a unit with
## no animator sounds it at once.
static func expect_cast(v: Node, info: Dictionary) -> void:
	var ua := of(v)
	if ua == null:
		return
	if ua._an == null or (v is BWUnitView and (v as BWUnitView).character == null):
		ua._sfx(cast_sound(info), { "tag": "big_cast_now" })
		return
	var e := info.duplicate()
	e["at"] = Time.get_ticks_msec() / 1000.0
	ua._cast = e


static func cast_sound(info: Dictionary) -> String:
	return "ph_fan_knives" if str(info.get("kind", "")) == "fan" else "ph_cast_" + str(info.get("element", "fire"))


func _take_cast(kind: String) -> Dictionary:
	var c := _cast
	if c.is_empty() or str(c.get("kind", "")) != kind or Time.get_ticks_msec() / 1000.0 - float(c.get("at", 0.0)) > EXPECT_TTL:
		return {}
	_cast = {}
	return c


static func of(v: Node) -> BWUnitAudio:
	if v == null or not is_instance_valid(v):
		return null
	for c in v.get_children():
		if c is BWUnitAudio:
			return c
	return null


func _pitch() -> float:
	if view == null or view.unit == null:
		return 1.0
	if view.unit.size > 1:
		return 0.62                       # the Giant
	return float(view.unit.cosmetics.get("voice_pitch", 1.0))


func _set_id() -> String:
	return _an.set_id if _an else ""


func _process(_delta: float) -> void:
	if view == null:
		return
	_being_hum()
	var an: BWAnimator = view.character.animator if view.character else null
	if an != _an:
		if _an and _an.marker.is_connected(_on_marker):
			_an.marker.disconnect(_on_marker)
		_an = an
		_top = ""
		if _an:
			_an.marker.connect(_on_marker)
	if _an == null:
		return
	var top := _an.top_clip()
	var layer: Variant = _an.layers.back() if not _an.layers.is_empty() else null
	if not is_same(layer, _layer):
		_layer = layer
		_serial += 1
		_led.clear()
	if top != _top:
		_on_clip_change(top, _top)
		_top = top
	_lead(_delta)
	_footsteps()


## Plays the markers that the next frame will cross, now (see LEAD).
func _lead(delta: float) -> void:
	if not _layer is Dictionary or str(_layer.get("kind", "")) != "clip":
		return
	var l: Dictionary = _layer
	var marks: Dictionary = _an.clip_meta(str(l.clip)).get("markers", {})
	for m in LEAD:
		if not marks.has(m) or _led.has(m):
			continue
		var mt := float(marks[m])
		var hold := float(l.get("hold", -1.0))
		if hold >= 0.0 and float(l.t) <= hold + 1e-4 and mt > hold + 1e-4:
			continue                          # held (a windup at its coil): not moving toward it
		var tt := _an.time_to(m)
		if tt > 0.0 and tt <= delta * LEAD_FRAMES:
			_led[m] = true
			_handle(str(l.clip), m, Time.get_ticks_usec() + int(tt * 1e6), true)


func _exit_tree() -> void:
	BWSfx.loop_stop(_channel, 0.05)
	_channel = null
	BWSfx.loop_stop(_hum, 0.05)
	_hum = null


## D393: an Elemental Being hums while it lives (pitched by its element so
## three don't phase into one tone).
const HUM_PITCH := { "fire": 1.0, "water": 0.89, "ice": 1.12, "thunder": 1.06, "wind": 0.94, "light": 1.19, "dark": 0.84 }

func _being_hum() -> void:
	if view.unit == null or str(view.unit.encounter) != "being":
		return
	var on := view.unit.alive() and view.is_inside_tree() and view.visible
	if on and (_hum == null or not is_instance_valid(_hum)):
		_hum = BWSfx.loop_start("ph_being_hum", view, { "tag": "being_hum", "stack": true,
			"pitch": float(HUM_PITCH.get(str(view.unit.element), 1.0)) })
	elif not on and _hum != null:
		BWSfx.loop_stop(_hum, 0.6)
		_hum = null


# ---------------------------------------------------------------- clips

func _on_clip_change(top: String, prev: String) -> void:
	if prev == "channel" and top != "channel":
		BWSfx.loop_stop(_channel)
		_channel = null
	match top:
		"channel":
			if _channel == null or not is_instance_valid(_channel):
				_channel = BWSfx.loop_start("channel_loop", view, { "tag": "channel" })
		"strike":
			if _set_id() == "bow" and prev != "strike":
				_sfx("bow_draw", { "tag": "bow_draw" })
		"cast":
			_aligned("cast_whoom", "release", "cast_whoom")


func _on_marker(clip: String, m: String) -> void:
	# the true moment the playhead crossed it (it is reported a frame late)
	var now := Time.get_ticks_usec()
	var true_usec := now
	var mt := _an.marker_time(clip, m)
	if mt > 0.0 and not _an.layers.is_empty():
		var l: Dictionary = _an.layers.back()
		var rate := maxf(float(l.get("rate", 1.0)), 0.05)
		var t1 := float(l.t) + get_process_delta_time() * rate
		true_usec = now - int(maxf(t1 - mt, 0.0) / rate * 1e6)
	if _led.has(m) and not _an.layers.is_empty() and is_same(_an.layers.back(), _layer):
		_log(clip, m, true_usec, false, true)
		return                                   # already played ahead
	_handle(clip, m, true_usec, false)


func _log(clip: String, m: String, true_usec: int, led: bool, skipped: bool = false) -> void:
	if log_enabled:
		events.append({ "unit": view.unit.id if view and view.unit else "", "clip": clip, "marker": m,
			"usec": Time.get_ticks_usec(), "true_usec": true_usec, "frame": Engine.get_process_frames(),
			"led": led, "report_after_lead": skipped })


func _handle(clip: String, m: String, true_usec: int, led: bool) -> void:
	_log(clip, m, true_usec, led)
	var st := _set_id()
	if clip == "strike" or clip == "strike_axe":
		match m:
			"launch":
				var kind := "swing_axe" if clip == "strike_axe" else ("swing_heavy" if st in HEAVY_SETS else "swing_light")
				_aligned(kind, "hit", "launch")
				_maybe_shout()
			"hit2":
				_sfx("swing_light", { "offset": 0.04, "tag": "hit2" })
			"release":
				if st == "bow":
					_sfx("bow_release", { "tag": "release" })
				elif st == "pistol":
					var model := str(view.unit.weapon_model) if view and view.unit else ""
					_sfx("flintlock_shot" if model == "flintlock" else "pistol_shot", { "tag": "release" })
					_maybe_shout()
		return
	if clip == "cast":
		if m == "release":
			var big := _take_cast("cast")
			if big.is_empty():
				_sfx("bolt_fizz", { "tag": "release" })
			else:
				_sfx(cast_sound(big), { "tag": "big_cast" })      # D393
		return
	# ---- D393 placeholders: Fan of Knives, the Colossus ----
	if clip == "strike_spin" and m == "launch" and not _take_cast("fan").is_empty():
		_aligned("ph_fan_knives", "hit", "fan_knives")
		return
	if clip == "strike_colossus" and m == "launch":
		_aligned("ph_colossus_thrust", "hit", "colossus_thrust")
		return
	if clip == "stomp_colossus" and m == "stomp":
		_sfx("ph_colossus_step", { "gain_db": 4.0, "stack": true, "tag": "colossus_stomp" })
		return
	if clip == "fall":
		if m == "grounded":
			_sfx("ko_thud", { "tag": "grounded", "pitch": 0.75 if view.unit.size > 1 else 1.0, "gain_db": 4.0 if view.unit.size > 1 else 0.0 })
		return
	if clip in REACTIONS:
		if m == "impact":
			_impact(clip)
		var vb: Dictionary = VARIANT_BARKS.get(clip, {})
		if not vb.is_empty() and m == str(vb.marker) and m != "impact":
			_grunt(vb.clips, true)
		if clip == "stricken_knockback" and m == "slide_end":
			for k in 3:
				_sfx("step_stone", { "delay": 0.06 * k, "stack": true, "gain_db": 6.0, "tag": "skid" })


## A sound whose loudest moment should land on a marker still ahead (a
## swing's whoosh on `hit`, the cast's whoom on `release`): delayed if the
## marker is far, started part-way in if it is close.
func _aligned(name: String, marker_name: String, tag: String) -> void:
	var v := BWSfx.pick(name)
	var pk := BWSfx.peak_s(name, v)
	var tt := _an.time_to(marker_name) if _an else -1.0
	var opts := { "variant": v, "tag": tag }
	if tt > pk:
		opts["delay"] = tt - pk
	elif tt >= 0.0:
		opts["offset"] = pk - tt
	_sfx(name, opts)


func _impact(clip: String) -> void:
	var e := _expect
	_expect = {}
	if e.is_empty() or Time.get_ticks_msec() / 1000.0 - float(e.get("at", 0.0)) > EXPECT_TTL:
		return                               # a pose with no blow behind it (shoves, previews)
	var res: Dictionary = e.get("result", {})
	var hit := bool(res.get("hit", false))
	var big := view.unit.size > 1
	var po := { "pitch": 0.8 if big else 1.0, "tag": "impact" }
	if not hit:
		_sfx("hit_miss", po)
		return
	if bool(res.get("resisted", false)):
		_sfx("hit_block", po)
	elif bool(res.get("glance", false)):
		_sfx("hit_glance" if clip != "block" or _rng.randf() < 0.5 else "hit_block", po)
	elif bool(res.get("crit", false)):
		_sfx("hit_crit", po)
	else:
		_sfx("hit_flesh", po)
	if str(e.get("set", "")) == "bow":
		_sfx("arrow_thunk", { "tag": "impact" })
	var el := str(e.get("element", ""))
	if el != "" and BWSfx.variants("elem_" + el) > 0:
		_sfx("elem_" + el, { "tag": "impact" })
	# the defender's voice: the variant's own line, or a generic grunt
	var vb: Dictionary = VARIANT_BARKS.get(_variant(clip), {})
	if not vb.is_empty():
		if str(vb.marker) == "impact":
			_grunt(vb.clips, true)
	elif not bool(e.get("ko", false)) and clip != "block":
		_grunt(HIT_GRUNTS, false)


## The reaction variant this unit is playing: the clip itself, or what the
## reactions lane recorded on the view (BWUnitView.last_reaction).
func _variant(clip: String) -> String:
	if VARIANT_BARKS.has(clip):
		return clip
	var lr: Variant = view.get("last_reaction") if view else null
	return str(lr) if lr != null and VARIANT_BARKS.has(str(lr)) else ""


func _maybe_shout() -> void:
	if _rng.randf() < SHOUT_CHANCE:
		_grunt(STRIKE_SHOUTS, false)


func _grunt(clips: Variant, force_chance: bool) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_grunt < GRUNT_COOLDOWN or now - _last_grunt_any < GRUNT_GAP:
		return
	if not force_chance and _rng.randf() > GRUNT_CHANCE:
		return
	var list: Array = Array(clips)
	if list.is_empty() or view == null or not view.is_inside_tree():
		return
	_last_grunt = now
	_last_grunt_any = now
	BWVoice.grunt(view, str(list[_rng.randi() % list.size()]), _pitch())


func _sfx(name: String, opts: Dictionary = {}) -> void:
	if view == null or not view.is_inside_tree() or not view.visible:
		return
	opts["unit"] = view.unit.id if view.unit else ""
	BWSfx.play(name, view, opts)


# ---------------------------------------------------------------- feet

## A foot lock engaging is a contact. Only while the root actually travels
## (idle fidgets and turns on the spot stay quiet).
func _footsteps() -> void:
	var lock: Variant = _an.get("_lock")
	if not lock is Dictionary:
		return
	var moving := Vector2(_an.velocity.x, _an.velocity.z).length() > MOVING
	var now := Time.get_ticks_msec() / 1000.0
	for s in ["l", "r"]:
		var L: Variant = (lock as Dictionary).get(s, {})
		var on := L is Dictionary and bool((L as Dictionary).get("on", false))
		if on and not bool(_locked[s]) and moving and now - float(_step_at[s]) > STEP_MIN:
			_step_at[s] = now
			var big := view.unit.size > 1
			match str(view.unit.encounter):            # D393 placeholders
				"colossus": _sfx("ph_colossus_step", { "stack": true, "tag": "step" })
				"blank": _sfx("ph_blank_step", { "stack": true, "tag": "step" })
				_: _sfx("step_stone", { "stack": true, "tag": "step", "pitch": 0.55 if big else 1.0, "gain_db": 9.0 if big else 0.0 })
		_locked[s] = on
