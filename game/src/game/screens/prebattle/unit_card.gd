class_name BWUnitCard
extends PanelContainer
## A hover card for a unit on the pre-battle map (the enemies you face, or
## your own placed units), in the combat HUD's unit-card language
## (BWCombatUI._fill_card: frame weight, head icon, ticked HP bar, name,
## weapon · element, HP/Move/Speed, the seven stats) plus what the
## pre-battle needs: every piece of gear, its name in its element colour.

const W := 500.0

var unit: BWUnit
var _icon: BWWidgets.LivePortrait
var _bar: BWWidgets.HPBar
var _text: RichTextLabel


func _init() -> void:
	var sb := BWStyle.frame_style()
	sb.bg_color = Color(0.06, 0.06, 0.07, 0.98)     # over the map and panels: opaque
	add_theme_stylebox_override("panel", sb)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(W, 0)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(h)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(left)
	_icon = BWWidgets.LivePortrait.new(null, 92.0)
	left.add_child(_icon)
	_bar = BWWidgets.HPBar.new(Vector2(92, 11))
	left.add_child(_bar)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.custom_minimum_size = Vector2(W - 130, 0)
	h.add_child(_text)


func show_unit(u: BWUnit) -> void:
	unit = u
	var enemy := u.team == "enemy"
	_icon.set_unit(u)
	_bar.enemy = enemy
	_bar.set_hp(u.max_hp(), u.max_hp())
	var dim := BWGearText.hex(BWStyle.TEXT_DIM)
	var lab := BWGearText.hex(BWStyle.LABEL)
	var faint := BWGearText.hex(BWStyle.FAINT)
	var el := BWGearText.hex(BWGearText.readable(BWLook.element_color(u.element)))
	var lines: PackedStringArray = []
	lines.append("[font_size=%d][b]%s[/b][/font_size]  [color=#%s]%s · Lv %d[/color]" % [BWStyle.F_NAME - 4, u.name, dim,
		"enemy" if enemy else "yours", u.level])
	var wname := BWText.weapon(u.weapon_class)
	lines.append("[font_size=%d][color=#%s]%s (%s)   [/color][color=#%s]◆[/color] [color=#%s]%s[/color][/font_size]" % [
		BWStyle.F_SMALL, lab, wname, u.expertise_letter(u.weapon_class), BWGearText.hex(BWLook.element_color(u.element)), el,
		u.element.capitalize()])
	lines.append_array(BWCombatUI.badge_lines(u, BWStyle.F_SMALL))      # D129/D130: Disobedient, immunity, next battle
	lines.append("[font_size=%d]HP %d    Move %d    Speed %d[/font_size]" % [BWStyle.F_BODY, u.max_hp(), u.move_range(), u.speed()])
	var st: PackedStringArray = []
	for s in BWUnit.STATS:
		st.append("%s [b]%d[/b]" % [s.to_upper(), u.stat(s)])
	lines.append("[font_size=%d][color=#%s]%s\n%s[/color][/font_size]" % [BWStyle.F_SMALL, dim,
		"   ".join(st.slice(0, 4)), "   ".join(st.slice(4))])
	# affinities other than rank 0
	var aff: PackedStringArray = []
	for e in BWFormulas.ELEMENTS:
		var r := u.affinity_rank(e)
		if r > 0:
			aff.append("[color=#%s]◆ %s %d[/color]" % [BWGearText.hex(BWGearText.readable(BWLook.element_color(e))), e.capitalize(), r])
	if not aff.is_empty():
		lines.append("[font_size=%d][color=#%s]Affinity[/color]  %s[/font_size]" % [BWStyle.F_SMALL, faint, "  ".join(aff)])
	lines.append("[font_size=%d][color=#%s]GEAR[/color][/font_size]" % [BWStyle.F_MENU_TITLE - 2, faint])
	for slot in BWRun.SLOTS:
		var it: Dictionary = u.equipment.get(slot, {})
		var sl := str(BWGearText.SLOT_NAMES[slot])
		if it.is_empty():
			lines.append("[font_size=%d][color=#%s]%s   —[/color][/font_size]" % [BWStyle.F_SMALL, faint, sl])
			continue
		var stats: PackedStringArray = []
		for s in it.stats:
			stats.append("+%d %s" % [int(it.stats[s]), s.to_upper()])
		var p := BWGearText.passive_text(it)
		lines.append("[font_size=%d][color=#%s]%s[/color]   [b][color=#%s]%s[/color][/b] [color=#%s][%s]  %s[/color][/font_size]" % [
			BWStyle.F_SMALL, faint, sl, BWGearText.hex(BWGearText.readable(BWGearText.item_color(it))), BWGearText.plain_name(it),
			lab, str(it.tier), " ".join(stats)])
		if p != "":
			lines.append("[font_size=%d][color=#%s]      %s[/color][/font_size]" % [BWStyle.F_SMALL - 3, dim, p])
	_text.text = "\n".join(lines)
	reset_size()
