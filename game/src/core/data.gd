class_name BWData
## Reads the CSV tables in res://data/ (design/SCHEMA.md is the contract).
##
## Every table loads as an Array of row Dictionaries keyed by header, plus an
## index by `id`. Cells that look like numbers become numbers; `|` lists stay
## strings — call list() on them. Results are cached per path; clear_cache()
## exists for tests and hot-reload.

const DATA_DIR := "res://data/"

static var _cache := {}
static var errors: PackedStringArray = []
## D150: roster.csv holds the 20 identities; table("roster") / row("roster")
## answer from the active roll (BWRosterGen.roll), BWRosterGen.DEFAULT_SEED
## unless use_roster() set another. A run keeps its own rows (BWRun.roster_rows).
static var _roster: Array = []
static var _roster_by_id := {}
static var roster_seed := -1


static func table(name: String) -> Array:
	if name == "roster":
		return roster()
	return _raw(name)


## The 20 core identity rows of roster.csv (fixed facets only), in seat order.
## D379: the csv also holds the rolling POOL (`pool` 1): pool_identities().
static func identities() -> Array:
	return _raw("roster").filter(func(r): return int(r.get("pool", 0)) == 0)


## D379: the pool identities (`pool` 1) that rotate into the back row on a
## Randomize and fill the enemy side.
static func pool_identities() -> Array:
	return _raw("roster").filter(func(r): return int(r.get("pool", 0)) == 1)


## D379: every identity, core and pool.
static func all_identities() -> Array:
	return _raw("roster")


## The active rolled roster (BWRosterGen.roll of identities()).
static func roster() -> Array:
	if roster_seed < 0:
		use_roster(BWRosterGen.roll(identities(), BWRosterGen.DEFAULT_SEED), BWRosterGen.DEFAULT_SEED)
	return _roster


## Make `rows` (a BWRosterGen.roll result) the active roster.
static func use_roster(rows: Array, p_seed: int) -> void:
	_roster = rows
	roster_seed = p_seed
	_roster_by_id.clear()
	for r in rows:
		_roster_by_id[str(r.id)] = r


static func _raw(name: String) -> Array:
	var path := DATA_DIR + name + ".csv"
	if _cache.has(path):
		return _cache[path].rows
	var rows: Array = []
	var by_id := {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_err("missing table %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		_cache[path] = { "rows": rows, "by_id": by_id }
		return rows
	var header := f.get_csv_line()
	var line_no := 1
	while not f.eof_reached():
		var cells := f.get_csv_line()
		line_no += 1
		if cells.size() == 1 and cells[0].strip_edges() == "":
			continue
		if cells.size() != header.size():
			_err("%s:%d has %d cells, header has %d" % [path, line_no, cells.size(), header.size()])
			continue
		var row := {}
		for i in header.size():
			row[header[i].strip_edges()] = _coerce(cells[i])
		rows.append(row)
		if row.has("id"):
			var id := str(row.id)
			if by_id.has(id):
				_err("%s:%d duplicate id '%s'" % [path, line_no, id])
			by_id[id] = row
	_cache[path] = { "rows": rows, "by_id": by_id }
	return rows


static func row(name: String, id: String) -> Dictionary:
	if name == "roster":
		roster()
		return _roster_by_id.get(id, {})
	table(name)
	return _cache[DATA_DIR + name + ".csv"].by_id.get(id, {})


static func has_table(name: String) -> bool:
	return FileAccess.file_exists(DATA_DIR + name + ".csv")


static func list(cell: Variant) -> PackedStringArray:
	var s := str(cell).strip_edges()
	if s == "":
		return PackedStringArray()
	var out := PackedStringArray()
	for part in s.split("|"):
		out.append(part.strip_edges())
	return out


static func clear_cache() -> void:
	_cache.clear()
	errors.clear()
	_roster = []
	_roster_by_id.clear()
	roster_seed = -1


static func _coerce(cell: String) -> Variant:
	var s := cell.strip_edges()
	if s.is_valid_int():
		return s.to_int()
	if s.is_valid_float():
		return s.to_float()
	return s


static func _err(msg: String) -> void:
	errors.append(msg)
	push_warning("BWData: " + msg)
