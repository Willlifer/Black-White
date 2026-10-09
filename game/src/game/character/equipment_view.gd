class_name BWEquipmentView
extends Node
## Puts armour items (head / chest / legs) onto a BWCharacterRig.
##
##   var eq := BWEquipmentView.new()
##   rig.add_child(eq)              # or BWEquipmentView.for_rig(rig)
##   eq.equip(item)                 # item from BWRun.make_item(): base, slot, enchant
##   eq.unequip("head")
##
## Models come from tools/blender/build_equipment.py: one glb per armour id in
## res://art/equipment/, plus equipment_models.json (the manifest: attach
## type, socket, hair_mode, bones). Never hand-edit those.
##   attach "socket"  -> rigid, parented to its socket (socket_hat, socket_chest)
##   attach "skinned" -> the glb's MeshInstance3D moves under the rig's
##                       Skeleton3D and is rebound to it (named skin binds)
## Colour: every piece has two surfaces, `armour` (greyscale) and `accent`.
## The accent takes the element colour of the item's enchantment
## (BWRun.item_element), or neutral grey when there is none. One mesh per
## piece; the 7 "of <Element>" variants are only this tint.
## Hair: a head piece's hair_mode hides hair under socket_hair (see
## design/art/EQUIPMENT_MODELS.md for the contract with the hair lane).
## Needs only BWCharacterRig, BWLook, BWRun.item_element and the shaders.
## Shader instance slots follow the project rule (dim 0, tint 1); the accent
## colour is a per-material uniform, not an instance uniform.

const DIR := "res://art/equipment/"
const MANIFEST := DIR + "equipment_models.json"
const SHADER := "res://shaders/equipment.gdshader"
const SLOTS: PackedStringArray = ["head", "chest", "legs"]
const OUTLINE := 0.02          ## black hull around white armour (D42: black around white)
const NEUTRAL := Color(0.55, 0.55, 0.55)   ## accent on a plain (unenchanted) piece: BWLook.GREY_MID
const HAIR_MODES: PackedStringArray = ["show", "hide_top", "hide_all"]

var rig: BWCharacterRig
var _pieces := {}            # slot -> { node, base, element, info }

static var _manifest := {}
static var _materials := {}  # "armour" / "accent|<element>" -> ShaderMaterial


## Pieces live under the rig's own nodes (sockets, skeleton), so freeing the
## rig frees them too.
static func for_rig(r: BWCharacterRig) -> BWEquipmentView:
	var v := BWEquipmentView.new()
	v.name = "equipment"
	v.rig = r
	r.add_child(v)
	return v


func _enter_tree() -> void:
	if rig == null and get_parent() is BWCharacterRig:
		rig = get_parent()


# ------------------------------------------------------------ manifest

## Manifest row for an armour id ({} if it has no model).
static func info(base_id: String) -> Dictionary:
	if _manifest.is_empty():
		var j = load(MANIFEST)
		if j is JSON and j.data is Dictionary:
			_manifest = j.data
		else:
			push_error("BWEquipmentView: cannot read %s (run build_equipment.py, then --import)" % MANIFEST)
			_manifest = { "pieces": {} }
	return _manifest.get("pieces", {}).get(base_id, {})


static func model_ids() -> PackedStringArray:
	info("")
	var out := PackedStringArray(_manifest.get("pieces", {}).keys())
	out.sort()
	return out


static func model_path(base_id: String) -> String:
	return DIR + base_id + ".glb"


static func has_model(base_id: String) -> bool:
	return not info(base_id).is_empty() and ResourceLoader.exists(model_path(base_id))


# --------------------------------------------------------------- colour

## The accent colour for an element id ("" = plain piece, neutral grey).
static func accent_color(element: String) -> Color:
	if element == "":
		return NEUTRAL
	return BWLook.element_color(element)


static func material_for(surface: String, element: String = "") -> ShaderMaterial:
	var key := surface if surface != "accent" else "accent|" + element
	if _materials.has(key):
		return _materials[key]
	var m := ShaderMaterial.new()
	m.shader = load(SHADER)
	m.set_shader_parameter("paint", accent_color(element) if surface == "accent" else Color.WHITE)
	m.next_pass = BWLook.outline(OUTLINE, Color.BLACK)
	m.resource_name = "bw_equip_" + key
	_materials[key] = m
	return m


# ---------------------------------------------------------------- equip

## Build a piece's node tree for an armour id, materials applied, not yet
## attached. Element "" = plain. Returns null if there is no model.
static func instantiate(base_id: String, element: String = "") -> Node3D:
	var row := info(base_id)
	if row.is_empty():
		push_error("BWEquipmentView: no model for '%s'" % base_id)
		return null
	var scene := load(model_path(base_id)) as PackedScene
	if scene == null:
		push_error("BWEquipmentView: cannot load %s (run --import?)" % model_path(base_id))
		return null
	var root := scene.instantiate() as Node3D
	root.name = "equip_" + str(row.slot)
	root.set_meta("equip_base", base_id)
	for mi in meshes_of(root):
		paint(mi, element)
	return root


## Equip an item Dictionary (BWRun.make_item). Replaces whatever is in that
## slot. Returns the attached node (a socket child, or the rebound
## MeshInstance3D under the skeleton), or null on error.
func equip(item: Dictionary) -> Node3D:
	var base := str(item.get("base", ""))
	var row := info(base)
	if row.is_empty():
		push_error("BWEquipmentView: '%s' has no armour model" % base)
		return null
	var slot := str(item.get("slot", row.slot))
	if slot != str(row.slot) or not slot in SLOTS:
		push_error("BWEquipmentView: %s is a %s piece, not %s" % [base, row.slot, slot])
		return null
	return equip_model(base, BWRun.item_element(item))


## Equip by armour id and element ("" = plain). Used by equip() and by tools.
func equip_model(base_id: String, element: String = "") -> Node3D:
	if rig == null or (rig.model == null and not rig.build()):
		push_error("BWEquipmentView: no rig to equip onto")
		return null
	var row := info(base_id)
	var root := instantiate(base_id, element)
	if root == null:
		return null
	var slot := str(row.slot)
	unequip(slot)
	var node: Node3D
	if row.attach == "socket":
		if not rig.attach(root, str(row.socket)):
			root.free()
			return null
		node = root
	else:
		node = _rebind(root, slot)
		if node == null:
			return null
	node.set_meta("equip_base", base_id)
	node.set_meta("equip_element", element)
	_pieces[slot] = { "node": node, "base": base_id, "element": element, "info": row }
	refresh_hair()
	return node


func unequip(slot: String) -> void:
	if not _pieces.has(slot):
		return
	var n: Node = _pieces[slot].node
	_pieces.erase(slot)
	if is_instance_valid(n):
		if n.get_parent():
			n.get_parent().remove_child(n)
		n.free()
	refresh_hair()


func clear() -> void:
	for s in _pieces.keys():
		unequip(s)


func piece(slot: String) -> Node3D:
	return _pieces[slot].node if _pieces.has(slot) else null


func equipped() -> Dictionary:
	var out := {}
	for s in _pieces:
		out[s] = _pieces[s].base
	return out


## Retint one slot's accent (e.g. after re-imbuing) without rebuilding it.
func set_element(slot: String, element: String) -> void:
	if not _pieces.has(slot):
		return
	_pieces[slot].element = element
	_pieces[slot].node.set_meta("equip_element", element)
	for mi in meshes_of(_pieces[slot].node):
		paint(mi, element)


# ----------------------------------------------------------------- hair

## D228 (L-4): the equipment data's `hides_hair` flag decides, per item:
## all = hide_all (full cover: full helm, dragoon helm), top = hide_top (hair
## that fits under the brim shows), none = show (tiara, crown). A row without
## the flag falls back to the model manifest's hair_mode.
const HIDES_HAIR := { "all": "hide_all", "top": "hide_top", "none": "show" }


static func piece_hair_mode(base_id: String) -> String:
	if BWData.has_table("equipment"):
		var flag := str(BWData.row("equipment", base_id).get("hides_hair", "")).strip_edges()
		if HIDES_HAIR.has(flag):
			return HIDES_HAIR[flag]
	var m := str(info(base_id).get("hair_mode", ""))
	return m if m in HAIR_MODES else "show"


## D490: headgear never hides hair any more (the author: "show them even if
## they clip through the hats"); hair is the element's colour, so it must read.
## Set false to bring back the D228 per-item hiding below.
const HATS_SHOW_HAIR := true


## The strictest hair_mode among equipped pieces: show < hide_top < hide_all.
func hair_mode() -> String:
	if HATS_SHOW_HAIR:
		return "show"
	var best := 0
	for s in _pieces:
		best = maxi(best, HAIR_MODES.find(piece_hair_mode(str(_pieces[s].base))))
	return HAIR_MODES[best]


## How far above the crown (2.20) the hat leaves room for hair under
## hide_top (manifest `hair_clearance`); 0 when no head piece is worn.
func hair_clearance() -> float:
	var c := INF
	for s in _pieces:
		if piece_hair_mode(str(_pieces[s].base)) == "hide_top":
			c = minf(c, float(_pieces[s].info.get("hair_clearance", 0.0)))
	return c


## Apply hair_mode to everything under socket_hair. Hair is hidden (never
## deleted, RIG.md) when:
##   hide_all  always (full helms)
##   hide_top  its crown rises above the hat's hair_clearance (a mohawk under
##             a cap); hair that fits stays visible below the brim
##   show      never (tiara, crown)
## A hair node may also implement set_hair_mode(mode) to trim itself; it is
## called with the mode either way. Call again after attaching new hair.
func refresh_hair() -> void:
	if rig == null:
		return
	var s := rig.socket("hair")
	if s == null:
		return
	var mode := hair_mode()
	var room := hair_clearance()
	for h in s.get_children():
		if h is Node3D:
			var show := mode == "show" or (mode == "hide_top" and hair_rise(h) <= room)
			(h as Node3D).visible = show
		if h.has_method("set_hair_mode"):
			h.call("set_hair_mode", mode)


## Height of a hair node's crown above the head top, in socket_hair space:
## the highest vertex within 0.22 of the head axis (tails and side locks
## don't count). Cached per mesh.
static var _rise_cache := {}
static func hair_rise(hair: Node3D) -> float:
	var best := -INF
	for mi: MeshInstance3D in meshes_of(hair):
		var key := mi.mesh.get_rid().get_id()
		var r: float
		if _rise_cache.has(key):
			r = _rise_cache[key]
		else:
			r = -INF
			var xf := _relative(mi, hair)
			for i in mi.mesh.get_surface_count():
				for p: Vector3 in mi.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
					var q := xf * p
					if Vector2(q.x, q.z).length() < 0.22:
						r = maxf(r, q.y)
			_rise_cache[key] = r
		best = maxf(best, r)
	return best - (BWCharacterRig.HEIGHT - 1.92)


static func _relative(n: Node3D, ancestor: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c: Node = n
	while c != null and c != ancestor:
		if c is Node3D:
			t = (c as Node3D).transform * t
		c = c.get_parent()
	return t


# -------------------------------------------------------------- helpers

static func meshes_of(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	out.append_array(n.find_children("*", "MeshInstance3D", true, false))
	return out


## Surface role from the glb's material name: "accent" or "armour".
static func surface_role(mesh: Mesh, i: int) -> String:
	var mat := mesh.surface_get_material(i)
	var n := mat.resource_name if mat else ""
	if n == "" and mesh is ArrayMesh:
		n = (mesh as ArrayMesh).surface_get_name(i)
	return "accent" if n.begins_with("accent") else "armour"


static func paint(mi: MeshInstance3D, element: String) -> void:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in mi.mesh.get_surface_count():
		var role := surface_role(mi.mesh, i)
		mi.set_surface_override_material(i, material_for(role, element))


## Move a skinned piece's mesh under the rig's skeleton and bind it there.
## The glb carries its own copy of the 20 bones; the skin binds by bone
## name, so pointing the mesh at the rig's Skeleton3D is the whole rebind.
func _rebind(root: Node3D, slot: String) -> MeshInstance3D:
	var mis := meshes_of(root)
	if mis.is_empty():
		push_error("BWEquipmentView: no mesh in %s" % root.name)
		root.free()
		return null
	var mi: MeshInstance3D = mis[0]
	var skin := mi.skin
	if skin == null:
		push_error("BWEquipmentView: %s has no skin" % root.name)
		root.free()
		return null
	for b in skin.get_bind_count():
		var bn := str(skin.get_bind_name(b))
		if rig.skeleton.find_bone(bn) < 0:
			push_error("BWEquipmentView: bone '%s' of %s is not on the rig" % [bn, root.name])
			root.free()
			return null
	mi.get_parent().remove_child(mi)
	mi.owner = null
	root.free()
	mi.name = "equip_" + slot
	rig.skeleton.add_child(mi)
	mi.transform = Transform3D.IDENTITY
	mi.skin = skin
	mi.skeleton = NodePath("..")
	return mi
