class_name BWCapture
extends Node
## Saves real rendered frames (not mockups) for visual verification:
## `-- --shot <dir> --every <sec> --count <n>` grabs n frames from the live
## viewport. Requires a rendering window; headless has no renderer.

var out_dir := "user://shots"
var every := 1.0
var count := 6
var _taken := 0
var _t := 0.0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir) if out_dir.begins_with("user://") else out_dir)


func _process(delta: float) -> void:
	_t += delta
	if _t < every:
		return
	_t = 0.0
	var img := get_viewport().get_texture().get_image()
	var path := "%s/shot_%02d.png" % [out_dir, _taken]
	img.save_png(path)
	print("captured ", ProjectSettings.globalize_path(path) if path.begins_with("user://") else path)
	_taken += 1
	if _taken >= count:
		get_tree().quit(0)
