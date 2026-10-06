class_name BWCombatBarks
extends Node
## Squad chatter during a fight, per design/BARKS.md: who speaks for which
## event, at what chance, with one bark per action (priority order), a 2-turn
## per-unit cooldown and a 3 s global gap. Enemies never bark.
## Lines come from BWBarks; the voice is the unit's clip at its pitch.

const PRIORITY := ["self_ko", "ally_ko", "enemy_ko", "crit_landed", "healing_received", "dodged", "ally_attacking"]
const CHANCE := { "ally_attacking": 0.25, "healing_received": 0.6, "crit_landed": 0.5, "dodged": 0.35, "enemy_ko": 0.4 }
const GLOBAL_GAP := 3.0
const UNIT_COOLDOWN_TURNS := 2
const BUBBLE_SECONDS := 2.5

var screen: BWCombatScreen
var trust_fn: Callable          # (a_id, b_id) -> "strangers" | "acquainted" | "trusted"
var rng := RandomNumberGenerator.new()
var _last_time := -100.0
var _turn := 0
var _unit_last := {}            # unit id -> turn index of their last bark
var _used := {}                 # line id -> true, so lines don't repeat within a fight


func _stage(a: String, b: String) -> String:
	return trust_fn.call(a, b) if trust_fn.is_valid() else "strangers"


func _squad(team: String = "player") -> Array:
	return screen.battle.units.filter(func(u): return u.team == team and u.alive())


func _solo_trust(u: BWUnit) -> String:
	var pts: Array = []
	for o in screen.battle.units:
		if o.team == "player" and o != u:
			pts.append(BWBarks.STAGES.find(_stage(u.id, o.id)))
	pts.sort()
	return BWBarks.STAGES[pts[pts.size() / 2]] if not pts.is_empty() else "strangers"


func turn_passed() -> void:
	_turn += 1


## Call after an attack or skill resolves. `results` = [{target, result, ko}].
func after_action(attacker: BWUnit, results: Array) -> void:
	var cands := {}      # event -> [speaker, toward_unit]
	var player_attacking := attacker.team == "player"
	for r in results:
		var t: BWUnit = screen.battle._unit(str(r.target))
		if t == null:
			continue
		if t.team == "player" and not r.result.hit:
			cands["dodged"] = [t, null]
		if player_attacking and r.result.crit:
			cands["crit_landed"] = [attacker, null]
		if player_attacking and r.ko and t.team == "enemy":
			cands["enemy_ko"] = [attacker, null]
	if player_attacking:
		var watchers: Array = _squad().filter(func(w): return w != attacker)
		if not watchers.is_empty():
			cands["ally_attacking"] = [_weighted(watchers, attacker), attacker]
	for ev in PRIORITY:
		if cands.has(ev) and rng.randf() < CHANCE.get(ev, 1.0):
			if _say(ev, cands[ev][0], cands[ev][1]):
				return


## A squad unit went down: the fallen speak first, then the one who trusts them most.
func on_ko(fallen: BWUnit) -> void:
	if fallen.team != "player":
		return
	_say("self_ko", fallen, null, true)
	var best: BWUnit = null
	var best_s := -1
	for w in _squad():
		var s := BWBarks.STAGES.find(_stage(w.id, fallen.id))
		if s > best_s or (s == best_s and rng.randf() < 0.5):
			best = w
			best_s = s
	if best:
		await get_tree().create_timer(1.2).timeout
		_say("ally_ko", best, fallen, true)


func on_heal(u: BWUnit) -> void:
	if u.team == "player" and rng.randf() < CHANCE.healing_received:
		_say("healing_received", u, null)


func on_start() -> void:
	var sq := _squad()
	if not sq.is_empty():
		_say("battle_start", sq[rng.randi() % sq.size()], null, true)


func on_won() -> void:
	var sq := _squad()
	if not sq.is_empty():
		_say("battle_won", sq[rng.randi() % sq.size()], null, true)


func _weighted(cands: Array, toward: BWUnit) -> BWUnit:
	var total := 0
	var weights: Array = []
	for c in cands:
		var w := 1 + BWBarks.STAGES.find(_stage(c.id, toward.id))
		weights.append(w)
		total += w
	var roll := rng.randi() % total
	for i in cands.size():
		roll -= weights[i]
		if roll < 0:
			return cands[i]
	return cands[0]


func _say(event: String, speaker: BWUnit, toward: BWUnit, force: bool = false) -> bool:
	if speaker == null or speaker.team != "player":
		return false
	var now := Time.get_ticks_msec() / 1000.0
	if not force:
		if now - _last_time < GLOBAL_GAP:
			return false
		if _unit_last.has(speaker.id) and _turn - int(_unit_last[speaker.id]) < UNIT_COOLDOWN_TURNS:
			return false
	var trust := _stage(speaker.id, toward.id) if toward else _solo_trust(speaker)
	var tf := toward.friendliness if toward else "any"
	var line := {}
	for i in 4:          # a few draws to dodge lines already used this fight
		line = BWBarks.pick(event, speaker.friendliness, trust, tf, "", rng)
		if line.is_empty() or not _used.has(line.id):
			break
	if line.is_empty():
		return false
	_used[line.id] = true
	_last_time = now
	_unit_last[speaker.id] = _turn
	var text := BWBarks.fill(str(line.line), { "speaker": speaker.name, "ally": toward.name if toward else "",
		"target": "", "element": speaker.element, "weapon": speaker.weapon_class })
	_bubble(speaker, text)
	BWVoice.say(self, str(line.voice_clip), float(speaker.cosmetics.get("voice_pitch", 1.0)))
	screen.ui.feed("[i]%s: “%s”[/i]" % [speaker.name, text])
	return true


func _bubble(u: BWUnit, text: String) -> void:
	var v: Node3D = screen._views.get(u.id)
	if v == null:
		return
	var l := Label3D.new()
	l.text = "“%s”" % text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0011
	l.font_size = 17
	l.outline_size = 10
	l.modulate = Color.WHITE
	l.outline_modulate = Color.BLACK
	l.render_priority = 30             # over the board's transparent pass and the HP labels (as D102)
	l.outline_render_priority = 29
	l.width = 300
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	screen.add_child(l)
	l.global_position = v.global_position + Vector3(0, ((v as BWUnitView).head_height() + 1.2) if v is BWUnitView else 2.7, 0)
	var tw := create_tween()
	tw.tween_interval(BUBBLE_SECONDS)
	tw.tween_property(l, "modulate:a", 0.0, 0.3)
	tw.parallel().tween_property(l, "outline_modulate:a", 0.0, 0.3)
	tw.tween_callback(l.queue_free)
