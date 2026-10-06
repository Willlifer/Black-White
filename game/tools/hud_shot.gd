extends SceneTree
## Renders the combat HUD on a player turn with a skill group open and an
## enemy hovered, for visual review. Saves design/art/hud_*.png.
func _init() -> void:
	var roster := BWData.table("roster")
	var p: Array = []
	var e: Array = []
	for id in ["jericho", "aureli", "will"]:
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
	s.ui._open_group = str(s.battle.skills_for(u)[0].key)
	s._show_options()
	s.ui.set_card(e[0], s.battle.tiles, u)
	for k in 30:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://../design/art/hud_player_turn.png")
	var foe: BWUnit = e[0]
	foe.pos = u.pos + Vector2i(0, -1)
	s._views[foe.id].position = s.board_view.top_center(foe.pos)
	s.ui.show_forecast(u, foe, s.battle.forecast_basic(u, foe))
	for k in 20:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://../design/art/hud_forecast.png")
	quit()
