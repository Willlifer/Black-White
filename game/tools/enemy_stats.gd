extends SceneTree
## Prints the enemy squads for fights 1, 5 and 9 of a fixed run (D99 enemy
## scaling report). `godot --headless --path . --script res://tools/enemy_stats.gd`


func _init() -> void:
	var run := BWRun.start(["aureli", "della", "jericho", "will", "gail", "kira"], 1234)
	for n in [1, 5, 9]:
		var es := run.enemies_for(n)
		var lines: PackedStringArray = []
		for u in es:
			var items: Array = []
			for slot in u.equipment:
				items.append("%s %s" % [slot, u.equipment[slot].tier])
			lines.append("  %s L%d hp %d str %d dex %d wil %d def %d res %d spd %d | %s | exp %s | perks %s | skills %s" % [
				u.name, u.level, u.max_hp(), u.stat("str"), u.stat("dex"), u.stat("wil"), u.stat("def"), u.stat("res"),
				u.stat("spd"), ", ".join(items), u.expertise_letter(u.weapon_class), u.perks,
				u.skill_ranks.keys() + u.known_skills])
		print("fight %d (tier %s):" % [n, es[0].equipment.main_hand.tier])
		print("\n".join(lines))
	quit()
