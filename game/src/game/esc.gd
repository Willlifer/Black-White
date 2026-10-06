class_name BWEsc
extends Node
## D171: one stack of everything Esc can close (author: "when you press
## escape it should close the latest open window, had an issue a couple
## times where I couldn't close a small tooltip").
##
## Every closable thing registers when it opens and leaves when it closes:
##     BWEsc.push(owner, close_callable, { "name": "codex" })
##     BWEsc.track(control, close_callable, opts)   # follows its visibility
##     BWEsc.remove(owner)
## Esc closes the topmost entry. A `mandatory` entry (a pick that is owed)
## is never closed: Esc calls its `nudge` instead ("choose one"). Only when
## the stack is empty does Esc reach the screens' own handlers (combat:
## forecast → aim → undo the move → pause menu, D124).
##
## A `hover` entry (a tooltip or hover card) also closes when the mouse
## leaves the window or clicks outside it. Native tooltips (any control's
## tooltip_text, not only the glossary's) are swept first on Esc, the mouse
## leaving and a click: they are always the newest thing on screen.
##
## The stack itself is pure (static, no nodes needed: tests/test_esc_d171.gd).
## The router is one node (`BWEsc.ensure(host)`, PROCESS_MODE_ALWAYS) whose
## _input sees Esc before every _unhandled_input and GUI handler.

static var _stack: Array = []        # [{ id, close, mandatory, nudge, hover, name }]
static var _inst: BWEsc
static var log_closed: Array = []    # names closed by Esc, newest last (probes)
## The cursor in root-viewport coordinates, from the last mouse event the
## router saw (real or synthetic, so the probes drive it too).
static var mouse := Vector2(-1, -1)
## The input probes drive a synthetic cursor while the real one may sit
## outside the window: the OS "mouse left" is ignored then.
static var synthetic := false


# ---------------------------------------------------------------- the stack

## Register `owner` (any Object) on top. Pushing it again moves it to the top.
## opts: name (String), mandatory (bool), nudge (Callable), hover (bool).
static func push(owner: Object, close: Callable, opts: Dictionary = {}) -> void:
	if owner == null:
		return
	remove(owner)
	_stack.append({
		"id": owner.get_instance_id(), "close": close,
		"mandatory": bool(opts.get("mandatory", false)), "nudge": opts.get("nudge", Callable()),
		"hover": bool(opts.get("hover", false)), "name": str(opts.get("name", owner.get_class())),
	})


static func remove(owner: Object) -> void:
	if owner == null:
		return
	var id := owner.get_instance_id()
	_stack = _stack.filter(func(e): return e.id != id)


## Follow a control's (or CanvasLayer's) visibility: on top when it shows,
## gone when it hides or leaves the tree.
static func track(c: Node, close: Callable, opts: Dictionary = {}) -> void:
	var sync := func() -> void:
		if not is_instance_valid(c):
			return
		if _shown(c):
			if not has(c):
				push(c, close, opts)
		else:
			remove(c)
	c.connect("visibility_changed", sync)
	c.tree_exiting.connect(func(): remove(c))
	c.tree_entered.connect(sync)
	if c.is_inside_tree() and _shown(c):
		push(c, close, opts)


static func has(owner: Object) -> bool:
	if owner == null:
		return false
	var id := owner.get_instance_id()
	return _stack.any(func(e): return e.id == id)


static func size() -> int:
	_prune()
	return _stack.size()


static func names() -> Array:
	_prune()
	return _stack.map(func(e): return e.name)


static func top_name() -> String:
	_prune()
	return "" if _stack.is_empty() else str(_stack.back().name)


static func clear() -> void:
	_stack.clear()


static func _shown(n: Object) -> bool:
	if n is CanvasItem:
		return (n as CanvasItem).is_visible_in_tree()
	if n is CanvasLayer:
		return (n as CanvasLayer).visible
	return true


## Drop entries whose owner is gone, out of the tree, or hidden (a card
## hidden by its screen without telling anyone). Nodes register once they
## are in the tree; the pure tests register plain objects.
static func _prune() -> void:
	_stack = _stack.filter(func(e):
		var o := instance_from_id(e.id)
		if o == null or not is_instance_valid(o):
			return false
		if o is Node:
			return (o as Node).is_inside_tree() and not (o as Node).is_queued_for_deletion() and _shown(o)
		return true)


## Esc: close the topmost entry. "closed:<name>", "nudged:<name>", or ""
## when there was nothing to close (the screen's own Esc runs then).
static func escape() -> String:
	if _sweep_tooltips(false):                     # a plain tooltip (not on the stack) is the newest thing
		log_closed.append("tooltip")
		return "closed:tooltip"
	_prune()
	if _stack.is_empty():
		return ""
	var e: Dictionary = _stack.back()
	if e.mandatory:
		if (e.nudge as Callable).is_valid():
			(e.nudge as Callable).call()
		return "nudged:" + str(e.name)
	_stack.pop_back()
	log_closed.append(str(e.name))
	if (e.close as Callable).is_valid():
		(e.close as Callable).call()
	return "closed:" + str(e.name)


## Close every hover entry (the mouse left the window); with `at`, only the
## ones whose owner control doesn't contain that point (a click elsewhere).
static func close_hovers(at: Variant = null) -> int:
	_prune()
	var n := 0
	for e in _stack.duplicate():
		if not e.hover:
			continue
		var o := instance_from_id(e.id)
		if at != null and o is Control and (o as Control).get_global_rect().has_point(at):
			continue
		_stack.erase(e)
		n += 1
		if (e.close as Callable).is_valid():
			(e.close as Callable).call()
	return n


# ---------------------------------------------------------------- native tooltips

## Godot's tooltip popups (a PopupPanel of theme type TooltipPanel, an
## internal child of the hovered control) for any control's tooltip_text or
## _make_custom_tooltip. Walked only on Esc, a click or the mouse leaving.
static func _tooltips() -> Array:
	var out: Array = []
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return out
	_find_tips(tree.root, out)
	return out


static func _find_tips(n: Node, out: Array) -> void:
	for c in n.get_children(true):
		if c is PopupPanel and (c as Window).theme_type_variation == &"TooltipPanel":
			if (c as Window).visible:
				out.append(c)
			continue
		_find_tips(c, out)


## Hide tooltip popups. `registered` false: only the ones with no stack
## entry (a plain tooltip_text); a glossary card waits for its turn on the
## stack (it may sit under a codex opened after it).
static func _sweep_tooltips(registered: bool = true) -> bool:
	var n := 0
	for w in _tooltips():
		var mine: Array = _stack.filter(func(e):
			var o := instance_from_id(e.id)
			return o is Node and (w as Node).is_ancestor_of(o))
		if not registered and not mine.is_empty():
			continue
		for e in mine:
			_stack.erase(e)
		(w as Window).hide()
		n += 1
	return n > 0


## Every tooltip off the screen (the mouse left the window; probes).
static func close_tooltips() -> bool:
	return _sweep_tooltips(true)


static func tooltip_open() -> bool:
	return not _tooltips().is_empty()


## The glossary's tooltip card: close = hide its popup (the viewport frees it).
static func close_tooltip_of(c: Control) -> void:
	if not is_instance_valid(c):
		return
	var w := c.get_parent()
	if w is Window:
		(w as Window).hide()


# ---------------------------------------------------------------- the router

## Whether a router is listening (the review tools run without one: the
## overlays then close themselves on Esc, as before D171).
static func routed() -> bool:
	return _inst != null and is_instance_valid(_inst) and _inst.is_inside_tree()


static func ensure(host: Node) -> void:
	if _inst and is_instance_valid(_inst):
		return
	_inst = BWEsc.new()
	_inst.name = "BWEsc"
	host.add_child(_inst)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var w := get_window()
	if w and not w.mouse_exited.is_connected(_on_mouse_left):
		w.mouse_exited.connect(_on_mouse_left)


func _exit_tree() -> void:
	if _inst == self:
		_inst = null


## The watchdog: a tooltip whose control the cursor has left, which was
## hidden or freed, or under a drag, goes now, whatever Godot's own tooltip
## timer thinks (the pre-battle gear panel left one standing: its tiles and
## card are rebuilt under the cursor on an equip). Glossary cards every
## frame; plain tooltip_text popups by a tree walk, a few times a second
## and only after the mouse moved.
var _walk_t := 0.0
var _last_mouse := Vector2(-1, -1)


func _process(delta: float) -> void:
	var dragging := get_viewport().gui_is_dragging()
	for e in BWEsc._stack.duplicate():
		if str(e.name) != "tooltip":
			continue
		var o := instance_from_id(e.id)
		if o is Control and (o as Control).is_inside_tree() and BWEsc.tooltip_stale(o as Control, dragging):
			BWEsc._stack.erase(e)
			BWEsc.close_tooltip_of(o as Control)
	_walk_t += delta
	if _walk_t >= 0.25 and (mouse != _last_mouse or dragging):
		_walk_t = 0.0
		_last_mouse = mouse
		for w in BWEsc._tooltips():
			var host := (w as Node).get_parent()
			if not (host is Control) or BWEsc.tooltip_stale_host(host as Control, dragging):
				(w as Window).hide()


## The control showing a glossary card (its popup's parent) no longer has
## the cursor, is hidden or gone, or a drag is on.
static func tooltip_stale(card: Control, dragging: bool) -> bool:
	var w := card.get_parent()
	if not (w is Window) or not (w as Window).visible:
		return false
	var host := w.get_parent()
	return not (host is Control) or tooltip_stale_host(host as Control, dragging)


static func tooltip_stale_host(host: Control, dragging: bool) -> bool:
	if dragging or not is_instance_valid(host) or not host.is_inside_tree() or host.is_queued_for_deletion()  or not host.is_visible_in_tree():
		return true
	var r := host.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, host.size)
	return not r.grow(2.0).has_point(mouse)


func _on_mouse_left() -> void:
	if synthetic:
		return
	BWEsc.close_tooltips()
	BWEsc.close_hovers()


func _input(ev: InputEvent) -> void:
	if ev is InputEventMouse:
		mouse = (ev as InputEventMouse).position     # the GUI's own coordinates (what it hit-tests with)
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_ESCAPE:
		if BWEsc.escape() != "":
			get_viewport().set_input_as_handled()
	elif ev is InputEventMouseButton and ev.pressed:
		BWEsc.close_hovers((ev as InputEventMouseButton).position)
