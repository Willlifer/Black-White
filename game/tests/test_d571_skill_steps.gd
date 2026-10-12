extends RefCounted
## D571-D572 (author, 2026-10-11): Warded leaves every roll pool; ten
## underused skills lay 2 steps of the chosen element; Inversion flips, then
## maxes each flipped axis to 3.

const TWO := ["lunge", "en_passant", "pinning_shot", "dualthrow", "kindle", "fan_of_knives",
	"ley_line", "axe_throw", "earthsplitter", "sweep"]

var K: Object = preload("res://tests/test_keystones_v3.gd").new()


func test_warded_never_rolls(t) -> void:
	t.eq(BWRun.ench_weight(BWData.row("enchantments", BWEffects.WARDED), "A"), 0, "Warded weighs 0 at every tier")
	var r := BWRun.start(BWData.table("roster").slice(0, 6).map(func(x): return str(x.id)), 5)
	var seen := 0
	for i in 300:
		var it := r.make_item("chaps", "B")
		if str(it.enchant) == BWEffects.WARDED:
			seen += 1
	t.eq(seen, 0, "300 chaps: none Warded")
	for tier in ["C", "A"]:
		r.fight = 5
		r.roll_scrolls()
		t.ok(r.scrolls.all(func(s): return str(s.enchant) != BWEffects.WARDED), "no Warded scroll (%s)" % tier)
	var old := r.make_item("chaps", "E", "warded")
	t.eq(str(old.enchant), BWEffects.WARDED, "an item that has it keeps it")


func test_two_steps(t) -> void:
	for k in TWO:
		t.eq(int(BWSkillRegistry.row(k).get("steps", 1)), 2, "%s lays 2 steps" % k)


func test_earthsplitter_paints_again(t) -> void:
	var me: BWUnit = K._u("me", "axe", "fire")
	var b: BWBattle = K._duel(me, [K._u("f", "axe", "ice")], [Vector2i(10, 10)])
	var h: Vector2i = K._nb(K.C, 0)
	BWSkillRegistry.get_def("earthsplitter").ground(b, me, "fire", h, { "hexes": [h], "steps": 2 })
	t.eq(b.tiles.intensity(h, "fire"), 2, "the line takes 2 steps (D416's no-paint is gone)")


func test_inversion_maxes(t) -> void:
	var me: BWUnit = K._u("me", "staff", "water")
	var b: BWBattle = K._duel(me, [K._u("f", "axe", "ice")], [Vector2i(10, 10)])
	var a: Vector2i = K._nb(K.C, 0, 2)
	var c: Vector2i = K._nb(K.C, 3, 2)
	K._lay(b, a, 1, -2, "x")
	K._lay(b, c, -3, 0, "x")
	var d := BWSkillRegistry.get_def("inversion")
	t.eq(d.swap_text(b.tiles.at(a)), "fire 1 → water 3, dark 2 → light 3", "the text names the max")
	d.ground(b, me, "", a, { "hexes": [a, c] })
	t.eq(b.tiles.intensity(a, "water"), 3, "fire 1 -> water 3")
	t.eq(b.tiles.intensity(a, "light"), 3, "dark 2 -> light 3")
	t.eq(b.tiles.intensity(c, "fire"), 3, "water 3 -> fire 3")
