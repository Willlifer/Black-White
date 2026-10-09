extends RefCounted
## D495: HP bars are coloured by team, not by HP (supersedes D215's half rule).


func _u(team: String) -> BWUnit:
	var u := BWUnit.from_roster({ "id": "u_" + team, "name": team, "weapon_class": "sword", "element": "fire" })
	u.team = team
	return u


func test_palette(t) -> void:
	var a := BWWidgets.HPBar.palette(true)
	var e := BWWidgets.HPBar.palette(false)
	t.eq(a.fill, Color.BLACK, "an ally's bar is black")
	t.eq(a.pip, Color.WHITE, "with white pips")
	t.eq(e.fill, Color.WHITE, "an enemy's bar is white")
	t.eq(e.pip, Color.BLACK, "with black pips")
	for p in [a, e]:
		var f: Color = p.fill
		var w: Color = p.well
		var g: Color = p.ghost
		t.ok(absf(w.v - f.v) >= 0.3, "the empty well stands off the fill (%.2f vs %.2f)" % [w.v, f.v])
		t.ok(absf(g.v - w.v) >= 0.3 and absf(g.v - f.v) >= 0.3, "the ghost stands off both")
		t.ok(absf((p.pip as Color).v - w.v) >= 0.3, "pips read on the empty well")


func test_by_team_not_hp(t) -> void:
	var me := _u("player")
	var foe := _u("enemy")
	var stone := BWObelisk.new()
	stone.team = "neutral"
	t.ok(BWHPBar3D.ally_side(me), "the player's side")
	t.ok(not BWHPBar3D.ally_side(foe), "an enemy")
	t.ok(not BWHPBar3D.ally_side(stone), "a neutral stone reads as an enemy")
	for u in [me, foe]:
		var bar := BWHPBar3D.new(u)
		var mat := bar.quad.material_override as ShaderMaterial
		for f in [1.0, 0.6, 0.4, 0.1]:
			bar.set_hp(int(round(100 * f)), 100, false)
			t.eq(bool(mat.get_shader_parameter("ally")), u == me, "%s at %d%%: the shader's ally flag" % [u.team, int(f * 100)])
			t.eq(bar.mode(), "black" if u == me else "white", "%s at %d%%: %s" % [u.team, int(f * 100), "black" if u == me else "white"])
		bar.free()
	var hb := BWWidgets.HPBar.new()
	hb.enemy = true
	hb.set_hp(20, 100)
	t.ok(hb.enemy, "the 2D bar keeps its team at 20%")
	hb.free()
