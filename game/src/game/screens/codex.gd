class_name BWCodex
extends CanvasLayer
## The codex: what the elements do, every weapon's numbers and skills, what
## the stats are for, and the terrain. A self-contained overlay any screen
## can open:
##     BWCodex.summon(self, "weapons")    # adds itself to `self`, opens on that tab
##     var c := BWCodex.new(); add_child(c); c.open("stats")
## Esc (or the Close button) closes it and emits `closed`; it frees itself.
## While open it swallows keys and clicks, so the screen underneath doesn't
## react. Tabs: elements, weapons, stats, terrain (1-4, or Left/Right).
## Everything is read from the rules (BWTiles, BWFormulas, BWSkills, the
## CSVs), so it stays in sync with the data.

signal closed

const TABS := ["elements", "weapons", "stats", "terrain", "bosses", "glossary"]     # D125: + glossary; D260: + bosses
const LAYER := 90                 # under BWGame's fade (100)

## Intensity names per axis element (design/ELEMENTS.md §4 / elements.csv).
const TIERS := {
	"fire": ["Smouldering", "Burning", "Blazing"],
	"water": ["Damp", "Flooded", "Deep"],
	"light": ["First light", "Lightfall", "Pillar"],
	"dark": ["Gloaming", "Deep shadow", "Abyss"],
}
const TARGETING := {
	"unit": "an enemy in range", "hex": "any hex in range", "leap": "a free hex in range, or any hex carrying the element",
	"dir": "a direction", "adjacent_unit": "an adjacent enemy", "self": "yourself",
}
const STAT_NAMES := {
	"con": "Constitution", "str": "Strength", "dex": "Dexterity", "wil": "Willpower",
	"def": "Defense", "res": "Resistance", "spd": "Speed",
}

var tab := "elements"
var _tabs := {}                   # name -> Button
var _scroll: ScrollContainer
var _body: VBoxContainer


## Open a codex over `host` on `tab`. Returns it (connect `closed` if needed).
static func summon(host: Node, p_tab: String = "elements") -> BWCodex:
	var c := BWCodex.new()
	c.tab = p_tab
	host.add_child(c)
	return c


func _ready() -> void:
	layer = LAYER
	_build()
	open(tab)
	BWEsc.push(self, close, { "name": "codex" })              # ---- D171


func open(p_tab: String = "elements") -> void:
	tab = p_tab if p_tab in TABS else "elements"
	visible = true
	for k in _tabs:
		(_tabs[k] as Button).button_pressed = k == tab
	for c in _body.get_children():
		c.queue_free()
	match tab:
		"elements": _elements()
		"weapons": _weapons()
		"stats": _stats()
		"terrain": _terrain()
		"bosses": _bosses()
		"glossary": _glossary()
	_scroll.scroll_vertical = 0


func close() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()


func _input(ev: InputEvent) -> void:
	if not visible:
		return
	if ev is InputEventKey:
		if ev.keycode == KEY_ESCAPE and BWEsc.routed():
			return                                # ---- D171: BWEsc closes the newest window
		if ev.pressed and not ev.echo:
			var i := TABS.find(tab)
			match ev.keycode:
				KEY_ESCAPE, KEY_I: close()
				KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6: open(TABS[mini(ev.keycode - KEY_1, TABS.size() - 1)])
				KEY_LEFT: open(TABS[(i + TABS.size() - 1) % TABS.size()])
				KEY_RIGHT, KEY_TAB: open(TABS[(i + 1) % TABS.size()])
				KEY_UP: _scroll.scroll_vertical -= 80
				KEY_DOWN: _scroll.scroll_vertical += 80
				KEY_F11: return                       # fullscreen toggle passes through
		if not (ev.keycode == KEY_F11 or (ev.keycode == KEY_ENTER and ev.alt_pressed)):
			get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- frame

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP        # nothing underneath gets clicks
	root.theme = BWStyle.theme()
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", BWStyle.box_style())
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 110
	panel.offset_right = -110
	panel.offset_top = 48
	panel.offset_bottom = -48
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	v.add_child(bar)
	var title := Label.new()
	title.text = "Codex"
	title.add_theme_font_size_override("font_size", BWStyle.F_NAME)
	title.custom_minimum_size.x = 170
	bar.add_child(title)
	var group := ButtonGroup.new()
	for i in TABS.size():
		var k: String = TABS[i]
		var b := Button.new()
		b.text = "%s  %d" % [k.capitalize(), i + 1]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(150, 44)
		b.add_theme_stylebox_override("pressed", _tab_on())
		b.add_theme_color_override("font_pressed_color", Color.BLACK)
		b.add_theme_color_override("font_hover_pressed_color", Color.BLACK)
		b.pressed.connect(open.bind(k))
		bar.add_child(b)
		_tabs[k] = b
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	var x := Button.new()
	x.text = "Close  [Esc]"
	x.focus_mode = Control.FOCUS_NONE
	x.custom_minimum_size.y = 44
	x.pressed.connect(close)
	bar.add_child(x)
	v.add_child(HSeparator.new())

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 12)
	_scroll.add_child(_body)


func _tab_on() -> StyleBoxFlat:
	var sb := BWStyle.button_style("hover")
	sb.bg_color = Color(0.94, 0.94, 0.95)
	return sb


# ---------------------------------------------------------------- pieces

func _rt(bb: String, size: int = BWStyle.F_BODY, gloss: bool = true) -> RichTextLabel:
	var r := BWGlossary.Rich.new()                   # D125: every codex term hovers
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_font_size_override("italics_font_size", size)
	r.add_theme_font_size_override("table_font_size", size)
	r.add_theme_constant_override("table_h_separation", 18)
	r.add_theme_constant_override("table_v_separation", 3)
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	r.text = BWGlossary.markup(bb) if gloss else bb
	return r


## A framed card with an element-coloured left edge (white when "").
func _card(element: String = "") -> VBoxContainer:
	var p := PanelContainer.new()
	var sb := BWStyle.frame_style()
	sb.set_content_margin_all(12)
	sb.border_color = Color(1, 1, 1, 0.35)
	sb.set_border_width_all(1)
	if element != "":
		sb.border_color = BWLook.element_color(element)
		sb.border_width_left = 6
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	_pending_parent.add_child(p)
	return v


var _pending_parent: Control


func _grid(cols: int = 2) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 12)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(g)
	return g


func _intro(bb: String) -> void:
	_body.add_child(_rt("[color=#%s]%s[/color]" % [BWStyle.TEXT_DIM.to_html(false), bb], BWStyle.F_BODY))


static func _hex(c: Color) -> String:
	return c.to_html(false)


func _dim(t: String) -> String:
	return "[color=#%s]%s[/color]" % [_hex(BWStyle.TEXT_DIM), t]


func _faint(t: String) -> String:
	return "[color=#%s]%s[/color]" % [_hex(BWStyle.FAINT), t]


## Element-coloured text. Dark's deep violet is lifted a little so it reads
## on the black panel (the swatch keeps the true colour).
func _el(e: String, t: String = "") -> String:
	var c := BWLook.element_color(e)
	if c.get_luminance() < 0.25:
		c = c.lerp(Color.WHITE, 0.35)
	return "[color=#%s]%s[/color]" % [_hex(c), t if t != "" else e.capitalize()]


# ---------------------------------------------------------------- elements

func _elements() -> void:
	_intro("Every unit carries an element (its hair colour) and paints the ground with it through skills. "
		+ "Four are [b]axes[/b] that build up on a tile to intensity %d: %s ↔ %s and %s ↔ %s, so an opposite steps a tile back. "
		% [BWTiles.AXIS_MAX, _el("fire"), _el("water"), _el("light"), _el("dark")]
		+ "Three are [b]operators[/b] that act on whatever charge a tile already holds: %s detonates, %s locks, %s spreads."
		% [_el("thunder"), _el("ice"), _el("wind")])
	_pending_parent = _grid(2)
	# Axes first (as they pair up), then the operators; data order otherwise.
	var rows: Array = BWData.table("elements").duplicate()
	var axes := rows.filter(func(r): return str(r.get("role", "")).begins_with("axis"))
	var ops := rows.filter(func(r): return not str(r.get("role", "")).begins_with("axis"))
	for row in axes + ops:
		_element_card(row)
	_rules_card()


func _element_card(row: Dictionary) -> void:
	var e := str(row.id)
	var v := _card(e)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	v.add_child(head)
	head.add_child(BWWidgets.Portrait.new(BWWidgets.Portrait.stand_in(e), 46))
	var role := str(row.get("role", ""))
	var axis := role.begins_with("axis")
	var opp := str(row.get("opposite", ""))
	var opp_txt := "every element (ice ranks resist all)" if opp == "all" else _el(opp)
	head.add_child(_rt("[font_size=%d][b]%s[/b][/font_size]   %s\n%s" % [BWStyle.F_SUB + 3, _el(e, str(row.name)),
		_faint(("AXIS · " + ("raises" if role.ends_with("pos") else "lowers") + (" heat" if e in ["fire", "water"] else " light")) if axis else "OPERATOR"),
		_dim("Opposite: ") + opp_txt]))
	v.add_child(_rt(_element_body(e), BWStyle.F_SMALL))
	v.add_child(_rt(_build_body(e), BWStyle.F_SMALL))       # D278: perks, keystones, the set


## D278: what an element offers a build: its 4 perks, its 3 keystones (gold,
## the sigil) and its set's 2 / 3 pieces. Hover a name for the rule.
func _build_body(e: String) -> String:
	var hint := func(text: String) -> String: return BWPicker.hint_safe(str(text))
	var perks: PackedStringArray = []
	for r in BWPicks.perks_of(e):
		perks.append("[hint=%s]%s[/hint]" % [hint.call(str(r.effect_text)), str(r.name)])
	var gold := BWPicker.GOLD.to_html(false)
	var ks: PackedStringArray = []
	for id in BWKeystones.of_element(e):
		var r := BWKeystones.row(str(id))
		ks.append("[hint=%s][color=#%s]%s[/color][/hint]%s" % [hint.call(str(r.get("text", ""))), gold, str(r.get("name", id)),
			_faint(" (action)") if BWKeystones.is_action(str(id)) else ""])
	var st := BWSets.row(e)
	return "%s %s
[color=#%s]◈ Keystones[/color] %s
%s %s · 3: [hint=%s]%s[/hint]" % [
		_faint("Perks (ranks 1, 2, 4, 5)"), " · ".join(perks),
		gold, _faint("(rank 3: 1 of 2; rank 6: a second; 2 per unit)") + " " + " · ".join(ks),
		_faint("Set (head, chest, legs, drawn weapon's imbue)"), _dim("2: " + str(st.get("two_text", ""))),
		hint.call(str(st.get("three_text", ""))), str(st.get("three", ""))]


func _element_body(e: String) -> String:
	var t: Array = TIERS.get(e, [])
	var hdr := "[table=4][cell]%s[/cell]" % _faint("Intensity")
	for i in t.size():
		hdr += "[cell][b]%d[/b] %s[/cell]" % [i + 1, _dim(t[i])]
	match e:
		"fire":
			return hdr + _row("Turn start", func(i): return "%d%% HP dmg" % (BWTiles.FIRE_STAND_PCT * i)) \
				+ _row("Each hex crossed", func(i): return "%d%% HP" % (BWTiles.FIRE_CROSS_PCT * i)) \
				+ _row("On grass", func(i): return "lights the grass around" if i >= BWTiles.GRASS_IGNITE_MIN else "just burns") \
				+ "[/table]\nFire on a glazed tile melts the glaze."
		"water":
			return hdr + _row("Move cost", func(i): return "+%d" % BWTiles.WATER_MOVE[i]) \
				+ _row("Thunder hits on it", func(i): return "+%d%% dmg" % roundi(BWTiles.CONDUCT_HIT_MULT * 100 * i)) \
				+ _row("Adds to a detonation", func(i): return "+%d%% HP" % (BWTiles.CONDUCT_DET_PCT * i)) \
				+ "[/table]\nGlazed (frozen) water costs no extra move: freeze a river to cross it."
		"light":
			return hdr + _row("Turn start", func(i): return "heals %d%% HP" % (BWTiles.LIGHT_HEAL_PCT * i)) \
				+ _row("Attacks on it", func(i): return "%+d hit" % (BWTiles.HIT_PER_POINT * i)) \
				+ "[/table]\nLight heals and exposes: a trade, not a pure buff."
		"dark":
			return hdr + _row("Attacks on it", func(i): return "%+d hit" % (-BWTiles.HIT_PER_POINT * i)) \
				+ _row("Turn start", func(i): return "drains %d%% HP" % BWTiles.DARK3_DRAIN_PCT if i == 3 else "—") \
				+ "[/table]\nDark hides whoever stands in it; the Abyss bites."
		"thunder":
			return "[b]On charged ground: detonate.[/b] The tile explodes and is erased. Whoever stands on it takes "\
				+ "%d%% + %d%% per charge point of their max HP (+%d%% per water intensity), each neighbour takes half, ×%.1f if glazed.\n" \
				% [BWTiles.DETONATE_BASE_PCT, BWTiles.DETONATE_PER_POINT_PCT, BWTiles.CONDUCT_DET_PCT, BWTiles.SHATTER_MULT] \
				+ "[b]On empty ground:[/b] arms a fuse for %d cycles; the next element cast there blows it." % BWTiles.MARK_CYCLES
		"ice":
			return "[b]On charged ground: glaze.[/b] Locks the tile for %d cycles: it stops fading and can't be painted over. " % BWTiles.GLAZE_CYCLES \
				+ "Fire melts a glaze; thunder shatters it for ×%.1f.\n" % BWTiles.SHATTER_MULT \
				+ "[b]On empty ground:[/b] arms stasis for %d cycles; the next element cast there is glazed." % BWTiles.MARK_CYCLES
		"wind":
			return "[b]On charged ground: gale.[/b] Copies the tile's charge onto its six neighbours (the copies last 1 cycle, never ignite, and skip glazed or marked hexes).\n" \
				+ "[b]On empty ground:[/b] arms a gale for %d cycles; the next element cast there spreads." % BWTiles.MARK_CYCLES
	return ""


func _row(label: String, f: Callable) -> String:
	var s := "[cell]%s[/cell]" % _dim(label)
	for i in range(1, 4):
		s += "[cell]%s[/cell]" % str(f.call(i))
	return s


func _rules_card() -> void:
	var v := _card("")
	var per := BWUnit.POINTS_PER_RANK
	v.add_child(_rt("[font_size=%d][b]Affinity and the ground[/b][/font_size]" % (BWStyle.F_SUB + 3)))
	v.add_child(_rt(
		"[b]Affinity[/b] ranks 0–%d, %d points each. Everyone starts at rank 1 in their own element; any element at rank 1+ can be used in skills. " % [BWUnit.MAX_AFFINITY_RANK, per]
		+ "An attack with an element earns %d point, a knockout %d.\n" % [BWProgression.ATTACK.affinity, BWProgression.KNOCKOUT.affinity]
		+ "Each rank: [b]+%d%%[/b] damage with it, [b]+%d[/b] resist against it, [b]+%.1f[/b] resist against its opposite. Ice ranks give +%.1f against every other element.\n"
		% [roundi(BWFormulas.AFFINITY_DMG_PER_RANK * 100), roundi(BWFormulas.AFFINITY_RES_PER_RANK), BWFormulas.OPPOSITE_RES_PER_RANK, BWFormulas.OPPOSITE_RES_PER_RANK]
		+ "[b]Ground[/b] ticks once per cycle (after everyone has acted). Each intensity step lasts %d cycles, then fades a step; markers last %d. " % [BWTiles.STEP_CYCLES, BWTiles.MARK_CYCLES]
		+ "Tile damage is a share of the victim's max HP, cut by their resist (at most %d%%). " % roundi(BWTiles.ELEM_RESIST_CAP)
		+ "[b]Tiles hurt everyone, allies included.[/b]", BWStyle.F_SMALL))


# ---------------------------------------------------------------- weapons

## D359-D361, D371/D372: "5", "4 · jump 4", "4 · HighGrounder pick", "4 · mud 1".
func _move_cell(wc: String) -> String:
	var t := str(BWWeaponMove.base_move(wc))
	if BWWeaponMove.class_jump(wc) > BWBoard.DEFAULT_JUMP:
		t += " · jump %d" % BWWeaponMove.class_jump(wc)
	for k in BWWeaponMove.passives_of(wc):
		t += " · %s pick" % BWWeaponMove.passive_name(str(k))
	if BWWeaponMove.ROUGH_FOOTED in BWWeaponMove.traits(wc):
		t += " · mud 1"
	return t


func _weapons() -> void:
	_intro("Every weapon has a basic attack and its own skills. Skills that use an element come in one version per element you know, "
		+ "and each version has its own cooldown. Skill damage: [b]power + ½ STR + ½ DEX[/b]; staff spells: [b]power + WIL[/b].")
	var tbl := "[table=6][cell]%s[/cell][cell]%s[/cell][cell]%s[/cell][cell]%s[/cell][cell]%s[/cell][cell]%s[/cell]" % [
		_faint("CLASS"), _faint("DAMAGE"), _faint("BASE"), _faint("RANGE"), _faint("SPEED"), _faint("MOVE")]
	var rows: Array = BWData.table("weapons")
	for w in rows:
		tbl += "[cell][b]%s[/b][/cell][cell]%s[/cell][cell]%d[/cell][cell]%s[/cell][cell]%s[/cell][cell]%s[/cell]" % [
			str(w.get("name", w.id)), _dmg_type(w), int(w.get("base_dmg", 0)), _range(int(w.get("range", 1))),
			_mod(int(w.get("speed_mod", 0))), _move_cell(str(w.id))]   # D359-D361
	tbl += "[/table]"
	_pending_parent = _body
	var top := _card("")
	top.add_child(_rt(tbl))
	top.add_child(_rt(_faint("Speed adds to SPD for turn order. Move is the weapon drawn when the turn starts; jump is the levels one step may rise."), BWStyle.F_SMALL))
	_pending_parent = _grid(2)
	for w in rows:
		_weapon_card(w)


func _weapon_card(w: Dictionary) -> void:
	var v := _card("")
	var wc := str(w.id)
	v.add_child(_rt("[font_size=%d][b]%s[/b][/font_size]   %s" % [BWStyle.F_SUB + 3, BWText.weapon(wc),
		_faint("%s · %d dmg · range %s" % [_dmg_type(w), int(w.get("base_dmg", 0)), _range(int(w.get("range", 1)))])]))
	var lines: PackedStringArray = []
	lines.append("[b]Basic attack[/b]  " + _dim("weapon damage + %s, range %s%s" % [_dmg_stat(w), _range(int(w.get("range", 1))),
		", paints the target hex" if str(w.get("damage_type", "")) == "spell" else ""]))
	var kit: Array = BWSkills.kit(wc)
	if kit.is_empty():
		lines.append(_faint("No skills."))
	for s in kit:
		var meta: PackedStringArray = []
		if s.get("follow_up_only", false):
			meta.append("follow-up")
		meta.append("range %s" % ("self" if int(s.range) == 0 and s.targeting == "self" else str(int(s.range))))
		var cd := int(s.get("cd", 0))
		meta.append("cooldown %d" % cd if cd > 0 else ("free action" if s.get("free", false) else "no cooldown"))
		if int(s.get("power", 0)) > 0:
			meta.append("power %d%s" % [int(s.power), " (spell)" if s.get("spell", false) else ""])
		if s.get("needs_element", false):
			meta.append("uses an element")
		lines.append("[b]%s%s[/b]  %s\n[indent]%s[/indent]" %["   ↳ " if s.get("follow_up_only", false) else "", s.name,
			_faint(" · ".join(meta)), _dim(str(s.desc) + ". Targets " + str(TARGETING.get(s.targeting, s.targeting)) + ".")])
	v.add_child(_rt("\n".join(lines), BWStyle.F_SMALL))


func _dmg_type(w: Dictionary) -> String:
	return "%s (%s)" % [str(w.get("damage_type", "martial")).capitalize(), _dmg_stat(w)]


func _dmg_stat(w: Dictionary) -> String:
	match str(w.get("damage_type", "martial")):
		"dexterous": return "DEX"
		"spell": return "WIL"
	return "STR"


func _range(r: int) -> String:
	return "melee" if r <= 1 else str(r)


func _mod(m: int) -> String:
	return "%+d" % m if m != 0 else "—"


# ---------------------------------------------------------------- stats

func _stats() -> void:
	_intro("Seven stats. Starting values are 1–6; they grow by 1–2 a level (biased by weapon and armour), and every unit in the squad gains a level after every fight, won or lost. "
		+ "Every number below is the game's own formula, the same one the attack forecast shows when you hover a number.")
	var sword := _sample("sword")
	var bow := _sample("bow")
	var staff := _sample("staff")
	var F := BWFormulas
	var defs := {
		"con": ["How much you can take.", [F.hp(sword)]],
		"str": ["Hits harder with martial weapons (sword, axe, lance) and with every weapon skill.",
			[F.damage_base(sword, F.WEAPON, 0), F.damage_base(sword, F.SKILL, 0)]],
		"dex": ["Hits harder with dexterous weapons; lands hits, finds crits, slips blows.",
			[F.damage_base(bow, F.WEAPON, 0), F.hit_basis(sword, F.WEAPON), F.crit_chance(sword), F.avoid(sword)]],
		"wil": ["Spell damage: the staff and its spells.", [F.damage_base(staff, F.SPELL, 0)]],
		"def": ["Turns clean hits into glances (half damage) and soaks weapon damage.",
			[F.glance_chance(sword), F.damage_taken(sword, sword, F.WEAPON, 0), F.damage_taken(sword, sword, F.SKILL, 0)]],
		"res": ["Resists magic (spells, and skills that carry an element) and soaks spell damage.",
			[F.resist_chance(sword, ""), F.damage_taken(sword, sword, F.SPELL, 0)]],
		"spd": ["Turn order: the fastest acts first.", []],
	}
	_pending_parent = _grid(2)
	for s in BWUnit.STATS:
		var d: Array = defs.get(s, ["", []])
		var v := _card("")
		v.add_child(_rt("[font_size=%d][b]%s[/b][/font_size]   %s" % [BWStyle.F_SUB + 3, s.to_upper(), _faint(STAT_NAMES.get(s, s))]))
		var lines: PackedStringArray = [_dim(d[0])]
		for c in d[1]:
			lines.append("[b]%s[/b]  =  %s" % [_calc_name(c), _fmt(c.formula)])
		if s == "spd":
			lines.append("[b]Speed[/b]  =  SPD + weapon speed modifier")
		v.add_child(_rt("\n".join(lines), BWStyle.F_SMALL))
	var v2 := _card("")
	v2.add_child(_rt("[font_size=%d][b]One attack, rolled[/b][/font_size]" % (BWStyle.F_SUB + 3)))
	v2.add_child(_rt(
		"[b]Hit[/b]  =  %s\n" % _fmt(F.hit_chance(sword, sword, F.WEAPON).formula)
		+ "Then: glance (×%.1f damage) → crit on a clean hit (×%.1f, chance %s) → resist, magic only (×%.1f, no side effects).\n" % [F.GLANCE_MULT, F.CRIT_MULT, _fmt(F.crit_chance(sword).formula), F.RESIST_MULT]
		+ "Damage never drops below 1. Move: the drawn weapon's (4 or 5 hexes); climbing costs 1 per level, at most the jump (2; lance 4, a bow with HighGrounder 4) up a step.",
		BWStyle.F_SMALL))


## "Damage base" / "Damage" read the same for every kind; name the kind.
func _calc_name(c: Dictionary) -> String:
	var f := str(c.formula)
	if c.label == "Damage base":
		return "Spell damage" if f.begins_with("spell") else ("Skill damage" if f.begins_with("skill") else "Weapon damage")
	if c.label == "Damage":
		return "Skill hit taken" if f.contains("+") and f.contains("/ 2") else ("Spell hit taken" if f.contains("RES") else "Weapon hit taken")
	return str(c.label)


func _fmt(f: String) -> String:
	return f.replace("  (min 1)", "  " + _faint("(min 1)")).replace("  (5–100)", "  " + _faint("(5–100)"))


func _sample(wc: String) -> BWUnit:
	return BWUnit.from_roster({ "id": "codex_" + wc, "name": "", "element": "", "weapon_class": wc })


# ---------------------------------------------------------------- terrain

func _terrain() -> void:
	_intro("Terrain belongs to the map and never changes; elements lie on top of it.")
	var info := {
		BWBoard.NEUTRAL: ["Neutral", "Move cost 1. No interaction."],
		BWBoard.GRASSY: ["Grassy", "Move cost 1. Fire cast here at intensity %d+ lights the grass around it on the next tick (grass to grass only). Fire dries wet grass instead." % BWTiles.GRASS_IGNITE_MIN],
		BWBoard.MUDDY: ["Muddy", "Move cost 2. Water's move penalty adds on top: mud + Deep water costs 4."],
		BWBoard.JAGGED: ["Jagged", "Impassable rock. Blocks line of sight and never holds an element."],
	}
	_pending_parent = _grid(2)
	for k in BWBoard.KINDS:
		var d: Array = info.get(k, [str(k).capitalize(), ""])
		var v := _card("")
		v.add_child(_rt("[font_size=%d][b]%s[/b][/font_size]" % [BWStyle.F_SUB + 3, d[0]]))
		v.add_child(_rt(_dim(d[1]), BWStyle.F_SMALL))
	var v2 := _card("")
	v2.add_child(_rt("[font_size=%d][b]Height[/b][/font_size]" % (BWStyle.F_SUB + 3)))
	v2.add_child(_rt(_dim("Each level climbed costs one extra move, and a step can rise at most the walker's jump: 2, or 4 with a lance or with a bow and the HighGrounder pick. Dropping down is free. Leaps and charges from 1+ level above reach 1 farther."), BWStyle.F_SMALL))


# ---------------------------------------------------------------- bosses (D260)

## The fixed fights: the Twins at fight 7 (BWTwins), the Giant at the end.
func _bosses() -> void:
	_intro("Fight %d offers a boss: the Obelisks or the Twins, your pick. The Giant ends the run. No weather on a boss." % BWRun.TWINS_FIGHT)   # D353
	_pending_parent = _body
	var v := _card("light")
	v.add_child(_rt("[font_size=%d][b]%s[/b][/font_size]  %s" % [BWStyle.F_SUB + 3, BWTwins.TITLE, _dim("a card at fight %d · the Court" % BWRun.TWINS_FIGHT)]))
	v.add_child(_rt(_dim("Two tall figures, one hex each. Noon is white with a halo-ring head; Dusk is black with a hollow ring for a head. They mirror each other. Their HP follows your squad's level."), BWStyle.F_SMALL))
	v.add_child(_rt("[b]Phase 1.[/b] At the end of its turn each paints its colour (+%d) on itself and the ring around it: Noon light, Dusk dark. Each heals %d%% max HP per point of its own colour under it at its turn start. More than %d hexes apart, a [b]Beam[/b] joins them: %s" % [
		BWTwins.PAINT_STEPS, int(BWTwins.HEAL_PCT), BWTwins.BEAM_GAP, BWTwins.beam_text()], BWStyle.F_SMALL))
	v.add_child(_rt("[b]Phase 2[/b] (either under 50%%). The colours swap: Noon paints dark, Dusk light, and each heals ×2 on its own colour.", BWStyle.F_SMALL))
	v.add_child(_rt("[b]Phase 3.[/b] When one falls, the other [b]Rage[/b]s %d cycles later: +1 move, paint radius 2. Down both within those %d cycles and the rage never comes." % [BWTwins.RAGE_DELAY, BWTwins.RAGE_DELAY], BWStyle.F_SMALL))
	v.add_child(_rt(_dim("Counter: light and dark cancel, so paint the opposite colour over their ground; thunder the beam (it breaks for a cycle and jolts both for %d%%); burst both together. Win: every squad unit gets one extra pick (two cards). A loss still levels the squad." % int(BWTwins.FEEDBACK_PCT)), BWStyle.F_SMALL))
	var g := _card("dark")
	g.add_child(_rt("[font_size=%d][b]The Giant[/b][/font_size]  %s" % [BWStyle.F_SUB + 3, _dim("the end · the Arena")]))
	g.add_child(_rt(_dim("500 HP, 50 in every stat, seven hexes. It isn't forced to be unbeatable."), BWStyle.F_SMALL))


# ---------------------------------------------------------------- glossary (D125)

## Every term of data/glossary.csv by category: the term, what else it is
## called, the one-line definition (its own terms hover too), and "see".
func _glossary() -> void:
	var all := BWGlossary.entries()
	_intro("The words the game uses, in one place. Anywhere one of these appears with a [b]dotted underline[/b] "
		+ "(forecasts, unit cards, statuses, pick cards, the gear panel, this codex) hover it for the definition. %d terms." % all.size())
	_pending_parent = _body
	var by_cat := {}
	for e in all:
		if not by_cat.has(e.category):
			by_cat[e.category] = []
		by_cat[e.category].append(e)
	var cats: Array = BWGlossary.CATEGORY_ORDER.filter(func(c): return by_cat.has(c))
	for c in by_cat:
		if not c in cats:
			cats.append(c)
	for c in cats:
		var v := _card(_cat_element(c))
		v.add_child(_rt("[font_size=%d][b]%s[/b][/font_size]" % [BWStyle.F_SUB + 3, BWGlossary.CATEGORY_NAMES.get(c, str(c).capitalize())], BWStyle.F_BODY, false))
		var bb := "[table=2]"
		for e in by_cat[c]:
			var name := "[b]%s[/b]" % (_el(e.id, e.term) if e.category == "element" else str(e.term))
			if not (e.aliases as Array).is_empty():
				name += "
" + _faint(", ".join((e.aliases as Array).slice(0, 3)))
			var d := BWGlossary.markup(str(e.definition))
			if str(e.see) != "" and not BWGlossary.entry(str(e.see)).is_empty():
				d += "  " + _faint("See %s." % BWGlossary.entry(str(e.see)).term)
			bb += "[cell]%s[/cell][cell]%s[/cell]" % [name, d]
		bb += "[/table]"
		var t := _rt(bb, BWStyle.F_SMALL, false)
		t.add_theme_constant_override("table_v_separation", 8)
		v.add_child(t)


func _cat_element(c: String) -> String:
	return { "element": "fire", "operator": "thunder", "tile": "", "status": "", "rider": "ice" }.get(c, "")
