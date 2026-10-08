class_name BWKit2
## Weapon kit pass 2 (D425-D432, design/SKILLS.md): the battle-side halves
## of the sword / lance / dagger changes that aren't one skill's own hook.
## Rules only, no nodes; BWBattle calls in at three points (turn start, the
## end of a skill, a hurt landing) and the defs call the rest.
##
##   Riposte release (D425)  a guard still unanswered when its holder's next
##                           turn starts lets go: six 3-hex lines of its
##                           element round the duelist (rock stops a line),
##                           painted like Ley Line. riposte.gd draws it.
##   Lance Charge (D428)     a line set last turn runs at this turn's start,
##                           before the unit acts (lance_charge.gd `run`).
##   Blade Dance (D427)      a sword passive (BWWeaponMove.PASSIVES): after a
##                           sword skill lands, one free step of up to 2 hexes, chosen
##                           (or skipped) before anything else.
##   Barrier (D429b)         Consume's shield: absorbs up to `hp` damage of
##                           any kind until the holder's next turn.
##   Reaction shield (D430)  Fan of Knives: while its own paint resolves, the
##                           reactions it sets off (detonations, shocks,
##                           overheats, overfreezes, arcs) can't hurt the user.

const BLADE_DANCE := "blade_dance"
const DANCE := "dance"                  # u.fx: a Blade Dance step is owed
const BARRIER := "barrier"              # u.fx: { hp, by }
const SHIELD := "reaction_shield"       # u.fx: true while Fan of Knives paints


# ---------------------------------------------------------------- turn start

## BWBattle._begin_turn, right after the "turn" event: the barrier and an
## unclaimed dance end; an unanswered guard releases (`release` = the guard
## that just dropped, {} when none or it answered); a set Lance Charge runs.
static func turn_start(b: BWBattle, u: BWUnit, release: Dictionary) -> void:
	u.fx.erase(DANCE)
	if u.fx.has(BARRIER):
		u.fx.erase(BARRIER)
		b._emit({ "type": "barrier_end", "unit": u.id })
	if not release.is_empty() and u.alive() and not b.over:
		var rd := BWSkillRegistry.get_def("riposte")
		if rd != null and rd.has_method("release"):
			rd.call("release", b, u, str(release.get("element", "")))
	if u.alive() and not b.over and u.fx.has("lance_charge"):
		var ld := BWSkillRegistry.get_def("lance_charge")
		if ld != null and ld.has_method("run"):
			ld.call("run", b, u)
		else:
			u.fx.erase("lance_charge")


# ---------------------------------------------------------------- Blade Dance (D427)

## BWBattle.use_skill's end: a sword skill that landed (some blow hit) and
## granted no follow-up owes its Blade Dance holder one free step.
static func after_skill(b: BWBattle, u: BWUnit, s: Dictionary, results: Array) -> void:
	if b.over or not u.alive() or str(s.get("weapon", "")) != "sword" or not u.follow_up.is_empty():
		return
	if not BWWeaponMove.has_passive(u, BLADE_DANCE):
		return
	if not results.any(func(r): return bool((r.get("result", {}) as Dictionary).get("hit", false))):
		return
	var hexes := dance_hexes(b, u)
	if hexes.is_empty():
		return
	u.fx[DANCE] = true
	b._emit({ "type": "blade_dance", "unit": u.id, "hexes": hexes })


static func dance_pending(b: BWBattle, u: BWUnit) -> bool:
	return u != null and u == b.current() and u.alive() and not b.over and u.fx.get(DANCE, false)


## D427 (author, 2026-10-08: "these aren't that impactful strangely
## enough"): the step is up to DANCE_REACH hexes. The hexes a dance may end
## on, each with its path: walkable steps within the unit's jump, never
## through or onto a unit. { hex: [path from the unit's hex] }.
const DANCE_REACH := 2


static func dance_paths(b: BWBattle, u: BWUnit) -> Dictionary:
	var out := {}
	var opts := { "jump": BWWeaponMove.jump(u) }
	var frontier: Array = [[u.pos]]
	for _r in DANCE_REACH:
		var nxt: Array = []
		for path in frontier:
			var at: Vector2i = path[-1]
			for n in b.board.neighbors(at):
				if n == u.pos or out.has(n):
					continue
				if b.board.step_cost(at, n, opts) < 0 or not b.can_stand(u, n):
					continue
				var p2: Array = path + [n]
				out[n] = p2
				nxt.append(p2)
		frontier = nxt
	return out


static func dance_hexes(b: BWBattle, u: BWUnit) -> Array:
	var keys := dance_paths(b, u).keys()
	keys.sort()
	return keys


## Take the step: no move spent, nothing undone later. Fire on the way burns
## (it's a walk), and the lay-ons, zones and Static Field apply.
static func dance_step(b: BWBattle, u: BWUnit, h: Vector2i) -> bool:
	if not dance_pending(b, u):
		return false
	var paths := dance_paths(b, u)
	if not paths.has(h):
		return false
	var path: Array = paths[h]
	u.fx.erase(DANCE)
	u.pos = h
	u.facing = BWHex.direction_index(path[-2], h)
	u.fx["moved_hexes"] = int(u.fx.get("moved_hexes", 0)) + path.size() - 1
	b._undo = {}                                    # the dance is final
	b._emit({ "type": "move", "unit": u.id, "path": path, "kind": "dance" })
	for i in range(1, path.size()):
		var pct := b.tiles.crossing_pct(path[i])
		if pct > 0 and u.alive() and not BWEffects.has(u, "heat_rush"):
			b._tile_hurt(u, b._tile_dmg(u, pct, "fire"), "fire_cross", str(b.tiles.at(path[i]).get("source", "")))
	b._lay_on_move(u, path)
	if u.alive() and not b.over:
		b._static_field_check(u)
		b._zone_check(u)
	b._check_end()
	return true


static func dance_skip(b: BWBattle, u: BWUnit) -> void:
	if dance_pending(b, u):
		u.fx.erase(DANCE)
		b._emit({ "type": "blade_dance_skip", "unit": u.id })


## The AI's step: the neighbour with the least danger (BWAI.danger), unless
## staying is as safe; a likely finishing hit still in reach from the new hex
## is never given up for it.
static func ai_dance(b: BWBattle, u: BWUnit) -> void:
	if not dance_pending(b, u):
		return
	var best := u.pos
	var best_d := BWAI.danger(b, u, u.pos)
	for h in dance_hexes(b, u):
		var d := BWAI.danger(b, u, h)
		if d < best_d - 0.01:
			best_d = d
			best = h
	if best == u.pos:
		dance_skip(b, u)
	else:
		dance_step(b, u, best)


# ---------------------------------------------------------------- barrier (D429b)

static func set_barrier(b: BWBattle, u: BWUnit, hp: int, by: String) -> void:
	if hp <= 0 or not u.alive():
		return
	var cur := int((u.fx.get(BARRIER, {}) as Dictionary).get("hp", 0))
	u.fx[BARRIER] = { "hp": maxi(cur, hp), "by": by }
	b._emit({ "type": "barrier", "unit": u.id, "hp": maxi(cur, hp) })


static func barrier_hp(u: BWUnit) -> int:
	return int((u.fx.get(BARRIER, {}) as Dictionary).get("hp", 0)) if u != null else 0


## Damage about to land on `u` (a blow or a ground hurt): the barrier soaks
## what it can and stays up with the rest; it breaks at 0.
static func barrier_absorb(b: BWBattle, u: BWUnit, dmg: int) -> int:
	var left := barrier_hp(u)
	if dmg <= 0 or left <= 0:
		return dmg
	var took := mini(dmg, left)
	left -= took
	if left <= 0:
		u.fx.erase(BARRIER)
	else:
		u.fx[BARRIER].hp = left
	b._emit({ "type": "barrier_hit", "unit": u.id, "absorbed": took, "left": left })
	return dmg - took


# ---------------------------------------------------------------- reaction shield (D430)

## A hurt from a reaction is about to land on `u`: true (and an `immune`
## event) while u's own Fan of Knives paint is resolving.
static func shielded(b: BWBattle, u: BWUnit) -> bool:
	if u == null or not u.fx.get(SHIELD, false):
		return false
	b._emit({ "type": "immune", "unit": u.id, "class": "its own Fan of Knives" })
	return true


# ---------------------------------------------------------------- Lance Charge (D428)

## Every pending charge line of `u`'s foes: { holder id: [hexes] }.
static func charge_lines(b: BWBattle, team: String = "") -> Dictionary:
	var out := {}
	for o in b.units:
		if o.alive() and (team == "" or o.team != team) and o.fx.has("lance_charge"):
			out[o.id] = (o.fx.lance_charge.get("line", []) as Array).duplicate()
	return out


## BWAI._best_hex: how much worse `h` is for `u` because a foe's set charge
## runs over it (the charge's power; 0 when none). The AI steps off it.
static func ai_avoid(b: BWBattle, u: BWUnit, h: Vector2i) -> float:
	for o in b.units:
		if o.team == u.team or not o.alive() or not o.fx.has("lance_charge"):
			continue
		if h in (o.fx.lance_charge.get("line", []) as Array):
			return 10.0
	return 0.0
