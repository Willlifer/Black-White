extends BWSkillDef
## Fists (D76). FLURRY_HITS jabs at an adjacent foe, each FLURRY_PCT% of the
## power and rolled on its own; the last lays the element on its hex. D87:
## the last strike has +FLURRY_FINISH_CRIT crit. Pummeling (multi_hit
## skill=flurry) raises the count, and so does Brace (+1, once). Flurry+:
## the last strike has +PLUS_FINISH_CRIT crit instead.

const PLUS_FINISH_CRIT := 30


func _init() -> void:
	define({
		"key": "flurry", "name": "Flurry", "weapon": "fists", "clip": "flurry",
		"desc": "Three quick jabs at an adjacent enemy; the last has +15 crit chance and lays your element on its hex",
		"plus": "Flurry+: the last strike gets +30 crit",
		"targeting": "adjacent_unit", "needs_element": true, "range": 1, "cd": BWSkills.DEFAULT_CD,
		"power": BWSkills.FLURRY_DMG, "hits": BWSkills.FLURRY_HITS, "hit_pct": BWSkills.FLURRY_PCT,
	}, 160)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p.hexes = [target]                 # the last jab lays the element on the target's hex
	p.victims = b._foes_on(u, [target])
	p["hits"] = hits(u)


func forecast_mods(_b: BWBattle, u: BWUnit, _el: String, _v: BWUnit, p: Dictionary, strike: int,
		mods: Array, notes: Array) -> void:
	var n := int(p.get("hits", 1))
	var crit := BWSkills.FLURRY_FINISH_CRIT
	var label := "Flurry finisher"
	if upgraded(u):
		crit = PLUS_FINISH_CRIT
		label = "Flurry+ finisher"
	if strike == n - 1:
		mods.append({ "stage": "crit", "value": float(crit), "label": label })
	elif strike == 0:
		notes.append("Last strike: +%d crit chance" % crit)
	if strike == 0 and u.fx.get("brace_flurry", false):
		notes.append("Braced: +1 strike")


## The strike count: the row's, or a multi_hit skill=flurry row's `count`
## if higher (Pummeling: 4), +1 after a Brace.
func hits(u: BWUnit) -> int:
	var n := int(data.get("hits", 3))
	for e in BWEffects.list(u, "multi_hit"):
		if str(BWEffects.p(e, "skill", "")) == "flurry":
			n = maxi(n, int(BWEffects.p(e, "count", n)))
	if u.fx.get("brace_flurry", false):
		n += 1
	return n


## Brace's extra strike is spent by this Flurry.
func ground(b: BWBattle, u: BWUnit, el: String, target_hex: Vector2i, p: Dictionary) -> int:
	u.fx.erase("brace_flurry")
	return super.ground(b, u, el, target_hex, p)
