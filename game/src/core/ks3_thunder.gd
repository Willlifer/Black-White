class_name BWKs3Thunder
extends RefCounted
## D452-D453 thunder's keystones (Keystones v3, design/ELEMENTS.md).
##
## Superconductor  your explosions and reactions reach radius 2: a detonation
##                 you set off (or credited to you) splashes 2 rings (the
##                 normal half), an Overheat ring / Overfreeze burst / pool
##                 reaction of yours reaches 2, a Pitch Black or Solar Flare
##                 too. If an action of yours sets off a reaction ON YOUR OWN
##                 HEX, nothing from that action's reactions can hurt you
##                 (mark_own_hex, then shielded() in BWKs3.filter_hurt). Also
##                 grants SELF-DETONATE (D306, kept provisionally: D452; the
##                 def self_detonate, BWThunderKeys): free, once per turn.
## Overflow        (id thunder_overflow; the old light Overflow is the Ward of
##                 Light enchantment now) every explosion or reaction you set
##                 off heals you HEAL_PCT of your max HP, at most CAP_PCT an
##                 action; healing past your max becomes a SHIELD up to
##                 SHIELD_PCT of your max HP that lasts until hit (the Ward of
##                 Light's shield, BWBeams.ward_absorb, under its own name).

const SUPER := "superconductor"
const OVERFLOW := "thunder_overflow"


static func ks(u: BWUnit, id: String) -> bool:
	return BWKs3.ks(u, id)


## Right after BWTiles.apply (before any damage): a Superconductor whose paint
## set off a reaction on its own hex is immune to this action's reactions.
static func mark_own_hex(b: BWBattle, by: BWUnit, r: Dictionary) -> void:
	if by == null or not ks(by, SUPER):
		return
	var mine := by.footprint()
	var hexes: Array = []
	for d in r.get("detonations", []):
		hexes.append(d.hex)
	for o in r.get("overheat", []):
		hexes.append(o.hex)
	for o in r.get("overfreeze", []):
		hexes.append(o.hex)
	hexes.append_array((r.get("pools", {}) as Dictionary).get("shock", []))
	for h in hexes:
		if h in mine:
			if int(by.fx.get("sc_act", -1)) != b._action_serial:
				by.fx["sc_act"] = b._action_serial
				b._emit({ "type": "superconductor", "unit": by.id, "hex": by.pos })
			return


## Is `u` immune to this action's reactions (Superconductor)?
static func shielded(b: BWBattle, u: BWUnit) -> bool:
	return int(u.fx.get("sc_act", -1)) == b._action_serial and ks(u, SUPER)


## `n` reactions `u` just set off: Overflow heals it (capped per action) and
## the overheal becomes a shield.
static func overflow(b: BWBattle, u: BWUnit, n: int) -> void:
	if n <= 0 or u == null or not u.alive() or b.over or not ks(u, OVERFLOW):
		return
	if int(u.fx.get("of_act", -1)) != b._action_serial:
		u.fx["of_act"] = b._action_serial
		u.fx["of_used"] = 0.0
	var cap := BWKeystones.param(OVERFLOW, "cap_pct", 20)
	var pct := minf(BWKeystones.param(OVERFLOW, "heal_pct", 5) * n, cap - float(u.fx.of_used))
	if pct <= 0.0:
		return
	u.fx["of_used"] = float(u.fx.of_used) + pct
	var room := u.max_hp() - u.hp
	var fade := BWFormulas.fatigue_heal_mult(b.cycle)   # D474: the overheal shield wanes with the heal
	var amt := maxi(1, roundi(u.max_hp() * pct * fade / 100.0)) if fade > 0.0 else 0
	b._emit({ "type": "overflow", "unit": u.id, "pct": pct, "n": n })
	b._heal(u, pct, "overflow")
	var excess := amt - room
	if excess <= 0 or not u.alive() or BWKs3Dark.hopekiller_on(b, u) != null:
		return
	var shield_cap := roundi(u.max_hp() * BWKeystones.param(OVERFLOW, "shield_pct", 30) / 100.0)
	var cur := int((u.fx.get("light_ward", {}) as Dictionary).get("hp", 0))
	var hp := mini(shield_cap, cur + excess)
	if hp <= cur:
		return
	u.fx["light_ward"] = { "hp": hp, "until": b.cycle + 9999, "by": u.id, "name": "Overflow" }
	b._emit({ "type": "light_ward", "unit": u.id, "hp": hp, "by": u.id, "name": "Overflow" })


static func card_lines(b: BWBattle, h: Vector2i) -> Array:
	var out: Array = []
	var u := b._centre_at(h)
	if u == null or not u.alive():
		return out
	if ks(u, SUPER):
		out.append("%s (Superconductor): its blasts and reactions reach radius 2; one set off on its own hex can't hurt it" % u.name)
	if ks(u, OVERFLOW):
		var w: Dictionary = u.fx.get("light_ward", {})
		out.append("%s (Overflow): each reaction it sets off heals it 5%% (20%% an action); overheal shields up to 30%%%s" % [
			u.name, "" if w.is_empty() else ", shield %d now" % int(w.hp)])
	return out
