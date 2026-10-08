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
## D209 special encounters: the forecast carries the immunities (an immune blow
## expects 0 and is no target) and the Blank's x2 from melee, so both sides
## pick element skills and the ground against Elemental Beings and basic
## strikes against Blanks without a special case.

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
## D323: big-board pruning (a 6v6 on a 17×15-19×17 map ran 400-560 ms worst
## turns): on a map fielding more than BWRun.DEPLOY a side, a turn forecasts
## from at most BIG_HEX_CAP attack hexes and previews at most BIG_TARGET_CAP
## targets per skill and element (see _skip_hexes, _cap_targets). Counts,
## not the clock, so a seed still replays the same fight. 0 = no cap.
static var BIG_HEX_CAP := 12
static var BIG_TARGET_CAP := 8
## D323: skill previews per _best_skill call on a big board, shared over the
## kit's skill × element pairs (each pair keeps at least one); the swap look
## (turn_value, both weapons) gets BIG_SWAP_PREVIEWS.
static var BIG_PREVIEWS := 16
static var BIG_SWAP_PREVIEWS := 6
## D323: attack hexes the swap look forecasts from (per weapon).
static var BIG_SWAP_HEXES := 6
## D323: previews per _best_skill call that also run the simulated extras
## (Blast Rider, Overfreeze, squall: each may simulate the whole action), the
## targets nearest a foe first. 0 = no cap.
static var BIG_SIMS := 3


## Who BWAI plays: every enemy (D177 removed D129's rogue, a player unit the
## AI played). `autoplay` = every unit.
static func controls(u: BWUnit, autoplay: bool = false) -> bool:
	return u != null and (autoplay or u.team != "player")


## Play the current unit's whole turn on `b`. Returns nothing; read b.history.
## D347: a GROUP TURN plays every member of the open block here, one after
## another in the block's order (each an ordinary turn), so one call covers
## the whole group and the view replays its events together.
static func take_turn(b: BWBattle) -> void:
	var u := b.current()
	if u == null or b.over:
		return
	if b.in_group_turn():
		var serial := int(b.group_live.serial)
		var guard := 0
		while not b.over and b.current() != null and not b.group_live.is_empty() 				and int(b.group_live.serial) == serial and guard < 64:
			_take_one(b)
			guard += 1
		return
	_take_one(b)


static func _take_one(b: BWBattle) -> void:
	var u := b.current()
	if u == null or b.over:
		return
	if BWObjective.is_object(u) and BWObjectives.ai_turn(b, u):
		return                                        # D348: an acting objective object (the Lil Fella)
	if BWObelisk.is_objective(u):
		b.obelisk_turn(u)                             # D140: the pulse, then the turn passes
		return
	if BWTwins.is_twin(u):
		BWTwins.ai_turn(b, u)                         # D257: the Twins' phase-aware turn
		return
	if BWObjectives.ai_turn(b, u):
		return                                        # D327: a mode plays this turn (grunts walk for the exit)
	_consider_swap(b, u)                              # D181: draw the carried weapon if it scores better
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
			BWWindShape.ai_refine(b, u, sk.key, str(sk.element), sk.target)   # D368: ≤ 4 shaping sims for a wind skill
			if sk.has("choice"):
				b.use_skill(u, sk.key, sk.element, sk.target, sk.choice)
			else:
				b.use_skill(u, sk.key, sk.element, sk.target)
			if not b.over and u.alive() and "basic" in u.follow_up:
				var fu := _best_target(b, u, u.pos)       # Transfer / Inversion: then a basic
				if not fu.is_empty():
					b.attack(u, fu.target)
		elif not best.is_empty():
			b.attack(u, best.target)
			if not b.over and u.alive() and "basic" in u.follow_up:
				var again := _best_target(b, u, u.pos)    # D197 Relentless: the extra attack
				if not again.is_empty():
					b.attack(u, again.target)
	if not b.over and u.alive() and u.follow_up.is_empty():
		_guard_up(b, u)
	if not b.over:
		b.end_turn()


## D181/D195: the swap is free (and unlimited), so the AI weighs both weapons
## once, at the start of its turn (at most one swap per decision: no oscillation):
## each one's best option this turn (the best basic attack from any hex it can
## reach, or its best damaging skill from where it stands), and draws the
## carried weapon when that beats the one in hand by SWAP_MARGIN.
const SWAP_MARGIN := 1.1


static func _consider_swap(b: BWBattle, u: BWUnit) -> void:
	if not b.can_swap(u) or u.size > 1:
		return
	var now := turn_value(b, u)
	u.swap_weapons()                                  # a look only: swapped back below
	var other := turn_value(b, u)
	u.swap_weapons()
	b.refresh_effects()
	if other > now * SWAP_MARGIN and other > 0.0:
		b.swap_weapon(u)


## D181: the best this unit could do this turn with the weapon in hand.
static func turn_value(b: BWBattle, u: BWUnit) -> float:
	var best := 0.0
	var reach := b.reachable(u) if b.can_move(u) else { u.pos: { "stop": true } }
	var skip := _skip_hexes(b, u, reach, BIG_SWAP_HEXES)   # D323: big boards only
	for h in reach:
		if (reach[h].stop or h == u.pos) and not skip.has(h):
			var t := _best_target(b, u, h)
			if not t.is_empty():
				best = maxf(best, float(t.score))
	var sk := _best_skill(b, u, BIG_SWAP_PREVIEWS)     # D323: a lighter look on big boards
	if not sk.is_empty():
		best = maxf(best, float(sk.score))
	return best


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
			if s.has("choice"):
				best["choice"] = s.choice                  # D304: a second pick (a wall's heading, a wave's)
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
static func _best_skill(b: BWBattle, u: BWUnit, previews: int = -1) -> Dictionary:
	var best := {}
	var per := _pair_cap(b, u, BIG_PREVIEWS if previews < 0 else previews)   # D323: 0 off a big board
	var sims := 0
	for row in b.skills_for(u):
		var d := BWSkillRegistry.get_def(str(row.key))
		if not d.ai_considers(row):
			continue
		for el in row.elements:
			for h in _cap_targets(b, u, b.skill_targets(u, row.key, el), per):   # D323: big boards only
				var pv := b.skill_preview(u, row.key, el, h)
				if pv.is_empty():
					continue
				var score := d.ai_score(b, u, pv)
				score += BWOverheat.ai_skill(b, u, pv)                      # D285: Overheat rings and setups
				sims += 1
				if per <= 0 or BIG_SIMS <= 0 or sims <= BIG_SIMS:            # D323: big boards cap the simulated extras
					score += BWThunderKeys.ai_skill(b, u, row.key, el, h, pv)   # D291: the Blast Rider dive (simulated)
					score += BWOverfreeze.ai_skill(b, u, row.key, el, h, pv)   # D314: Overfreeze bursts (simulated, ice on glazed water only)
					score += BWSquall.ai_skill(b, u, row.key, el, h, pv)       # D314: a squall's front (simulated, light/dark 2+ only)
				if score > 0.0 and (best.is_empty() or score > best.score):
					best = { "key": row.key, "element": el, "target": h, "score": score }
	return best


static func _best_target(b: BWBattle, u: BWUnit, from: Vector2i) -> Dictionary:
	var best := {}
	for f in b.foes_of(u):
		if not b.in_range(u, f, from):
			continue
		var fc := b.forecast_basic(u, f, 1.0, "", from)
		if fc.has("immune"):
			continue                                        # D209: a Being shrugs off the blow: not a target
		var ev: float = fc.expected.value
		var w := BWObjectives.ai_target_weight(b, u, f)    # D327: a mode's weights (0 = not a target)
		if w <= 0.0:
			continue
		var score := ev + (1000.0 if ev >= f.hp else 0.0)   # finishing blows first
		score += float(fc.get("arc_ev", 0.0))               # D86 chain lightning
		score += objective_bonus(b, u, f, ev)               # D145
		score += BWThunderKeys.ai_target(b, u, f, from)     # D290: a Static Blades backstab bursts
		score *= w
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
	var wfc := BWWeather.forecast(b)                  # D253: the next tick's telegraphed hazards
	var skip := _skip_hexes(b, u, reach)              # D323: big boards only
	for h in keys:
		if not reach[h].stop or skip.has(h):
			continue
		var score := 0.0
		var t := _best_target(b, u, h)
		var hz := BWWeather.hazard_pct(b, u, h, wfc) if not wfc.is_empty() else 0.0
		hz += BWPools.hazard_pct(b, u, h, reach[h])     # D264/D401: an electrified pool, standing Unsteady on glaze
		if not t.is_empty():
			score = 10000.0 + t.score - hz * u.max_hp() / 100.0
		elif b.objective_mode():
			score = -objective_approach(b, u, h)          # D145
		else:
			var nearest := 1 << 20
			for f in foes:
				nearest = mini(nearest, BWHex.distance(h, f.pos))
			score = -nearest
			score -= hz * 0.3                             # D253: ~3 hexes of approach for a 10% hazard
		score += BWKeystoneFx.ai_hex(b, u, h)          # D297: Riptide reach, Event Horizon wariness
		score -= reach[h].cost * 0.01
		score += BWBeams.ai_hex(b, u, h)                  # D287: form a beam on light, step off a foe's beam
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
			var sc := b.board.step_cost(n, h, BWBoard.WALK)              # walking n -> h, toward the stone
			if sc < 0 or n == o.pos:
				continue
			if c + sc < int(dist.get(n, 1 << 20)):
				dist[n] = c + sc
				frontier.append([c + sc, n])
	b.set_meta(key, dist)
	return dist


# ---------------------------------------------------------------- D323 big boards

## A map fielding more than the 3v3 default (BWBoard.deploy_count, D319).
static func big(b: BWBattle) -> bool:
	return b.board.deploy_count > BWRun.DEPLOY


## D323: the reachable stops NOT worth a full forecast this turn ({} on a 3v3
## map: nothing pruned). An attack hex has a foe within weapon range by
## distance; past BIG_HEX_CAP of them, the kept ones are dealt round-robin
## over the foes, the weakest (fewest HP) first, each foe's hexes cheapest walk
## first (then hex order), so every foe in reach keeps its best approaches.
## `cap` -1 = BIG_HEX_CAP (the swap look passes BIG_SWAP_HEXES).
## Hexes with no foe in range are never skipped (their score is cheap).
static func _skip_hexes(b: BWBattle, u: BWUnit, reach: Dictionary, cap: int = -1) -> Dictionary:
	if cap < 0:
		cap = BIG_HEX_CAP
	if cap <= 0 or not big(b):
		return {}
	var wr := b.weapon_range(u)
	var foes: Array = b.foes_of(u).filter(func(f): return f.alive())
	foes.sort_custom(func(x, y): return x.hp < y.hp or (x.hp == y.hp and x.id < y.id))
	var per: Array = []
	var attack := {}
	for f in foes:
		var hs: Array = []
		for h in reach:
			if (reach[h].stop or h == u.pos) and BWHex.distance(h, f.pos) <= wr + maxi(f.size, 1) - 1:
				hs.append(h)
				attack[h] = true
		hs.sort_custom(func(x, y):
			var cx: float = reach[x].get("cost", 0) if reach[x] is Dictionary else 0
			var cy: float = reach[y].get("cost", 0) if reach[y] is Dictionary else 0
			return cx < cy or (cx == cy and x < y))
		per.append(hs)
	if attack.size() <= cap:
		return {}
	var keep := {}
	var i := 0
	while keep.size() < cap:
		var any := false
		for hs in per:
			if i < hs.size():
				any = true
				keep[hs[i]] = true
				if keep.size() >= cap:
					break
		if not any:
			break
		i += 1
	var skip := {}
	for h in attack:
		if not keep.has(h):
			skip[h] = true
	return skip


## D323: targets previewed per skill × element pair on a big board: `budget`
## previews shared over the kit's pairs, at least 1, at most BIG_TARGET_CAP.
## 0 (no cap) on a 3v3 map or with the caps off.
static func _pair_cap(b: BWBattle, u: BWUnit, budget: int) -> int:
	if BIG_TARGET_CAP <= 0 or budget <= 0 or not big(b):
		return 0
	var pairs := 0
	for row in b.skills_for(u):
		if BWSkillRegistry.get_def(str(row.key)).ai_considers(row):
			pairs += row.elements.size()
	return clampi(budget / maxi(pairs, 1), 1, BIG_TARGET_CAP)


## D323: a skill's targets, at most `cap` (0 = all): the ones nearest a living
## foe (then hex order). Unchanged on a 3v3 map (cap 0).
static func _cap_targets(b: BWBattle, u: BWUnit, targets: Array, cap: int) -> Array:
	if cap <= 0 or targets.size() <= cap:
		return targets
	var foes: Array = b.foes_of(u).filter(func(f): return f.alive())
	var near := {}
	for h in targets:
		var d := 1 << 20
		for f in foes:
			d = mini(d, BWHex.distance(h, f.pos))
		near[h] = d
	var out: Array = targets.duplicate()
	out.sort_custom(func(x, y): return near[x] < near[y] or (near[x] == near[y] and x < y))
	return out.slice(0, cap)
