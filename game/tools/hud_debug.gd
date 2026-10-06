extends SceneTree
func _init() -> void:
	var roster := BWData.table("roster")
	var p: Array = []
	var e: Array = []
	for i in 3:
		p.append(BWUnit.from_roster(roster[i]))
		e.append(BWUnit.from_roster(roster[i + 10]))
	for u in p:
		u.stats["spd"] = 20
	var s := BWCombatScreen.new()
	s.configure("res://maps/arena.json", p, e, [], 3)
	root.add_child(s)
	for k in 180:
		await process_frame
	print("order children: ", s.ui._order.get_child_count(), " current: ", s.battle.current().name)
	print("acting text: [", s.ui._acting.text.text.left(80), "]")
	print("acting panel size: ", s.ui._acting.panel.size, " text size ", s.ui._acting.text.size)
	quit()
