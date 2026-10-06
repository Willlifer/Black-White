class_name BWForecastSheet
## A printable balance sheet: every roster character's basic attack against
## a few reference defenders, at level 1 and with grown stats. Run with
## `godot --headless --path game -- --forecast`. This is the Gate 0 page.


static func render() -> String:
	var out: PackedStringArray = []
	var roster := BWData.table("roster")
	if roster.is_empty():
		return "no roster.csv"
	var defenders := {
		"avg L1 (all 4)": _flat("avg", 4),
		"tank L1 (con6 def6)": _make({ "con": 6, "def": 6, "res": 3, "dex": 2 }),
		"grown (all 30)": _flat("g30", 30),
		"boss (all 50, 500hp)": _flat("boss", 50),
	}
	out.append("BASIC ATTACK FORECAST — hit% / crit% / glance% / dmg per clean hit / hits to KO")
	out.append("defender HP: " + ", ".join(defenders.keys().map(func(k): return "%s=%d" % [k, _hp(defenders[k], k)])))
	out.append("")
	var head := "%-12s %-8s %-8s" % ["attacker", "weapon", "element"]
	for k in defenders:
		head += " | %-26s" % k
	out.append(head)
	out.append("-".repeat(head.length()))
	for row in roster:
		var a := BWUnit.from_roster(row)
		var line := "%-12s %-8s %-8s" % [a.name, a.weapon_class, a.element]
		for k in defenders:
			var d: BWUnit = defenders[k]
			var fc := _fc(a, d)
			var dmg: float = fc.damage.value
			var hp := _hp(d, k)
			line += " | %3.0f/%4.1f/%3.0f %3.0fdmg %3dhits" % [fc.hit.value, fc.crit.value, fc.glance.value, dmg, ceili(hp / maxf(dmg, 1.0))]
		out.append(line)
	out.append("")
	out.append("One worked example (first roster row vs avg L1), every number explained:")
	var a0 := BWUnit.from_roster(roster[0])
	var fc0 := _fc(a0, defenders["avg L1 (all 4)"])
	for k in ["hit", "avoid", "glance", "crit", "damage", "resist", "expected"]:
		if fc0.has(k):
			out.append("  %-16s %7.2f   = %s   [%s]" % [fc0[k].label, fc0[k].value, fc0[k].formula, fc0[k].values])
	return "\n".join(out)


static func _fc(a: BWUnit, d: BWUnit) -> Dictionary:
	var w := a.weapon()
	var p := int(w.get("base_dmg", 10))
	if str(w.get("damage_type", "")) == "spell":
		return BWFormulas.forecast(a, d, BWFormulas.SPELL, p, a.element)
	return BWFormulas.forecast(a, d, BWFormulas.WEAPON, p)


static func _hp(d: BWUnit, k: String) -> int:
	return 500 if k.begins_with("boss") else d.max_hp()


static func _flat(id: String, v: int) -> BWUnit:
	var row := { "id": id, "weapon_class": "sword" }
	for s in BWUnit.STATS:
		row[s] = v
	return BWUnit.from_roster(row)


static func _make(stats: Dictionary) -> BWUnit:
	var row := { "id": "tank", "weapon_class": "axe" }
	for s in BWUnit.STATS:
		row[s] = stats.get(s, 4)
	return BWUnit.from_roster(row)
