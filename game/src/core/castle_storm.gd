class_name BWCastleStorm
extends BWObjectiveMode
## D335-D342: STORM THE CASTLE (6v6, `maps/stronghold.json`; design/MAPS.md
## §14). The squad attacks the keep. Shared castle rules (high ground, the
## gate) are BWCastle's.
##
##   Phase 1  Break the WOODEN GATE (fire x1.5 on wood; thunder shatters a
##            glazed gate). Guards hold the wall walk with the high ground; the
##            Warden holds the throne (it doesn't leave its post). Every
##            REINFORCE_EVERY rounds REINFORCE_COUNT guards come in by the back
##            doors (BWObjectives waves, telegraphed a round ahead) until the
##            gate falls.
##   Phase 2  The gate falls (BWPhases: a `ko` trigger on the script, D255):
##            the reinforcements stop, the THRONE unseals (the squad may now
##            strike it) and the Warden takes the field.
##   Win      break the throne or down the Warden. Downing the Warden early
##            (over the wall, through a breach) wins too: "if we win, we win".
##   Lose     the squad is down.

const REINFORCE_FROM := 3
const REINFORCE_EVERY := 2
const REINFORCE_WAVES := 3
const REINFORCE_COUNT := 2
## D341 tuning: the gate's and the throne's HP as multiples of the squad's mean
## max HP; the Warden's HP share and stat multiplier.
## D357 re-tune for D353's fights 7-10 (castle_sim on 96 campaign squads):
## gate 3.5 -> 2.9, every guard and the Warden x0.93; 7 and 9 BWCastle.FIGHT_MULT.
static var GATE_HP := 2.9
static var THRONE_HP := 2.0
static var WARDEN_HP := 2.05
static var WARDEN_MULT := 1.12
## D341 tuning: the guards' base-stat multiplier and HP share (BWCastle.soldiers).
static var ENEMY_MULT := 0.8
static var ENEMY_HP := 0.52
const GATE_WEIGHT := 2.5
const THRONE_WEIGHT := 3.0
const WARDEN_WEIGHT := 1.5

const SCRIPT := {
	"kind": "storm",
	"units": [],
	"rules": {},
	"phases": [
		{ "id": "throne", "name": "The gate falls",
			"text": "The throne is open: break it, or down the Warden. No more reinforcements.",
			"trigger": { "ko": 1 } },
	],
}


func title() -> String:
	return "Storm the Castle"


func objective_text(b: BWBattle) -> String:
	if phase2(b):
		return "Break the throne or down the Warden"
	return "Break the gate, then the throne"


## The enemies for fight n (BWRun): four wall guards (ranged first), a yard
## guard, the Warden, then the reinforcement waves, marked.
static func build(run: BWRun, n: int) -> Array:
	var out: Array = BWCastle.soldiers(run, n, "guard", "Guard", 4, ["bow", "pistols", "staff", "bow"], ENEMY_HP, ENEMY_MULT, "storm")
	out += BWCastle.soldiers(run, n, "yard", "Guard", 1, ["sword", "axe", "lance"], ENEMY_HP, ENEMY_MULT, "storm")
	var w: BWUnit = BWCastle.soldiers(run, n, "warden", "The Warden", 1, ["lance", "axe", "sword"], WARDEN_HP, WARDEN_MULT, "storm")[0]
	w.name = "The Warden"
	w.cosmetics = { "hair_style": "short_mohawk", "top": "sweater_scarf", "bottom": "tight_pants", "clothing_shade": "dark", "voice_pitch": 0.7 }
	w.set_meta("castle_role", "warden")
	out.append(w)
	for k in REINFORCE_WAVES:
		out += BWCastle.as_wave(BWCastle.soldiers(run, n, "guard_w%d" % (k + 1), "Guard", REINFORCE_COUNT, [], ENEMY_HP, ENEMY_MULT, "storm"), k + 1)
	return out


static func warden(b: BWBattle) -> BWUnit:
	var id := str(b.objective_state.get("warden", ""))
	for u in b.units:
		if u.team == "enemy" and (u.id == id if id != "" else str(u.get_meta("castle_role", "")) == "warden"):
			return u
	return null


static func throne(b: BWBattle) -> BWObjective:
	return BWCastle.object(b, "throne")


static func phase2(b: BWBattle) -> bool:
	return bool(b.objective_state.get("breached", false))


func setup(b: BWBattle) -> void:
	var avg := BWCastle.squad_hp(b)
	BWObjectives.place(b, BWCastle.make_gate(b, "wood", maxi(50, roundi(avg * GATE_HP)), "enemy"))
	var th: Array = b.board.objective.get("throne", [])
	var t := BWObjective.make("throne", Vector2i(int(th[0]), int(th[1])), {
		"id": "castle_throne", "name": "The Throne", "hp": maxi(50, roundi(avg * THRONE_HP)),
		"def": 8, "res": 8, "allegiance": "enemy", "hittable": [], "look": "dark", "height": 2.4,
		"tag": "throne", "dodge": "none",
		"rule": "Sealed while the gate stands. Break it to win.",
		"codex": "A black stone seat with a tall back. Whoever holds it holds the keep.",
	})
	BWObjectives.place(b, t)
	var w := warden(b)
	var wh: Array = b.board.objective.get("warden", [])
	if w != null and wh.size() == 2:
		var post := Vector2i(int(wh[0]), int(wh[1]))
		var o := b.unit_at(post)
		if o != null and o != w and o.team == "enemy":
			o.pos = w.pos                         # trade places: the Warden starts at the throne
		w.pos = post
		b.objective_state["warden"] = w.id
		b.objective_state["warden_post"] = post
	var doors := BWCastle.hexes(b, "back_door")
	for k in REINFORCE_WAVES:
		var us := BWCastle.wave_units(b, k + 1)
		if not us.is_empty():
			BWObjectives.schedule_wave(b, REINFORCE_FROM + k * REINFORCE_EVERY, us, doors)
	b.objective_state["waves_total"] = BWObjectives.waves(b).size()       # the reinforcements, for the view
	b.objective_state["waves_first"] = 0
	# each defender's post: where it starts (the guards hold the walls)
	var posts := {}
	for u in b.units:
		if u.team == "enemy":
			posts[u.id] = u.pos
	b.objective_state["posts"] = posts


func cycle_start(b: BWBattle, c: int) -> void:
	if c == 1 and not BWPhases.active(b):
		# D255's framework: the phase fires when the gate (or the Warden) falls.
		# Started here, after BWPhases.setup (which resets the battle's boss state).
		var s: Dictionary = SCRIPT.duplicate(true)
		var ids: Array = []
		var g := BWCastle.gate(b)
		if g != null:
			ids.append(g.id)
		var w := warden(b)
		if w != null:
			ids.append(w.id)
		s.units = ids
		BWPhases.start(b, s)


func on_ko(b: BWBattle, victim: BWUnit, _by: BWUnit) -> void:
	if BWCastle.is_gate(victim) and not phase2(b):
		b.objective_state["breached"] = true
		var t := throne(b)
		if t != null:
			t.hittable = ["player"]
		var cut := 0
		for w in BWObjectives.waves(b).duplicate():
			if str(w.state) != "spawned":
				BWObjectives.waves(b).erase(w)
				cut += 1
		b._emit({ "type": "castle_breach", "mode": "storm", "gate": victim.id, "cut": cut,
			"throne": t.id if t != null else "" })


func verdict(b: BWBattle) -> String:
	if b.side("player").is_empty():
		return "enemy"
	var t := throne(b)
	if t != null and not t.alive():
		return "player"
	var w := warden(b)
	if w != null and not w.alive():
		return "player"
	if w == null and t == null:
		return ""
	return "-"


func ai_target_weight(b: BWBattle, u: BWUnit, f: BWUnit) -> float:
	if u.team != "player":
		return 1.0
	if BWCastle.is_gate(f):
		return GATE_WEIGHT
	if f is BWObjective and (f as BWObjective).tag == "throne":
		return THRONE_WEIGHT
	if f == warden(b) and phase2(b):
		return WARDEN_WEIGHT
	return 1.0


func ai_turn(b: BWBattle, u: BWUnit) -> bool:
	if u.team == "player":
		var g := BWCastle.gate(b)
		var goal: Variant = g if g != null and g.alive() else throne(b)
		BWCastle.march(b, u, goal)
		return false
	if u.team != "enemy":
		return false
	var w := warden(b)
	if u == w and not phase2(b):
		# the Warden holds the throne: no step off its post, a blow if one is in reach
		var best := BWAI._best_target(b, u, u.pos)
		if not best.is_empty():
			b.attack(u, best.target)
		if not b.over:
			b.end_turn()
		return true
	# guards: strike from where they can; with nothing in reach, hold their post
	var post: Variant = b.objective_state.get("posts", {}).get(u.id, null)
	if post == null or phase2(b):
		return false
	BWCastle.march(b, u, post, true)
	return false


func hud_lines(b: BWBattle) -> Array:
	var out: Array = []
	var g := BWCastle.gate(b)
	if g != null:
		out.append("Gate %d / %d" % [g.hp, g.max_hp()] if g.alive() else "Gate BROKEN")
	var t := throne(b)
	if t != null:
		out.append(("Throne %d / %d" % [t.hp, t.max_hp()]) if phase2(b) else "Throne SEALED")
	var w := warden(b)
	if w != null:
		out.append("Warden %d / %d" % [w.hp, w.max_hp()] if w.alive() else "Warden DOWN")
	if not phase2(b):
		var nxt := BWObjectives.next_wave(b)
		out.append("Reinforcements in %d" % maxi(0, int(nxt.cycle) - b.cycle) if not nxt.is_empty() else "No more reinforcements")
	out.append("Round %d" % b.cycle)
	return out
