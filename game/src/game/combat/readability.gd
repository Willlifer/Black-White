class_name BWReadability
extends Node
## Combat readability (author: "explosions are very strong and I don't know
## what's going on most of the time"). One node on the combat screen,
## reading its state; the screen calls it from three marked hooks only
## (`played` at the top of _play, `beat` on a detonation / chain arc).
##
##   D160 blast preview  while an action is aimed (a skill's target hovered,
##                       an attackable foe hovered, or any confirm box open),
##                       BWBattle.simulate resolves it on a clone and
##                       BWBlastPreview draws every hex it changes, the arcs,
##                       and a damage tag over every unit it touches, red on
##                       friendlies. The confirm box gets the same in words.
##   D161 tile hover     any hex: a small card with its charge, marker and
##                       timer, glaze, static / seeded, terrain, what thunder
##                       would blast for, and the occupant's tile damage at
##                       its next turn. Terms hover (BWGlossary).
##   D162 recap          after an action with ground effects or 2+ damage
##                       sources, one line near the combat log ("Detonation:
##                       Kyla 31 · Bob 15 splash · arc → Rui 7") and the full
##                       detail in the log. Fades after RECAP_HOLD; in Minimal
##                       cutscene mode it stays until the next action.
##   D163 slow beat      a detonation or chain arc in playback: BEAT_SEC real
##                       seconds at BEAT_SCALE time with a small camera push
##                       toward it; Fast halves it, Minimal and hold-to-skip
##                       skip it. Once per action.

const RECAP_HOLD := 3.0
const BEAT_SEC := 0.5
const BEAT_SCALE := 0.3
const BEAT_PUSH := 0.86              # camera distance x this at the beat's peak
const BEAT_LEAN := 0.3               # the pivot leans this far toward the blast
const CARD_W := 380.0

var screen: BWCombatScreen
var preview: BWBlastPreview
var _root: Control
var _card: PanelContainer
var _card_text: RichTextLabel
var _card_hex := Vector2i(-99, -99)
var _card_at := -1
var _card_off := Vector2i(-99, -99)  # D171: dismissed (Esc, a click, the mouse leaving) until the hover moves on
var _recap: PanelContainer
var _recap_label: RichTextLabel
var _recap_tw: Tween
var _sig := ""
var _cheap := ""
var _cache := {}                     # action signature -> simulation (cleared each history step)
var _cache_at := -1
var _group: Array = []               # the events of the action now playing
var _beat_done := false
var _was_busy := false
var beats := 0                       # beats played (probes / review)
var last_recap := ""                 # the last recap line shown (probes / review)
var last_detail := ""


func setup(p_screen: BWCombatScreen) -> void:
	screen = p_screen
	preview = BWBlastPreview.new(screen.board_view)
	preview.obstacles = _unit_rects                 # ---- D171: tags keep off the HP bars
	screen.add_child(preview)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = BWStyle.theme()
	screen.ui.add_child(_root)
	_build_card()
	_build_recap()


## D171: every unit's HP bar, HP number and name on screen (the blast tags
## stay off them).
func _unit_rects() -> Array:
	var out: Array = []
	var cam: Camera3D = screen.cam if screen else null
	if cam == null:
		return out
	for id in screen._views:
		var v: BWUnitView = screen._views[id]
		if not is_instance_valid(v) or not v.is_visible_in_tree() or v._hp_label == null:
			continue
		var hp := BWBlastPreview.label_rect(cam, v._hp_label)
		var c := v._hp_label.global_position
		if not cam.is_position_behind(c):
			var half := cam.global_basis.x * (BWUnitView.BAR_W * v.scale.x * 0.5 + 0.02)
			var a := cam.unproject_position(c - half)
			var b := cam.unproject_position(c + half)
			var bar := Rect2(minf(a.x, b.x), minf(a.y, b.y), absf(b.x - a.x), absf(b.y - a.y)).grow_individual(0, 6, 0, 6)
			hp = bar.merge(hp) if hp.has_area() else bar
		out.append(hp)
		var nm := BWBlastPreview.label_rect(cam, v._label)
		if nm.has_area():
			out.append(nm)
	return out


func _exit_tree() -> void:
	if _root and is_instance_valid(_root):
		_root.queue_free()


# ---------------------------------------------------------------- polling

func _process(_delta: float) -> void:
	if screen == null or screen.battle == null:
		return
	var busy: bool = screen._busy
	if _was_busy and not busy:
		_flush()                                   # the action's playback is over
	_was_busy = busy
	_refresh_preview()
	_refresh_card()


## What is being aimed right now, as a simulate() action ({} = nothing).
func aimed_action() -> Dictionary:
	var s := screen
	var b := s.battle
	if s._busy or b.over or not s._player_turn():
		return {}
	var u := b.current()
	if s.ui.forecast_open():
		if s._pending_target != null:
			return { "kind": "attack", "target": s._pending_target.id }
		if not s._pending_skill.is_empty():
			var ps: Dictionary = s._pending_skill
			return { "kind": "skill", "key": ps.key, "element": ps.element, "hex": ps.hex,
				"choice": ps.get("choice", BWBattle.NOWHERE) }
		return {}
	var h: Vector2i = s._hover
	if not s._skill.is_empty():
		var sk: Dictionary = s._skill
		if sk.has("first"):
			if h in s._seconds(u):
				return { "kind": "skill", "key": sk.key, "element": sk.element, "hex": sk.first, "choice": h }
			return {}
		if str(sk.row.get("second_pick", "")) == "hex":
			return {}
		if h in b.skill_targets(u, sk.key, sk.element):
			return { "kind": "skill", "key": sk.key, "element": sk.element, "hex": h }
		return {}
	var t := b.unit_at(h)
	if t != null and b.can_harm(u, t) and t.team != u.team and (not u.acted or "basic" in u.follow_up) \
			and b.in_range(u, t):
		return { "kind": "attack", "target": t.id }
	return {}


func _refresh_preview() -> void:
	var s := screen
	# cheap state first: aimed_action() walks skill targets, so only when something moved
	var cheap := "%s|%s|%s|%s|%s|%s|%s|%d|%s" % [s._hover, s._skill.get("key", ""), s._skill.get("element", ""),
		s._skill.get("first", ""), var_to_str(s._pending_skill), s._pending_target.id if s._pending_target else "",
		s.ui.forecast_open(), s.battle.history.size(), s._busy]
	if cheap == _cheap:
		return
	_cheap = cheap
	var act := aimed_action()
	var sig := var_to_str(act) + "|%d|%s" % [s.battle.history.size(), s.ui.forecast_open()]
	if sig == _sig:
		return
	_sig = sig
	if act.is_empty():
		preview.clear()
		return
	var sim := simulate(act)
	preview.show_sim(sim, str(act.get("element", "")) if act.kind == "skill" else _basic_element())
	if screen.ui.forecast_open():
		screen.ui.forecast_extra(confirm_lines(sim))


## The simulation for an action, cached until the battle moves on.
func simulate(act: Dictionary) -> Dictionary:
	var b := screen.battle
	if _cache_at != b.history.size():
		_cache.clear()
		_cache_at = b.history.size()
	var key := var_to_str(act)
	if not _cache.has(key):
		_cache[key] = b.simulate(b.current(), act)
	return _cache[key]


func _basic_element() -> String:
	var u := screen.battle.current()
	if u and str(u.weapon().get("damage_type", "")) == "spell":
		return u.attuned
	return ""


## The confirm box's ground lines: what goes off, and every friendly hurt.
static func confirm_lines(sim: Dictionary) -> Array:
	var out: Array = []
	if sim.is_empty():
		return out
	for d in sim.detonations:
		out.append({ "text": "Detonation: %d%% blast here, half on the ring" % roundi(float(d.pct)), "warn": false })
	var kinds := {}
	for h in sim.hexes:
		for k in sim.hexes[h].kinds:
			kinds[k] = int(kinds.get(k, 0)) + 1
	if kinds.has("gale"):
		out.append({ "text": "Gale: copies onto %d hexes" % int(kinds.get("spread", 0)), "warn": false })
	if kinds.has("glaze"):
		out.append({ "text": "Glaze: %d hex%s locked" % [int(kinds.glaze), "" if int(kinds.glaze) == 1 else "es"], "warn": false })
	if kinds.has("ignite"):
		out.append({ "text": "Fire on grass: spreads at the cycle's end", "warn": false })
	for c in sim.chains:
		var nm := str(sim.units.get(c.to, {}).get("name", c.to))
		out.append({ "text": "Chain arc → %s %s" % [nm, BWBlastPreview.damage_text(int(c.amount), bool(c.approx))], "warn": bool(sim.units.get(c.to, {}).get("friendly", false)) })
	for id in sim.units:
		var r: Dictionary = sim.units[id]
		if r.friendly and int(r.damage) > 0:
			out.append({ "text": "Friendly fire: %s %s (%s)%s" % ["You" if r.self else r.name, BWBlastPreview.damage_text(int(r.damage), bool(r.approx)),
				BWBlastPreview._sources_text(r).get_slice("   ", 0), "  KO" if r.ko else ""], "warn": true })
	return out


# ---------------------------------------------------------------- D161 tile card

func _build_card() -> void:
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", BWStyle.hud_style())
	_card.mouse_filter = Control.MOUSE_FILTER_PASS
	_card.visible = false
	_root.add_child(_card)
	BWEsc.track(_card, dismiss_card, { "name": "tile card", "hover": true })     # ---- D171
	_card_text = BWGlossary.Rich.new()
	_card_text.fit_content = true
	_card_text.scroll_active = false
	_card_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_text.custom_minimum_size = Vector2(CARD_W, 0)
	_card_text.add_theme_font_size_override("normal_font_size", BWStyle.F_SMALL)
	_card_text.add_theme_font_size_override("bold_font_size", BWStyle.F_SMALL + 1)
	_card.add_child(_card_text)


func card_shown() -> bool:
	return _card.visible


func card_text() -> String:
	return _card_text.get_parsed_text() if _card.visible else ""


## D171: Esc (or a click, or the mouse leaving the window) hides the card
## until the hovered hex changes.
func dismiss_card() -> void:
	_card_off = screen._hover if screen else Vector2i(-99, -99)
	_card.visible = false
	_card_hex = Vector2i(-99, -99)


## D171: the card belongs to the board: not while the cursor is over a panel
## (the hover hex stops updating there, which left the card standing); the
## window's "mouse left" dismisses it through BWEsc.
func _cursor_on_board() -> bool:
	var vp := _root.get_viewport()
	var over: Control = vp.gui_get_hovered_control()
	return over == null or over == _card or _card.is_ancestor_of(over)


func _refresh_card() -> void:
	var s := screen
	var h: Vector2i = s._hover
	if _card_off != Vector2i(-99, -99) and h != _card_off:
		_card_off = Vector2i(-99, -99)
	var want: bool = not s._busy and not s.battle.over and s.battle.board.exists(h) \
		and not s.get_tree().paused and not s.ui._cine and not s.ui.forecast_open() and not preview.shown() \
		and h != _card_off and _cursor_on_board()
	if not want:
		_card.visible = false
		_card_hex = Vector2i(-99, -99)
		return
	if h == _card_hex and _card.visible and s.battle.history.size() == _card_at:
		_dock_card()
		return
	_card_hex = h
	_card_at = s.battle.history.size()
	_card_text.set_glossed(card_bbcode(s.battle, h))
	_card.visible = true
	_card.reset_size()
	_dock_card()


## Docked on the right, stacked on the bottom-right column (the hovered
## unit's card when it shows, else the combat log), so it never covers the
## hex it describes.
func _dock_card() -> void:
	var vp := _root.get_viewport_rect().size
	var sz := _card.get_combined_minimum_size()
	var top := vp.y - 196.0
	var hov: Control = screen.ui._hovered.panel
	if hov.visible:
		top = minf(top, hov.get_global_rect().position.y)
	var at := Vector2(vp.x - 16.0 - sz.x, top - 8.0 - sz.y).round()
	var menu: Control = screen.ui._menu
	if menu.visible and Rect2(at, sz).intersects(menu.get_global_rect().grow(6)):
		at = Vector2(16.0, vp.y - 276.0 - sz.y).round()     # the left column, over the hint line
	_card.position = at


static func _hx(c: Color) -> String:
	return BWGearText.readable(c).to_html(false)


## The hover card's text for one hex (BBCode; terms are linked by the label).
static func card_bbcode(b: BWBattle, h: Vector2i) -> String:
	var r := b.ground_report(h)
	var e: Dictionary = r.entry
	var lines: PackedStringArray = []
	var dim := BWStyle.TEXT_DIM.to_html(false)
	var head: PackedStringArray = []
	var hv := int(e.get("h", 0))
	var vv := int(e.get("v", 0))
	if hv != 0:
		var el := "fire" if hv > 0 else "water"
		head.append("[color=#%s]%s %d[/color]" % [_hx(BWLook.element_color(el)), el.capitalize(), absi(hv)])
	if vv != 0:
		var el2 := "light" if vv > 0 else "dark"
		head.append("[color=#%s]%s %d[/color]" % [_hx(BWLook.element_color(el2)), el2.capitalize(), absi(vv)])
	var mk := str(e.get("marker", ""))
	if mk != "":
		var mel := str(BWTiles.MARKER_ELEMENT.get(mk, ""))
		var lvl := " 2" if mk == "gale" and int(e.get("gale_level", 1)) > 1 else ""
		head.append("[color=#%s]%s%s[/color]" % [_hx(BWLook.element_color(mel)), mk.capitalize(), lvl])
	if head.is_empty():
		head.append("Bare ground")
	lines.append("[b]%s[/b]" % "  ·  ".join(head))
	lines.append("[color=#%s]%s ground · elevation %d[/color]" % [dim, str(r.terrain).capitalize(), int(r.elevation)])
	# timers
	var glaze := int(e.get("glaze", 0))
	if glaze > 0:
		lines.append("Glazed: %d cycle%s left, decay paused" % [glaze, "" if glaze == 1 else "s"])
	if mk != "":
		var what := { "fuse": "detonates the next fire, water, light or dark laid here",
			"stasis": "glazes the next charge laid here", "gale": "copies the next charge to its ring" }
		lines.append("%s mark: %s; fades in %d cycle%s" % [mk.capitalize(), what.get(mk, ""), int(e.timer), "" if int(e.timer) == 1 else "s"])
	elif (hv != 0 or vv != 0) and glaze == 0 and not bool(e.get("permanent", false)) and r.static == null:
		lines.append("Decay: steps down in %d cycle%s" % [int(e.timer), "" if int(e.timer) == 1 else "s"])
	if r.static != null:
		var sv: Vector2i = r.static
		lines.append("Static (%s): returns every cycle%s" % [_hv_words(sv.x, sv.y), "; spent, back after the next tick" if r.scarred else ""])
	if r.seeded:
		lines.append("Seeded: holds until play changes it")
	# what it does
	var does: PackedStringArray = []
	if int(r.move_extra) > 0:
		does.append("+%d move to enter" % int(r.move_extra))
	if absf(float(r.hit_mod)) > 0.01:
		does.append("%+d hit on attacks at it" % roundi(float(r.hit_mod)))
	if glaze > 0:
		does.append("Shatter +15% on hits here")
	if bool(r.conductive):
		does.append("conductive: half the damage taken here arcs to the nearest ally")
	if str(r.terrain) == BWBoard.GRASSY:
		does.append("grassy: fire 2+ spreads")
	elif str(r.terrain) == BWBoard.MUDDY:
		does.append("muddy: 2× move")
	if not does.is_empty():
		lines.append("[color=#%s]%s[/color]" % [dim, " · ".join(does)])
	if hv != 0 or vv != 0:
		var plan: Dictionary = b.tiles._route(e, "thunder", true, 1, "")
		if plan.has("detonate"):
			lines.append("[color=#%s]Thunder here: %d%% blast, half on the ring[/color]" % [_hx(BWLook.element_color("thunder")), roundi(float(plan.detonate))])
	# the occupant
	if str(r.unit) != "":
		var u := b._unit(str(r.unit))
		var t: Dictionary = r.turn
		if (t.lines as Array).is_empty():
			lines.append("%s: no tile damage next turn" % u.name)
		else:
			var parts: PackedStringArray = []
			for l in t.lines:
				parts.append("%s %s%d" % [l[0], "+" if int(l[1]) > 0 else "−", absi(int(l[1]))])
			var net := int(t.heal) - int(t.damage)
			var col := "#e05050" if net < 0 and u.team == "player" else "#ffffff"
			lines.append("[color=%s]%s next turn: %s%s[/color]" % [col, u.name, ", ".join(parts),
				"" if (t.lines as Array).size() < 2 else "  (net %+d)" % net])
	return "\n".join(lines)


static func _hv_words(h: int, v: int) -> String:
	var p: PackedStringArray = []
	if h != 0:
		p.append("%s %d" % ["fire" if h > 0 else "water", absi(h)])
	if v != 0:
		p.append("%s %d" % ["light" if v > 0 else "dark", absi(v)])
	return " + ".join(p)


# ---------------------------------------------------------------- D162 recap

func _build_recap() -> void:
	_recap = PanelContainer.new()
	_recap.add_theme_stylebox_override("panel", BWStyle.frame_style())
	_recap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_recap.visible = false
	BWEsc.track(_recap, _hide_recap, { "name": "recap" })                          # ---- D171
	_recap.anchor_top = 1.0
	_recap.anchor_bottom = 1.0
	_recap.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_recap.offset_bottom = -16
	_root.add_child(_recap)
	_recap_label = RichTextLabel.new()
	_recap_label.bbcode_enabled = true
	_recap_label.fit_content = true
	_recap_label.scroll_active = false
	_recap_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_recap_label.add_theme_font_size_override("normal_font_size", BWStyle.F_BODY)
	_recap_label.add_theme_font_size_override("bold_font_size", BWStyle.F_BODY)
	_recap_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_recap.add_child(_recap_label)


func recap_shown() -> bool:
	return _recap.visible and _recap.modulate.a > 0.05


const GROUP_STARTS := ["skill", "turn", "cycle", "pulse", "battle_end"]


## Hook: every event as the screen plays it (top of _play).
func played(e: Dictionary) -> void:
	var t := str(e.get("type", ""))
	var starts := t in GROUP_STARTS or (t == "attack" and int(e.get("strike", 0)) == 0 and not e.has("skill")) \
		or (t == "move" and str(e.get("kind", "")) == "")
	if starts and not _group.is_empty():
		_flush()
	if starts:
		_beat_done = false
		if str(BWSettings.value("cutscenes")) == "minimal" and t in ["skill", "attack"]:
			_hide_recap()                          # Minimal: the last recap stays until the next action
	_group.append(e)


func _flush() -> void:
	var g := _group
	_group = []
	if g.is_empty():
		return
	var rc := recap(g, screen.battle)
	if not rc.show:
		return
	last_recap = rc.line
	last_detail = rc.detail
	screen.ui.feed(rc.detail)
	_show_recap(rc.line)


## One action's events → { show, line, detail }. Shown when the action had
## ground effects (a detonation, an arc, a gale, a glaze, tile damage, an
## eruption) or two or more damage sources.
static func recap(g: Array, b: BWBattle) -> Dictionary:
	var name_of := func(id: String) -> String:
		var u := b._unit(id)
		return u.name if u else id
	var dets: Array = []
	var head := ""
	var direct: PackedStringArray = []
	var blast: PackedStringArray = []
	var splash: PackedStringArray = []
	var actor: BWUnit = null
	var other: PackedStringArray = []
	var detail: PackedStringArray = []
	var sources := 0
	var ground := false
	var totals := {}
	var add_total := func(id: String, n: int) -> void:
		totals[id] = int(totals.get(id, 0)) + n
	for e in g:
		match str(e.type):
			"skill":
				head = "%s · %s" % [name_of.call(str(e.unit)), str(BWSkills.get_skill(str(e.skill)).get("name", e.skill))]
				actor = b._unit(str(e.unit))
				for r in e.get("results", []):
					var res: Dictionary = r.result
					sources += 1
					direct.append(_hit_words(name_of.call(str(r.target)), res))
					add_total.call(str(r.target), int(res.damage))
			"attack", "counter":
				if head == "":
					head = "%s attacks" % name_of.call(str(e.unit))
					actor = b._unit(str(e.unit))
				var res2: Dictionary = e.result
				sources += 1
				var w := _hit_words(name_of.call(str(e.target)), res2)
				if e.type == "counter":
					w = "%s counters: %s" % [name_of.call(str(e.unit)), w]
				direct.append(w)
				add_total.call(str(e.target), int(res2.damage))
			"riposte":
				for r in e.get("results", []):
					sources += 1
					direct.append("%s ripostes: %s" % [name_of.call(str(e.unit)), _hit_words(name_of.call(str(r.target)), r.result)])
					add_total.call(str(r.target), int(r.result.damage))
			"detonate":
				ground = true
				if not e.get("echo", false):
					dets.append(e)
					detail.append("detonation %d%% at %s" % [roundi(float(e.pct)), str(e.hex)])
			"tile_damage":
				ground = true
				sources += 1
				var id := str(e.unit)
				add_total.call(id, int(e.amount))
				if str(e.cause) == "detonation":
					var u := b._unit(id)
					var at_blast := false
					for d in dets:
						if u and u.pos == d.hex:
							at_blast = true
					var ff := " (ally!)" if actor != null and u != null and u.team == actor.team else ""
					if at_blast:
						blast.append("%s %d%s" % [name_of.call(id), int(e.amount), ff])
					else:
						splash.append("%s %d splash%s" % [name_of.call(id), int(e.amount), ff])
				elif str(e.cause) != "pulse":
					other.append("%s %d %s" % [name_of.call(id), int(e.amount), str(e.cause).replace("_", " ")])
			"chain":
				ground = true
				sources += 1
				other.append("arc → %s %d" % [name_of.call(str(e.to)), int(e.amount)])
				add_total.call(str(e.to), int(e.amount))
			"paint":
				for gl in e.get("gales", []):
					ground = true
					other.append("gale ×%d" % (gl.copies as Array).size())
			"erupt":
				ground = true
				other.append("%s eruption" % str(e.element))
			"ko":
				other.append("%s KO" % name_of.call(str(e.unit)))
	var segs: PackedStringArray = []
	segs.append_array(direct)
	if not blast.is_empty() or not splash.is_empty():
		segs.append("Detonation: " + " · ".join(blast + splash))
	segs.append_array(other)
	var show := not segs.is_empty() and (ground or sources >= 2)
	var line := " · ".join(segs)
	if head != "":
		line = "%s: %s" % [head, line]
	var tot: PackedStringArray = []
	for id in totals:
		if int(totals[id]) > 0:
			tot.append("%s %d" % [name_of.call(id), int(totals[id])])
	var dl := "[b]Recap[/b] %s" % line
	if not detail.is_empty():
		dl += " [color=#9a9aa0](%s)[/color]" % ", ".join(detail)
	if tot.size() >= 2:
		dl += " · totals: " + ", ".join(tot)
	return { "show": show, "line": line, "detail": dl }


static func _hit_words(who: String, res: Dictionary) -> String:
	if not bool(res.get("hit", false)):
		return "%s miss" % who
	var tag := ""
	if bool(res.get("crit", false)):
		tag = " crit"
	elif bool(res.get("glance", false)):
		tag = " glance"
	elif bool(res.get("resisted", false)):
		tag = " resisted"
	return "%s %d%s" % [who, int(res.get("damage", 0)), tag]


func _show_recap(line: String) -> void:
	# bottom centre, between the acting card and the combat log; wraps when long
	var vp := _root.get_viewport_rect().size
	var right := vp.x - BWCombatUI.CARD_W - 32.0
	var room := right - (16.0 + BWCombatUI.CARD_W + 16.0)
	var font := _recap_label.get_theme_font("normal_font")
	var need := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, BWStyle.F_BODY).x + 8.0 if font else room
	var w := minf(need, room - 28.0)
	_recap_label.custom_minimum_size = Vector2(w, 0)
	_recap_label.text = "[b]%s[/b]" % line.get_slice(": ", 0) + (": " + line.substr(line.find(": ") + 2) if line.contains(": ") else "")
	_recap_label.text = _recap_label.text.replace("(ally!)", "[color=#ff5a5a](ally!)[/color]")
	_recap.offset_left = right - w - 28.0
	_recap.offset_right = right
	_recap.offset_top = -16
	_recap.visible = true
	if _recap_tw:
		_recap_tw.kill()
	_recap.modulate.a = 0.0
	_recap_tw = create_tween().set_ignore_time_scale(true)
	_recap_tw.tween_property(_recap, "modulate:a", 1.0, 0.15)
	if str(BWSettings.value("cutscenes")) == "minimal":
		return                                     # stays until the next action
	_recap_tw.tween_interval(RECAP_HOLD)
	_recap_tw.tween_property(_recap, "modulate:a", 0.0, 0.4)
	_recap_tw.tween_callback(func(): _recap.visible = false)


func _hide_recap() -> void:
	if _recap_tw:
		_recap_tw.kill()
	if _recap:
		_recap.visible = false


# ---------------------------------------------------------------- D163 slow beat

## Hook: a detonation or chain arc is on screen now. Slows time for a beat
## and leans the camera toward `hex`. Awaitable; returns at once when the
## mode or the skip hold says no, or when this action already had its beat.
func beat(hex: Vector2i) -> void:
	var mode := str(BWSettings.value("cutscenes"))
	if _beat_done or mode == "minimal" or screen.skipping or screen._freezing:
		return
	_beat_done = true
	beats += 1
	var dur := BEAT_SEC * (0.5 if mode == "fast" else 1.0)
	var rig := screen.rig
	var d0 := rig.dist
	var p0 := rig.pivot
	var target := screen.board_view.top_center(hex)
	Engine.time_scale = BEAT_SCALE
	rig.following = false
	var tw := create_tween().set_ignore_time_scale(true).set_parallel(true)
	tw.tween_property(rig, "dist", d0 * BEAT_PUSH, dur * 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(rig, "pivot", p0.lerp(target, BEAT_LEAN), dur * 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(dur * 1000.0):
		if screen.skipping or screen._freezing:
			break
		await get_tree().process_frame
	tw.kill()
	if not screen._freezing:
		Engine.time_scale = BWCombatScreen.SKIP_SCALE if screen.skipping else 1.0
	var back := create_tween().set_ignore_time_scale(true).set_parallel(true)
	back.tween_property(rig, "dist", d0, 0.3).set_trans(Tween.TRANS_SINE)
	rig.follow(p0)
