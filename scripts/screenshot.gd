extends Node

## `--screenshot=PATH@SECONDS` from any scene.
##
## Lives in an autoload rather than in run.gd so it can also capture the menu
## and its overlays; previously it only worked once a run had started.

var _path := ""
var _delay := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # captures work while paused
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			var parts := arg.split("=")[1].split("@")
			_path = parts[0]
			_delay = float(parts[1]) if parts.size() > 1 else 5.0


func _process(delta: float) -> void:
	if _path == "":
		return
	_delay -= delta
	if _delay <= 0.0:
		var path := _path
		_path = ""
		_capture(path)


func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(path)
	print("[shot] %s (err %d)" % [path, error])
