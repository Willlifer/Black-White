extends BWSkillDef
## RETIRED (D440 Overload): never offered; the def stays for old saves, which map it
## (BWSkillRegistry.RENAMED, migrate_unit). Its helpers may still be shared.
## Daggers. Once per battle, from behind only (BWBattle.behind: the back
## three of the foe's six sides): a killing stroke that can't glance, with
## +CRIT crit and a +BACKSTAB_PCT% backstab.

const POWER := 12
const CRIT := 25
const BACKSTAB_PCT := 50
const ONCE_CD := 999


func _init() -> void:
	define({
		"key": "assassinate", "name": "Assassinate", "weapon": "daggers", "clip": "",
		"desc": "Once per battle, from behind an adjacent enemy only: can't glance, +25 crit, backstab +50%",
		"targeting": "adjacent_unit", "needs_element": true, "range": 1, "cd": 0, "once_per_battle": true,
		"power": POWER,
		"retired": true,
	}, 355)


## Only from behind.
func target_ok(b: BWBattle, u: BWUnit, h: Vector2i, _element: String) -> bool:
	var v := b.unit_at(h)
	return v != null and b.behind(v, u.pos)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p.hexes = [target]
	p.victims = b._foes_on(u, [target])


func forecast_mods(_b: BWBattle, _u: BWUnit, _el: String, _v: BWUnit, _p: Dictionary, _strike: int,
		mods: Array, _notes: Array) -> void:
	mods.append({ "stage": "glance_x", "value": 0.0, "label": "Assassinate: can't glance" })
	mods.append({ "stage": "crit", "value": float(CRIT), "label": "Assassinate: +%d crit" % CRIT })
	mods.append({ "stage": "dmg", "value": 1.0 + BACKSTAB_PCT / 100.0,
		"label": "Backstab (from behind): +%d%%" % BACKSTAB_PCT, "tag": "Backstab" })


## Once per battle: every element of it goes dark for the rest of the fight.
func cooldown(u: BWUnit) -> int:
	for el in [""] + BWFormulas.ELEMENTS:
		u.cooldowns[BWSkills.cd_key(id, el)] = ONCE_CD
	return ONCE_CD
