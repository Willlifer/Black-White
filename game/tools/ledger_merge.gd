extends SceneTree
## D473: merge campaign_sim ledger shards (LEDGER_OUT=<file> per shard) into
## one report. Env FILES="a.json,b.json,..." (or a directory in DIR: every
## .json in it).
##   godot --headless --path . --script res://tools/ledger_merge.gd


func _init() -> void:
	var files: Array = []
	if OS.get_environment("DIR") != "":
		var d := OS.get_environment("DIR")
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".json"):
				files.append(d.path_join(f))
	else:
		files = Array(OS.get_environment("FILES").split(","))
	var recs: Array = []
	for f in files:
		var a = JSON.parse_string(FileAccess.get_file_as_string(f))
		if a is Array:
			recs.append_array(a)
	var sim = load("res://tools/campaign_sim.gd")
	print("\n".join(sim.ledger_lines(recs)))
	quit()
