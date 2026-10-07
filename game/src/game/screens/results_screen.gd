class_name BWResultsScreen
extends Control
## After every fight, won or lost: the battle summary (D119–D121) on the
## left — a row per deployed unit, the highlights, the MVP, and on a loss
## one factual "what went wrong" line — and on the right the spoils,
## abilities learned and where everyone stands. Item names take the colour
## of their enchantment's element (plain items stay white). There is
## nothing to choose here, so there is no button (D75): after MIN_SHOW
## seconds any key or click continues to downtime. Hover a unit row for its
## full breakdown. Everything fits the 1600×900 design size (no scrolling),
## which canvas_items stretch scales to 1080p and 4K.

signal done

const MIN_SHOW := 1.2
const STAT_COLS := [["taken", "Taken", "HP this unit lost to blows, tiles and arcs"],
	["kos", "KOs", "Knockouts landed (tile and arc KOs go to whoever laid them)"],
	["crits", "Crits", "Critical hits landed"],
	["misses", "Miss", "Swings the target avoided"],
	["healed", "Healed", "HP healed onto this unit"],
	["statuses", "Status", "Statuses laid on foes"]]
const BUCKET_SHADE := { "basic": 0.96, "skill": 0.70, "ground": 0.46, "chain": 0.30 }

var run: BWRun
var report: Dictionary
var _t := 0.0
var _sent := false
var _prompt: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_fit()
	get_viewport().size_changed.connect(_fit)
	theme = BWStyle.theme()
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_bottom = -40
	add_child(center)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _box())
	center.add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	box.add_child(v)

	var won: bool = report.get("won", true)
	var h := Label.new()
	h.text = ("Fight %d won" if won else "Fight %d lost") % int(report.fight)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_theme_font_size_override("font_size", 46)
	v.add_child(h)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 40)
	v.add_child(cols)
	var bs: Dictionary = report.get("stats", {})
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.custom_minimum_size.x = 820
	cols.add_child(left)
	_summary(left, bs, won)
	var rule := VSeparator.new()
	rule.add_theme_stylebox_override("separator", _vline())
	cols.add_child(rule)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.custom_minimum_size.x = 560
	cols.add_child(right)
	_spoils(right)

	_prompt = _label("press any key", BWStyle.F_SMALL, BWStyle.TEXT_DIM)
	_prompt.anchor_top = 1.0
	_prompt.anchor_bottom = 1.0
	_prompt.anchor_right = 1.0
	_prompt.offset_top = -64
	_prompt.offset_bottom = -30
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.modulate.a = 0.0
	add_child(_prompt)


# ---------------------------------------------------------------- summary

## The deployed squad's ids, in the order they fought.
func _mine(bs: Dictionary) -> Array:
	var units: Dictionary = bs.get("units", {})
	return Array(bs.get("order", [])).filter(func(id): return units[id].team == BWBattleStats.TEAM \
		and (run == null or run.unit(id) != null))


func _summary(v: VBoxContainer, bs: Dictionary, won: bool) -> void:
	var mine := _mine(bs)
	var rounds := int(bs.get("rounds", 0))
	v.add_child(_section("Battle summary" + ("  ·  %d rounds" % rounds if rounds > 0 else "")))
	if mine.is_empty():
		var l := _label("No battle record.", BWStyle.F_BODY, BWStyle.TEXT_DIM)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
		return
	var units: Dictionary = bs.units
	var top := 1
	for id in mine:
		top = maxi(top, int(units[id].dealt_total))
	v.add_child(_header_row())
	for id in mine:
		v.add_child(_unit_row(units[id], id == bs.get("mvp", ""), top))
	v.add_child(_gap(4))
	var hl: Array = bs.get("highlights", [])
	if not hl.is_empty():
		v.add_child(_section("Highlights"))
		for h in hl:
			v.add_child(_bullet(str(h.text)))
	var mvp := str(bs.get("mvp", ""))
	if mvp != "":
		var m: Dictionary = units[mvp]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(mvp_tag())
		row.add_child(_label(str(m.name), BWStyle.F_SUB))
		row.add_child(_label(score_text(m), BWStyle.F_SMALL, BWStyle.TEXT_DIM))
		row.tooltip_text = "MVP score (D120) = damage dealt + %d per KO + %d per status on a foe + %d per ward that caught a blow" \
			% [BWBattleStats.KO_PTS, BWBattleStats.STATUS_PTS, BWBattleStats.WARD_PTS]
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		v.add_child(_gap(2))
		v.add_child(row)
	var wrong := str(bs.get("wrong", ""))
	if not won and wrong != "":
		v.add_child(_gap(4))
		var plate := PanelContainer.new()
		plate.add_theme_stylebox_override("panel", BWStyle.hud_style())
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 14)
		plate.add_child(hb)
		hb.add_child(BWStyle.section_label("What went wrong"))
		var l := _label(wrong, BWStyle.F_BODY, BWStyle.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(l)
		v.add_child(plate)


## "142 = 102 dealt + 2 KOs + 3 statuses"
static func score_text(m: Dictionary) -> String:
	var parts: PackedStringArray = ["%d dealt" % int(m.dealt_total)]
	if int(m.kos) > 0:
		parts.append("%d KO%s" % [int(m.kos), "" if int(m.kos) == 1 else "s"])
	if int(m.statuses) > 0:
		parts.append("%d status%s" % [int(m.statuses), "" if int(m.statuses) == 1 else "es"])
	if int(m.wards) > 0:
		parts.append("%d ward%s" % [int(m.wards), "" if int(m.wards) == 1 else "s"])
	return "score %d  ·  %s" % [int(m.score), "  +  ".join(parts)]


func _header_row() -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 0)
	var pad := Control.new()
	pad.custom_minimum_size.x = 52 + 190
	hb.add_child(pad)
	var dcol := VBoxContainer.new()                  # ---- D125: "Dealt" over a tiny legend of the split
	dcol.add_theme_constant_override("separation", -2)
	dcol.custom_minimum_size.x = 210
	hb.add_child(dcol)
	var d := _label("Dealt", BWStyle.F_SMALL - 2, BWStyle.LABEL)
	d.tooltip_text = "Damage dealt to foes, as HP they lost.\nThe bar splits it: basic · skill · ground (tiles, detonations) · chain"
	d.mouse_filter = Control.MOUSE_FILTER_PASS
	dcol.add_child(d)
	dcol.add_child(_split_text(["basic", "skill", "ground", "chain"], BWStyle.F_SMALL - 5))
	for c in STAT_COLS:
		var l := _label(c[1], BWStyle.F_SMALL - 2, BWStyle.LABEL)
		l.custom_minimum_size.x = 62
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.tooltip_text = c[2]
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		hb.add_child(l)
	return hb


func _unit_row(s: Dictionary, is_mvp: bool, top: int) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 0)
	hb.mouse_filter = Control.MOUSE_FILTER_PASS
	hb.tooltip_text = detail_text(s)
	var ru: BWUnit = run.unit(str(s.get("id", ""))) if run != null else null
	var icon: BWWidgets.HeadIcon = BWWidgets.Portrait.new(ru, 40, false) if ru != null 		else BWWidgets.HeadIcon.new(str(s.element), false, 40)          # D156
	icon.selected = is_mvp
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(icon)
	var gap := Control.new()
	gap.custom_minimum_size.x = 12
	hb.add_child(gap)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 0)
	nv.custom_minimum_size.x = 190
	nv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(nv)
	var nrow := HBoxContainer.new()
	nrow.add_theme_constant_override("separation", 8)
	nv.add_child(nrow)
	nrow.add_child(_label(str(s.name), BWStyle.F_BODY, BWStyle.TEXT if not s.downed else BWStyle.TEXT_DIM))
	if is_mvp:
		nrow.add_child(mvp_tag())
	nv.add_child(_label("Knocked out" if s.downed else BWText.weapon(s.weapon_class), BWStyle.F_SMALL - 2, BWStyle.FAINT))
	# dealt: the number, the split bar, the split numbers
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 2)
	dv.custom_minimum_size.x = 210
	dv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(dv)
	var dt := _label(str(int(s.dealt_total)), BWStyle.F_SUB)
	dv.add_child(dt)
	var bar := SplitBar.new(s.dealt, top)
	dv.add_child(bar)
	var sp: Array = []
	for b in BWBattleStats.BUCKETS:
		sp.append(str(int(s.dealt[b])))
	dv.add_child(_split_text(sp, BWStyle.F_SMALL - 3))   # ---- D125: each number hovers its bucket
	for c in STAT_COLS:
		var n := int(s.get(c[0], 0))
		var l := _label(str(n), BWStyle.F_BODY, BWStyle.TEXT if n > 0 else BWStyle.FAINT)
		l.custom_minimum_size.x = 62
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hb.add_child(l)
	return hb


## The hover window for a unit row: every number with what it counts.
static func detail_text(s: Dictionary) -> String:
	var d: Dictionary = s.dealt
	var lines: PackedStringArray = [
		"%s — dealt %d" % [s.name, int(s.dealt_total)],
		"  basic attacks & counters  %d" % int(d.basic),
		"  skills & ripostes  %d" % int(d.skill),
		"  ground & detonations  %d" % int(d.ground),
		"  chain arcs  %d" % int(d.chain),
		"best single hit  %d" % int(s.best_hit),
		"swings %d  ·  crits %d  ·  missed %d" % [int(s.attempts), int(s.crits), int(s.misses)],
		"took %d  ·  healed %d%s" % [int(s.taken), int(s.healed), "  ·  knocked out" if s.downed else ""],
		"KOs %d  ·  statuses laid %d  ·  wards that caught a blow %d" % [int(s.kos), int(s.statuses), int(s.wards)],
		"MVP score %d" % int(s.score),
	]
	return "\n".join(lines)


## A small white plate with black "MVP".
static func mvp_tag() -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := Label.new()
	l.text = "MVP"
	l.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 3)
	l.add_theme_color_override("font_color", Color.BLACK)
	p.add_child(l)
	return p


## Damage dealt, split basic / skill / ground / chain in four greys, its
## length relative to the best on the squad.
class SplitBar:
	extends Control
	var parts := {}
	var top := 1

	func _init(p: Dictionary, t: int) -> void:
		parts = p
		top = maxi(t, 1)
		custom_minimum_size = Vector2(190, 7)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := size
		draw_rect(Rect2(Vector2(-1, -1), s + Vector2(2, 2)), Color(0, 0, 0, 0.85))
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.08, 0.08, 0.09))
		var x := 0.0
		for b in BWBattleStats.BUCKETS:
			var w := s.x * float(parts.get(b, 0)) / top
			if w <= 0.0:
				continue
			var g: float = BWResultsScreen.BUCKET_SHADE[b]
			draw_rect(Rect2(Vector2(x, 0), Vector2(w, s.y)), Color(g, g, g))
			x += w
			draw_line(Vector2(x, 0), Vector2(x, s.y), Color.BLACK, 1.0)


func _bullet(t: String) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	var dot := ColorRect.new()
	dot.color = BWStyle.TEXT
	dot.custom_minimum_size = Vector2(7, 7)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(dot)
	var l := _label(t, BWStyle.F_BODY)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(l)
	return hb


# ---------------------------------------------------------------- spoils

func _spoils(v: VBoxContainer) -> void:
	v.add_child(_section("Spoils" if not report.loot.is_empty() else "No spoils"))
	for it in report.loot:
		v.add_child(_loot_row(it))
	if report.has("twins_reward"):                     # D258: the Twins' gift
		v.add_child(_gap(4))
		v.add_child(_section("The Twins' gift: one extra pick for every unit"))
	if not report.learned.is_empty():
		v.add_child(_gap(4))
		v.add_child(_section("Learned"))
		# one line per unit (a fight can teach a unit several at once)
		var by := {}
		var order: Array = []
		for e in report.learned:
			if not by.has(e.unit):
				by[e.unit] = PackedStringArray()
				order.append(e.unit)
			by[e.unit].append(str(BWData.row("abilities", e.ability).get("name", e.ability)))
		for id in order:
			var l := _label("%s learned %s" % [run.unit(id).name, ", ".join(by[id])], BWStyle.F_SMALL)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = 540
			v.add_child(l)
	v.add_child(_gap(4))
	v.add_child(_section("The squad"))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 24)
	g.add_theme_constant_override("v_separation", 8)
	g.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(g)
	for u in run.squad:
		g.add_child(_squad_cell(u))


func _box() -> StyleBoxFlat:
	var sb := BWStyle.box_style()
	sb.content_margin_left = 36
	sb.content_margin_right = 36
	sb.content_margin_top = 18
	sb.content_margin_bottom = 24
	return sb


func _vline() -> StyleBoxLine:
	var l := StyleBoxLine.new()
	l.color = Color(1, 1, 1, 0.18)
	l.thickness = 1
	l.vertical = true
	return l


## D125: the four split parts (basic · skill · ground · chain), each in its
## bar shade, each hovering what it counts (BWGlossary cards).
const BUCKET_HINT := {
	"basic": "Basic: basic attacks, extra strikes and counters",
	"skill": "Skill: blows from weapon skills",
	"ground": "Ground: tile damage, detonations and other elemental effects",
	"chain": "Chain: chain lightning arcs from a conductive (fused) unit",
}

func _split_text(parts: Array, size: int) -> RichTextLabel:
	var r := BWGlossary.Rich.new()
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_OFF
	r.add_theme_font_size_override("normal_font_size", size)
	var bits: PackedStringArray = []
	for i in mini(parts.size(), BWBattleStats.BUCKETS.size()):
		var b: String = BWBattleStats.BUCKETS[i]
		var shade := float(BUCKET_SHADE.get(b, 0.6))
		bits.append("[color=#%s][hint=%s]%s[/hint][/color]" % [Color(shade, shade, shade).to_html(false), BUCKET_HINT.get(b, b), parts[i]])
	r.text = (" [color=#%s]·[/color] " % BWStyle.FAINT.to_html(false)).join(bits)
	return r


func _label(t: String, size: int, col: Color = BWStyle.TEXT) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _gap(px: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = px
	return c


## A centred section heading with a rule either side.
func _section(t: String) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	for i in 3:
		if i == 1:
			var l := BWStyle.section_label(t)
			hb.add_child(l)
		else:
			var s := HSeparator.new()
			s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			hb.add_child(s)
	return hb


## Item name in its element's colour, stat lines dim, the enchantment's
## effect small underneath.
func _loot_row(it: Dictionary) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	col.add_child(row)
	var el := BWRun.item_element(it)
	var name_col := BWLook.element_color(el) if el != "" else Color.WHITE
	if el != "":
		var sw := ColorRect.new()
		sw.color = name_col
		sw.custom_minimum_size = Vector2(12, 12)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(sw)
	var n := _label(BWRun.item_name(it), BWStyle.F_BODY, name_col)
	n.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	if el == "dark":
		# Dark's deep violet needs a light edge to read on the black box.
		n.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.35))
		n.add_theme_constant_override("outline_size", 3)
	row.add_child(n)
	var st: PackedStringArray = []
	for s in it.get("stats", {}):
		st.append("+%d %s" % [int(it.stats[s]), s.to_upper()])
	if not st.is_empty():
		row.add_child(_label("  ".join(st), BWStyle.F_SMALL, BWStyle.TEXT_DIM))
	var fx := str(BWData.row("enchantments", it.get("enchant", "")).get("effect_text", ""))
	if fx != "":
		var f := _label(fx, BWStyle.F_SMALL - 2, BWStyle.FAINT.lerp(BWStyle.TEXT_DIM, 0.5))
		f.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		f.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		f.custom_minimum_size.x = 540
		col.add_child(f)
	return col


func _squad_cell(u: BWUnit) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.custom_minimum_size.x = 266
	var icon := BWWidgets.Portrait.new(u, 36, false)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(icon)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var n := _label(u.name, BWStyle.F_SMALL + 1)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.clip_text = true
	top.add_child(n)
	top.add_child(_label("Lv %d  %s" % [u.level, u.expertise_letter(u.weapon_class)], BWStyle.F_SMALL - 2, BWStyle.TEXT_DIM))
	# D179/D194: no XP bar; every fight levels everyone, so say so per unit
	var gains: Dictionary = report.get("levels", {}).get(u.id, {})
	if not gains.is_empty():
		var up := _label("Level up!  →  Lv %d" % u.level, BWStyle.F_SMALL - 1, Color.WHITE)
		var parts: PackedStringArray = []
		for k in gains:
			parts.append("+%d %s" % [int(gains[k]), str(k).to_upper()])
		up.tooltip_text = "  ".join(parts)
		up.mouse_filter = Control.MOUSE_FILTER_PASS
		v.add_child(up)
	return hb


func _process(delta: float) -> void:
	_t += delta
	if _t >= MIN_SHOW:
		_prompt.modulate.a = 0.4 + 0.25 * sin((_t - MIN_SHOW) * 2.4)


func can_continue() -> bool:
	return _t >= MIN_SHOW and not _sent


func _unhandled_input(ev: InputEvent) -> void:
	var pressed: bool = (ev is InputEventKey and ev.pressed and not ev.echo) \
		or (ev is InputEventMouseButton and ev.pressed) \
		or (ev is InputEventJoypadButton and ev.pressed)
	if pressed and can_continue():
		_sent = true
		done.emit()


## These screens are Controls under a plain Node (BWGame), so anchors have
## no parent rect to follow: size to the viewport ourselves, and keep it.
func _fit() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = get_viewport_rect().size
