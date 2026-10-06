class_name BWSkillRegistry
## Every weapon skill, one BWSkillDef per file in res://src/core/skill_defs/,
## loaded once on first use. Adding a skill = adding a file (and a test).
##
##   get_def(key)       the def (null if unknown)
##   row(key)           its data row (what BWSkills.get_skill returns)
##   for_class(wc)      every def of a weapon class, menu order
##   pool(wc)           keys a unit of that class can learn (no follow-up halves)
##   starter(wc)        the class's starting skills: weapons.csv `skills`, else the pool
##   expand(keys)       keys plus the follow-up halves they grant, in kit order
##   kit_for(u)         the rows a unit fights with: its loadout for the weapon
##                      it holds (BWUnit.skill_loadout), else the starter kit

const DIR := "res://src/core/skill_defs/"

static var _defs := {}          # key -> BWSkillDef
static var _keys: Array = []    # every key, class then order


static func _ensure() -> void:
	if not _keys.is_empty():
		return
	var files := Array(DirAccess.get_files_at(DIR))
	var seen := {}
	var found: Array = []
	for f in files:
		var n := str(f).trim_suffix(".remap")       # exported builds
		if n.ends_with(".gdc"):
			n = n.trim_suffix("c")
		if not n.ends_with(".gd") or seen.has(n):
			continue
		seen[n] = true
		var script: Script = load(DIR + n)
		if script == null or not script.can_instantiate():
			push_error("BWSkillRegistry: %s failed to load" % n)
			continue
		var d: Variant = script.new()
		if not d is BWSkillDef or (d as BWSkillDef).id == "":
			push_error("BWSkillRegistry: %s is not a BWSkillDef with a key" % n)
			continue
		if _defs.has(d.id):
			push_error("BWSkillRegistry: duplicate skill key '%s' (%s)" % [d.id, n])
			continue
		_defs[d.id] = d
		found.append(d)
	found.sort_custom(func(a: BWSkillDef, b: BWSkillDef) -> bool:
		return a.order < b.order if a.order != b.order else a.id < b.id)
	_keys = found.map(func(d): return d.id)


## Add a def built in code (tests; a mod). Replaces nothing: false if taken.
static func register(d: BWSkillDef) -> bool:
	_ensure()
	if d == null or d.id == "" or _defs.has(d.id):
		return false
	_defs[d.id] = d
	_keys.append(d.id)
	_keys.sort_custom(func(a: String, b: String) -> bool:
		var da: BWSkillDef = _defs[a]
		var db: BWSkillDef = _defs[b]
		return da.order < db.order if da.order != db.order else a < b)
	return true


static func unregister(key: String) -> void:
	_ensure()
	_defs.erase(key)
	_keys.erase(key)


static func get_def(key: String) -> BWSkillDef:
	_ensure()
	return _defs.get(key, null)


static func has(key: String) -> bool:
	_ensure()
	return _defs.has(key)


static func row(key: String) -> Dictionary:
	var d := get_def(key)
	return d.data if d != null else {}


static func keys() -> Array:
	_ensure()
	return _keys.duplicate()


static func for_class(weapon_class: String) -> Array:
	_ensure()
	var out: Array = []
	for k in _keys:
		if str(_defs[k].data.get("weapon", "")) == weapon_class:
			out.append(_defs[k])
	return out


## Learnable keys of a class (follow-up halves ride along with their skill).
static func pool(weapon_class: String) -> Array:
	return for_class(weapon_class).filter(func(d): return not d.data.get("follow_up_only", false)).map(func(d): return d.id)


## The class's starting skills. weapons.csv `skills` is the contract when
## filled in; a blank cell falls back to the whole pool.
static func starter(weapon_class: String) -> Array:
	var cell := str(BWData.row("weapons", weapon_class).get("skills", "")).strip_edges()
	if cell == "":
		return pool(weapon_class)
	var out: Array = []
	for k in cell.split("|", false):
		k = k.strip_edges()
		if has(k) and not k in out:
			out.append(k)
	return out


## Keys plus the follow-up halves each grants, right after it (kit order).
static func expand(keys_in: Array) -> Array:
	var out: Array = []
	for k in keys_in:
		if not has(k) or k in out:
			continue
		out.append(k)
		for f in row(k).get("follow_up", []):
			if f != "basic" and has(f) and not f in out:
				out.append(f)
	return out


## The rows a unit fights with right now.
static func kit_for(u: BWUnit) -> Array:
	return expand(u.loadout(u.weapon_class)).map(func(k): return row(k))


## The cutscene pose for a skill ("" = unknown).
static func clip(key: String) -> String:
	return str(row(key).get("clip", ""))
