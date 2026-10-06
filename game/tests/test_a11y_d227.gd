extends RefCounted
## D227-D232: the cleanup and accessibility pass. Glossary stops (L-9),
## headgear hides hair by data (L-4), HP bars culled under HUD panels (L-21),
## the shader warm catalog (L-6), and the element kanji (D231).


func test_glossary_stops(t) -> void:
	BWGlossary.reset()
	var charge_skill := BWGlossary.markup("Charge: rush and strike.")
	t.ok(not charge_skill.contains("[hint="), "the axe skill Charge is not linked to the tile term")
	t.ok(BWGlossary.markup("a charged tile").contains("[hint=Charge"), "lower-case charged still links")
	t.ok(not BWGlossary.markup("a light grey shirt").contains("[hint="), "light grey is a colour")
	t.ok(not BWGlossary.markup("dark gray trousers").contains("[hint="), "dark gray is a colour")
	t.ok(not BWGlossary.markup("Covering Fire").contains("[hint="), "the skill Covering Fire is not linked")
	t.ok(BWGlossary.markup("draws covering fire").contains("[hint=Overwatch"), "lower-case covering fire still means overwatch")
	t.ok(BWGlossary.markup("a light tile heals").contains("[hint=Light"), "the element light still links")
	t.eq(BWGlossary.terms_in("Charge and light grey"), [], "stops are not terms")


func test_headgear_hides_hair(t) -> void:
	var want := { "feathered_full_helm": "hide_all", "dragoon_helm": "hide_all", "baseball_cap": "hide_top",
		"feathered_cap": "hide_top", "tilted_beret": "hide_top", "wizard_hat": "hide_top", "tiara": "show", "crown": "show" }
	var heads := BWData.table("equipment").filter(func(r): return str(r.slot) == "head")
	t.eq(heads.size(), want.size(), "every head piece is listed")
	for r in heads:
		t.ok(str(r.get("hides_hair", "")) in BWEquipmentView.HIDES_HAIR, "%s has a hides_hair flag" % r.id)
		t.eq(BWEquipmentView.piece_hair_mode(str(r.id)), want.get(str(r.id), "?"), "%s hair mode" % r.id)


func test_hide_all_hides_hair_on_the_rig(t) -> void:
	var u := BWUnit.new()
	u.id = "a11y_helm"
	u.name = "Helm"
	u.element = "water"
	u.cosmetics = { "hair_style": "long_hair", "top": "tshirt", "bottom": "sweatpants", "clothing_shade": "mid" }
	u.equipment["head"] = { "base": "feathered_full_helm", "slot": "head" }
	var c := BWCharacter.create(u)
	t.ok(c != null and c.hair != null, "built with hair")
	if c and c.hair:
		t.ok(not c.hair.visible, "a full helm hides the hair")
		u.equipment["head"] = { "base": "tiara", "slot": "head" }
		c.refresh_equipment()
		t.ok(c.hair.visible, "a tiara shows it again")
	if c:
		c.free()


func test_hp_bar_cover(t) -> void:
	var bar := BWHPBar3D.new(null)
	var lbl := Label3D.new()
	bar.add_child(lbl)
	bar.set_covered(true)
	t.eq(bar.quad.layers, 0, "a covered bar draws on no layer")
	t.eq(lbl.layers, 0, "its labels too")
	bar.set_covered(false)
	t.eq(bar.quad.layers, 1, "uncovered restores the layer")
	t.eq(lbl.layers, 1, "and the labels'")
	bar.free()


func test_warm_catalog(t) -> void:
	var cat := BWShaderWarm.catalog()
	var names := cat.map(func(it): return it[0])
	for k in ["tile_fire", "glaze", "tile_flame", "burst", "vfx_column", "vfx_ribbon", "vfx_particle", "hp_bar", "kanji"]:
		t.ok(k in names, "warm pass covers " + k)
	for it in cat:
		(it[1] as Node).free()


func test_kanji_text(t) -> void:
	BWKanji.force = false
	t.eq(BWSettings.DEFAULTS.get("element_kanji"), false, "off by default")
	t.eq(BWKanji.bb("water"), "", "nothing when off")
	t.eq(BWKanji.tag_words("Light"), "Light", "tag_words is a no-op when off")
	BWKanji.force = true
	t.eq(BWKanji.glyph("water"), "水", "water")
	t.eq(BWKanji.glyph("Thunder"), "雷", "case-insensitive")
	t.eq(BWKanji.glyph(""), "", "no element, no glyph")
	t.eq(BWKanji.prefix("fire"), "火 ", "plain prefix")
	var once := BWKanji.tag_words("[hint=Light: opposite of dark]Light[/hint] and wind")
	t.ok(once.contains("光[/font] Light") and once.contains("風[/font] wind"), "element words get their kanji")
	t.ok(once.contains("[hint=Light: opposite of dark]"), "never inside a tag")
	t.eq(BWKanji.tag_words(once), once, "idempotent")
	t.ok(BWKanji.base_font() != null, "the subset font loads")
	for el in BWKanji.GLYPHS:
		t.ok(BWKanji.base_font().has_char(BWKanji.glyph(el).unicode_at(0)), "the subset has " + el)
	BWKanji.force = null


func test_kanji_layer(t) -> void:
	var layer := BWKanjiLayer.new()
	var one := Vector2i(1, 1)
	var two := Vector2i(2, 2)
	var mk := Vector2i(3, 3)
	layer.apply(one, Vector3.ZERO, BWTileFX.layers({ "h": -3 }))
	layer.apply(two, Vector3.ZERO, BWTileFX.layers({ "h": 1, "v": -2 }))
	layer.apply(mk, Vector3.ZERO, BWTileFX.layers({ "marker": "fuse" }))
	t.eq(layer.shown(one), [["水", 3]], "water 3: one heavy glyph")
	t.eq(layer.shown(two), [["闇", 2], ["火", 1]], "two axes side by side, the dominant first")
	t.eq(layer.shown(mk), [["雷", 0]], "a fuse marker shows thunder")
	layer.apply(one, Vector3.ZERO, BWTileFX.layers({}))
	t.eq(layer.shown(one), [], "a cleared tile shows nothing")
	t.eq(layer.shown(Vector2i(9, 9)), [], "an untouched tile has no nodes")
	layer.free()
