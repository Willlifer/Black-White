extends BWSkillDef
## Staff spell (ELEMENTS §9). Strip a hex back toward bare stone, then a
## basic follow-up. D87: the caster heals SIPHON_HEAL_PCT% max HP per step
## stripped (each axis up to 2, a marker 1, a glaze 1). Siphon+ (D107):
## PLUS_HEAL_PCT% per step, to an ally standing on the hex if there is one,
## else to the caster.

const PLUS_HEAL_PCT := 6


func _init() -> void:
	define({
		"key": "siphon", "name": "Siphon", "weapon": "staff", "clip": "",
		"desc": "Strip a hex back toward bare stone, healing 4% HP per step stripped, then act again",
		"plus": "Siphon+: heals 6% per step, to an ally on the hex (else you)",
		"targeting": "hex", "needs_element": false, "range": BWSkills.STAFF_RANGE, "cd": BWSkills.DEFAULT_CD,
		"power": 0, "follow_up": ["basic"], "min_range": 0, "los": true, "spell": true,
	}, 220)


## Nothing to strip, nothing to aim at.
func target_ok(b: BWBattle, _u: BWUnit, h: Vector2i, _element: String) -> bool:
	return not b.tiles.at(h).is_empty()


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p.hexes = [target]
	var n := strip_steps(b, target)
	var h := heal_plan(b, u, target)
	if n > 0:                           # D87
		p.notes.append("Siphon heals %s %d%% HP (%d steps stripped)" % ["you" if h[0] == u else h[0].name, h[1] * n, n])


func ground(b: BWBattle, u: BWUnit, _el: String, target_hex: Vector2i, _p: Dictionary) -> int:
	var stripped := strip_steps(b, target_hex)
	b.tiles.siphon(target_hex)
	b._emit({ "type": "paint", "unit": u.id, "element": "", "hexes": [target_hex], "kind": "siphon" })
	return stripped


func after_paint(b: BWBattle, u: BWUnit, _el: String, target_hex: Vector2i, _p: Dictionary,
		_results: Array, stripped: int) -> void:
	if stripped > 0:
		var h := heal_plan(b, u, target_hex)
		b._heal(h[0], h[1] * stripped, "siphon")


## [who heals, % per step]: the caster at SIPHON_HEAL_PCT; Siphon+ an ally
## on the hex (else the caster) at PLUS_HEAL_PCT.
func heal_plan(b: BWBattle, u: BWUnit, hex: Vector2i) -> Array:
	if upgraded(u):
		var a := b._centre_at(hex)
		return [a if a != null and a.team == u.team else u, PLUS_HEAL_PCT]
	return [u, BWSkills.SIPHON_HEAL_PCT]


## What Siphon strips from a hex, in steps.
static func strip_steps(b: BWBattle, hex: Vector2i) -> int:
	var e := b.tiles.at(hex)
	if e.is_empty():
		return 0
	return mini(2, absi(int(e.h))) + mini(2, absi(int(e.v))) + (1 if str(e.marker) != "" else 0) \
		+ (1 if int(e.glaze) > 0 else 0)
