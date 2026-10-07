class_name BWTwins
extends RefCounted
## D256-D258: the mid-run boss, the Twins (Noon and Dusk). D353/D355: a boss
## card at fight 4, the other card the Obelisks; never weather (design/
## EXPANSION.md §3). Two tall figures, one
## hex each, built at the squad's level. Their phases are data for the phase
## framework (BWPhases, D255); this file owns their mechanics and their AI.
##
## Phase 1  Each Twin paints its colour (+2 on the light/dark axis) on its hex
##          and the ring around it at the end of its turn: Noon light, Dusk
##          dark. A Twin heals at its turn start from its OWN colour under it
##          (HEAL_PCT per point, instead of the usual light heal / dark drain).
##          While they stand more than BEAM_GAP hexes apart a BEAM joins them:
##          the hexes on the line between them, Noon's half in Noon's colour,
##          Dusk's half in Dusk's. A foe that crosses it or ends its turn on it
##          pays once per turn: BEAM_PCT % max HP (the segment's element, after
##          resistance) and Blinded (light) or Shrouded (dark).
## Phase 2  ("swap", either Twin under 50%): the colours trade (Noon paints
##          dark, Dusk light) and each heals x2 from its own (new) colour.
## Phase 3  ("rage"): when one falls, the other rages 2 cycles later: +1 move,
##          paint radius doubled (1 -> 2). Down the second within those 2
##          cycles and the rage never comes.
## Counters: light and dark cancel on the axis, so painting the opposite
##          colour over their ground starves the heal; THUNDER on any beam hex
##          (a player's fuse or detonation) breaks the beam for the rest of this
##          cycle and the next, and jolts both Twins for FEEDBACK_PCT % max HP;
##          bursting both together denies the rage.

const NOON := "noon"
const DUSK := "dusk"
const ROLES := [NOON, DUSK]
const NAMES := { NOON: "Noon", DUSK: "Dusk" }
const TITLE := "The Twins: Noon and Dusk"
const MODEL := "glaive"

## Tuning (tools/campaign_sim.gd, env TWINS="hp,mult").
static var TWINS_HP := 2.6          # x the unit's own D137 HP (D259; D308: 2.6 at fight 7; D355: 2.6 at fight 4, whole-run 58%)
static var TWINS_MULT := 1.1        # base-stat multiplier (D259; D308: 1.25 at fight 7; D355: 1.1 at fight 4)
const PAINT_STEPS := 2
const PAINT_RADIUS := 1
const HEAL_PCT := 2.0               # % max HP per point of own colour
const BEAM_GAP := 4                 # beam when more than this many hexes apart
const BEAM_PCT := 10.0
const FEEDBACK_PCT := 5.0
const RAGE_DELAY := 2

const SCRIPT := {
	"kind": "twins",
	"units": [],
	"rules": { "paint": { NOON: "light", DUSK: "dark" }, "heal_mult": 1.0, "paint_radius": PAINT_RADIUS, "move_plus": 0 },
	"phases": [
		{ "id": "swap", "name": "The colours swap",
			"text": "Noon now paints dark and Dusk light; each heals x2 on its own colour.",
			"trigger": { "hp_below": 0.5 },
			"rules": { "paint": { NOON: "dark", DUSK: "light" }, "heal_mult": 2.0 } },
		{ "id": "rage", "name": "Rage",
			"text": "+1 move, paint radius doubled.",
			"trigger": { "ko": 1, "delay_cycles": RAGE_DELAY },
			"rules": { "move_plus": 1, "paint_radius": PAINT_RADIUS * 2 }, "scope": "survivors" },
	],
}


static func is_twin(u: BWUnit) -> bool:
	return u != null and u.encounter == "twin"


static func role(u: BWUnit) -> String:
	return NOON if u.id.begins_with(NOON) else DUSK


static func twin(b: BWBattle, r: String) -> BWUnit:
	for u in b.units:
		if is_twin(u) and role(u) == r:
			return u
	return null


static func other(b: BWBattle, u: BWUnit) -> BWUnit:
	return twin(b, DUSK if role(u) == NOON else NOON)


## The colour `u` paints and heals on now ("light" / "dark").
static func colour(b: BWBattle, u: BWUnit) -> String:
	var p: Dictionary = BWPhases.rule(b, "paint", u, SCRIPT.rules.paint)
	return str(p.get(role(u), "light"))


static func raging(b: BWBattle, u: BWUnit) -> bool:
	return int(BWPhases.rule(b, "move_plus", u, 0)) > 0


# ---------------------------------------------------------------- build

## Fight n's Twins for `run`: the squad's level, the stage's gear tier,
## glaives, Noon light and Dusk dark, HP at TWINS_HP of their own D137 HP.
static func build(run: BWRun, n: int) -> Array:
	var bld := BWRooms.enemy_build(n, BWRooms.STANDARD)
	bld.mult = TWINS_MULT
	var lvl := run.squad_level()
	var tier := run.tier_for(int(bld.stage))
	var ranks: Array = BWRun.ENEMY_RANKS[tier]
	var erng := RandomNumberGenerator.new()
	erng.seed = hash("twins|%d|%d" % [run.seed_value, n])
	var out: Array = []
	for r in ROLES:
		var u := BWEncounters._unit(run, n, r, NAMES[r], MODEL, "light" if r == NOON else "dark",
			lvl, tier, ranks, bld, 1.0, TWINS_HP, erng)
		u.encounter = "twin"
		u.cosmetics = { "hair_style": "none", "top": "tshirt", "bottom": "tight_pants",
			"clothing_shade": "light" if r == NOON else "dark", "voice_pitch": 0.75 if r == NOON else 0.6 }
		out.append(u)
	return out


## D258: the win's reward: every squad unit gets one extra pick, a two-card
## offer (D174): a perk in its element while one is left to take, else a
## weapon skill in its class. [{ unit, kind }] for the report.
static func reward(run: BWRun) -> Array:
	var out: Array = []
	for u in run.squad:
		if u.element != "" and run.grant_perk_pick(u, u.element):
			out.append({ "unit": u.id, "kind": "perk", "element": u.element })
		elif run.grant_skill_pick(u, u.weapon_class):
			out.append({ "unit": u.id, "kind": "skill", "weapon": u.weapon_class })
	return out


# ---------------------------------------------------------------- battle hooks (BWPhases.dispatch)

static func begin(b: BWBattle) -> void:
	var s: Dictionary = SCRIPT.duplicate(true)
	s.units = b.units.filter(func(u): return is_twin(u)).map(func(u): return u.id)
	BWPhases.start(b, s)
	b.boss["beam"] = []              # [[hex, colour], ...]
	b.boss["beam_broken"] = -1       # the beam is down through this cycle
	b.boss["paid"] = {}              # unit id -> turn serial it last paid the beam
	update_beam(b, true)


## A Twin's turn start: heal from its own colour (x heal_mult). True for a
## Twin: the battle skips the usual light heal and dark drain on it.
static func turn_start(b: BWBattle, u: BWUnit) -> bool:
	if not is_twin(u):
		return false
	var pts := b.tiles.intensity(u.pos, colour(b, u))
	if pts > 0 and u.alive() and u.hp < u.max_hp():
		var pct := HEAL_PCT * pts * float(BWPhases.rule(b, "heal_mult", u, 1.0))
		b._heal(u, pct, "twin_" + colour(b, u))
	return true


static func turn_end(b: BWBattle, u: BWUnit) -> void:
	if b.over or not u.alive():
		update_beam(b)
		return
	if is_twin(u):
		var r := int(BWPhases.rule(b, "paint_radius", u, PAINT_RADIUS))
		var hexes: Array = BWHex.area(u.pos, r).filter(func(h): return b.tiles.can_hold(h))
		b.paint(hexes, colour(b, u), u, PAINT_STEPS)
		update_beam(b)
		return
	update_beam(b)
	if _foe(b, u):
		var c := beam_at(b, u.pos)
		if c != "":
			_pay(b, u, u.pos, c)


static func after_move(b: BWBattle, u: BWUnit, path: Array) -> void:
	if is_twin(u):
		update_beam(b)
		return
	if not _foe(b, u):
		return
	for i in range(1, path.size()):
		var c := beam_at(b, path[i])
		if c != "":
			_pay(b, u, path[i], c)
			return


## Thunder from a foe landing on the beam breaks it (this cycle and the next)
## and jolts both Twins.
static func after_paint(b: BWBattle, hexes: Array, element: String, by: BWUnit) -> void:
	if element != "thunder" or by == null or is_twin(by) or b.boss.beam.is_empty():
		return
	var hit := false
	for h in hexes:
		if beam_at(b, h) != "":
			hit = true
			break
	if not hit:
		return
	b.boss.beam_broken = b.cycle + 1
	b._emit({ "type": "beam_break", "unit": by.id, "until": b.boss.beam_broken })
	for t in b.units:
		if is_twin(t) and t.alive():
			b._tile_hurt(t, b._tile_dmg(t, FEEDBACK_PCT, "thunder"), "beam_break", by.id)
	update_beam(b)


static func on_ko(b: BWBattle, _v: BWUnit) -> void:
	update_beam(b)


static func new_cycle(b: BWBattle) -> void:
	update_beam(b)


static func on_phase(b: BWBattle, _id: String) -> void:
	update_beam(b)


static func move_plus(b: BWBattle, u: BWUnit) -> int:
	return int(BWPhases.rule(b, "move_plus", u, 0))


# ---------------------------------------------------------------- the beam

## The beam's hexes now: the line between the Twins, ends excluded, jagged
## hexes skipped; each hex in the colour of the nearer Twin (ties: Noon).
static func beam_line(b: BWBattle) -> Array:
	var n := twin(b, NOON)
	var d := twin(b, DUSK)
	if n == null or d == null or not n.alive() or not d.alive():
		return []
	if b.cycle <= int(b.boss.get("beam_broken", -1)):
		return []
	if BWHex.distance(n.pos, d.pos) <= BEAM_GAP:
		return []
	var out: Array = []
	for h in BWHex.line(n.pos, d.pos):
		if h == n.pos or h == d.pos or not b.board.exists(h) or not b.board.is_passable(h):
			continue
		var near_noon := BWHex.distance(h, n.pos) <= BWHex.distance(h, d.pos)
		out.append([h, colour(b, n) if near_noon else colour(b, d)])
	return out


## Recompute the beam; emit `beam` when it changed (or `force`).
static func update_beam(b: BWBattle, force: bool = false) -> void:
	if not BWPhases.active(b) or BWPhases.kind(b) != "twins":
		return
	var now := beam_line(b)
	if not force and now == b.boss.beam:
		return
	b.boss.beam = now
	var n := twin(b, NOON)
	var d := twin(b, DUSK)
	b._emit({ "type": "beam", "hexes": now.map(func(x): return x[0]), "colours": now.map(func(x): return x[1]),
		"on": not now.is_empty(), "ends": [n.pos if n else Vector2i.ZERO, d.pos if d else Vector2i.ZERO] })


## The beam's colour on `h` ("" = no beam there).
static func beam_at(b: BWBattle, h: Vector2i) -> String:
	if not BWPhases.active(b):
		return ""
	for x in b.boss.get("beam", []):
		if x[0] == h:
			return str(x[1])
	return ""


static func _foe(b: BWBattle, u: BWUnit) -> bool:
	return u.team == "player" and not BWObelisk.is_objective(u)


## One beam toll: once per unit per turn.
static func _pay(b: BWBattle, u: BWUnit, h: Vector2i, c: String) -> void:
	if int(b.boss.paid.get(u.id, -1)) == b._turn_serial or not u.alive():
		return
	b.boss.paid[u.id] = b._turn_serial
	var src := twin(b, NOON) if beam_owner_is_noon(b, h) else twin(b, DUSK)
	var dmg := b._tile_dmg(u, BEAM_PCT, c)
	b._emit({ "type": "beam_hit", "unit": u.id, "hex": h, "colour": c, "pct": BEAM_PCT })
	b._tile_hurt(u, dmg, "beam", src.id if src else "")
	if u.alive() and not b.over:
		b.add_status(u, "blinded" if c == "light" else "shrouded", src)


static func beam_owner_is_noon(b: BWBattle, h: Vector2i) -> bool:
	var n := twin(b, NOON)
	var d := twin(b, DUSK)
	if n == null or d == null:
		return n != null
	return BWHex.distance(h, n.pos) <= BWHex.distance(h, d.pos)


## The rule line for the HUD / glossary.
static func beam_text() -> String:
	return "Beam: crossing it or ending a turn on it costs %d%% max HP (its element) and Blinded (light) or Shrouded (dark), once per turn. Thunder breaks it." % int(BEAM_PCT)


# ---------------------------------------------------------------- AI (D257)

## A Twin's turn: pick the hex that weighs the best blow, the heal on its own
## colour (more the more it's hurt, none while raging), and keeping the beam
## up across the squad; then strike (or its best skill), then end the turn
## (the paint happens in turn_end).
static func ai_turn(b: BWBattle, u: BWUnit) -> void:
	if b.can_move(u):
		var dest := best_hex(b, u)
		if dest != u.pos:
			b.move(u, dest)
	if not b.over and u.alive():
		var t := target(b, u, u.pos)
		var sk := BWAI._best_skill(b, u)
		if not sk.is_empty() and (t.is_empty() or float(sk.score) > float(t.score)):
			b.use_skill(u, sk.key, sk.element, sk.target)
		elif not t.is_empty():
			b.attack(u, t.target)
	if not b.over:
		b.end_turn()


## Phase-aware target from `from`: expected damage, finishing blows first;
## after the swap the hurt are weighted up (finish them); a foe on the beam
## or on this Twin's colour is weighted up (pin it there).
static func target(b: BWBattle, u: BWUnit, from: Vector2i) -> Dictionary:
	var best := {}
	var swapped := BWPhases.fired(b, "swap")
	for f in b.foes_of(u):
		if not b.in_range(u, f, from):
			continue
		var fc := b.forecast_basic(u, f, 1.0, "", from)
		var ev: float = fc.expected.value
		var score := ev + (1000.0 if ev >= f.hp else 0.0)
		if swapped:
			score *= 1.0 + 0.5 * (1.0 - float(f.hp) / maxf(f.max_hp(), 1.0))
		if beam_at(b, f.pos) != "" or b.tiles.intensity(f.pos, colour(b, u)) > 0:
			score *= 1.15
		if best.is_empty() or score > best.score:
			best = { "target": f, "score": score }
	return best


static func best_hex(b: BWBattle, u: BWUnit) -> Vector2i:
	var reach := b.reachable(u)
	var keys := reach.keys()
	keys.sort()
	var best_h := u.pos
	var best_s := -INF
	for h in keys:
		if not reach[h].stop and h != u.pos:
			continue
		var s := hex_score(b, u, h) - float(reach[h].get("cost", 0)) * 0.01
		if s > best_s:
			best_s = s
			best_h = h
	return best_h


static func hex_score(b: BWBattle, u: BWUnit, h: Vector2i) -> float:
	var m := float(u.max_hp())
	var s := 0.0
	var t := target(b, u, h)
	var striking := not t.is_empty()
	if striking:
		s += 40.0 + float(t.score)
	else:
		var near := 99
		for f in b.foes_of(u):
			near = mini(near, BWHex.distance(h, f.pos))
		s -= 0.03 * m * near                    # close in: nobody in reach is a wasted turn
	var hurt := 1.0 - float(u.hp) / maxf(m, 1.0)
	if not raging(b, u):
		var pts := b.tiles.intensity(h, colour(b, u))
		var heal := HEAL_PCT * pts * float(BWPhases.rule(b, "heal_mult", u, 1.0)) * m / 100.0
		s += heal * (0.3 + 2.0 * hurt)
		if hurt > 0.6:
			s -= BWAI.danger(b, u, h) * 0.02 * m
	# keep the beam up across the squad: worth a little on its own, more for
	# every foe standing by the line; half as much from a hex with no blow
	var p := other(b, u)
	if p != null and p.alive() and BWHex.distance(h, p.pos) > BEAM_GAP:
		var beam := 0.02 * m
		for f in b.foes_of(u):
			for x in BWHex.line(h, p.pos):
				if BWHex.distance(x, f.pos) <= 1:
					beam += 0.03 * m
					break
		s += beam if striking else beam * 0.5
	return s
