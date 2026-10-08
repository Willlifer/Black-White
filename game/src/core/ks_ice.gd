class_name BWKsIce
extends RefCounted
## D294 ice's keystones (design/ELEMENTS-v3.md §2 "Keystones", ELEMENTS.md
## §16.2). Pure rules; the battle calls the hooks marked "D294".
##
## Sure-Footed    (id "skater", kept for saves; D399; D443: an item
##                enchantment now, "Sure-Footed {item}") you and allies within 2
##                ignore Unsteady footing; a foe that walks off your glaze stays
##                Unsteady until the end of its next turn. The rules live in
##                BWUnsteady (sure_cover, after_walk).
## Flash Freeze and Glacier Wall were REMOVED with Keystones v3 (D443). The
## FROZEN status they used stays as dormant rules (nothing applies it now):
## it skips one turn (not a boss), holds against displacement, counts as
## glazed for Shatter, and its next hit is x2, which thaws it.

const SKATER := "skater"
const FREEZE_MULT := 2.0


static func has(u: BWUnit, id: String) -> bool:
	return u != null and BWKeystones.has(u, id)


static func is_boss(u: BWUnit) -> bool:
	return u != null and (maxi(u.size, 1) > 1 or str(u.encounter) in ["twin", "colossus"])


# ---------------------------------------------------------------- Frozen

static func frozen(u: BWUnit) -> bool:
	return u != null and u.statuses.has("frozen")


## Freeze `v` (dormant since D443: nothing calls it in play).
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


## The tile card's line for a Frozen unit.
static func card_lines(b: BWBattle, h: Vector2i) -> Array:
	var out: Array = []
	var u := b._centre_at(h)
	if u != null and frozen(u):
		out.append("%s is Frozen: %s" % [u.name, BWSkills.STATUS.frozen[1]])
	return out
