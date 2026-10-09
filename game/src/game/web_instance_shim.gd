class_name BWWebInstanceShim
extends Node
## D492: the browser build's stand-in for `instance uniform`.
##
## WebGL caps the global shader-variable buffer at 4096 slots and Godot's
## Compatibility renderer reserves 16 per object, so only ~256 objects get
## their instance uniforms; a battle has thousands (every hex layer, every body
## part), and the rest draw with garbage (no board, no hair colour). On web only,
## every geometry whose ShaderMaterial (or a next_pass) declares instance
## uniforms gets a private copy of that material whose shader declares them as
## plain uniforms, and each frame, just before drawing, the values the game set
## with set_instance_shader_parameter (still stored per instance by the server)
## and the original material's own uniforms are copied into it.
## Desktop never installs this; nothing else in the game changes.

static var _shaders := {}        # original Shader -> {shader: Shader, inst: Array, mat: Array} or {} (no instance uniforms)
var _tracked := {}               # GeometryInstance3D -> Array of slot entries (the ones we copied)
var _watch := {}                 # GeometryInstance3D -> its materials per slot when last wrapped
var _by_copy := {}               # our copy Material -> its slot entry


static func install(tree: SceneTree) -> void:
	var shim := BWWebInstanceShim.new()
	shim.name = "WebInstanceShim"
	shim.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child.call_deferred(shim)


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	RenderingServer.frame_pre_draw.connect(_sync)
	for n in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		_wrap(n as GeometryInstance3D)


func _on_node_added(n: Node) -> void:
	if n is GeometryInstance3D:
		_wrap(n as GeometryInstance3D)


# ---------------------------------------------------------------- shaders

## The web twin of a shader: `instance uniform` -> `uniform`, includes inlined.
static func _twin(sh: Shader) -> Dictionary:
	if sh == null:
		return {}
	if _shaders.has(sh):
		return _shaders[sh]
	var code := _inline(sh.code, 0)
	var info := {}
	if code.contains("instance uniform") or code.contains("instance  uniform"):
		var names := []
		var re_name := RegEx.create_from_string("instance\\s+uniform\\s+(?:(?:lowp|mediump|highp)\\s+)?\\w+\\s+(\\w+)")
		for m in re_name.search_all(code):
			names.append(m.get_string(1))
		code = RegEx.create_from_string(",\\s*instance_index\\s*\\(\\s*\\d+\\s*\\)").sub(code, "", true)
		code = RegEx.create_from_string(":\\s*instance_index\\s*\\(\\s*\\d+\\s*\\)").sub(code, "", true)
		code = RegEx.create_from_string("instance\\s+uniform").sub(code, "uniform", true)
		var twin := Shader.new()
		twin.code = code
		var mat_names := []
		for u in twin.get_shader_uniform_list():
			if not (u.name in names):
				mat_names.append(u.name)
		info = {shader = twin, inst = names, mat = mat_names}
	_shaders[sh] = info
	return info


static func _inline(code: String, depth: int) -> String:
	if depth > 8 or not code.contains("#include"):
		return code
	var re := RegEx.create_from_string("(?m)^\\s*#include\\s+\"([^\"]+)\"\\s*$")
	var out := code
	for m in re.search_all(code):
		var inc = load(m.get_string(1))
		var body := ""
		if inc is ShaderInclude:
			body = _inline((inc as ShaderInclude).code, depth + 1)
		out = out.replace(m.get_string(0), body)
	return out


## Does this material (or its next_pass chain) need a twin?
static func _needs(m: Material) -> bool:
	var d := 0
	while m != null and d < 8:
		if m is ShaderMaterial and not _twin((m as ShaderMaterial).shader).is_empty():
			return true
		m = m.next_pass
		d += 1
	return false


## A private copy of the chain; returns [copy, pairs] where pairs = [[orig, copy, info], ...].
static func _copy_chain(m: Material) -> Array:
	var pairs := []
	var head: Material = null
	var prev: Material = null
	var d := 0
	while m != null and d < 8:
		var c: Material = m.duplicate(false)
		if m is ShaderMaterial:
			var info := _twin((m as ShaderMaterial).shader)
			if not info.is_empty():
				(c as ShaderMaterial).shader = info.shader
				pairs.append([m, c, info])
		if prev == null:
			head = c
		else:
			prev.next_pass = c
		prev = c
		m = m.next_pass
		d += 1
	return [head, pairs]


# ---------------------------------------------------------------- nodes

## Slots: -1 = material_override, i >= 0 = surface i (override, else the mesh's).
func _slot_material(g: GeometryInstance3D, slot: int) -> Material:
	if slot < 0:
		return g.material_override
	var mi := g as MeshInstance3D
	var m := mi.get_surface_override_material(slot)
	if m == null and mi.mesh != null and slot < mi.mesh.get_surface_count():
		m = mi.mesh.surface_get_material(slot)
	return m


func _set_slot(g: GeometryInstance3D, slot: int, m: Material) -> void:
	if slot < 0:
		g.material_override = m
	else:
		(g as MeshInstance3D).set_surface_override_material(slot, m)


func _slots(g: GeometryInstance3D) -> Array:
	var slots := [-1]
	if g is MeshInstance3D and (g as MeshInstance3D).mesh != null:
		for i in (g as MeshInstance3D).mesh.get_surface_count():
			slots.append(i)
	return slots


## What the node draws with now, slot by slot (to notice the game swapping one).
func _signature(g: GeometryInstance3D) -> Array:
	var sig := []
	for slot in _slots(g):
		sig.append(_slot_material(g, slot))
	return sig


func _wrap(g: GeometryInstance3D) -> void:
	var entries := []
	for slot in _slots(g):
		var m := _slot_material(g, slot)
		if m == null:
			continue
		if _by_copy.has(m):
			# Already ours (node re-entered the tree): keep tracking the same copy.
			entries.append(_by_copy[m])
			continue
		if not _needs(m):
			continue
		var res := _copy_chain(m)
		var copy: Material = res[0]
		var pairs: Array = res[1]
		# What the game already set on this instance, before the swap drops it.
		for p in pairs:
			for nm in p[2].inst:
				var v = g.get_instance_shader_parameter(nm)
				if v != null:
					(p[1] as ShaderMaterial).set_shader_parameter(nm, v)
		var e := {slot = slot, copy = copy, pairs = pairs, cache = {}}
		_by_copy[copy] = e
		_set_slot(g, slot, copy)
		entries.append(e)
	_forget(g)
	if not entries.is_empty():
		_tracked[g] = entries
	_watch[g] = _signature(g)


func _forget(g) -> void:
	for e in _tracked.get(g, []):
		_by_copy.erase(e.copy)
	_tracked.erase(g)


func _sync() -> void:
	var dead := []
	var rewrap := []
	for g in _watch:
		if not is_instance_valid(g):
			dead.append(g)
		elif g.is_inside_tree() and _signature(g) != _watch[g]:
			rewrap.append(g)     # the game swapped a material: wrap the new one
	for g in dead:
		_forget(g)
		_watch.erase(g)
	for g in rewrap:
		_wrap(g)
	for g in _tracked:
		if not g.is_inside_tree():
			continue
		for e in _tracked[g]:
			var cache: Dictionary = e.cache
			var k := 0
			for p in e.pairs:
				var orig := p[0] as ShaderMaterial
				var c := p[1] as ShaderMaterial
				for nm in p[2].inst:
					var v = g.get_instance_shader_parameter(nm)
					if v == null:
						continue
					var key: String = str(k) + nm
					if cache.get(key) != v:
						cache[key] = v
						c.set_shader_parameter(nm, v)
				for nm in p[2].mat:
					var v = orig.get_shader_parameter(nm)
					var key: String = str(k) + "m" + nm
					if cache.get(key) != v:
						cache[key] = v
						c.set_shader_parameter(nm, v)
				k += 1
