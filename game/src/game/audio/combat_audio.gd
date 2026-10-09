class_name BWCombatAudio
extends Node
## Sound for a BWCombatScreen, from its battle's events, timed to their
## replay: the screen queues every rules event and replays it with
## animation; an event leaves the queue when its replay starts, and that is
## when it sounds here. Nothing in the combat screen calls this; the
## director attaches it.
##
##   attack / counter / skill / riposte   tells each target's BWUnitAudio what
##                                        the blow was (hit, crit, glance,
##                                        resisted, miss, element, weapon), so
##                                        the reaction's `impact` frame sounds right
##   detonate / erupt                     tile boom at the hex
##   paint                                ice -> glaze freeze, wind -> gale gust
##   tile_damage                          the element's hit (or a thud)
##   heal                                 heal shimmer
##   growth (level)                       level-up sting
##   turn                                 turn chime (player turns)
##   battle_end                           victory / defeat sting (BWMusic ducks)
##   anything that changes HP or KOs      BWMusic.set_intensity (0..2)
##   move without an animator             a step per hex (the primitive stand-ins)
##   chain (D86)                          a zap at the chained unit (elem_thunder, pitched up)
##   reaction (D87)                       douse hiss / eclipse / storm at the hex; a paint's doused hexes hiss (D421)
##   rider_shown (D86/D87, screen signal) Spark crackle (bolt_fizz), Shatter glass
##                                        (tile_glaze, pitched up), at the blow's impact
##   skill_called (D100, screen signal)   a quick whoosh (cast_whoom pitched up) as the
##                                        skill's name wipes in
##   crit_flashed (D101, screen signal)   the crit sting, before the swing since D530: a
##                                        bright tile_glaze glint and a rising cast_whoom
##                                        (2D, so the frozen world doesn't matter); the
##                                        crack is the impact's hit_crit
##   ward_broken (D102, screen signal)    glass: tile_glaze pitched up twice, a hit_glance
##                                        crack under it
## D393 placeholders (ph_*, tools/audio/make_placeholders.py; the author replaces them):
##   enchant                              on-kill (Death Knell, Relentless, a kill's
##                                        spread) -> ph_proc_onkill; pity (Second Chance,
##                                        Graze, Follow-Through, Steady Hand) -> ph_proc_pity
##   heal from an enchantment / Mend-Link ph_proc_heal instead of the heal shimmer
##   immune                               ph_immune at the unit
##   skill: a big cast (a caster's AoE)   the caster's release plays ph_cast_<element>
##   skill: Fan of Knives                 the spin plays ph_fan_knives
##   Horde grunts walking                 one ph_horde_shuffle loop while any walks

var screen: BWCombatScreen
var _pending: Array = []
var _hooked := false
var _level := -1
var _shuffle: Node                   # D393: the Horde's shuffle loop


func _ready() -> void:
	screen = get_parent() as BWCombatScreen


func _process(_delta: float) -> void:
	if screen == null:
		return
	if not _hooked and screen.battle != null:
		# connected after the screen's own queueing handler, so an event is
		# already in the screen's queue when it reaches us
		screen.battle.event.connect(_on_event)
		if screen.has_signal("rider_shown"):
			screen.rider_shown.connect(_on_rider)      # D86/D87
		# ---- D100 / D101 / D102 presentation stings (existing SFX set, pitched)
		if screen.has_signal("skill_called"):
			screen.skill_called.connect(_on_callout)
		if screen.has_signal("crit_flashed"):
			screen.crit_flashed.connect(_on_crit_flash)
		if screen.has_signal("ward_broken"):
			screen.ward_broken.connect(_on_ward_break)
		_hooked = true
		_update_intensity()
	_horde_shuffle()
	var q: Variant = screen.get("_queue")
	while not _pending.is_empty():
		var e: Dictionary = _pending[0]
		if q is Array and (q as Array).any(func(x): return is_same(x, e)):
			break
		_pending.pop_front()
		_replayed(e)


func _on_event(e: Dictionary) -> void:
	_pending.append(e)


func _view(id: Variant) -> BWUnitView:
	var vs: Variant = screen.get("_views")
	return (vs as Dictionary).get(str(id)) if vs is Dictionary else null


func _hex_pos(h: Variant) -> Vector3:
	if h is Vector2i and screen.has_method("_unit_pos"):
		return screen.call("_unit_pos", h)
	return Vector3.ZERO


func _replayed(e: Dictionary) -> void:
	match str(e.get("type", "")):
		"attack", "counter":
			_expect(e.get("unit"), [{ "target": e.get("target"), "result": e.get("result", {}), "ko": e.get("ko", false) }], "")
		"skill", "riposte":
			_expect(e.get("unit"), e.get("results", []), str(e.get("element", "")))
			if str(e.get("type", "")) == "skill":
				_big_cast(e)
		"heal":
			var v := _view(e.get("unit"))
			if v:
				var cause := str(e.get("cause", ""))
				if cause.begins_with("enchant:") or cause == "mend_link":
					BWSfx.play("ph_proc_heal", v, { "tag": "proc_heal" })        # D393
				else:
					BWSfx.play("heal", v, { "tag": "heal" })
		# ---- D393 placeholders ----
		"enchant":
			var kind := proc_kind(str(e.get("text", "")))
			if kind != "":
				BWSfx.play("ph_proc_" + kind, _view(e.get("unit")), { "tag": "proc_" + kind })
		"immune":
			BWSfx.play("ph_immune", _view(e.get("unit")), { "tag": "immune" })
		"tile_damage":
			var v := _view(e.get("unit"))
			var cause := str(e.get("cause", ""))
			var el := ""
			for k in ["fire", "water", "ice", "thunder", "wind", "dark", "light"]:
				if cause.contains(k):
					el = k
			if cause.contains("detonat"):
				el = "thunder"
			if v:
				BWSfx.play("elem_" + el if el != "" else "hit_flesh", v, { "gain_db": -3.0, "tag": "tile_damage" })
		"paint":
			var kind := str(e.get("kind", ""))
			var hexes: Array = e.get("hexes", [])
			if not (e.get("doused", []) as Array).is_empty():   # D421: fire met water, a short hiss
				BWSfx.play("elem_water", _centroid(e.doused), { "pitch": 1.6, "gain_db": -6.0, "tag": "hiss" })
			if kind in ["consume", "siphon"] or hexes.is_empty():
				return
			var el := str(e.get("element", ""))
			var at := _centroid(hexes)
			if el == "ice":
				BWSfx.play("tile_glaze", at, { "tag": "glaze" })
			elif el == "wind":
				BWSfx.play("tile_gale", at, { "tag": "gale" })
		"detonate":
			BWSfx.play("tile_detonate", _hex_pos(e.get("hex")), { "gain_db": -6.0 if e.get("echo", false) else 0.0, "stack": true, "tag": "detonate" })
		"erupt":
			BWSfx.play("tile_detonate", _centroid(e.get("hexes", [])) if e.has("hexes") else Vector3.ZERO, { "gain_db": -4.0, "tag": "erupt" })
			BWSfx.play("elem_" + str(e.get("element", "fire")), null, { "gain_db": -4.0, "tag": "erupt" })
		"growth":
			for g in e.get("events", []):
				if g is Dictionary and str(g.get("type", "")) == "level":
					BWSfx.ui("ui_levelup", { "tag": "level" })
					break
		"turn":
			var u: BWUnit = screen.battle._unit(str(e.get("unit", "")))
			if u and u.team == "player" and not screen.autoplay:
				BWSfx.ui("ui_turn", { "tag": "turn" })
			_update_intensity()
		"ko":
			_update_intensity()
		"move":
			var v := _view(e.get("unit"))
			if v and v.character == null:
				var path: Array = e.get("path", [])
				for i in range(1, path.size()):
					BWSfx.play("step_stone", _hex_pos(path[i]), { "delay": 0.22 * i, "stack": true, "tag": "step_hex" })
		"battle_end":
			BWMusic.sting("victory" if str(e.get("winner", "")) == "player" else "defeat")
		# ---- D86/D87: chain lightning and Striketwice reactions (existing SFX set) ----
		"chain":
			BWSfx.play("elem_thunder", _view(e.get("to")), { "pitch": 1.35, "stack": true, "tag": "chain" })
		"reaction":
			var at := _hex_pos(e.get("hex"))
			match str(e.get("kind", "")):
				"douse": BWSfx.play("elem_water", at, { "pitch": 1.4, "tag": "douse" })
				"eclipse": BWSfx.play("elem_dark", at, { "pitch": 0.8, "tag": "eclipse" })
				"storm":
					BWSfx.play("elem_wind", at, { "tag": "storm" })
					BWSfx.play("elem_thunder", at, { "gain_db": -4.0, "delay": 0.08, "tag": "storm" })
	if str(e.get("type", "")) in ["attack", "counter", "skill", "riposte", "tile_damage", "detonate"]:
		_update_intensity()


## D86/D87: the floating rider tags, sounded as they pop: Spark = a crackle,
## Shatter = glass (the glaze sound pitched up), Backstab/Pierce = a crit-ish hit.
func _on_rider(unit_id: String, tag: String) -> void:
	var v := _view(unit_id)
	match tag:
		"Spark": BWSfx.play("bolt_fizz", v, { "pitch": 1.3, "gain_db": 2.0, "stack": true, "tag": "spark" })
		"Shatter": BWSfx.play("tile_glaze", v, { "pitch": 1.6, "stack": true, "tag": "shatter" })
		"Backstab", "Pierce", "Pierced": BWSfx.play("hit_crit", v, { "gain_db": -6.0, "pitch": 1.2, "stack": true, "tag": "rider" })


# ---- D100 / D101 / D102 (presentation lane, marked edit) ----

func _on_callout(_unit_id: String, _text: String, _element: String) -> void:
	BWSfx.ui("cast_whoom", { "pitch": 1.45, "gain_db": -3.0, "tag": "callout" })


## The crit sting. D530: the flash now comes BEFORE the swing, so the sting is
## an anticipation, a bright glint and a rising whoosh, not a crack: the crack
## is the impact's own hit_crit (unit_audio), which lands with the blow.
func _on_crit_flash(_unit_id: String) -> void:
	BWSfx.ui("tile_glaze", { "pitch": 2.4, "gain_db": 0.0, "stack": true, "tag": "crit_flash" })
	BWSfx.ui("cast_whoom", { "pitch": 1.9, "gain_db": -3.0, "stack": true, "tag": "crit_flash" })


func _on_ward_break(unit_id: String) -> void:
	var v := _view(unit_id)
	BWSfx.play("tile_glaze", v, { "pitch": 1.9, "gain_db": 4.0, "stack": true, "tag": "ward_break" })
	BWSfx.play("tile_glaze", v, { "pitch": 2.6, "gain_db": -2.0, "stack": true, "tag": "ward_break" })
	BWSfx.play("hit_glance", v, { "pitch": 1.5, "gain_db": -2.0, "stack": true, "tag": "ward_break" })

# ---- end D100 / D101 / D102 ----


# ---- D393 placeholders ----

## The proc an `enchant` event's text announces: "onkill", "pity" or "".
static func proc_kind(text: String) -> String:
	for w in ["Death Knell", "Relentless", " spreads"]:
		if text.contains(w):
			return "onkill"
	for w in ["Second Chance", "Graze", "Follow-Through", "Steady Hand"]:
		if text.begins_with(w):
			return "pity"
	return ""


## Keystone casts with no element of their own.
const KEYSTONE_EL := { "pitch_black": "dark", "solar_flare": "light", "self_detonate": "thunder" }   # D449-D452 (Keystones v3)
const ELEMENTS := ["fire", "water", "ice", "thunder", "wind", "light", "dark"]


## A big cast: a caster (staff, a Being, a cast-clip keystone) whose skill
## covers an area (aoe, or 3+ hexes) -> its element; else "".
static func big_cast_element(e: Dictionary, caster: BWUnit) -> String:
	var key := str(e.get("skill", ""))
	var row := BWSkillRegistry.row(key) if BWSkillRegistry.has(key) else {}
	var clip := str(row.get("clip", ""))
	var spell := caster != null and str(caster.weapon().get("damage_type", "")) == "spell"
	if not BWClipRoute.casts(caster, spell or str(row.get("weapon", "")) == "staff", clip):
		return ""
	var hexes: Variant = e.get("hexes", [])
	if not bool(row.get("aoe", false)) and not (hexes is Array and (hexes as Array).size() >= 3) and clip != "cast":
		return ""
	var el := str(e.get("element", ""))
	if el == "":
		el = str(KEYSTONE_EL.get(key, caster.attuned if caster and caster.attuned != "" else (caster.element if caster else "")))
	return el if el in ELEMENTS else ""


func _big_cast(e: Dictionary) -> void:
	var v := _view(e.get("unit"))
	if v == null:
		return
	if str(e.get("skill", "")) == "fan_of_knives":
		BWUnitAudio.expect_cast(v, { "kind": "fan" })
		return
	var el := big_cast_element(e, v.unit)
	if el != "":
		BWUnitAudio.expect_cast(v, { "kind": "cast", "element": el })


## One quiet shuffle loop while any Horde grunt walks, at the first walker.
func _horde_shuffle() -> void:
	var vs: Variant = screen.get("_views")
	var walker: BWUnitView = null
	if vs is Dictionary:
		for v in (vs as Dictionary).values():
			if v is BWUnitView and is_instance_valid(v) and v.unit and str(v.unit.encounter) == "grunt" and v.unit.alive() 					and v.character and v.character.animator 					and Vector2(v.character.animator.velocity.x, v.character.animator.velocity.z).length() > BWUnitAudio.MOVING:
				walker = v
				break
	if walker and (_shuffle == null or not is_instance_valid(_shuffle)):
		_shuffle = BWSfx.loop_start("ph_horde_shuffle", walker, { "tag": "horde_shuffle", "stack": true })
	elif walker == null and _shuffle != null:
		BWSfx.loop_stop(_shuffle, 0.4)
		_shuffle = null


func _exit_tree() -> void:
	BWSfx.loop_stop(_shuffle, 0.05)
	_shuffle = null


## Each target's BWUnitAudio learns what is about to hit it.
func _expect(attacker_id: Variant, results: Array, element: String) -> void:
	var a := _view(attacker_id)
	var st := ""
	var model := ""
	var el := element
	if a and a.unit:
		model = str(a.unit.weapon_model)
		if a.character and a.character.animator:
			st = a.character.animator.set_id
		if el == "" and str(a.unit.weapon().get("damage_type", "")) == "spell":
			el = a.unit.attuned if a.unit.attuned != "" else a.unit.element
	for r in results:
		if not r is Dictionary:
			continue
		var t := _view(r.get("target"))
		if t:
			BWUnitAudio.expect(t, { "result": r.get("result", {}), "element": el, "set": st, "model": model, "ko": r.get("ko", false) })


func _centroid(hexes: Array) -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for h in hexes:
		if h is Vector2i:
			c += _hex_pos(h)
			n += 1
	return c / maxf(n, 1)


## Combat intensity (music): 0 calm start; 1 once someone is hurt below half
## or knocked out; 2 when a squad member is under a quarter, three are down,
## or either side is down to its last unit.
func _update_intensity() -> void:
	if screen.battle == null:
		return
	var low := 1.0
	var kos := 0
	var alive := { "player": 0, "enemy": 0 }
	for u in screen.battle.units:
		if not u.alive():
			kos += 1
			continue
		alive[u.team] = int(alive.get(u.team, 0)) + 1
		if u.team == "player":
			low = minf(low, float(u.hp) / maxf(u.max_hp(), 1))
	var lvl := 0
	if kos >= 1 or low < 0.5:
		lvl = 1
	if kos >= 3 or low < 0.25 or int(alive.player) == 1 or int(alive.enemy) == 1:
		lvl = 2
	if lvl != _level:
		_level = lvl
		BWMusic.set_intensity(lvl)
