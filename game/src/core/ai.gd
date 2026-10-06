class_name BWAI
## Enemy turns. Moves like V8's slice_ai (toward the best basic attack), then
## uses one damaging skill instead of the basic attack when the skill's
## expected damage beats it. It knows the forecast, but not the ground: it
## never plans tiles, follow-ups, Reload or Quick Shot. The forecast carries
## the D86/D87 riders (Spark, Shatter, Cleave, Backstab, Pierce ...) and a
## conductive target's expected arc (`arc_ev`), so those count for free.
## Riposte is free (D87): a duelist sets it last, when a foe is within 3.
## D93/D96: hexes are weighed with forecasts made FROM that hex, so facing
## (rear and flank hits), the ground under the attacker and the perks that
## read it (Current Push, Ambush, Kindling, Gale Force ...) count for free.
## D94: Staggered and Blinded are rules of the battle (skills_for, in_range,
## skill_targets), so the AI obeys them without a special case.
## D112: support skills (War Cry, Phalanx, Aegis, Covering Fire, Transfer,
## Inversion) score through BWSkillDef.ai_support and compete with the
## attack on the same scale; a granted basic follow-up is then played.
## Tumble is a free action set after attacking, then the unit steps to the
## safest hex it can reach.
## D140/D145 obelisk fights (BWBattle.objective_mode): an obelisk's turn is
## its pulse (BWBattle.obelisk_turn). The enemy defends: it never targets an
## obelisk (foes_of), weighs player units by how close they are to a stone
## (THREAT_BONUS), and with nobody in reach walks to cut off the player unit
## nearest an island. The player side (autoplay, the sims) goes for the stone
## its weapon isn't dodged by, and hits it unless a KO is on offer.

## D145: an enemy's attack on a player unit within this many hexes of an
## obelisk scores this much more (a fraction of the blow's expected damage).
const THREAT_RANGE := 3
const THREAT_BONUS := 0.5
## D145: a player unit's expected damage on the squad's focus stone counts
## this many times (it is the win condition); a likely KO on an enemy still
## comes first. The other stone counts OFF_FOCUS_WEIGHT (chip it only when
## nothing else is in reach).
const OBJECTIVE_WEIGHT := 2.0
const OFF_FOCUS_WEIGHT := 0.25


## Who BWAI plays: every enemy, and a rogue on the player's side (D129: Wander's
## jackpot — it fights your enemies on its own, and allies can't target it as
## they can't target any teammate). `autoplay` = every unit.
static func controls(u: BWUnit, autoplay: bool = false) -> bool:
	return u != null and (autoplay or u.team != "player" or u.rogue)


## Play the current unit's whole turn on `b`. Returns nothing; read b.history.
static func take_turn(b: BWBattle) -> void:
	var u := b.current()
	if u == null or b.over:
		return
	if BWObelisk.is_objective(u):
		b.obelisk_turn(u)                             # D140: the pulse, then the turn passes
		return
	var best := _best_target(b, u, u.pos)
	if not best.is_empty() and b.objective_mode() and u.team == "player":
		# D145: a stone within a move beats the foe in reach (move, then strike)
		var there := _best_hex(b, u)
		if there != u.pos and float(_best_target(b, u, there).get("score", 0.0)) > float(best.score) * 1.15:
			b.move(u, there)
			best = _best_target(b, u, u.pos)
	if best.is_empty():
		var dest := _best_hex(b, u)
		if dest != u.pos:
			b.move(u, dest)
		best = _best_target(b, u, u.pos)
	if not b.over:
		# A multi-hex unit (the boss) keeps to move-and-hit: its skills' shapes
		# assume a one-hex body.
		var sk := _best_skill(b, u) if u.size <= 1 else {}
		var sup := _best_support(b, u) if u.size <= 1 else {}
		if not sup.is_empty() and (sk.is_empty() or sup.score > sk.score) and (best.is_empty() or sup.score > best.score):
			sk = sup
		if not sk.is_empty() and (best.is_empty() or sk.score > best.score):
			b.use_skill(u, sk.key, sk.element, sk.target)
			if not b.over and u.alive() and "basic" in u.follow_up:
				var fu := _best_target(b, u, u.pos)       # Transfer / Inversion: then a basic
				if not fu.is_empty():
					b.attack(u, fu.target)
		elif not best.is_empty():
			b.attack(u, best.target)
	if not b.over and u.alive() and u.follow_up.is_empty():
		_guard_up(b, u)
	if not b.over:
		b.end_turn()


## D87: a free action goes up last (Riposte: once the unit stands where it
## will take the next blow, if a foe is within 3; BWSkillDef.ai_free_wanted).
static func _guard_up(b: BWBattle, u: BWUnit) -> void:
	for row in b.skills_for(u):
		var free: bool = row.get("free_action", false) and not row.elements.is_empty()
		if free and BWSkillRegistry.get_def(str(row.key)).ai_free_wanted(b, u):
			var had := int(u.fx.get("bonus_move", 0)) + int(u.fx.get("extra_move", 0))
			b.use_skill(u, row.key, row.elements[0], u.pos)
			var got := int(u.fx.get("bonus_move", 0)) + int(u.fx.get("extra_move", 0)) > had
			if got and not b.over and u.alive() and b.can_move(u):     # D112 Tumble: the granted move
				var safe := _safest_hex(b, u)
				if safe != u.pos:
					b.move(u, safe)
			return


## D112: a support skill worth the action, scored by its def; a granted
## basic follow-up adds that attack's value.
static func _best_support(b: BWBattle, u: BWUnit) -> Dictionary:
	var best := {}
	for row in b.skills_for(u):
		if BWSkills.is_damaging(str(row.key)) or row.get("free_action", false) or row.get("free", false):
			continue
		var s := BWSkillRegistry.get_def(str(row.key)).ai_support(b, u, row)
		if s.is_empty() or float(s.score) <= 0.0:
			continue
		if not s.target in b.skill_targets(u, row.key, str(s.element)):
			continue
		var score := float(s.score)
		if "basic" in row.get("follow_up", []):
			var t := _best_target(b, u, u.pos)
			if not t.is_empty():
				score += float(t.score)
		if best.is_empty() or score > best.score:
			best = { "key": row.key, "element": s.element, "target": s.target, "score": score }
	return best


## D112: how many foes of `u` could reach `h` next turn (move + weapon range).
static func threat(b: BWBattle, u: BWUnit, h: Vector2i) -> int:
	var n := 0
	for f in b.foes_of(u):
		if BWObelisk.is_objective(f):
			continue                                    # D140: a stone hits everyone anyway
		if BWHex.distance(f.pos, h) <= f.move_range() + b.weapon_range(f):
			n += 1
	return n


## D112: how dangerous `h` is for `u`: foes that can reach it, then nearness.
static func danger(b: BWBattle, u: BWUnit, h: Vector2i) -> float:
	var near := 99
	for f in b.foes_of(u):
		near = mini(near, BWHex.distance(f.pos, h))
	return 10.0 * threat(b, u, h) - minf(near, 6)


## D112: the reachable hex with the least danger (ties: stay, then hex order).
static func _safest_hex(b: BWBattle, u: BWUnit) -> Vector2i:
	var reach := b.reachable(u)
	var best_h := u.pos
	var best_t := danger(b, u, u.pos)
	var keys := reach.keys()
	keys.sort()
	for h in keys:
		if not reach[h].stop or h == u.pos:
			continue
		var t := danger(b, u, h)
		if t < best_t:
			best_t = t
			best_h = h
	return best_h


## One damaging skill from where the unit stands, scored by its def
## (BWSkillDef.ai_score; the shared default sums expected damage over everyone
## hit, +1000 per likely finishing blow, plus the D86 arc). Which skills count
## as attacks is BWSkillDef.ai_considers (by default: not follow-up granters,
## set-ups or move-only skills). Deterministic: kit order, element order,
## target order; ties keep the first.
static func _best_skill(b: BWBattle, u: BWUnit) -> Dictionary:
	var best := {}
	for row in b.skills_for(u):
		var d := BWSkillRegistry.get_def(str(row.key))
		if not d.ai_considers(row):
			continue
		for el in row.elements:
			for h in b.skill_targets(u, row.key, el):
				var pv := b.skill_preview(u, row.key, el, h)
				if pv.is_empty():
					continue
				var score := d.ai_score(b, u, pv)
				if score > 0.0 and (best.is_empty() or score > best.score):
					best = { "key": row.key, "element": el, "target": h, "score": score }
	return best


static func _best_target(b: BWBattle, u: BWUnit, from: Vector2i) -> Dictionary:
	var best := {}
	for f in b.foes_of(u):
		if not b.in_range(u, f, from):
			continue
		var fc := b.forecast_basic(u, f, 1.0, "", from)
		var ev: float = fc.expected.value
		var score := ev + (1000.0 if ev >= f.hp else 0.0)   # finishing blows first
		score += float(fc.get("arc_ev", 0.0))               # D86 chain lightning
		score += objective_bonus(b, u, f, ev)               # D145
		if best.is_empty() or score > best.score:
			best = { "target": f, "score": score }
	return best


## Where to stand: somewhere I can hit from (best hit), else as close as I
## can get to the nearest foe. Ties go to the cheaper hex, then to hex order.
static func _best_hex(b: BWBattle, u: BWUnit) -> Vector2i:
	var reach := b.reachable(u)
	var foes := b.foes_of(u)
	var best_h := u.pos
	var best_score := -INF
	var keys := reach.keys()
	keys.sort()
	for h in keys:
		if not reach[h].stop:
			continue
		var score := 0.0
		var t := _best_target(b, u, h)
		if not t.is_empty():
			score = 10000.0 + t.score
		elif b.objective_mode():
			score = -objective_approach(b, u, h)          # D145
		else:
			var nearest := 1 << 20
			for f in foes:
				nearest = mini(nearest, BWHex.distance(h, f.pos))
			score = -nearest
		score -= reach[h].cost * 0.01
		if score > best_score:
			best_score = score
			best_h = h
	return best_h


# ---------------------------------------------------------------- D145 obelisk fights

## Extra score for a blow by `u` on `f` worth `ev`: the player side weighs an
## obelisk OBJECTIVE_WEIGHT times; the enemy weighs a player unit standing
## near a stone up by THREAT_BONUS.
static func objective_bonus(b: BWBattle, u: BWUnit, f: BWUnit, ev: float) -> float:
	if not b.objective_mode():
		return 0.0
	if BWObelisk.is_objective(f):
		if u.team != "player":
			return 0.0
		return ev * ((OBJECTIVE_WEIGHT if f == focus_stone(b) else OFF_FOCUS_WEIGHT) - 1.0)
	if u.team == "enemy" and stone_gap(b, f.pos) <= THREAT_RANGE:
		return ev * THREAT_BONUS
	return 0.0


## Hexes from `h` to the nearest standing obelisk (99 when none).
static func stone_gap(b: BWBattle, h: Vector2i) -> int:
	var best := 99
	for o in b.objectives():
		if o.alive():
			best = mini(best, BWHex.distance(h, o.pos))
	return best


## The stone the player side goes for together (splitting across both breaks
## neither): the one the most living squad members hit without its dodge
## (melee units: the Lantern; bows, pistols, staves: the Well), then the one
## with less HP left, then map order.
static func focus_stone(b: BWBattle) -> BWUnit:
	var best: BWUnit = null
	var best_k := -INF
	for o in b.objectives():
		if not o.alive():
			continue
		var k := 0.0
		for u in b.side("player"):
			k += 0.5 if preferred_kind(u) == (o as BWObelisk).dodge_vs else 1.0
		k -= float(o.hp) / maxf(o.max_hp(), 1.0) * 0.1
		if k > best_k + 1e-6:
			best_k = k
			best = o
	return best


## How a unit fights a stone: "ranged" (bow, pistols, staff) or "melee".
static func preferred_kind(u: BWUnit) -> String:
	return "ranged" if u.weapon_class in ["bow", "pistols", "staff"] else "melee"


static func chosen_stone(b: BWBattle, _u: BWUnit) -> BWUnit:
	return focus_stone(b)


## How far `h` is from where `u` wants to be (lower is better), with nobody in
## reach. Player side: walking cost to its chosen stone. Enemy side: cut off
## the player unit closest to a stone (the runner): near it, and on the stone
## side of it.
static func objective_approach(b: BWBattle, u: BWUnit, h: Vector2i) -> float:
	if u.team == "player":
		var st := chosen_stone(b, u)
		if st == null:
			return 0.0
		return float(walk_field(b, st).get(h, 999))
	var runner: BWUnit = null
	var rg := 1 << 20
	for f in b.side("player"):
		var g := stone_gap(b, f.pos)
		if runner == null or g < rg or (g == rg and BWHex.distance(u.pos, f.pos) < BWHex.distance(u.pos, runner.pos)):
			runner = f
			rg = g
	if runner == null:
		return 0.0
	return BWHex.distance(h, runner.pos) + 0.5 * stone_gap(b, h)


## Walking cost (terrain and climbs, units ignored) from every hex to a hex
## beside obelisk `o`, cached on the battle per stone.
static func walk_field(b: BWBattle, o: BWUnit) -> Dictionary:
	var key := "_walk_" + o.id
	if b.has_meta(key):
		return b.get_meta(key)
	var dist := {}
	var frontier: Array = []
	for n in b.board.neighbors(o.pos):
		if b.board.is_passable(n):
			dist[n] = 0
			frontier.append([0, n])
	while not frontier.is_empty():
		var idx := 0
		for i in frontier.size():
			if frontier[i][0] < frontier[idx][0]:
				idx = i
		var cur: Array = frontier.pop_at(idx)
		var c: int = cur[0]
		var h: Vector2i = cur[1]
		if c > int(dist.get(h, 1 << 20)):
			continue
		for n in b.board.neighbors(h):
			var sc := b.board.step_cost(n, h)              # walking n -> h, toward the stone
			if sc < 0 or n == o.pos:
				continue
			if c + sc < int(dist.get(n, 1 << 20)):
				dist[n] = c + sc
				frontier.append([c + sc, n])
	b.set_meta(key, dist)
	return dist
