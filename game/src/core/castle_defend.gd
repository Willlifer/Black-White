class_name BWCastleDefend
extends BWObjectiveMode
## D335-D342: DEFEND THE CASTLE (6v6, `maps/keep.json`; design/MAPS.md §13).
## The squad holds a walled keep; raiders come at it in waves and go for the
## IRON GATE. Shared castle rules (high ground, the gate) are BWCastle's.
##
##   Win   survive ROUNDS rounds (the start of round ROUNDS + 1), or down every
##         raider once no wave is left to come.
##   Lose  the gate breaks, or the squad is down. (The breaches lead onto the
##         wall walk and from there down into the yard: raiders who take them
##         fight the squad from behind, but only the gate decides the fight.)
##   Waves the opening six, then WAVES (round, count): each telegraphed a round
##         ahead on the map's wave hexes (objective.waves_at), BWObjectives.
##   AI    a raider goes for the gate (x GATE_WEIGHT on its score; with nothing in reach it marches
##         on the gate). The squad (autoplay, the sim) holds by the gate.

const ROUNDS := 8
## Waves after the opening six: [round they arrive, how many].
const WAVES := [[3, 3], [5, 3]]
## D341 tuning: the gate's HP as a multiple of the squad's mean max HP.
static var GATE_HP := 4.25
## D341 tuning: the raiders' base-stat multiplier and HP share (BWCastle.soldiers).
static var ENEMY_MULT := 1.06
static var ENEMY_HP := 0.9
const GATE_WEIGHT := 3.0


func title() -> String:
	return "Defend the Castle"


func objective_text(_b: BWBattle) -> String:
	return "Hold the gate for %d rounds" % ROUNDS


## The enemies for fight n (BWRun): six raiders, then each wave's, marked.
static func build(run: BWRun, n: int) -> Array:
	var out: Array = BWCastle.soldiers(run, n, "raider", "Raider", 6, [], ENEMY_HP, ENEMY_MULT, "defend")
	for k in WAVES.size():
		out += BWCastle.as_wave(BWCastle.soldiers(run, n, "raider_w%d" % (k + 1), "Raider", int(WAVES[k][1]), [], ENEMY_HP, ENEMY_MULT, "defend"), k + 1)
	return out


func setup(b: BWBattle) -> void:
	var hp := maxi(50, roundi(BWCastle.squad_hp(b) * GATE_HP))
	BWObjectives.place(b, BWCastle.make_gate(b, "iron", hp, "player"))
	b.objective_state["rounds"] = ROUNDS
	var at := BWCastle.hexes(b, "waves_at")
	for k in WAVES.size():
		var us := BWCastle.wave_units(b, k + 1)
		if not us.is_empty():
			BWObjectives.schedule_wave(b, int(WAVES[k][0]), us, at)
	b.objective_state["waves_total"] = BWObjectives.waves(b).size() + 1    # the opening six count as wave 1
	b.objective_state["waves_first"] = 1


func cycle_start(b: BWBattle, c: int) -> void:
	if c > ROUNDS:
		b.objective_state["held"] = true
		b._check_end()


func verdict(b: BWBattle) -> String:
	if b.side("player").is_empty():
		return "enemy"
	var g := BWCastle.gate(b)
	if g != null and not g.alive():
		return "enemy"
	if b.objective_state.get("held", false):
		return "player"
	if b.side("enemy").is_empty() and BWObjectives.waves_left(b) == 0:
		return "player"
	return "-"


func ai_target_weight(b: BWBattle, u: BWUnit, f: BWUnit) -> float:
	return GATE_WEIGHT if u.team == "enemy" and BWCastle.is_gate(f) else 1.0


func ai_turn(b: BWBattle, u: BWUnit) -> bool:
	var g := BWCastle.gate(b)
	if g != null and g.alive():
		BWCastle.march(b, u, g)                   # raiders on the gate, the squad holds by it
	return false


## The HUD plate: the gate, the wave counter, the rounds left.
func hud_lines(b: BWBattle) -> Array:
	var out: Array = []
	var g := BWCastle.gate(b)
	if g != null:
		out.append("Gate %d / %d" % [g.hp, g.max_hp()] if g.alive() else "Gate BROKEN")
	var total := int(b.objective_state.get("waves_total", 1))
	var nxt := BWObjectives.next_wave(b)
	var seen := total - BWObjectives.waves_left(b)
	var w := "Wave %d / %d" % [seen, total]
	if not nxt.is_empty():
		w += " (next in %d)" % maxi(0, int(nxt.cycle) - b.cycle)
	out.append(w)
	out.append("Round %d of %d  (%d left)" % [mini(b.cycle, ROUNDS), ROUNDS, maxi(0, ROUNDS - b.cycle)])
	return out
