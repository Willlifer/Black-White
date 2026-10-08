class_name BWHitFeel
extends Node
## D170: hit feel for a BWCombatScreen: screen shake scaled to the blow,
## a short hit-stop on big hits, damage numbers that grow with the hit, and
## the slow-mo + camera push on the fight's final knockout. The sizing rules
## are pure statics (tests/test_vfx_d167.gd); the screen calls in at marked
## points (numbers, the shake after a blow, `impact` at the impact frame).
##
## Everything honours the player's settings and playback: "Screen shake"
## (BWSettings "screen_shake", gates every shake, the screen's own too), the
## cutscene mode (Minimal: no hit-stop and no slow-mo; Fast: shorter), and
## hold-to-skip (no hit-stop and no slow-mo while skipping; the time scale is
## always handed back as the skip expects).

const SHAKE_MIN := 0.018          # a landed chip
const SHAKE_PER := 0.30           # per 100% of max HP
const SHAKE_CAP := 0.14           # never more than this (the old crit shake was 0.12)
const SHAKE_CRIT := 1.3
const STOP_BIG := 0.2             # share of max HP that earns a hit-stop
const STOP_HUGE := 0.35
const STOP_SECS := [0.045, 0.075] # real seconds frozen (big, huge)
const STOP_SCALE := 0.03
const NUM_MIN := 30               # font size: a miss / tiny chip
const NUM_MAX := 46               # a hit for 40%+ of max HP (D344: was 58)
const NUM_CRIT := 1.3
const NUM_CAP := 54               # D344: a crit's ceiling (was 76: it covered the crowd)
const KO_SCALE := 0.25            # final knockout slow-mo
const KO_SECS := 0.85             # real seconds (Fast: x0.55)
const KO_FOV := 0.8               # the camera pushes in to this share of its FOV

var screen: Node                  # BWCombatScreen
var last := {}                    # the last impact's numbers (probes / tests)


# ------------------------------------------------------------------ pure rules

static func share(damage: int, max_hp: int) -> float:
	return clampf(float(damage) / float(maxi(max_hp, 1)), 0.0, 1.0)


## Shake strength for one blow (0 for a miss or no damage). Gentle and capped.
static func shake_for(damage: int, max_hp: int, crit: bool = false) -> float:
	if damage <= 0:
		return 0.0
	var s := SHAKE_MIN + SHAKE_PER * share(damage, max_hp)
	if crit:
		s *= SHAKE_CRIT
	return minf(s, SHAKE_CAP)


## Real seconds of hit-stop for one blow (0 = none).
static func hitstop_for(damage: int, max_hp: int) -> float:
	var f := share(damage, max_hp)
	if f >= STOP_HUGE:
		return STOP_SECS[1]
	if f >= STOP_BIG:
		return STOP_SECS[0]
	return 0.0


## Floating number font size: grows with the hit's share of max HP (a sqrt
## curve, so mid hits already read bigger), crits a third larger.
static func number_size(damage: int, max_hp: int, crit: bool = false, hit: bool = true) -> int:
	if not hit or damage <= 0:
		return NUM_MIN
	var k := clampf(share(damage, max_hp) / 0.4, 0.0, 1.0)
	var s := lerpf(float(NUM_MIN) + 4.0, float(NUM_MAX), sqrt(k))
	if crit:
		s *= NUM_CRIT
	return mini(int(round(s)), NUM_CAP)


static func shake_on() -> bool:
	return bool(BWSettings.value("screen_shake"))


# ------------------------------------------------------------------ runtime

func _skipping() -> bool:
	return screen != null and bool(screen.get("skipping"))


func _mode() -> String:
	return str(BWSettings.value("cutscenes"))


func shake(strength: float) -> void:
	if strength > 0.0 and screen and screen.has_method("_shake"):
		screen.call("_shake", strength)     # the screen's _shake checks the setting


## After a blow's numbers: one shake for the biggest of its results.
func shake_blows(targets: Array, results: Array) -> void:
	var s := 0.0
	for k in mini(targets.size(), results.size()):
		var res: Dictionary = (results[k] as Dictionary).get("result", {})
		if not bool(res.get("hit", true)):
			continue
		var t: Node = targets[k]
		var mh: int = t.unit.pct_base_hp() if t and t.get("unit") else 100
		s = maxf(s, shake_for(int(res.get("damage", 0)), mh, bool(res.get("crit", false))))
	shake(s)


## A floating damage number sized by the hit (replaces the fixed-size one).
func float_number(v: Node3D, text: String, res: Dictionary, hold: float = 0.8) -> void:
	var mh: int = v.unit.pct_base_hp() if v.get("unit") else 100   # D485: the Giant's hits feel against 500
	var hit := bool(res.get("hit", true))
	var crit := bool(res.get("crit", false)) and hit
	var size := number_size(int(res.get("damage", 0)), mh, crit, hit)
	var l := BWFloaters.label(text, Color.WHITE, size, clampi(int(size * 0.34), 10, 22), v)   # D344: kept below the turn order
	screen.add_child(l)
	var h: float = screen.call("_label_height", v) if screen.has_method("_label_height") else 2.4
	l.global_position = v.global_position + Vector3(0, h, 0)
	var big := float(size) / float(NUM_MAX)
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector3.ONE, 0.09 + 0.06 * big).from(Vector3.ONE * (1.2 + 0.25 * big))
	BWFloaters.rise(tw, l, hold)                 # D344: a fixed screen rise
	tw.tween_property(l, "modulate:a", 0.0, 0.25)
	tw.parallel().tween_property(l, "outline_modulate:a", 0.0, 0.25)
	tw.tween_callback(l.queue_free)
	last = { "text": text, "size": size, "damage": int(res.get("damage", 0)), "max_hp": mh, "crit": crit }


## The impact frame (after the crit flash, if any): the cast VFX's impact
## hook, a hit-stop on a big hit, the final-knockout slow-mo.
func impact(a: Node3D, targets: Array, results: Array, flash: String) -> void:
	var vfx = screen.get("vfx") if screen else null
	if vfx:
		vfx.impact(a, targets, results)
	var crit_full := false
	var stop := 0.0
	for k in mini(targets.size(), results.size()):
		var res: Dictionary = (results[k] as Dictionary).get("result", {})
		if not bool(res.get("hit", true)):
			continue
		if bool(res.get("crit", false)) and flash == "full":
			crit_full = true                  # D101 already froze this frame
		var t: Node = targets[k]
		var mh: int = t.unit.pct_base_hp() if t and t.get("unit") else 100
		stop = maxf(stop, hitstop_for(int(res.get("damage", 0)), mh))
	if final_blow(results):
		await final_ko(targets, results)
		return
	if stop > 0.0 and not crit_full and not _skipping() and _mode() != "minimal" and not bool(screen.get("_freezing")):
		await _freeze(stop, STOP_SCALE)


## The time scale held for `secs` real seconds, then handed back as playback
## expects (x4 while skipping, else 1). Shares the screen's freeze flag so
## the D123 skip toggle never overrides it mid-stop.
func _freeze(secs: float, scale: float) -> void:
	screen.set("_freezing", true)
	Engine.time_scale = scale
	await get_tree().create_timer(secs, true, false, true).timeout
	screen.set("_freezing", false)
	Engine.time_scale = screen.SKIP_SCALE if _skipping() else 1.0


## True when this blow knocks out the last unit the fight needs: the rules
## already ended it, and no knockout later in the queue belongs to anyone
## outside these results.
func final_blow(results: Array) -> bool:
	if screen == null or screen.get("battle") == null or not screen.battle.over:
		return false
	var ids := {}
	for r in results:
		if bool((r as Dictionary).get("ko", false)):
			ids[str(r.target)] = true
	if ids.is_empty():
		return false
	for q in screen._queue:
		var ty := str(q.get("type", ""))
		if ty in ["attack", "counter", "riposte", "skill"] and BWCutsceneTier.has_ko(q):
			return false                       # a later blow still knocks someone out
	return true


## The final knockout: slow motion and a camera push onto the fallen.
func final_ko(targets: Array, results: Array) -> void:
	shake(SHAKE_CAP)
	if _skipping() or _mode() == "minimal" or bool(screen.get("_freezing")):
		return
	var secs := KO_SECS * (0.55 if _mode() == "fast" else 1.0)
	var cam: Camera3D = screen.cam
	var rig = screen.rig
	var focus: Vector3 = Vector3.ZERO
	var n := 0
	for k in mini(targets.size(), results.size()):
		if bool((results[k] as Dictionary).get("ko", false)):
			focus += (targets[k] as Node3D).global_position + Vector3(0, 1.0, 0)
			n += 1
	focus /= maxf(n, 1)
	var fov0 := cam.fov
	var piv0: Vector3 = rig.pivot
	var tw := create_tween().set_ignore_time_scale(true).set_parallel(true)
	tw.tween_property(cam, "fov", fov0 * KO_FOV, secs * 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(rig, "pivot", piv0.lerp(focus, 0.35), secs * 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var back := create_tween().set_ignore_time_scale(true).set_parallel(true)
	back.tween_interval(secs * 0.62)
	back.chain().tween_property(cam, "fov", fov0, secs * 0.38).set_trans(Tween.TRANS_SINE)
	back.tween_property(rig, "pivot", piv0, secs * 0.38).set_trans(Tween.TRANS_SINE)
	last["final_ko"] = true
	await _freeze(secs, KO_SCALE)
	if back.is_running():
		await back.finished
	cam.fov = fov0
	rig.pivot = piv0
