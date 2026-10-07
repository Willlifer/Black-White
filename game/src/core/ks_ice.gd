class_name BWKsIce
extends RefCounted
## D294 ice's keystones (design/ELEMENTS-v3.md §2 "Keystones", ELEMENTS.md
## §16.2). Pure rules; the battle calls the hooks marked "D294".
##
## Skater         never slides unless it chooses to: a push or pull onto ice
##                stops on the ice (BWSlides.slides is false for it), and a
##                walk crosses ice like ground, so "where to stop on the slide
##                line" is simply where the walk ends. Its first FREE_ICE ice
##                hexes entered each turn cost 0 move (then the normal 1).
##                Skate (the perk) is the cheap version: it already never
##                slides; with both, Skater's free hexes come first, then
##                Skate's cost (1).
## Flash Freeze   an action keystone (skill def flash_freeze), once a battle,
##                range 3, a foe: FROZEN (a status that keeps until thawed):
##                  * it skips its next turn (a boss doesn't, Claude: the
##                    Twins, the Giant, the Colossus);
##                  * it can't be displaced (only a slide could move it, and
##                    a slide needs a push first, so in practice it holds);
##                  * it counts as standing on glaze for Shatter (+15%);
##                  * its next hit taken is x2, and that hit thaws it;
##                  * unhit, it thaws at the first tick after its skipped
##                    turn (Claude: the window is the rest of that cycle).
## Glacier Wall   your pillars last all battle (still PILLAR_MAX) until melted
##                or shattered. Shatter your own pillar: the menu's Break Pillar
##                row (a basic aimed at it: the pillar has no HP to hit) or any
##                of your skills whose shape covers it. SHATTER_PCT ice to all
##                six neighbours, both teams, and a push of 1 away (onto ice
##                they slide). The hex is left bare.

const SKATER := "skater"
const FREEZE := "flash_freeze"
const GLACIER := "glacier_wall"
const SHATTER_KEY := "glacier_shatter"
const FREE_ICE := 4
const FREEZE_RANGE := 3
const FREEZE_MULT := 2.0
const SHATTER_PCT := 12.0
const GLACIER_TICKS := 999        # "all battle": the view shows ∞


static func has(u: BWUnit, id: String) -> bool:
	return u != null and BWKeystones.has(u, id)


static func is_boss(u: BWUnit) -> bool:
	return u != null and (maxi(u.size, 1) > 1 or str(u.encounter) in ["twin", "colossus"])


# ---------------------------------------------------------------- Skater

## Does `u` slide? (BWSlides.slides asks.)
static func never_slides(u: BWUnit) -> bool:
	return has(u, SKATER)


## Ice hexes still free for `u` this turn.
static func free_left(b: BWBattle, u: BWUnit) -> int:
	if not has(u, SKATER):
		return 0
	if int(u.fx.get("skater_turn", -1)) != b._turn_serial:
		return FREE_ICE
	return maxi(0, FREE_ICE - int(u.fx.get("skater_used", 0)))


static func is_ice(b: BWBattle, h: Vector2i) -> bool:
	return b.tiles.is_glazed(h) and not b.tiles.is_pillar(h)


## BWBattle._move_rules: the walk search learns the free ice hexes.
static func move_rules(b: BWBattle, u: BWUnit, r: Dictionary) -> void:
	var n := free_left(b, u)
	if n > 0:
		r["skater"] = n


## BWBattle._reach_fx: a step onto ice while free hexes are left costs only
## its climb. The count rides the state key's bits 3+ (value 8 per hex).
## Returns [cost, state] (unchanged when it doesn't apply).
static func step(b: BWBattle, rules: Dictionary, h: Vector2i, n: Vector2i, sc: int, state: int) -> Array:
	if not rules.has("skater") or not is_ice(b, n):
		return [sc, state]
	var used := state >> 3
	if used >= int(rules.skater):
		return [sc, state]
	return [maxi(b.board.elevation(n) - b.board.elevation(h), 0), state + 8]


## After a walk: spend the free ice hexes it crossed.
static func after_walk(b: BWBattle, u: BWUnit, path: Array) -> void:
	if not has(u, SKATER):
		return
	var left := free_left(b, u)
	var used := 0
	for i in range(1, path.size()):
		if used < left and is_ice(b, path[i]):
			used += 1
	if int(u.fx.get("skater_turn", -1)) != b._turn_serial:
		u.fx["skater_turn"] = b._turn_serial
		u.fx["skater_used"] = 0
	u.fx["skater_used"] = int(u.fx.get("skater_used", 0)) + used


# ---------------------------------------------------------------- Frozen

static func frozen(u: BWUnit) -> bool:
	return u != null and u.statuses.has("frozen")


## Freeze `v` (Flash Freeze by `by`).
static func freeze(b: BWBattle, v: BWUnit, by: BWUnit) -> bool:
	if v == null or not v.alive() or BWObelisk.is_objective(v) or frozen(v):
		return false
	var boss := is_boss(v)
	v.statuses["frozen"] = { "armed": false, "keep": true, "source": by.id if by != null else "",
		"served": false, "boss": boss }
	b._emit({ "type": "status", "unit": v.id, "status": "frozen", "label": BWSkills.STATUS.frozen[0],
		"rule": BWSkills.STATUS.frozen[1], "by": by.id if by != null else "" })
	b._emit({ "type": "frozen", "unit": v.id, "hex": v.pos, "by": by.id if by != null else "", "boss": boss })
	return true


static func thaw(b: BWBattle, v: BWUnit, why: String) -> void:
	if not frozen(v):
		return
	v.statuses.erase("frozen")
	b._emit({ "type": "thaw", "unit": v.id, "hex": v.pos, "why": why })
	b._emit({ "type": "status_end", "unit": v.id, "status": "frozen" })


## BWBattle._begin_turn (after the ground): true = this turn is skipped.
static func turn_start(b: BWBattle, u: BWUnit) -> bool:
	if not frozen(u) or not u.alive():
		return false
	var st: Dictionary = u.statuses.frozen
	if bool(st.served):
		return false
	st.served = true
	if bool(st.boss):
		b._emit({ "type": "frozen_hold", "unit": u.id, "text": "a boss shrugs off the skip; still takes x2" })
		return false
	b._emit({ "type": "frozen_skip", "unit": u.id, "hex": u.pos })
	return true


## The tick: a frozen unit whose skipped turn has passed thaws.
static func tick(b: BWBattle) -> void:
	for u in b.units:
		if frozen(u) and bool(u.statuses.frozen.served):
			thaw(b, u, "tick")


## BWBattle._mods: Frozen counts as glazed for Shatter, and its next hit is x2.
static func blow_mods(b: BWBattle, att: BWUnit, dfn: BWUnit, mods: Array) -> void:
	if not frozen(dfn):
		return
	if not b.tiles.is_glazed(dfn.pos) and not BWEffects.has(dfn, "rime_armour"):
		mods.append({ "stage": "dmg", "value": 1.0 + BWTiles.SHATTER_HIT_PCT / 100.0,
			"label": "Shatter (Frozen): +%d%%" % BWTiles.SHATTER_HIT_PCT, "tag": "Shatter" })
	mods.append({ "stage": "dmg", "value": FREEZE_MULT, "label": "Frozen: x2, and the hit thaws it", "tag": "Frozen x2" })


## BWBattle._after_blow: a landed hit thaws a frozen unit.
static func after_blow(b: BWBattle, v: BWUnit, res: Dictionary) -> void:
	if frozen(v) and bool(res.get("hit", false)) and int(res.get("damage", 0)) > 0:
		thaw(b, v, "hit")


# ---------------------------------------------------------------- Flash Freeze (the action)

static func freeze_used(u: BWUnit) -> bool:
	return bool(u.fx.get("flash_freeze_used", false))


## BWWind.keystone_actions: is this action keystone open now?
static func action_open(u: BWUnit, id: String) -> bool:
	if id == FREEZE:
		return not freeze_used(u)
	return true


## The AI: the foe that would hurt most (its best basic on anyone of `u`'s
## side, or its weapon's power), not a boss unless nothing else.
static func ai_freeze(b: BWBattle, u: BWUnit, row: Dictionary) -> Dictionary:
	var legal := b.skill_targets(u, str(row.key), "")
	var best := {}
	for h in legal:
		var f := b.unit_at(h)
		if f == null or frozen(f):
			continue
		var dmg := 0.0
		for a in b.side(u.team):
			if BWObelisk.is_objective(a):
				continue
			var fc := b.forecast_basic(f, a, 1.0, "", f.pos)
			dmg = maxf(dmg, float(fc.expected.value))
		var score := dmg * (0.6 if is_boss(f) else 1.2) + 4.0
		if best.is_empty() or score > float(best.score):
			best = { "target": h, "element": "", "score": score }
	return best


# ---------------------------------------------------------------- Glacier Wall

## BWBattle.paint, after the tiles changed: a Glacier holder's new pillars
## last all battle; stamp the action that raised them (a shape that raises a
## pillar never shatters it in the same action).
static func after_paint(b: BWBattle, by: BWUnit, r: Dictionary) -> void:
	var pl: Array = (r.get("pools", {}) as Dictionary).get("pillars", [])
	for h in pl:
		var rec: Dictionary = b.tiles.pillars.get(h, {})
		if rec.is_empty():
			continue
		rec["act"] = b._action_serial
		var o := b._unit(str(rec.owner))
		if has(o, GLACIER):
			rec.ticks = GLACIER_TICKS
			rec["glacier"] = true


## `u`'s own pillars (hexes, sorted).
static func own_pillars(b: BWBattle, u: BWUnit) -> Array:
	var out: Array = []
	if u == null:
		return out
	for h in b.tiles.pillars:
		if str(b.tiles.pillars[h].owner) == u.id and b.tiles.is_pillar(h):
			out.append(h)
	out.sort()
	return out


## BWBattle.use_skill, after the ground: a Glacier holder's skill whose shape
## covers one of its own pillars (raised before this action) shatters it.
static func after_skill(b: BWBattle, u: BWUnit, p: Dictionary) -> void:
	if not has(u, GLACIER) or b.over or not u.alive():
		return
	var shape: Array = (p.get("hexes", []) as Array) + (p.get("ring", []) as Array)
	for h in own_pillars(b, u):
		if h in shape and int(b.tiles.pillars[h].get("act", -1)) != b._action_serial:
			shatter(b, u, h)


## Shatter `u`'s pillar at `h`: SHATTER_PCT (ice) to every unit on the six
## neighbours, both teams, then each is pushed 1 away (it slides on ice).
static func shatter(b: BWBattle, u: BWUnit, h: Vector2i) -> Array:
	if not b.tiles.is_pillar(h):
		return []
	b.tiles.pillars.erase(h)
	b.tiles.entries.erase(h)
	var hit: Array = []
	for n in BWHex.neighbors(h):
		var v := b.unit_at(n)
		if v != null and v.alive() and not v in hit and not BWObelisk.is_objective(v):
			hit.append(v)
	b._emit({ "type": "pillar_shatter", "hex": h, "unit": u.id if u != null else "", "units": hit.map(func(x): return x.id),
		"pct": SHATTER_PCT })
	for v in hit:
		if b.over or not v.alive():
			continue
		b._tile_hurt(v, b._tile_dmg(v, SHATTER_PCT, "ice"), "shatter", u.id if u != null else "")
	for v in hit:
		if b.over or not v.alive():
			continue
		var d := BWBattle.pulse_heading(h, v.pos, true)
		if d < 0:
			d = BWHex.direction_index(h, v.pos)
		b._displace(v, d, 1, "push", true)
	return hit


## The AI's Break Pillar: worth it when it hurts foes more than friends.
static func ai_shatter(b: BWBattle, u: BWUnit, row: Dictionary) -> Dictionary:
	var best := {}
	for h in b.skill_targets(u, str(row.key), ""):
		var sc := 0.0
		for n in BWHex.neighbors(h):
			var v := b.unit_at(n)
			if v == null or BWObelisk.is_objective(v):
				continue
			var d := float(b._tile_dmg(v, SHATTER_PCT, "ice"))
			sc += -1.5 * d if v.team == u.team else d + (1000.0 if d >= v.hp else 0.0)
		if sc > 0.0 and (best.is_empty() or sc > float(best.score)):
			best = { "target": h, "element": "", "score": sc }
	return best


## The tile card's line for a Glacier pillar.
static func card_lines(b: BWBattle, h: Vector2i) -> Array:
	var out: Array = []
	if b.tiles.is_pillar(h) and bool(b.tiles.pillars[h].get("glacier", false)):
		out.append("Glacier Wall: this pillar lasts all battle; its owner can shatter it (%d%% to the six around, push 1 away)" % int(SHATTER_PCT))
	var u := b._centre_at(h)
	if u != null and frozen(u):
		out.append("%s is Frozen: %s" % [u.name, BWSkills.STATUS.frozen[1]])
	return out
