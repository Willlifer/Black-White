extends BWSkillDef
## RETIRED (D439 Tapestry): never offered; the def stays for old saves, which map it
## (BWSkillRegistry.RENAMED, migrate_unit). Its helpers may still be shared.
## Sword (D103). Once per battle: a held, heavy cut at an adjacent foe for
## POWER x MULT. A KO with it is a triumph: +STR_PCT% STR (battle_mods) for
## the rest of the battle. "Once" = every element's cooldown set to ONCE_CD.

const POWER := 12
const MULT := 1.5
const STR_PCT := 25
const ONCE_CD := 999


func _init() -> void:
	define({
		"key": "triumph", "name": "Triumph", "weapon": "sword", "clip": "",
		"desc": "Once per battle: a held, heavy cut at an adjacent enemy for x1.5. If it knocks the foe out, +25% STR for the rest of the battle",
		"targeting": "adjacent_unit", "needs_element": true, "range": 1, "cd": 0, "once_per_battle": true,
		"power": POWER,
		"retired": true,
	}, 302)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p.hexes = [target]
	p.victims = b._foes_on(u, [target])
	p.notes.append("A KO: +%d%% STR for the rest of the battle (+%d)" % [STR_PCT, bonus(u)])


func forecast_mods(_b: BWBattle, _u: BWUnit, _el: String, _v: BWUnit, _p: Dictionary, _strike: int,
		mods: Array, _notes: Array) -> void:
	mods.append({ "stage": "dmg", "value": MULT, "label": "Triumph: x%.1f" % MULT })


func after_hits(b: BWBattle, u: BWUnit, _p: Dictionary, results: Array) -> void:
	if results.is_empty() or not results[0].ko or not u.alive():
		return
	var amt := bonus(u)
	u.battle_mods["str"] = int(u.battle_mods.get("str", 0)) + amt
	b._emit({ "type": "stat_up", "unit": u.id, "stats": ["str"], "amount": amt, "source": id, "name": "Triumph" })


## The STR a triumph grants: STR_PCT% of the current STR, at least 1.
func bonus(u: BWUnit) -> int:
	return maxi(1, roundi(u.stat("str") * STR_PCT / 100.0))


## Once per battle: every element of it goes dark.
func cooldown(u: BWUnit) -> int:
	for el in [""] + BWFormulas.ELEMENTS:
		u.cooldowns[BWSkills.cd_key(id, el)] = ONCE_CD
	return ONCE_CD
