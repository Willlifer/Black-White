class_name BWAnimator
extends RefCounted
## Plays a clip set (BWAnimClips: one library per weapon style) on a
## BWCharacter, in pose space.
##
##   var an := BWAnimator.new(character, "heavy")
##   an.play("run")             # pose names: BWAnimClips.ACTION_NAMES (+ any static key)
##   an.update(delta)           # every frame: sample, blend, lock feet, solve, secondary motion
##   an.time_to("hit")          # seconds until a marker of the playing clip (-1: none ahead)
##   an.marker.connect(...)     # (clip, marker) as the playhead crosses it
##   an.plan_move(dist, hexes)  # gait + root timing for a move (run with start/stop, walk, limp)
##
## STATE MACHINE (design/art/ANIMATION.md has the diagram):
##   idle (home loop, per personality) rotates idle variants (one-shots)
##     every few seconds; a variant never blocks anything
##   idle <-> walk / run (loops; rate follows the root speed, or the move
##     plan's rate for a planned run)
##   standstill -> run: run_start first (authored footsteps), then run
##   run -> run_stop: the stop entered on whichever foot is down
##   any -> windup: the strike from 0, HELD at "coil"; strike releases it
##   channel (loop) -> cast: the cast starts at its "coil"
##   any -> hit / fumble / block / dodge / kneel: the reaction from 0
##   any -> fall: plays and HOLDS on the ground (hold_end)
##   wounded (HP < 35%, BWUnitView sets it): idle -> wounded, walk / run -> limp
##   turn_l / turn_r: BWCharacter starts them on a snap turn while standing
##   WEAPON HANDLING (BWAnimHandling, D80): standing, the idle rotates HOLDS
##     (guard, side, shoulder, ground, the daggers' reverse grip) through
##     authored transitions every hold_iv seconds, with ACTIONS (heft,
##     admire, the style's trick and specials, look / fidget) every act_iv
##     between; `showcase` (the roster stage) roughly doubles both rates.
##     Any other request leaves the hold: the hands lead back to the guard
##     over ~0.25 s inside the incoming clip (a hand-only fade, so marker
##     timing is untouched; for reversed daggers it is the quick flip back)
##   one-shot end -> idle (or whatever was asked for while it played)
##   idle() during a one-shot is deferred to its end; any other request cuts in
##   pose names the set has no clip for: the static key pose (the fallback)
##
## BLENDING: a stack of layers, each fading in over its blend time with a
## smoothstep; a layer that reaches full weight drops the ones beneath. The
## outgoing clip keeps playing while it fades, so motion carries through,
## and an interrupted blend just stacks another layer: nothing ever pops.
## Hands keyed in different frames (root vs chest) are converted into the
## incoming frame before mixing. Feet don't cross-fade along the floor: a
## foot that must move more than 4 cm steps there on a lifted arc.
##
## RUNTIME LAYERS on top of the clips:
##   foot lock     contact frames pin the foot in world space (no skid when
##                 the root turns, eases or changes speed); a foot that
##                 drifts too far from its clip target re-steps on its own
##   inertia       root acceleration leans the upper body against it on a
##                 spring (stops overshoot and settle; starts lag); the head
##                 follows a beat later
##   turn          the head leads a turn, the chest banks into it
##   hair          long-hair tail bones on damped springs, chained so each
##                 bone lags the one above it (follow-through and overlap)
##   smear         a white swoosh with an ink rim behind the blade while the
##                 clip's `smear` channel is up
## The scarf (sweater_scarf) already rides BWClothing.ScarfSway, which
## follows whatever the skeleton does.

signal marker(clip: String, name: String)
signal finished(clip: String)

## Blend times (s), "from>to" with "*" wildcards; first match wins.
const BLENDS := {
	"walk>idle": 0.24, "idle>walk": 0.16, "*>stricken": 0.05, "*>stricken_flinch": 0.05, "*>stricken_shrug": 0.05,
	"*>stricken_stumble": 0.05, "*>stricken_knockback": 0.1, "*>stricken_rage": 0.05, "*>fumble": 0.05, "*>kneel": 0.05, "*>fall": 0.06,
	"*>block": 0.06, "*>dodge": 0.06, "*>strike": 0.1, "*>strike_axe": 0.1, "run_start>run": 0.05,
	"run_start>run_heavy": 0.1, "run>run_stop": 0.06, "run>run_stop_r": 0.06, "run_heavy>run_stop": 0.08,
	"run_heavy>run_stop_r": 0.08, "*>run_start": 0.08, "channel>cast": 0.06, "*>turn_l": 0.08, "*>turn_r": 0.08,
	"*>idle_fidget": 0.3, "*>idle_look": 0.3, "*>idle_weapon": 0.3, "*>hold_*": 0.25, "hold_*>act_*": 0.22,
	"hold_*>hold_*": 0.22, "*>act_*": 0.28, "*>wounded": 0.35, "*>limp": 0.2,
	"strike>idle": 0.2, "stricken>idle": 0.2, "*>idle": 0.22, "*>idle_bouncy": 0.22, "*>walk": 0.16, "*>run": 0.12, "*>*": 0.12,
}
const LOCK_DRIFT := 0.14          ## a locked foot this far from its clip target re-steps
const LOCK_TWIST := 0.7           ## ... or turned this far (radians) from it
const STEP_TIME := 0.16           ## procedural re-step duration
const RELEASE_TIME := 0.1         ## lock release ease
const WOUNDED_HP := 0.35          ## below this share of max HP: wounded idle, limp
const SMEAR_LIFE := 0.09          ## seconds of blade path the smear keeps (its tail)

var character: BWCharacter
var poser: BWCharacterPose
var set_id := ""
var weapon_class := ""
var library: AnimationLibrary
var actions := {}
var personality := {}             ## BWAnimClips.personality(): vibe, home idle, variants, rate ...
var current := ""                 ## last requested pose name
var layers: Array = []            ## bottom .. top; see _clip_layer()
var pending := ""                 ## pose to play when the running one-shot ends
var walk_rate := -1.0             ## >= 0 forces the locomotion playback rate (tools); < 0 = follow root speed
var run_rate := -1.0              ## > 0: a planned run's rate (phase-aligns the stop); reset by any other request
var wounded := false              ## HP < 35%: idle -> wounded, walk / run -> limp
var rotate_idles := true          ## play idle variants while standing (tools turn it off)
var hold := "guard"               ## weapon handling: the hold standing in (BWAnimHandling.HOLDS)
var showcase := false             ## the roster stage: more handling variety (set_showcase)
var lock_enabled := true
var secondary_enabled := true
## motion of the character root in its own (model) frame, set by BWCharacter
var velocity := Vector3.ZERO
var accel := Vector3.ZERO
var yaw_rate := 0.0
var last_pose := {}               ## the pose solved last frame (tests, tools)

var _tracks := {}                 # Animation -> Array of [track, key, sub]
var _lean := Vector2.ZERO         # inertia spring state (pitch, roll)
var _lean_v := Vector2.ZERO
var _head := Vector2.ZERO         # head follow spring
var _head_v := Vector2.ZERO
var _turn := 0.0
var _lock := { "l": {}, "r": {} }
var _hair: Array = []             # [{bone, parent, len, tip, vel, k, c}]
var _hair_sk: Skeleton3D
var _swoosh: MeshInstance3D
var _swoosh_hist: Array = []
var _swoosh_hist2: Array = []     # the paired daggers' second blade
var _idle_t := 0.0                # seconds standing in the home idle
var _idle_next := 0.0             # when the next variant plays
var _variant_i := 0
var _rng := RandomNumberGenerator.new()
var _hold_clock := 0.0            # seconds standing in this hold
var _hold_next := 0.0
var _act_clock := 0.0             # seconds standing since the last action
var _act_next := 0.0
var _seq: Array = []              # handling clips still to play (out, then in)
var _last_act := ""
var _hand_lead := false           # the next push leads the hands back from a hold
## D219-D220: the special encounter this body belongs to ("" = none):
## "colossus", "grunt", "blank", "being" (BWAnimEncounter's header).
var encounter := ""
## The figure's world scale (BWCharacter sets it; the Colossus's 2.6): a
## gait's rate is the root speed over the clip speed times this, so a big
## stride isn't played at a small one's cadence.
var body_scale := 1.0
var _enc_t := 0.0
var _enc_w := 0.0                 # the blank's / being's layer weight (eased)
var _enc_pace := 1.0              # grunt: its own walking pace
var _base := {}                   # the set's guard (the blank holds it)


func _init(c: BWCharacter, set_name: String) -> void:
	character = c
	poser = c.poser
	set_id = set_name
	library = BWAnimClips.load_set(set_name)
	weapon_class = str(c.weapon.meta.get("class", "")) if c.weapon else ""
	actions = BWAnimClips.actions_for(set_name, weapon_class)
	var uid := c.unit.id if c.unit else "x"
	personality = BWAnimClips.personality(uid, BWAnimClips.vibe_of(c.unit))   # D153
	# the character's own home idle, careful walk and celebration
	actions.idle = { "clip": str(personality.idle) }
	actions.cheer = { "clip": str(personality.cheer) }
	# the plain "hit" plays the character's own stricken (the cutscene picks
	# a variant by context instead: BWReactionPick)
	if library.has_animation(StringName(str(personality.get("hit", "stricken")))):
		actions.hit = { "clip": str(personality.hit) }
	if str(actions.walk.clip) == "walk":
		actions.walk = { "clip": str(personality.walk) }
	_rng.seed = absi(hash(uid + "|idle"))
	_encounter_setup(c.unit)
	_idle_next = _next_interval()
	_hold_next = _rng.randf_range(0.25, 0.7) * float(_hiv()[1])
	_act_next = _rng.randf_range(0.3, 0.8) * float(_aiv()[1])


## True when this set has a clip for the pose (otherwise play() holds the static key).
## A clip's own name is a pose too (idle_look, cheer_cool, stricken ...: the
## hall asks for them by name, D222).
func has_clip(pose_name: String) -> bool:
	var act := _act(pose_name)
	return not act.is_empty() and library.has_animation(StringName(str(act.clip)))


## The action for a pose name: actions_for's route, else a clip of that name.
func _act(pose_name: String) -> Dictionary:
	if actions.has(pose_name):
		return actions[pose_name]
	if pose_name != "" and library != null and library.has_animation(StringName(pose_name)):
		return { "clip": pose_name }
	return {}


func clip_meta(clip: String) -> Dictionary:
	if library == null or not library.has_animation(clip):
		return {}
	return library.get_animation(clip).get_meta("bw", {})


## Root speed (u/s) at which the walk's feet don't slide.
func walk_speed() -> float:
	return float(clip_meta(str(actions.get("walk", {}).get("clip", "walk"))).get("speed", 0.0))


## Root speed (u/s) of the run.
func run_speed() -> float:
	return float(clip_meta(str(actions.get("run", {}).get("clip", "run"))).get("speed", 0.0))


func set_wounded(v: bool) -> void:
	if v == wounded:
		return
	wounded = v
	if current in ["idle", "walk", "run"]:
		play(current)


# ------------------------------------------------------------------ control

## The clip a pose name plays now (wounded swaps idle / walk / run).
func _clip_for(pose_name: String) -> String:
	if wounded and pose_name == "idle" and library.has_animation(&"wounded"):
		return "wounded"
	if wounded and pose_name in ["walk", "run"] and library.has_animation(&"limp"):
		return "limp"
	if pose_name == "idle" and hold != "guard" and library.has_animation(StringName(BWAnimHandling.loop_clip(hold))):
		return BWAnimHandling.loop_clip(hold)
	return str(_act(pose_name).clip)


## Request a pose. blend < 0: the BLENDS table; 0: snap (stills, tests: a
## clip snaps to its "pose" marker).
func play(pose_name: String, blend: float = -1.0) -> void:
	var top: Dictionary = layers.back() if not layers.is_empty() else {}
	var act: Dictionary = _act(pose_name)
	if not pose_name in ["run", "run_stop"]:
		run_rate = -1.0
	if act.is_empty() or not library.has_animation(StringName(str(act.clip))):
		current = pose_name
		_leave_hold(top)
		_push(_key_layer(pose_name), blend, top)
		pending = ""
		return
	var clip := _clip_for(pose_name)
	if pose_name == "run_stop":
		clip = _stop_clip(top)
	var hold := float(clip_meta(clip).get("markers", {}).get(str(act.get("hold", "")), -1.0))
	if not top.is_empty() and top.kind == "clip" and top.clip == clip and blend != 0.0:
		if top.loop:
			current = pose_name
			return                                   # already looping it
		if top.hold >= 0.0 and hold < 0.0:
			current = pose_name
			top.hold = -1.0                          # windup -> strike: release the coil
			pending = ""
			return
		if top.hold >= 0.0 and is_equal_approx(hold, float(top.hold)):
			current = pose_name
			return                                   # D221: already holding this coil (a dash's windup, then the cutscene's)
	# a one-shot runs out before idle; a held anticipation (aim, a dash's
	# coil) has no end, so idle takes over from it (D221)
	var held: bool = not top.is_empty() and top.kind == "clip" and float(top.get("hold", -1.0)) >= 0.0
	if pose_name == "idle" and not top.is_empty() and _is_oneshot(top) and not top.ended and blend != 0.0 and not held:
		pending = "idle"                             # let the action finish; it ends on idle
		if bool(top.get("variant", false)):
			current = "idle"
		return
	if pose_name != "idle" or wounded:
		_leave_hold(top)
	current = pose_name
	# a run from a standstill starts with its authored start
	var start := str(act.get("start", ""))
	if start != "" and clip != "limp" and blend != 0.0 and library.has_animation(StringName(start)):
		var moving: bool = not top.is_empty() and top.kind == "clip" and (clip_meta(top.clip).has("gait") or top.clip == start)
		if not moving:
			_push(_clip_layer(start), blend, top)
			pending = pose_name
			return
		if top.get("clip", "") == start and not top.ended:
			pending = pose_name                      # the start hands over at its end
			return
	var l := _clip_layer(clip)
	l.hold = hold
	if act.has("from"):
		l.t = float(clip_meta(clip).get("markers", {}).get(str(act.from), 0.0))   # D221: war_cry, land
	var after: Dictionary = act.get("after", {})
	if not top.is_empty() and after.has(str(top.get("clip", ""))):
		l.t = float(clip_meta(clip).get("markers", {}).get(str(after[top.clip]), 0.0))
	if blend == 0.0:
		l.t = float(clip_meta(clip).get("markers", {}).get("pose", 0.0))
	_push(l, blend, top)
	pending = ""


## The stop clip for the run on top: entered on whichever foot is down.
func _stop_clip(top: Dictionary) -> String:
	if top.is_empty() or top.kind != "clip" or not str(top.clip).begins_with("run"):
		return "run_stop"
	var ph := fposmod(float(top.t) / maxf((top.anim as Animation).length, 1e-3), 1.0)
	return "run_stop_r" if ph >= 0.25 and ph < 0.75 and library.has_animation(&"run_stop_r") else "run_stop"


## Seconds until a marker of the clip on top (-1 if it has none ahead).
## A held clip (windup) counts the hold as released.
func time_to(marker_name: String) -> float:
	if layers.is_empty():
		return -1.0
	var top: Dictionary = layers.back()
	if top.kind != "clip":
		return -1.0
	var mt := float(clip_meta(top.clip).get("markers", {}).get(marker_name, -1.0))
	if mt < 0.0 or mt < top.t - 1e-4:
		return -1.0
	return (mt - top.t) / maxf(float(top.rate), 0.05)


## Time of a marker in a clip (seconds from the clip's start; -1: none).
func marker_time(clip: String, marker_name: String) -> float:
	return float(clip_meta(clip).get("markers", {}).get(marker_name, -1.0))


## The clip a pose name would play now ("" = a static key).
func clip_of(pose_name: String) -> String:
	if not has_clip(pose_name):
		return ""
	return _clip_for(pose_name)


func top_clip() -> String:
	if layers.is_empty() or layers.back().kind != "clip":
		return ""
	return layers.back().clip


func is_busy() -> bool:
	if layers.is_empty():
		return false
	var top: Dictionary = layers.back()
	return _is_oneshot(top) and not top.ended and not bool(top.get("variant", false))


func _is_oneshot(l: Dictionary) -> bool:
	return l.kind == "clip" and not l.loop


func _clip_layer(clip: String) -> Dictionary:
	var a := library.get_animation(clip)
	var m: Dictionary = a.get_meta("bw", {})
	return { "kind": "clip", "clip": clip, "anim": a, "t": 0.0, "rate": 1.0, "loop": a.loop_mode != Animation.LOOP_NONE,
		"hold": -1.0, "alpha": 1.0, "fade": 0.0, "ended": false, "from_clip": "", "variant": bool(m.get("variant", false)),
		"hold_end": bool(m.get("hold_end", false)), "halpha": 1.0, "hand_fade": 0.0 }


func _key_layer(pose_name: String) -> Dictionary:
	var p := BWAnimClips.with_extras(BWCharacterPose.resolve(pose_name, poser.style))
	return { "kind": "key", "clip": pose_name, "pose": p, "t": 0.0, "rate": 0.0, "loop": true, "hold": -1.0,
		"alpha": 1.0, "fade": 0.0, "ended": false, "from_clip": "" }


func _push(l: Dictionary, blend: float, top: Dictionary) -> void:
	var from := str(top.get("clip", "")) if not top.is_empty() else ""
	var lead := _hand_lead
	_hand_lead = false
	if blend < 0.0:
		blend = _blend_time(from, str(l.clip))
		# never faster than the body can travel: a big gap (a hit landing
		# mid-dash) stretches the blend so nothing moves > ~2.4 u/s extra
		if not last_pose.is_empty():
			var smp := _sample(l)
			blend = clampf(maxf(blend, _pose_gap(last_pose, smp, not lead) / 2.4), blend, 0.35)
			if set_id == "fists" and str(l.clip).begins_with("stricken"):
				# the fists' high guard swings far on a recoil: ease it in
				blend = maxf(blend, 0.18)
			if lead:
				# leaving a hold: the hands lead back on their own, slower fade
				l.halpha = 0.0
				l.hand_fade = clampf(_hand_gap(last_pose, smp) / 1.6, 0.24, 0.45)
	_idle_t = 0.0
	if blend <= 0.0 or layers.is_empty():
		layers = [l]
		_reset_locks()
		return
	l.alpha = 0.0
	l.fade = blend
	l.from_clip = from
	# feet that must travel step there; remember where they start
	if not last_pose.is_empty():
		l["feet_from"] = { "l": last_pose.foot_l.pos, "r": last_pose.foot_r.pos }
	layers.append(l)
	if layers.size() > 4:
		layers = layers.slice(layers.size() - 4)


## Rough distance between two poses (u): the largest of the root, hand and
## foot offsets, and the spine/head angles at about a head's lever.
static func _pose_gap(a: Dictionary, b: Dictionary, hands: bool = true) -> float:
	var d := (a.root as Vector3).distance_to(b.root)
	for k in (["hand_r", "hand_l", "foot_l", "foot_r"] if hands else ["foot_l", "foot_r"]):
		d = maxf(d, (a[k].pos as Vector3).distance_to(b[k].pos))
	for k in ["hips", "spine", "chest", "head"]:
		d = maxf(d, (a[k] as Vector3).distance_to(b[k]) * 0.6)
	return d


## How far the hands must travel between two poses (u): positions, plus
## the weapon's turn at about a forearm's lever (a dagger flip counts).
static func _hand_gap(a: Dictionary, b: Dictionary) -> float:
	var d := 0.0
	for k in ["hand_r", "hand_l"]:
		d = maxf(d, (a[k].pos as Vector3).distance_to(b[k].pos))
		var x: Vector3 = (a[k].get("aim", Vector3.UP) as Vector3).normalized()
		var y: Vector3 = (b[k].get("aim", Vector3.UP) as Vector3).normalized()
		d = maxf(d, x.angle_to(y) * 0.45)
	return d


func _blend_time(from: String, to: String) -> float:
	var gf := _glob(from)
	var gt := _glob(to)
	for k in [from + ">" + to, "*>" + to, from + ">*", gf + ">" + gt, "*>" + gt, gf + ">*", "*>*"]:
		if BLENDS.has(k):
			return BLENDS[k]
	return 0.12


## "hold_side_in" -> "hold_*", "act_heft" -> "act_*" (BLENDS wildcards).
static func _glob(n: String) -> String:
	for p in ["hold_", "act_"]:
		if n.begins_with(p):
			return p + "*"
	return n


# ---------------------------------------------------------- weapon handling

## Leaving the hold (any request but idle): the hold resets to the guard,
## queued handling clips are dropped, and the next layer leads the hands
## back from wherever the hold or the action had them.
func _leave_hold(top: Dictionary) -> void:
	var on := hold != "guard" or (not top.is_empty() and str(top.get("kind", "")) == "clip" and clip_meta(str(top.clip)).has("handling"))
	if on:
		hold = "guard"
		_seq.clear()
		_hand_lead = true


func _hiv() -> Array:
	var iv: Array = (personality.get("handling", {}) as Dictionary).get("hold_iv", [9.0, 14.0])
	var k := 0.5 if showcase else 1.0
	return [float(iv[0]) * k, float(iv[1]) * k]


func _aiv() -> Array:
	var iv: Array = (personality.get("handling", {}) as Dictionary).get("act_iv", [6.0, 10.0])
	var k := 0.45 if showcase else 1.0
	return [float(iv[0]) * k, float(iv[1]) * k]


## The roster stage: shorter handling intervals (more variety on show).
func set_showcase(v: bool) -> void:
	if v == showcase:
		return
	showcase = v
	_hold_next = minf(_hold_next, _rng.randf_range(float(_hiv()[0]), float(_hiv()[1])))
	_act_next = minf(_act_next, _rng.randf_range(float(_aiv()[0]), float(_aiv()[1])))


## The holds this set can stand in (the ones it has clips for).
func holds() -> Array:
	var out: Array = []
	for h in BWAnimHandling.holds(set_id):
		# the heavy axes' grip sits mid-haft: planted head-down the haft end
		# stands in the face, so they lean them on the shoulder instead
		if h == "ground" and weapon_class == "axe":
			continue
		if h == "guard" or (library.has_animation(StringName("hold_" + h)) and library.has_animation(StringName("hold_%s_in" % h))):
			out.append(h)
	return out


## Daggers: "reverse" while in the reverse (icepick) grip, else "forward".
func grip() -> String:
	return "reverse" if hold == "reverse" else "forward"


## The actions on offer in the current hold: [[kind, clip], ...]; standing
## at the guard the body variants (look, fidget) join them as "body".
func handling_actions() -> Array:
	var out: Array = []
	for a in BWAnimHandling.actions(set_id, hold):
		if library.has_animation(StringName(str(a[1]))):
			out.append(a)
	if hold == "guard":
		for v in personality.get("variants", []):
			if library.has_animation(StringName(str(v))):
				out.append(["body", str(v)])
	return out


func _pick_hold() -> String:
	var ws: Dictionary = (personality.get("handling", {}) as Dictionary).get("holds", {})
	var opts: Array = []
	var total := 0.0
	for h in holds():
		if h == hold:
			continue
		var w := float(ws.get(h, 1.0))
		opts.append([h, w])
		total += w
	if opts.is_empty():
		return ""
	var r := _rng.randf() * total
	for o in opts:
		r -= float(o[1])
		if r <= 0.0:
			return str(o[0])
	return str(opts.back()[0])


func _pick_action() -> String:
	var ws: Dictionary = (personality.get("handling", {}) as Dictionary).get("acts", {})
	var opts: Array = []
	var total := 0.0
	for a in handling_actions():
		var w := float(ws.get(str(a[0]), 1.0))
		if str(a[1]) == _last_act:
			w *= 0.25
		opts.append([str(a[1]), w])
		total += w
	if opts.is_empty():
		return ""
	var r := _rng.randf() * total
	for o in opts:
		r -= float(o[1])
		if r <= 0.0:
			return str(o[0])
	return str(opts.back()[0])


## Go to a hold through the authored transitions (out of the current one,
## then into the new one). False if there is nothing to do.
func _change_hold(to: String, top: Dictionary) -> bool:
	if to == "" or to == hold or not to in holds():
		return false
	var seq: Array = []
	if hold != "guard":
		seq.append("hold_%s_out" % hold)
	if to != "guard":
		seq.append("hold_%s_in" % to)
	for n in seq:
		if not library.has_animation(StringName(str(n))):
			return false
	_push(_clip_layer(str(seq[0])), -1.0, top)
	_seq = seq.slice(1)
	pending = "idle"
	current = "idle"
	return true


func _do_action(clip: String, top: Dictionary) -> bool:
	if clip == "" or not library.has_animation(StringName(clip)):
		return false
	_push(_clip_layer(clip), -1.0, top)
	_seq.clear()
	pending = "idle"
	current = "idle"
	_last_act = clip
	return true


## Tools and tests: change to a hold, or play an action (a clip name or a
## kind) available in the current hold, now. True if something started.
func handle(what: String) -> bool:
	var top: Dictionary = layers.back() if not layers.is_empty() else {}
	if what in BWAnimHandling.holds(set_id):
		return _change_hold(what, top)
	for a in handling_actions():
		if what == str(a[1]) or what == str(a[0]):
			return _do_action(str(a[1]), top)
	return false


# ------------------------------------------------------------- move planning

## How a unit moves `distance` (u) over `hexes` hexes (D62): a run with its
## authored start and stop for 2+ hexes, the walk for one hex, the limp when
## wounded. Returns {} when the set has no locomotion, else
##   gait      "run" | "walk" | "limp"
##   pose      the pose name to request at t = 0 ("run" / "walk")
##   dur       seconds until the root arrives
##   stop_at   (run) when to request "run_stop"; -1 otherwise
##   s         Callable(t) -> distance travelled along the path at time t
## For a run the root follows the start's and the stop's authored root
## curves exactly (their feet are planted for those curves) and cruises at
## the run speed between; the run's rate is set so a whole number of steps
## fits the cruise, so the stop starts on a contact.
func plan_move(distance: float, hexes: int) -> Dictionary:
	var ramp := 0.22
	if encounter in ["being", "twin"]:
		# D220: a Being glides (no steps); D298: so do the Twins: a trapezoid at the glide speed
		var gd := distance / GLIDE_SPEED + 0.3
		var gs := func(t: float) -> float:
			return BWCombatScreen._trapezoid(t, gd, 0.3) * distance
		return { "gait": "glide", "pose": "walk", "dur": gd, "stop_at": -1.0, "s": gs, "rate": -1.0 }
	if encounter == "colossus" and character and character.is_inside_tree():
		body_scale = character.global_basis.get_scale().y
	var walks_only := encounter in ["colossus", "blank", "grunt"]   # D219/D220: no runs (the Horde shuffles)
	if not wounded and not walks_only and hexes >= 2 and has_clip("run") and library.has_animation(&"run_start") and library.has_animation(&"run_stop"):
		var st: Dictionary = clip_meta("run_start")
		var sp: Dictionary = clip_meta("run_stop")
		var rm: Dictionary = clip_meta(str(actions.run.clip))
		var rs: Array = st.get("root_s", [])
		var re: Array = sp.get("root_s", [])
		if rs.size() > 1 and re.size() > 1:
			var fps := float(rm.get("fps", BWAnimClips.FPS))
			var hz := float(st.get("root_hz", fps))
			var d_s := float(rs.back())
			var t_s := (rs.size() - 1) / hz
			var t_e := float(sp.get("root_end", (re.size() - 1) / hz))
			var d_e := _curve(re, t_e * hz)
			var V := float(rm.speed) * _enc_pace
			var half := float(rm.stride) * 0.5
			var cruise := distance - d_s - d_e
			if cruise >= half * 0.6:
				var k := maxi(1, int(round(cruise / half)))
				var tc := cruise / V
				var rate := k * 0.5 * (float(rm.frames) / fps) / tc
				var s := func(t: float) -> float:
					if t <= t_s:
						return _curve(rs, t * hz)
					if t <= t_s + tc:
						return d_s + V * (t - t_s)
					return minf(distance, d_s + cruise + _curve(re, minf(t - t_s - tc, t_e) * hz))
				return { "gait": "run", "pose": "run", "dur": t_s + tc + t_e, "stop_at": t_s + tc, "s": s, "rate": rate }
	# a careful walk (one hex) or the limp: the style bar's trapezoid at the clip speed
	var clip := "limp" if wounded and library.has_animation(&"limp") else str(actions.get("walk", {}).get("clip", "walk"))
	var sp2 := float(clip_meta(clip).get("speed", 0.0)) * _enc_pace
	if encounter == "colossus":
		sp2 *= body_scale              # D219: its stride is 2.6x; the clip's speed is in model units
		ramp = 0.45                    # and it gets going slowly
	if sp2 <= 0.0:
		return {}
	var dur2 := distance / sp2 + ramp
	var s2 := func(t: float) -> float:
		return BWCombatScreen._trapezoid(t, dur2, ramp) * distance
	return { "gait": "limp" if clip == "limp" else "walk", "pose": "walk", "dur": dur2, "stop_at": -1.0, "s": s2, "rate": -1.0 }


## Start a planned move (sets the run's phase-aligning rate).
func begin_move(plan: Dictionary) -> void:
	play(str(plan.get("pose", "walk")))
	run_rate = float(plan.get("rate", -1.0)) if str(plan.get("gait", "")) == "run" else -1.0


static func _curve(arr: Array, f: float) -> float:
	var i := clampi(int(floor(f)), 0, arr.size() - 1)
	var j := mini(i + 1, arr.size() - 1)
	return lerpf(float(arr[i]), float(arr[j]), clampf(f - i, 0.0, 1.0))


# --------------------------------------------------------------------- turns

## True when a snap turn should play an authored turn: standing in the
## home idle (or a variant of it).
func can_turn() -> bool:
	if layers.is_empty() or current != "idle" or not library.has_animation(&"turn_l"):
		return false
	var top: Dictionary = layers.back()
	if top.kind != "clip":
		return false
	return (top.loop and not clip_meta(top.clip).has("gait")) or bool(top.get("variant", false))


func start_turn(side: float) -> void:
	var clip := "turn_l" if side > 0.0 else "turn_r"
	var top: Dictionary = layers.back() if not layers.is_empty() else {}
	_leave_hold(top)
	_push(_clip_layer(clip), -1.0, top)
	pending = "idle"


## Progress (0..1, may overshoot) of the turn on top; -1 when none plays.
func turn_progress() -> float:
	if layers.is_empty():
		return -1.0
	var top: Dictionary = layers.back()
	if top.kind != "clip" or not str(top.clip).begins_with("turn_"):
		return -1.0
	var a: Animation = top.anim
	var i := a.find_track(NodePath("pose:turn"), Animation.TYPE_VALUE)
	return float(a.value_track_interpolate(i, float(top.t))) if i >= 0 else -1.0


## D102: the whole-body turn (radians, CCW from above) of a spin clip
## (meta spin_yaw, e.g. strike_spin), read at that layer's own time from
## the topmost layer carrying one; 0 when none. It is 0 before the clip's
## launch and exactly TAU from its hit on, so the hand-over to the next
## clip (a TAU -> 0 jump) is invisible and never unwinds.
func spin_yaw() -> float:
	for i in range(layers.size() - 1, -1, -1):
		var l: Dictionary = layers[i]
		if l.kind != "clip":
			continue
		var m := clip_meta(l.clip)
		if not m.has("spin_yaw"):
			continue
		var ys: Array = m.spin_yaw
		var v := _curve(ys, float(l.t) * float(m.get("spin_hz", BWAnimClips.BAKE_HZ)))
		# a spin covered by a later request mid-turn fades its yaw out with that layer's weight
		var w := 1.0
		for j in range(i + 1, layers.size()):
			w *= 1.0 - _w(layers[j])
		return wrapf(v, -PI, PI) * w if w < 1.0 else v
	return 0.0


# ------------------------------------------------------------------- update

func update(delta: float) -> void:
	if layers.is_empty():
		play("idle", 0.0)
	_advance(delta)
	var pose := _sample(layers[0])
	for i in range(1, layers.size()):
		var l: Dictionary = layers[i]
		pose = _blend(pose, _sample(l), l)
	if encounter != "":
		pose = pose.duplicate(true)          # (a key layer's pose is shared: never write into it)
		_encounter_layer(pose, delta)
	if secondary_enabled:
		_motion_layer(pose, delta)
	if lock_enabled:
		_foot_lock(pose, delta)
	var keyw := 0.0
	for l in layers:
		if l.kind == "key":
			keyw = maxf(keyw, _w(l))
	poser.breath_amount = keyw
	poser.apply(pose)
	last_pose = pose
	if secondary_enabled:
		_hair_springs(delta)
		_smear(pose, delta)


func _w(l: Dictionary) -> float:
	return smoothstep(0.0, 1.0, float(l.alpha))


func _next_interval() -> float:
	var iv: Array = personality.get("interval", [6.0, 10.0])
	return _rng.randf_range(float(iv[0]), float(iv[1]))


func _advance(delta: float) -> void:
	var top: Dictionary = layers.back()
	for l in layers:
		if l.fade > 0.0 and l.alpha < 1.0:
			l.alpha = minf(1.0, l.alpha + delta / l.fade)
		if float(l.get("halpha", 1.0)) < 1.0:
			l.halpha = minf(1.0, float(l.halpha) + delta / maxf(float(l.hand_fade), 0.01))
		if l.kind != "clip":
			continue
		var a: Animation = l.anim
		var rate := 1.0
		var m: Dictionary = clip_meta(l.clip)
		if m.has("gait"):
			var sp := float(m.get("speed", 0.0))
			if walk_rate >= 0.0:
				rate = walk_rate
			elif run_rate > 0.0 and str(l.clip).begins_with("run"):
				rate = run_rate
			elif sp > 0.0:
				var sc := body_scale if encounter == "colossus" else 1.0
				rate = clampf(Vector2(velocity.x, velocity.z).length() / (sp * sc), 0.0, 1.6)
		elif l.loop and str(l.clip) in ["idle", "idle_bouncy", "wounded"]:
			rate = float(personality.get("rate", 1.0))
		l.rate = rate
		var t0 := float(l.t)
		var t1 := t0 + delta * rate
		if l.hold >= 0.0 and t0 <= l.hold:
			t1 = minf(t1, l.hold)
		if l.loop:
			if t1 >= a.length:
				t1 = fmod(t1, a.length)
		elif t1 >= a.length:
			t1 = a.length
		if is_same(l, top) and delta > 0.0:
			_fire_markers(l, t0, t1)
		l.t = t1
		if not l.loop and t1 >= a.length and not l.ended:
			l.ended = true
			if is_same(l, top):
				finished.emit(l.clip)
	# drop layers covered by a fully faded-in one
	for i in range(layers.size() - 1, 0, -1):
		if layers[i].alpha >= 1.0 and float(layers[i].get("halpha", 1.0)) >= 1.0:
			layers = layers.slice(i)
			break
	top = layers.back()
	if _is_oneshot(top) and top.ended and not bool(top.get("hold_end", false)):
		var hm := clip_meta(top.clip)
		if hm.has("handling"):
			hold = str(hm.get("to", hold))
			if not _seq.is_empty() and pending in ["", "idle"]:
				_push(_clip_layer(str(_seq.pop_front())), -1.0, top)
				pending = "idle"
				return
		var next := pending if pending != "" else "idle"
		pending = ""
		var keep := current
		var rr := run_rate
		play(next)
		if next == "run":
			run_rate = rr                            # the start hands over to the planned run
		if keep != next and (keep in ["strike", "hit", "fumble", "windup", "block", "dodge", "kneel", "cast", "run_stop"] or keep.begins_with("stricken")):
			current = next
		return
	# standing: change holds and handle the weapon now and then (D80); the
	# body variants (look, fidget) are among the actions at the guard
	if rotate_idles and current == "idle" and not wounded and top.kind == "clip" and top.loop and top.alpha >= 1.0 \
			and float(top.get("halpha", 1.0)) >= 1.0 and not clip_meta(top.clip).has("gait") \
			and Vector2(velocity.x, velocity.z).length() < 0.05:
		_hold_clock += delta
		_act_clock += delta
		if _hold_clock >= _hold_next:
			_hold_clock = 0.0
			_hold_next = _rng.randf_range(float(_hiv()[0]), float(_hiv()[1]))
			if _change_hold(_pick_hold(), top):
				_act_clock = 0.0
				_act_next = _rng.randf_range(float(_aiv()[0]), float(_aiv()[1])) * 0.6
		elif _act_clock >= _act_next:
			_act_clock = 0.0
			_act_next = _rng.randf_range(float(_aiv()[0]), float(_aiv()[1]))
			_do_action(_pick_action(), top)


func _fire_markers(l: Dictionary, t0: float, t1: float) -> void:
	var marks: Dictionary = clip_meta(l.clip).get("markers", {})
	for m in marks:
		var mt := float(marks[m])
		var crossed := (mt > t0 and mt <= t1) if t1 >= t0 else (mt > t0 or mt <= t1)
		if crossed or (t0 == 0.0 and mt == 0.0 and t1 > 0.0):
			marker.emit(l.clip, m)


## Pose dictionary for one layer at its time.
func _sample(l: Dictionary) -> Dictionary:
	if l.kind == "key":
		return l.pose
	var a: Animation = l.anim
	if not _tracks.has(a):
		var list: Array = []
		for t in a.get_track_count():
			var ch := str(a.track_get_path(t).get_concatenated_subnames())
			if BWAnimClips.CHANNELS.has(ch):
				list.append([t, BWAnimClips.CHANNELS[ch][0], BWAnimClips.CHANNELS[ch][1]])
		_tracks[a] = list
	var fr := str((a.get_meta("bw", {}) as Dictionary).get("hand_frame", "chest"))
	var p := {
		"foot_l": {}, "foot_r": {},
		"hand_r": { "frame": fr, "edge": Vector3.BACK, "aim": Vector3.UP, "grip": 0.0 },
		"hand_l": { "frame": fr, "aim": Vector3.UP, "edge": Vector3.BACK, "grip": 0.0 },
	}
	var t := float(l.t)
	for e in _tracks[a]:
		var v: Variant = a.value_track_interpolate(e[0], t)
		if e[2] == "":
			p[e[1]] = v
		else:
			p[e[1]][e[2]] = v
	return p


## Mix two poses by a layer's weight; feet that travel take a stepping arc.
## Hands keyed in another frame are first carried into the incoming one.
func _blend(a: Dictionary, b: Dictionary, l: Dictionary) -> Dictionary:
	var w := _w(l)
	var out := BWCharacterPose._mix(a, b, w)
	if str(a.hand_r.get("frame", "chest")) != str(b.hand_r.get("frame", "chest")):
		# carry the outgoing hands into the incoming frame of the MIXED body
		# (that is the frame the solver will use), so at w = 0 they land
		# exactly where the outgoing clip put them
		a = _reframe(a, str(b.hand_r.get("frame", "chest")), out)
		out = BWCharacterPose._mix(a, b, w)
	if float(l.get("halpha", 1.0)) < 1.0:
		# leaving a hold: the hands (and the weapon's flat / plant) keep their
		# own, slower fade, so they travel back instead of snapping with the
		# body (a reversed dagger's quick flip back to forward)
		var wh := smoothstep(0.0, 1.0, float(l.halpha))
		for hk in ["hand_r", "hand_l"]:
			out[hk] = BWCharacterPose._mix(a[hk], b[hk], wh)
		for k in ["flat", "smear"]:
			out[k] = lerpf(float(a.get(k, 0.0)), float(b.get(k, 0.0)), wh)
		# a planted weapon lets go of the floor first (before its aim swings
		# far enough for the planting solve to change sides)
		out["plant"] = lerpf(float(a.get("plant", 0.0)), float(b.get("plant", 0.0)), minf(1.0, wh * 5.0))
	for s in ["l", "r"]:
		var fa: Dictionary = a["foot_" + s]
		var fb: Dictionary = b["foot_" + s]
		var start: Vector3 = l.get("feet_from", {}).get(s, fa.pos)
		var d := Vector2(fb.pos.x - start.x, fb.pos.z - start.z).length()
		if d < 0.04:
			continue
		# staggered: the left foot steps in the first 70%, the right in the last 70%
		var u := clampf(float(l.alpha) / 0.7 if s == "l" else (float(l.alpha) - 0.3) / 0.7, 0.0, 1.0)
		var e := smoothstep(0.0, 1.0, u)
		var f: Dictionary = out["foot_" + s]
		f.pos = (fa.pos as Vector3).lerp(fb.pos, e)
		f.rot = (fa.rot as Vector3).lerp(fb.rot, e)
		var lift := minf(0.12, 0.05 + d * 0.35) * sin(PI * u)
		f.pos.y += lift
		out["contact_" + s] = minf(float(out["contact_" + s]), 1.0 - sin(PI * u))
	return out


## A copy of pose p with both hands re-expressed in `frame` of the pose
## `target` (each pose's own FK gives its frame transform), so a chest-frame
## hand and a root-frame hand mix in one space.
func _reframe(p: Dictionary, frame: String, target: Dictionary) -> Dictionary:
	var q := p.duplicate()
	var fa := poser.frame_of(p, str(p.hand_r.get("frame", "chest")))
	var fb := poser.frame_of(target, frame)
	var x := fb.affine_inverse() * fa
	for h in ["hand_r", "hand_l"]:
		var d: Dictionary = (p[h] as Dictionary).duplicate()
		d.pos = x * (d.pos as Vector3)
		for k in ["aim", "edge", "pole"]:
			if d.has(k):
				d[k] = x.basis * (d[k] as Vector3)
		d.frame = frame
		q[h] = d
	return q


# ------------------------------------------------------------ encounters

const GLIDE_SPEED := 2.4          ## a Being's glide (u/s)
const BEING_HOVER := 0.17         ## a Being floats this high (m), +- BEING_BOB
const BEING_BOB := 0.025
const TWIN_HOVER := 0.3          ## D298: the Twins float a little higher, a slower, wider bob
const TWIN_BOB := 0.045
const BLANK_LOOK := 2.6           ## the Blanks' shared head-turn beat (s)
const BLANK_SNAP := 0.11          ## ... each turn takes this long: a snap, then dead still
## The Blanks' head yaw / tilt per beat (radians); one shared sequence.
const BLANK_LOOKS := [[0.0, 0.0], [0.75, 0.0], [0.75, 0.0], [0.0, 0.0], [-0.65, 0.0], [-0.65, 0.26], [0.0, 0.0], [0.0, -0.22]]


## D219-D220: the encounter's own routes and pace (see BWAnimEncounter).
func _encounter_setup(u: BWUnit) -> void:
	encounter = str(u.encounter) if u != null else ""
	if encounter == "":
		return
	var uid := u.id
	_base = BWAnimClips.base_channels(set_id)
	match encounter:
		"colossus":
			rotate_idles = false                  # a giant doesn't twirl its spear
			personality.rate = 0.8
			if library.has_animation(&"walk_colossus"):
				actions.walk = { "clip": "walk_colossus" }
				actions.run = { "clip": "walk_colossus" }
				actions.run_stop = { "clip": "stomp_colossus" }
				actions.stomp = { "clip": "stomp_colossus" }
			if library.has_animation(&"strike_colossus"):
				actions.windup = { "clip": "strike_colossus", "hold": "coil" }
				actions.strike = { "clip": "strike_colossus" }
		"grunt":
			# out of step: each grunt its own pace and breathing rate
			var h := float(absi(hash(uid + "|pace")) % 1000) / 1000.0
			_enc_pace = lerpf(0.82, 1.12, h)
			personality.rate = float(personality.get("rate", 1.0)) * lerpf(0.9, 1.15, 1.0 - h)
			var jab := "strike_axe_jab" if weapon_class == "axe" else "strike_jab"
			if library.has_animation(StringName(jab)):
				actions.windup = { "clip": jab, "hold": "coil" }
				actions.strike = { "clip": jab }
		"blank":
			rotate_idles = false                  # economy: no weapon play, no fidgets
			actions.walk = { "clip": "walk_calm" if library.has_animation(&"walk_calm") else "walk" }
			actions.idle = { "clip": "idle" }
		"being":
			rotate_idles = false
			actions.idle = { "clip": "idle" }
			actions.walk = { "clip": "idle" }     # it glides: no steps
			actions.run = { "clip": "idle" }
		"twin":
			# D298 (the author: "Noon and Dusk should float around"): a hover
			# idle and a glide, the Being's motion at a slightly higher float
			rotate_idles = false
			actions.idle = { "clip": "idle" }
			actions.walk = { "clip": "idle" }
			actions.run = { "clip": "idle" }


## The encounter's runtime layer, on the blended clip pose (any set).
func _encounter_layer(p: Dictionary, delta: float) -> void:
	_enc_t += delta
	var top: Dictionary = layers.back()
	var clip := str(top.get("clip", ""))
	var gait: bool = top.kind == "clip" and clip_meta(clip).has("gait")
	var standing: bool = current == "idle" and top.kind == "clip" and bool(top.loop) and not gait
	match encounter:
		"grunt":
			# hunched: over at the spine and chest, chin up to see, knees bent
			p.spine = (p.spine as Vector3) + Vector3(0.12, 0, 0)
			p.chest = (p.chest as Vector3) + Vector3(0.07, 0, 0)
			p.head = (p.head as Vector3) + Vector3(-0.15, 0, 0)
			p.root = (p.root as Vector3) + Vector3(0, -0.035, 0)
			if gait:
				# the shuffle: the swing foot barely leaves the floor
				for sd in ["l", "r"]:
					var f: Dictionary = p["foot_" + sd]
					var r: Vector3 = f.rot
					var yf := BWAnimClips.ankle(Vector2.ZERO, r.x, r.y).y
					var pos: Vector3 = f.pos
					pos.y = yf + maxf(pos.y - yf, 0.0) * 0.5
					f.pos = pos
		"blank":
			# economy of motion: standing dead still at the guard with exact
			# head turns on a clock shared by every Blank; walking, only the legs
			var want := 1.0 if standing or (gait and current == "walk") else 0.0
			_enc_w = move_toward(_enc_w, want, delta * 7.0)
			if _enc_w <= 0.0:
				return
			var w := smoothstep(0.0, 1.0, _enc_w)
			var look := _blank_look() if standing else Vector2.ZERO
			var still := {
				"hips": _base.hips, "spine": (_base.spine as Vector3) + (Vector3(0.03, 0, 0) if gait else Vector3.ZERO),
				"chest": (_base.chest as Vector3) + Vector3(0, look.x * 0.35, 0), "neck": _base.neck,
				"head": (_base.head as Vector3) + Vector3(0, look.x * 0.65, look.y),
			}
			for k in still:
				p[k] = (p[k] as Vector3).lerp(still[k], w)
			var root: Vector3 = p.root
			var br: Vector3 = _base.root
			p.root = Vector3(lerpf(root.x, br.x, w), lerpf(root.y, br.y - (0.02 if gait else 0.0), w), root.z)
			p.squash = lerpf(float(p.get("squash", 0.0)), 0.0, w)
			p.head_sq = lerpf(float(p.get("head_sq", 0.0)), 0.0, w)
			for h in ["hand_r", "hand_l"]:
				var d: Dictionary = p[h]
				if str(d.get("frame", "chest")) != "chest":
					continue
				d.pos = (d.pos as Vector3).lerp(_base[h + "_pos"], w)
				d.aim = (d.aim as Vector3).lerp(_base[h + "_aim"], w).normalized()
		"being", "twin":
			# hovering: no contacts (the lock lets the feet hang), toes down,
			# a slow bob; leaning into a glide. A knocked-out Being drops.
			var want := 0.0 if clip == "fall" else 1.0
			_enc_w = move_toward(_enc_w, want, delta * (4.0 if want > 0.0 else 6.0))
			var w := smoothstep(0.0, 1.0, _enc_w)
			var ph := float(absi(hash(character.unit.id if character and character.unit else "b")) % 628) / 100.0
			var hov := TWIN_HOVER if encounter == "twin" else BEING_HOVER
			var bob := TWIN_BOB if encounter == "twin" else BEING_BOB
			var h := (hov + bob * sin(_enc_t * (1.2 if encounter == "twin" else 1.6) + ph)) * w
			var v := clampf(Vector2(velocity.x, velocity.z).length() / GLIDE_SPEED, 0.0, 1.0)
			p.root = (p.root as Vector3) + Vector3(0, h, 0)
			p.spine = (p.spine as Vector3) + Vector3(0.16 * v * w, 0, 0)
			p.head = (p.head as Vector3) + Vector3(-0.1 * v * w, 0, 0)
			for sd in ["l", "r"]:
				var f: Dictionary = p["foot_" + sd]
				var pos: Vector3 = f.pos
				var r: Vector3 = f.rot
				var hang := 0.55 + 0.06 * sin(_enc_t * 1.6 + ph - 0.5 + (0.4 if sd == "r" else 0.0))
				pos.y += h * 0.92 + 0.03 * w
				pos.z -= 0.12 * v * w
				f.pos = pos
				f.rot = Vector3(lerpf(r.x, hang, w), r.y, r.z)
				p["contact_" + sd] = lerpf(float(p.get("contact_" + sd, 1.0)), 0.0, w)


## The Blanks' shared head turn now: (yaw, tilt), snapped between held beats.
func _blank_look() -> Vector2:
	var t := Time.get_ticks_msec() / 1000.0
	var k := int(floor(t / BLANK_LOOK))
	var a: Array = BLANK_LOOKS[posmod(k, BLANK_LOOKS.size())]
	var b: Array = BLANK_LOOKS[posmod(k - 1, BLANK_LOOKS.size())]
	var u := smoothstep(0.0, BLANK_SNAP, t - k * BLANK_LOOK)
	return Vector2(lerpf(float(b[0]), float(a[0]), u), lerpf(float(b[1]), float(a[1]), u))


# ------------------------------------------------------------ motion layer

## Inertia + turning, as small offsets on the spine, chest and head.
func _motion_layer(p: Dictionary, delta: float) -> void:
	if delta <= 0.0:
		return
	# accel forward (+z) leaves the upper body behind (pitch back), braking
	# throws it forward; sideways accel rolls it. Spring: w 13, z 0.42.
	var target := Vector2(clampf(-accel.z * 0.010, -0.22, 0.22), clampf(accel.x * 0.008, -0.15, 0.15))
	if not (target.is_finite() and is_finite(yaw_rate)):
		target = Vector2.ZERO
	var w := 13.0
	var z := 0.42
	var hw := 9.0
	# explicit springs: sub-step so a long frame (a hitch, a load) can't blow up
	var n := clampi(int(ceil(delta * 120.0)), 1, 8)
	var h := minf(delta, 0.066) / n
	for i in n:
		_lean_v += ((target - _lean) * w * w - _lean_v * 2.0 * z * w) * h
		_lean += _lean_v * h
		# the head trails the lean
		_head_v += ((_lean - _head) * hw * hw - _head_v * 2.0 * 0.5 * hw) * h
		_head += _head_v * h
	if not (_lean.is_finite() and _head.is_finite() and _lean_v.is_finite() and _head_v.is_finite()):
		_lean = Vector2.ZERO
		_lean_v = Vector2.ZERO
		_head = Vector2.ZERO
		_head_v = Vector2.ZERO
	_turn = lerpf(_turn, clampf(yaw_rate * 0.09, -0.4, 0.4) if is_finite(yaw_rate) else 0.0, 1.0 - exp(-delta * 14.0))
	p.spine = (p.spine as Vector3) + Vector3(_lean.x * 0.4, 0, _lean.y * 0.4)
	p.chest = (p.chest as Vector3) + Vector3(_lean.x * 0.6, _turn * 0.25, _lean.y * 0.6 - _turn * 0.18)
	p.head = (p.head as Vector3) + Vector3((_head.x - _lean.x) * 0.9, _turn * 0.9, 0)


# ---------------------------------------------------------------- foot lock

func _reset_locks() -> void:
	_lock = { "l": {}, "r": {} }


## The lock pins the foot's GROUND POINT (where the sole meets the floor
## with the foot flat: the `ground` the clip authored through
## BWAnimClips.ankle), not the ankle, so the clip's own heel-to-toe roll
## still plays on top of a locked foot.
func _foot_lock(p: Dictionary, delta: float) -> void:
	var sk := poser.skeleton
	if sk == null or not sk.is_inside_tree():
		return
	var to_world := sk.global_transform
	var to_model := to_world.affine_inverse()
	var yaw_w := atan2(to_world.basis.z.x, to_world.basis.z.z)
	var stepping := false
	for s in ["l", "r"]:
		stepping = stepping or (_lock[s] as Dictionary).get("step", -1.0) >= 0.0
	for s in ["l", "r"]:
		var f: Dictionary = p["foot_" + s]
		var c := float(p.get("contact_" + s, 1.0))
		var L: Dictionary = _lock[s]
		var rot: Vector3 = f.rot
		var tyaw := rot.y
		var g := ground_point(f.pos, rot)                 # model space, y = 0
		if L.get("step", -1.0) >= 0.0:
			# procedural re-step toward the clip's foot
			L.step = minf(1.0, float(L.step) + delta / STEP_TIME)
			var u := smoothstep(0.0, 1.0, float(L.step))
			var from: Vector3 = to_model * (L.world as Vector3)
			var gy := lerpf(float(L.yaw) - yaw_w, tyaw, u)
			f.pos = ankle_at(from.lerp(g, u), Vector3(rot.x, gy, 0), f.pos.y) + Vector3(0, 0.07 * sin(PI * float(L.step)), 0)
			f.rot = Vector3(rot.x, gy, 0)
			if L.step >= 1.0:
				L.clear()
			continue
		if c >= 0.5:
			if not L.get("on", false):
				L.on = true
				L.world = to_world * g
				L.yaw = tyaw + yaw_w
			var m: Vector3 = to_model * (L.world as Vector3)
			var twist := wrapf(float(L.yaw) - yaw_w - tyaw, -PI, PI)
			var drift := Vector2(m.x - g.x, m.z - g.z).length()
			if (drift > LOCK_DRIFT or absf(twist) > LOCK_TWIST) and not stepping:
				L.step = 0.0                      # too far: step to the clip's foot
				L.on = false
				stepping = true
				continue
			var r2 := Vector3(rot.x, tyaw + twist, 0)
			f.pos = ankle_at(m, r2, f.pos.y)
			f.rot = r2
		elif L.get("on", false):
			# release: ease from the locked spot back onto the clip curve
			var m: Vector3 = to_model * (L.world as Vector3)
			L.on = false
			L.rel = Vector3(m.x - g.x, 0, m.z - g.z)
			L.rel_t = 0.0
		if L.has("rel"):
			L.rel_t = float(L.rel_t) + delta
			var k := 1.0 - smoothstep(0.0, RELEASE_TIME, float(L.rel_t))
			f.pos = (f.pos as Vector3) + (L.rel as Vector3) * k
			if k <= 0.0:
				L.erase("rel")


## Ground point (model space, y 0) of a foot: its ankle minus the rolling
## offset for its pitch, along its yaw. Inverse of ankle_at().
static func ground_point(ankle: Vector3, rot: Vector3) -> Vector3:
	var r := BWAnimClips.roll(rot.x)
	return Vector3(ankle.x - sin(rot.y) * r.x, 0.0, ankle.z - cos(rot.y) * r.x)


## Ankle for a ground point and foot rotation; keeps the clip's ankle height.
static func ankle_at(g: Vector3, rot: Vector3, y: float) -> Vector3:
	var r := BWAnimClips.roll(rot.x)
	return Vector3(g.x + sin(rot.y) * r.x, y, g.z + cos(rot.y) * r.x)


# --------------------------------------------------------------- hair springs

func _hair_springs(delta: float) -> void:
	var hair := character.hair
	if hair == null or hair.skeleton == null or not hair.skeleton.is_inside_tree():
		return
	var hs := hair.skeleton
	if hs != _hair_sk:
		_hair_sk = hs
		_hair.clear()
		var names := hair.tail_bone_names()
		for i in names.size():
			var b := hs.find_bone(names[i])
			if b < 0:
				continue
			var child := hs.find_bone(names[i + 1]) if i + 1 < names.size() else -1
			var ln := hs.get_bone_rest(child).origin.length() if child >= 0 else 0.22
			_hair.append({ "bone": b, "parent": hs.get_bone_parent(b), "len": maxf(ln, 0.05),
				"tip": Vector3.ZERO, "vel": Vector3.ZERO, "prev": Vector3.ZERO, "primed": false,
				"k": [320.0, 210.0, 140.0][mini(i, 2)], "c": [13.0, 10.0, 8.0][mini(i, 2)] })
	if _hair.is_empty():
		return
	var W := hs.global_transform
	# the back's outward normal: the chest's forward (a deep lean tips it)
	var fwd := poser.skeleton.global_transform.basis.z.normalized()
	if poser.globals.has("chest"):
		fwd = (poser.skeleton.global_transform.basis * (poser.globals.chest as Transform3D).basis.z).normalized()
	var parent_g := hs.get_bone_global_pose(int(_hair[0].parent))
	for h in _hair:
		var b: int = h.bone
		# the first tail bone carries the solver's hang (counter-pitch, collar
		# push) this frame; the others hang from their rest, not from last
		# frame's swing (that would feed the swing back into its own target)
		var local_now := Transform3D(Basis(hs.get_bone_pose_rotation(b)), hs.get_bone_pose_position(b))
		if not is_same(h, _hair[0]):
			local_now = hs.get_bone_rest(b)
		var rigid := parent_g * local_now
		var anchor := W * rigid.origin
		var rdir := (W.basis * rigid.basis.y).normalized()
		# gravity: when the head tips far from upright (a kneel, a fall, a
		# deep lean) the curtain falls toward the floor instead of following
		# the head like a flag; upright (rdir already hanging) nothing changes.
		# It lies along the back rather than through it.
		var hang := rdir
		var gw := clampf((0.85 - rdir.dot(Vector3.DOWN)) / 0.85, 0.0, 1.0) * 0.7
		if gw > 0.0:
			hang = rdir.slerp(Vector3.DOWN, gw).normalized()
			if hang.dot(fwd) > 0.04:
				hang = (hang - fwd * (hang.dot(fwd) - 0.04)).normalized()
		var target := anchor + hang * float(h.len)
		if not h.primed or delta <= 0.0 or delta > 0.25:
			h.tip = target
			h.vel = Vector3.ZERO
			h.prev = target
			h.primed = true
		else:
			# damped relative to the target's own motion: steady movement
			# carries the hair along; changes of speed or direction swing it
			var tv: Vector3 = (target - (h.prev as Vector3)) / delta
			var prev: Vector3 = h.prev
			h.prev = target
			# sub-stepped (stable at any frame time); the target moves linearly
			var n := clampi(int(ceil(delta * 120.0)), 1, 8)
			var sh := delta / n
			for k in n:
				var tg := prev.lerp(target, float(k + 1) / n)
				var acc: Vector3 = (tg - (h.tip as Vector3)) * float(h.k) - ((h.vel as Vector3) - tv) * float(h.c) - (h.vel as Vector3) * 0.6
				h.vel += acc * sh
				h.tip += (h.vel as Vector3) * sh
			if not ((h.tip as Vector3).is_finite() and (h.vel as Vector3).is_finite()):
				h.tip = target
				h.vel = Vector3.ZERO
		var dir := ((h.tip as Vector3) - anchor).normalized()
		if dir.length_squared() < 0.5:
			dir = rdir
		# the curtain hangs behind the back: it may swing out, not into the body
		var lim := hang.dot(fwd) + 0.06
		if dir.dot(fwd) > lim:
			dir = (dir - fwd * (dir.dot(fwd) - lim)).normalized()
		var ang := hang.angle_to(dir)
		if ang > 0.6:
			dir = hang.slerp(dir, 0.6 / ang).normalized()
		h.tip = anchor + dir * float(h.len)
		var q := Quaternion(rdir, dir) if rdir.angle_to(dir) > 1e-4 else Quaternion.IDENTITY
		var wb := Basis(q) * (W.basis * rigid.basis)
		var lb := (W.basis * parent_g.basis).inverse() * wb
		var lq := _quat(lb)
		hs.set_bone_pose_rotation(b, lq)
		parent_g = parent_g * Transform3D(Basis(lq), local_now.origin)


## Rotation of a basis that may carry a little skew (the head bone's
## squash scale rides into the hair's parent transform): orthonormalize,
## then Shepperd's method, with no strictness check (Godot's cast rejects
## bases a float's width off orthonormal).
static func _quat(b: Basis) -> Quaternion:
	var m := b.orthonormalized()
	if m.determinant() < 0.0:
		m = m.scaled(Vector3(-1, -1, -1))
	var tr := m.x.x + m.y.y + m.z.z
	var q := Quaternion()
	if tr > 0.0:
		var s := sqrt(tr + 1.0) * 2.0
		q = Quaternion((m.y.z - m.z.y) / s, (m.z.x - m.x.z) / s, (m.x.y - m.y.x) / s, 0.25 * s)
	elif m.x.x > m.y.y and m.x.x > m.z.z:
		var s := sqrt(1.0 + m.x.x - m.y.y - m.z.z) * 2.0
		q = Quaternion(0.25 * s, (m.y.x + m.x.y) / s, (m.z.x + m.x.z) / s, (m.y.z - m.z.y) / s)
	elif m.y.y > m.z.z:
		var s := sqrt(1.0 + m.y.y - m.x.x - m.z.z) * 2.0
		q = Quaternion((m.y.x + m.x.y) / s, 0.25 * s, (m.z.y + m.y.z) / s, (m.z.x - m.x.z) / s)
	else:
		var s := sqrt(1.0 + m.z.z - m.x.x - m.y.y) * 2.0
		q = Quaternion((m.z.x + m.x.z) / s, (m.z.y + m.y.z) / s, 0.25 * s, (m.x.y - m.y.x) / s)
	return q.normalized()


# ---------------------------------------------------------------- the smear

func _smear(p: Dictionary, delta: float) -> void:
	var w := character.weapon
	var amount := float(p.get("smear", 0.0))
	if w == null or poser.skeleton == null or not poser.skeleton.is_inside_tree():
		return
	if _swoosh == null:
		_swoosh = MeshInstance3D.new()
		_swoosh.name = "smear"
		_swoosh.top_level = true
		_swoosh.mesh = ImmediateMesh.new()
		_swoosh.material_override = _swoosh_material()
		_swoosh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_swoosh.set_instance_shader_parameter("dim", 0.0)
		character.add_child(_swoosh)
	# one trail per blade: the paired daggers' off-hand copy smears too
	var hand_key := "hand_l" if poser.hold_hand == "l" else "hand_r"
	var hands := [hand_key]
	if is_instance_valid(w.offhand_view) and hand_key == "hand_r":
		hands.append("hand_l")
	var any := false
	for hk in hands:
		var sock := poser.socket_l if hk == "hand_l" else poser.socket_r
		var g: Transform3D = poser.skeleton.global_transform * (poser.globals[hk] as Transform3D) * sock
		var hist: Array = _swoosh_hist if hk == hand_key else _swoosh_hist2
		for e in hist:
			e.age += delta
		hist.push_front({ "b": g * (BWWeaponView.v3(w.meta.get("trail_base", [0, 0.3, 0]))),
			"t": g * (BWWeaponView.v3(w.meta.get("tip", [0, 1, 0]))), "a": amount, "age": 0.0 })
		while hist.size() > 2 and float(hist.back().age) > SMEAR_LIFE:
			hist.pop_back()
		for e in hist:
			any = any or float(e.a) > 0.02
	var im := _swoosh.mesh as ImmediateMesh
	im.clear_surfaces()
	if not any:
		return
	# one band per pair of samples, hilt (UV.x 0) to tip (UV.x 1), UV.y = age
	# (0 at the blade, 1 at the tail): the shader cuts the crescent from it
	var tris: Array = []
	var pairs: Array = []
	for hist in [_swoosh_hist, _swoosh_hist2]:
		for i in (hist as Array).size() - 1:
			pairs.append([hist[i], hist[i + 1]])
	for pr in pairs:
		var e0: Dictionary = pr[0]
		var e1: Dictionary = pr[1]
		var u0 := clampf(float(e0.age) / SMEAR_LIFE, 0.0, 1.0)
		var u1 := clampf(float(e1.age) / SMEAR_LIFE, 0.0, 1.0)
		var c0 := Color(1, 1, 1, float(e0.a))
		var c1 := Color(1, 1, 1, float(e1.a))
		if c0.a <= 0.01 and c1.a <= 0.01:
			continue
		var b0: Vector3 = e0.b
		var b1: Vector3 = e1.b
		var t0: Vector3 = e0.t
		var t1: Vector3 = e1.t
		tris.append_array([[b0, c0, Vector2(0, u0)], [t0, c0, Vector2(1, u0)], [t1, c1, Vector2(1, u1)],
			[b0, c0, Vector2(0, u0)], [t1, c1, Vector2(1, u1)], [b1, c1, Vector2(0, u1)]])
	if tris.is_empty():
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in tris:
		im.surface_set_color(v[1])
		im.surface_set_uv(v[2])
		im.surface_add_vertex(v[0])
	im.surface_end()


func _quad(out: Array, a0: Vector3, b0: Vector3, a1: Vector3, b1: Vector3, ca0: Color, cb0: Color, ca1: Color, cb1: Color, ua: float, ub: float) -> void:
	out.append_array([[a0, ca0, ua], [b0, cb0, ub], [b1, cb1, ub], [a0, ca0, ua], [b1, cb1, ub], [a1, ca1, ua]])


static var _smear_mat: ShaderMaterial

static func _swoosh_material() -> ShaderMaterial:
	if _smear_mat == null:
		_smear_mat = ShaderMaterial.new()
		_smear_mat.shader = load("res://shaders/smear.gdshader")
	return _smear_mat


## Free the runtime nodes this animator added (on weapon change).
func dispose() -> void:
	if _swoosh and is_instance_valid(_swoosh):
		_swoosh.queue_free()
	_swoosh = null
	if _hair_sk and is_instance_valid(_hair_sk) and character and character.hair:
		character.hair.reset_pose()
