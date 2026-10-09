class_name BWKs3View
extends Node3D
## D443-D463 readability for Keystones v3 (rules: BWKs3 and its element
## files, BWDuo). Reuses BWKeystoneView's inked ring, shard and droplet
## one-shots (screen.ks_view) and adds its own:
##
## Standing marks (rebuilt when the battle's signature changes):
##   Drowned     a dark water ring at its feet, a DROWNED tag on its bar
##   overcharge  a pulsing ring over an overcharged dark 4 / light 4 hex
## One-shots (on_event, from BWCombatScreen._play):
##   lava_react     D494: AS FIRE 1 over each lava hex an arrival met (a reaction spends a step)
##   pitch_black    an ink-violet burst of the burst's radius, a shake, a beat
##   solar_flare    a white-gold burst, the same
##   rain_cloud     a small grey cloud that follows the walker (not awaited)
##   rain           the cloud rains and fades; the tiles refresh
##   superconductor / overflow / hopekiller / la_nina / shatterer / blizzard
##                  a word over the unit and a feed line (shards for Shatterer)
##   submerge / leviathan_form   a splash ring; the unit sinks / rises
##   drowned_lunge / drowned_return   the Drowned melee blow: the unit's view
##                  jumps to the lunge hex with a splash, then back

const INK := Color(0.02, 0.02, 0.03)
const PITCH := Color(0.3, 0.12, 0.45)
const FLARE := Color(1.0, 0.86, 0.45)
const LEVIATHOS_SCALE := 1.45

var screen: BWCombatScreen
var _sig := ""
var _marks: Array = []
var _tags := {}
var _clouds := {}                  # unit id -> Node3D (the rain cloud riding the walk)
var shown := {}                    # review / probes: { drowned: [ids], overcharged: [hexes] }
var _t := 0.0


func setup(s: BWCombatScreen) -> void:
	screen = s


func _process(delta: float) -> void:
	if screen == null or screen.battle == null:
		return
	_t += delta
	for id in _clouds:
		var v: Node3D = screen._views.get(str(id))
		var c: Node3D = _clouds[id]
		if v != null and is_instance_valid(c):
			c.global_position = c.global_position.lerp(v.global_position + Vector3(0, 2.7, 0), minf(1.0, delta * 9.0))
			c.rotation.y += delta * 0.4
	for m in _marks:
		if is_instance_valid(m) and m.has_meta("pulse"):
			var k := 0.85 + 0.15 * sin(_t * 4.0)
			(m as Node3D).scale = Vector3(k, 1.0, k)
	var sig := _signature(screen.battle)
	if sig != _sig and not screen._busy:
		_sig = sig
		rebuild()


func _signature(b: BWBattle) -> String:
	var parts: PackedStringArray = []
	for u in b.units:
		if u.alive() and BWKs3Water.drowned(u):
			parts.append("d:%s@%s" % [u.id, u.pos])
		if u.alive() and BWKs3Water.leviathos(u):
			parts.append("l:%s" % u.id)
	for h in b.tiles.entries:
		if absi(int(b.tiles.entries[h].get("v", 0))) >= 4:
			parts.append("o:%s" % h)
	return ",".join(parts)


func rebuild() -> void:
	for m in _marks:
		if is_instance_valid(m):
			m.queue_free()
	_marks.clear()
	for id in _tags.keys():
		if is_instance_valid(_tags[id]):
			(_tags[id] as Node).queue_free()
	_tags.clear()
	var b := screen.battle
	shown = { "drowned": [], "overcharged": [] }
	for u in b.units:
		if u.alive() and BWKs3Water.leviathos(u):
			var lv: Node3D = screen._views.get(u.id)
			if lv and not screen._busy:
				lv.scale = Vector3.ONE * LEVIATHOS_SCALE      # D451b: the scaled-up body
			shown["leviathos"] = (shown.get("leviathos", []) as Array) + [u.id]
		if not u.alive() or not BWKs3Water.drowned(u):
			continue
		shown.drowned.append(u.id)
		var ring := _ring_node(BWLook.element_color("water").darkened(0.35), 0.62, 0.1)
		add_child(ring)
		ring.global_position = screen._unit_pos(u.pos) + Vector3(0, 0.04, 0)
		_marks.append(ring)
		var v: Node3D = screen._views.get(u.id)
		if v:
			var l := BWKeystoneView.make_tag(22)
			l.text = "DROWNED"
			BWKeystoneView.bar_mark(v, l, 1)
			_tags[u.id] = l
	for h in b.tiles.entries:
		var vv := int(b.tiles.entries[h].get("v", 0))
		if absi(vv) < 4:
			continue
		shown.overcharged.append(h)
		var col := FLARE if vv > 0 else PITCH
		var ring2 := _ring_node(col, 0.5, 0.08)
		ring2.set_meta("pulse", true)
		add_child(ring2)
		ring2.global_position = screen.board_view.top_center(h) + Vector3(0, 0.06, 0)
		_marks.append(ring2)


## A flat inked ring mesh (radius r, width w) in `col`.
func _ring_node(col: Color, r: float, w: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.material_override = BWKeystoneView.material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.sorting_offset = 3.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_ring(st, r, w + 0.05, INK)
	_ring(st, r, w, Color(col, 0.95))
	mi.mesh = st.commit()
	return mi


func _ring(st: SurfaceTool, r: float, w: float, col: Color) -> void:
	var n := 40
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var o0 := Vector3(cos(a0), 0, sin(a0))
		var o1 := Vector3(cos(a1), 0, sin(a1))
		var p0 := o0 * (r - w * 0.5)
		var p1 := o0 * (r + w * 0.5)
		var p2 := o1 * (r + w * 0.5)
		var p3 := o1 * (r - w * 0.5)
		for p in [p0, p1, p2, p0, p2, p3]:
			st.set_color(col)
			st.add_vertex(p)


# ---------------------------------------------------------------- one-shots

func on_event(e: Dictionary) -> void:
	var b := screen.battle
	var kv: BWKeystoneView = screen.ks_view
	match str(e.type):
		"lava_react":                              # D494: met as fire 1 (no more fizzle)
			var hs: Array = e.get("hexes", [])
			var el := str(e.get("element", ""))
			for i in mini(hs.size(), 6):
				var at: Vector3 = screen.board_view.top_center(hs[i])
				_word(at + Vector3(0, 1.0, 0), "AS FIRE 1", BWLook.element_color("fire").lightened(0.3))
			if el in ["fire", "light", "dark"]:
				screen.ui.feed("[b]Lava[/b]: %s lands beside it (the lava stands)" % el.capitalize())
			else:
				screen.ui.feed("[b]Lava[/b]: %s meets it as fire 1, a step burns off" % el.capitalize())
			await get_tree().create_timer(0.2).timeout
		"pitch_black", "solar_flare":
			var dark := str(e.type) == "pitch_black"
			var at: Vector3 = screen.board_view.top_center(e.hex)
			var col := PITCH if dark else FLARE
			if kv:
				kv.blast(at, col, 1.9 * maxi(1, int(e.radius)) + 0.4)
				kv.blast(at, INK if dark else Color.WHITE, 1.1 * maxi(1, int(e.radius)), true)
			_column(at, col, dark)
			screen._shake(0.14)
			screen.ui.banner("Pitch Black" if dark else "Solar Flare", 0.8)
			screen.ui.feed("[b]%s[/b]: %d%% to %d foe%s%s" % ["Pitch Black" if dark else "Solar Flare", int(e.pct),
				(e.units as Array).size(), "" if (e.units as Array).size() == 1 else "s",
				"" if dark else ", %d heal" % (e.allies as Array).size()])
			screen.board_view.refresh_tiles()
			_sig = ""
			if screen.readability:
				await screen.readability.beat(e.hex)
			await get_tree().create_timer(0.25).timeout
		"overcharge_end":
			screen.board_view.refresh_tiles()
			_sig = ""
		"hopekiller":
			var v: Node3D = screen._views.get(str(e.unit))
			if v:
				screen._float_text(v, "HOPEKILLER", Color(0.7, 0.55, 0.95), 0.8)
			screen.ui.feed("[b]Hopekiller[/b]: %s's heal hurts it (%d)" % [screen._name(str(e.unit)), int(e.amount)])
		"hopekiller_mark":
			screen.board_view.refresh_tiles()
			screen.ui.feed("[b]Hopekiller[/b]: dark 3 where %s fell" % screen._name(str(e.victim)))
		"superconductor":
			var v: Node3D = screen._views.get(str(e.unit))
			if v:
				screen._float_text(v, "SUPERCONDUCTOR", BWLook.element_color("thunder").lightened(0.2), 0.7)
				if kv:
					kv.blast(v.global_position + Vector3(0, 0.05, 0), BWLook.element_color("thunder"), 1.0, true)
		"overflow":
			var v: Node3D = screen._views.get(str(e.unit))
			if v:
				screen._float_text(v, "OVERFLOW", BWLook.element_color("thunder").lightened(0.3), 0.6)
		"la_nina":
			var v: Node3D = screen._views.get(str(e.unit))
			if v and kv:
				kv.blast(v.global_position + Vector3(0, 0.05, 0), BWLook.element_color("wind"), 3.2, true)
			screen.ui.banner("La Niña", 0.6)
			screen.ui.feed("[b]La Niña[/b]: %d%% to every foe, pulled toward %s" % [int(float(e.pct)), screen._name(str(e.unit))])
			await get_tree().create_timer(0.3).timeout
		"la_nina_pull":
			pass
		"shatterer":
			for h in e.get("hexes", []):
				if kv:
					kv.shards(screen.board_view.top_center(h) + Vector3(0, 0.3, 0), 8, 0.9)
			screen.board_view.refresh_tiles()
			screen.ui.feed("[b]Shatterer[/b]: %d glazed hex%s shatter" % [(e.hexes as Array).size(), "" if (e.hexes as Array).size() == 1 else "es"])
			await get_tree().create_timer(0.25).timeout
		"blizzard":
			if kv:
				kv.blast(screen.board_view.top_center(e.hex), BWLook.element_color("ice"), 0.9, true)
			screen.board_view.refresh_tiles()
		"rain_cloud":
			_cloud(str(e.unit))
		"rain":
			await _rain(str(e.unit), e.get("hexes", []))
			screen.board_view.refresh_tiles()
		"leviathan_offer":
			screen.ui.feed("%s stands in deep water: it may submerge (Leviathan)" % screen._name(str(e.unit)))
		"submerge":
			var v: Node3D = screen._views.get(str(e.unit))
			if v:
				if kv:
					kv.blast(v.global_position + Vector3(0, 0.05, 0), BWLook.element_color("water"), 1.6)
					kv.droplets(v.global_position)
				var tw := create_tween()
				tw.tween_property(v, "position:y", v.position.y - 0.6, 0.45).set_trans(Tween.TRANS_SINE)
				await tw.finished
			screen.ui.banner("Submerged", 0.7)
			screen.ui.feed("[b]%s submerges[/b]: its form waits for its next turn" % screen._name(str(e.unit)))
		"leviathan_form":
			var v: Node3D = screen._views.get(str(e.unit))
			if v and str(e.get("form", "")) == "leviathos":
				var tw0 := create_tween()
				tw0.tween_property(v, "global_position", screen._unit_pos(e.hex), 0.3)
				tw0.tween_property(v, "scale", Vector3.ONE * LEVIATHOS_SCALE, 0.5).set_trans(Tween.TRANS_BACK)
				await tw0.finished
				if kv:
					kv.blast(v.global_position + Vector3(0, 0.05, 0), BWLook.element_color("water"), 2.4)
				screen._shake(0.12)
				screen._float_text(v, "LEVIATHOS", BWLook.element_color("water").lightened(0.25), 1.0)
				v.call("refresh")
				screen.ui.feed("[b]%s rises as Leviathos[/b]: double HP, its blows splash" % screen._name(str(e.unit)))
				_sig = ""
				return
			if v:
				var tw := create_tween()
				tw.tween_property(v, "global_position", screen._unit_pos(e.hex), 0.4).set_trans(Tween.TRANS_BACK)
				await tw.finished
				if kv:
					kv.blast(v.global_position + Vector3(0, 0.05, 0), BWLook.element_color("water"), 2.0)
				screen._float_text(v, "DROWNED", BWLook.element_color("water").lightened(0.25), 1.0)
			screen.ui.feed("[b]%s is Drowned[/b]: rooted, its blows reach the whole board" % screen._name(str(e.unit)))
			_sig = ""
		"drowned_lunge":
			var v: Node3D = screen._views.get(str(e.unit))
			if v:
				if kv:
					kv.droplets(v.global_position)
				v.global_position = screen._unit_pos(e.to)
				if kv:
					kv.blast(v.global_position + Vector3(0, 0.05, 0), BWLook.element_color("water"), 1.2, true)
				var tgt: Node3D = screen._views.get(str(e.target))
				if tgt and v.has_method("face"):
					v.call("face", tgt.global_position)
				await get_tree().create_timer(0.12).timeout
		"drowned_return":
			var v: Node3D = screen._views.get(str(e.unit))
			if v:
				if kv:
					kv.droplets(v.global_position)
				v.global_position = screen._unit_pos(e.to)
				if kv:
					kv.blast(v.global_position + Vector3(0, 0.05, 0), BWLook.element_color("water"), 1.0, true)


## A word that rises and fades at `at`.
func _word(at: Vector3, text: String, col: Color) -> void:
	var l := BWKeystoneView.make_tag(26)
	l.text = text
	l.modulate = col
	l.outline_modulate = INK
	add_child(l)
	l.global_position = at
	var tw := create_tween()
	tw.tween_property(l, "global_position", at + Vector3(0, 0.6, 0), 0.7)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.25)
	tw.tween_callback(l.queue_free)


## Pitch Black / Solar Flare's column: a short inked cylinder of the colour.
func _column(at: Vector3, col: Color, dark: bool) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.55
	cm.bottom_radius = 0.7
	cm.height = 2.6
	cm.radial_segments = 12
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(col.darkened(0.2) if dark else col.lightened(0.25), 0.75)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at + Vector3(0, 1.3, 0)
	mi.scale = Vector3(0.3, 0.2, 0.3)
	var tw := create_tween()
	tw.tween_property(mi, "scale", Vector3(1.2, 1.0, 1.2), 0.25).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.45)
	tw.tween_callback(mi.queue_free)


## Being of Rain's cloud: a few grey puffs (inked) over the walker.
func _cloud(id: String) -> void:
	var v: Node3D = screen._views.get(id)
	if v == null:
		return
	if _clouds.has(id) and is_instance_valid(_clouds[id]):
		(_clouds[id] as Node).queue_free()
	var root := Node3D.new()
	add_child(root)
	root.global_position = v.global_position + Vector3(0, 2.7, 0)
	var puffs := [[Vector3(0, 0, 0), 0.42], [Vector3(0.38, -0.05, 0.1), 0.32], [Vector3(-0.36, -0.04, -0.08), 0.33],
		[Vector3(0.1, 0.12, -0.3), 0.3], [Vector3(-0.12, 0.08, 0.3), 0.28]]
	for pf in puffs:
		for pass_i in 2:                         # an ink hull, then the grey puff
			var mi := MeshInstance3D.new()
			var sm := SphereMesh.new()
			var r: float = float(pf[1]) + (0.035 if pass_i == 0 else 0.0)
			sm.radius = r
			sm.height = r * 1.5
			sm.radial_segments = 10
			sm.rings = 5
			mi.mesh = sm
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = INK if pass_i == 0 else Color(0.78, 0.8, 0.84)
			m.cull_mode = BaseMaterial3D.CULL_FRONT if pass_i == 0 else BaseMaterial3D.CULL_BACK
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position = pf[0]
			root.add_child(mi)
	_clouds[id] = root
	_drizzle(root, 2.0)


## Short blue streaks falling from the cloud for `dur` seconds.
func _drizzle(root: Node3D, dur: float) -> void:
	var water := BWLook.element_color("water").lightened(0.15)
	var n := int(dur * 14.0)
	for i in n:
		var tw := create_tween()
		tw.tween_interval(dur * float(i) / n)
		tw.tween_callback(func():
			if not is_instance_valid(root):
				return
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.025, 0.22, 0.025)
			mi.mesh = bm
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = water
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			var off := Vector3(randf_range(-0.45, 0.45), -0.25, randf_range(-0.35, 0.35))
			mi.global_position = root.global_position + off
			var t2 := create_tween()
			t2.tween_property(mi, "global_position", mi.global_position + Vector3(0, -2.3, 0), 0.45)
			t2.tween_callback(mi.queue_free))


## The walk's end: the cloud rains over the hexes, then fades.
func _rain(id: String, hexes: Array) -> void:
	var root: Node3D = _clouds.get(id)
	_clouds.erase(id)
	if root == null or not is_instance_valid(root):
		_cloud(id)
		root = _clouds.get(id)
		_clouds.erase(id)
	if root == null:
		return
	_drizzle(root, 0.7)
	var kv: BWKeystoneView = screen.ks_view
	for i in mini(hexes.size(), 12):
		if kv and i % 2 == 0:
			kv.blast(screen.board_view.top_center(hexes[i]), BWLook.element_color("water"), 0.7, true)
	screen.ui.feed("[b]Being of Rain[/b]: water 1 on %d hexes" % hexes.size())
	await get_tree().create_timer(0.55).timeout
	var tw := create_tween()
	tw.tween_property(root, "scale", Vector3(0.05, 0.05, 0.05), 0.35)
	tw.tween_callback(root.queue_free)
