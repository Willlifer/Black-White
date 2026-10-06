extends SceneTree
## Renders the movement radius (with a hovered path) and a skill's attack
## radius + splash for review: design/art/ranges_*.png.
func _init() -> void:
	var roster := BWData.table("roster")
	var p: Array = []
	var e: Array = []
	for id in ["will", "aureli", "jericho"]:
		p.append(BWRosterKits.unit(id))
	for i in 3:
		e.append(BWUnit.from_roster(roster[i + 10]))
	for u in p:
		u.stats["spd"] = 20
	var s := BWCombatScreen.new()
	s.configure("res://maps/arena.json", p, e, [], 3)
	root.add_child(s)
	for k in 90:
		await process_frame
	var u := s.battle.current()
	var r := s.battle.reachable(u)
	var far := u.pos
	for h in r:
		if r[h].stop and r[h].cost > r.get(far, {"cost": 0}).cost:
			far = h
	s._on_hover(far)
	for k in 20:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://../design/art/ranges_move.png")
	s.battle.move(u, far)
	await s._after_events()
	var rows := s.battle.skills_for(u)
	for row in rows:
		if str(row.targeting) != "self" and row.elements[0] != "":
			s._on_skill_chosen(str(row.key), str(row.elements[0]))
			var t := s.battle.skill_targets(u, row.key, row.elements[0])
			if not t.is_empty():
				s._hover = Vector2i(-9, -9)
				s._on_hover(t[t.size() / 2])
			break
	for k in 20:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://../design/art/ranges_attack.png")
	quit()
