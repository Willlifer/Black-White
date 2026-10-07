class_name BWEndScreen
extends Control
## A black card with centred text. Used for the intro, game over and the
## ending. Any key continues, or it advances itself after `auto_seconds`.
##
## D121: given the `run` (after the Giant, won or lost), the card's line
## sits above the run summary: the record, each unit's totals across the
## run (fights deployed, KOs, damage, MVPs), the perks and skills it
## picked, and the run's best highlight. Then a key continues only after
## MIN_SHOW seconds, like the results screen.

signal done

const MIN_SHOW := 1.2

var text := ""
var auto_seconds := 0.0
var run: BWRun
var report: Dictionary = {}       # the Giant fight's after_fight report, if any
var _sent := false
var _t := 0.0
var _prompt: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_fit()
	get_viewport().size_changed.connect(_fit)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	if run != null:
		_summary()
	else:
		var l := Label.new()
		l.text = text
		l.set_anchors_preset(Control.PRESET_FULL_RECT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 46)
		l.add_theme_color_override("font_color", Color.WHITE)
		add_child(l)
	if auto_seconds > 0.0:
		get_tree().create_timer(auto_seconds).timeout.connect(_finish)


# ---------------------------------------------------------------- run summary

func _summary() -> void:
	theme = BWStyle.theme()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_bottom = -40
	add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	center.add_child(v)
	var h := _label(text, 40, Color.WHITE)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(h)
	v.add_child(_gap(6))
	var box := PanelContainer.new()
	var sb := BWStyle.box_style()
	sb.content_margin_left = 36
	sb.content_margin_right = 36
	sb.content_margin_top = 18
	sb.content_margin_bottom = 22
	box.add_theme_stylebox_override("panel", sb)
	box.custom_minimum_size.x = 1480
	v.add_child(box)
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", 6)
	box.add_child(b)

	var st: Dictionary = run.stats
	var rec := "Won %d  ·  Lost %d" % [int(st.get("won", 0)), int(st.get("lost", 0))]
	if int(st.get("untracked", 0)) > 0:
		rec += "  ·  %d earlier fight%s not tracked" % [int(st.untracked), "" if int(st.untracked) == 1 else "s"]
	b.add_child(_section("The run"))
	var rl := _label(rec, BWStyle.F_SUB, BWStyle.TEXT)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_child(rl)
	b.add_child(_gap(4))
	b.add_child(_section("The squad"))
	b.add_child(_header())
	var units: Dictionary = st.get("units", {})
	var mvp := run_mvp(units)
	for u in run.squad:
		b.add_child(_row(u, units.get(u.id, {}), u.id == mvp))
	var best: Dictionary = st.get("best", {})
	if not best.is_empty():
		b.add_child(_gap(4))
		b.add_child(_section("Best moment of the run"))
		var bl := _label("%s  (fight %d)" % [best.text, int(best.fight)], BWStyle.F_BODY)
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_child(bl)
	var bs: Dictionary = report.get("stats", {})
	if not bs.is_empty() and str(bs.get("wrong", "")) != "" and not report.get("won", false):
		var wl := _label("Against the Giant: " + str(bs.wrong), BWStyle.F_SMALL, BWStyle.TEXT_DIM)
		wl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_child(wl)

	_prompt = _label("press any key", BWStyle.F_SMALL, BWStyle.TEXT_DIM)
	_prompt.anchor_top = 1.0
	_prompt.anchor_bottom = 1.0
	_prompt.anchor_right = 1.0
	_prompt.offset_top = -64
	_prompt.offset_bottom = -30
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.modulate.a = 0.0
	add_child(_prompt)


## The run's MVP: most battle MVPs, then most damage. "" if nobody fought.
static func run_mvp(units: Dictionary) -> String:
	var best := ""
	for id in units:
		var s: Dictionary = units[id]
		if int(s.get("fights", 0)) == 0:
			continue
		if best == "" or int(s.get("mvp", 0)) > int(units[best].get("mvp", 0)) \
				or (int(s.get("mvp", 0)) == int(units[best].get("mvp", 0)) and int(s.get("damage", 0)) > int(units[best].get("damage", 0))):
			best = id
	return best


const COLS := [["fights", "Fights"], ["kos", "KOs"], ["damage", "Damage"], ["mvp", "MVP"]]


func _header() -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 0)
	var pad := Control.new()
	pad.custom_minimum_size.x = 48 + 210
	hb.add_child(pad)
	for c in COLS:
		var l := _label(c[1], BWStyle.F_SMALL - 2, BWStyle.LABEL)
		l.custom_minimum_size.x = 84
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hb.add_child(l)
	var p := _label("Picks: perks · skills", BWStyle.F_SMALL - 2, BWStyle.LABEL)
	p.custom_minimum_size.x = 24
	hb.add_child(_gap_x(24))
	hb.add_child(p)
	return hb


func _row(u: BWUnit, s: Dictionary, is_mvp: bool) -> Control:
	var fought := int(s.get("fights", 0)) > 0
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 0)
	var icon := BWWidgets.Portrait.new(u, 36, false)
	icon.selected = is_mvp
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(icon)
	hb.add_child(_gap_x(12))
	var nr := HBoxContainer.new()
	nr.add_theme_constant_override("separation", 8)
	nr.custom_minimum_size.x = 210
	hb.add_child(nr)
	nr.add_child(_label(u.name, BWStyle.F_BODY, BWStyle.TEXT if fought else BWStyle.TEXT_DIM))
	if is_mvp:
		nr.add_child(BWResultsScreen.mvp_tag())
	for c in COLS:
		var n := int(s.get(c[0], 0))
		var l := _label(str(n), BWStyle.F_BODY if c[0] != "damage" else BWStyle.F_SUB, BWStyle.TEXT if n > 0 else BWStyle.FAINT)
		l.custom_minimum_size.x = 84
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hb.add_child(l)
	hb.add_child(_gap_x(24))
	var p := _label(picks_text(u), BWStyle.F_SMALL - 1, BWStyle.TEXT_DIM)
	p.custom_minimum_size.x = 760
	p.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(p)
	return hb


## "Perks: Flow State, Heat Rush  ·  Skills: Daggerleap+, Tumble"
## (skills learned beyond the starting kit, and any improved: "+").
static func picks_text(u: BWUnit) -> String:
	var perks: PackedStringArray = []
	for id in u.perks:
		perks.append(str(BWData.row("perks", id).get("name", id)))
	var skills: PackedStringArray = []
	for k in u.known_skills:
		skills.append(_sname(str(k)) + ("+" if u.skill_upgraded(str(k)) else ""))
	for k in u.skill_ranks:
		if int(u.skill_ranks[k]) >= 2 and not k in u.known_skills:
			skills.append(_sname(str(k)) + "+")
	var parts: PackedStringArray = []
	if not perks.is_empty():
		parts.append("Perks: " + ", ".join(perks))
	if not u.keystones.is_empty():                       # D278
		parts.append("Keystones: " + ", ".join(u.keystones.map(func(id): return BWKeystones.name_of(str(id)))))
	if not skills.is_empty():
		parts.append("Skills: " + ", ".join(skills))
	return "  ·  ".join(parts) if not parts.is_empty() else "—"


static func _sname(k: String) -> String:
	if BWWeaponMove.is_passive(k):                 # D372: HighGrounder
		return BWWeaponMove.passive_name(k)
	var row := BWSkills.get_skill(k)
	return str(row.get("name", k.capitalize())) if not row.is_empty() else k.capitalize()


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


func _gap_x(px: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size.x = px
	return c


func _section(t: String) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	for i in 3:
		if i == 1:
			hb.add_child(BWStyle.section_label(t))
		else:
			var s := HSeparator.new()
			s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			hb.add_child(s)
	return hb


func _process(delta: float) -> void:
	_t += delta
	if _prompt != null and _t >= MIN_SHOW:
		_prompt.modulate.a = 0.4 + 0.25 * sin((_t - MIN_SHOW) * 2.4)


func _unhandled_input(ev: InputEvent) -> void:
	if (ev is InputEventKey or ev is InputEventMouseButton) and ev.pressed:
		if run != null and _t < MIN_SHOW:
			return
		_finish()


func _finish() -> void:
	if not _sent:
		_sent = true
		done.emit()


## These screens are Controls under a plain Node (BWGame), so anchors have
## no parent rect to follow: size to the viewport ourselves, and keep it.
func _fit() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = get_viewport_rect().size
