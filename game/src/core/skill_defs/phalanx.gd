extends BWSkillDef
## Lance (D105). Brace the line: you and every adjacent ally take GUARD_PCT%
## less damage until your/their next turn starts (the FX `guard`, BWUnit.fx;
## the strongest guard holds, they don't stack), and you can't be displaced
## until your next turn (a temporary `immune displace` record on your
## effects, dropped when your turn comes round).

const CD := 4
const GUARD_PCT := 15


func _init() -> void:
	define({
		"key": "phalanx", "name": "Phalanx", "weapon": "lance", "clip": "block",
		"desc": "Brace: you and adjacent allies take 15% less damage until your next turn, and you can't be displaced",
		"targeting": "self", "needs_element": false, "range": 0, "cd": CD,
		"power": 0,
	}, 324)


func plan(b: BWBattle, u: BWUnit, _element: String, _target: Vector2i, p: Dictionary) -> void:
	var who: Array = covered(b, u).map(func(a): return a.name)
	p.notes.append("Phalanx: -%d%% damage taken for %s; you can't be displaced" % [GUARD_PCT, ", ".join(who)])


func covered(b: BWBattle, u: BWUnit) -> Array:
	return b.side(u.team).filter(func(a): return a == u or b.gap(u, a) <= 1)


func ground(b: BWBattle, u: BWUnit, _el: String, _target_hex: Vector2i, _p: Dictionary) -> int:
	for a in covered(b, u):
		guard(b, a, GUARD_PCT, "Phalanx")
	if not u.effects.any(func(e): return e.source == id):
		u.effects.append({ "key": "immune", "params": { "what": "displace" }, "source": id,
			"element": "", "kind": "skill", "rank": 1, "name": "Phalanx" })
	var cb := Callable(self, "_drop").bind(u)
	if not b.event.is_connected(cb):
		b.event.connect(cb)
	return 0


func _drop(e: Dictionary, u: BWUnit) -> void:
	if e.type == "turn" and str(e.get("unit", "")) == u.id:
		u.effects = u.effects.filter(func(r): return r.source != id)


## Raise `a`'s FX guard (damage taken -pct% until its next turn starts). The
## battle reads guards only while some unit carries effects, so the guarded
## unit joins that list.
static func guard(b: BWBattle, a: BWUnit, pct: int, label: String) -> void:
	if float(a.fx.get("guard", 0)) <= pct:
		a.fx["guard"] = float(pct)
		a.fx["guard_name"] = "%s: -%d%%" % [label, pct]
	if not a in b._fx_units:
		b._fx_units.append(a)
	b._emit({ "type": "guard", "unit": a.id, "pct": a.fx.guard, "name": label })


## D112: brace with an ally beside you and a foe within 3; worth a little per
## unit covered (an attack in hand usually wins).
func ai_support(b: BWBattle, u: BWUnit, _row: Dictionary) -> Dictionary:
	var cov := covered(b, u)
	if cov.size() < 2 or not b.foes_of(u).any(func(f): return b.gap(u, f) <= 3):
		return {}
	return { "target": u.pos, "element": "", "score": 3.0 * cov.size() }
