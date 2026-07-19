extends Node

## Player settings, persisted to user://settings.json.
##
## Separate from SaveStore on purpose: settings are preferences the player may
## want to reset or sync, while SaveStore holds the ranked ledger and score
## history. Losing one should never take the other with it.

const SETTINGS_PATH := "user://settings.json"

signal changed

var music_volume := Balance.DEFAULT_MUSIC_VOLUME      # 0..1
var sfx_volume := Balance.DEFAULT_SFX_VOLUME          # 0..1
var fullscreen := false
## Scales all screen shake. 0 disables it entirely — motion sensitivity is a
## real accessibility need, and shake is the one effect here that can trigger it.
var shake_scale := 1.0


func _ready() -> void:
	load_from_disk()
	apply_all()


func load_from_disk() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SettingsStore: settings unreadable, using defaults")
		return
	music_volume = clampf(float(parsed.get("music_volume", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(parsed.get("sfx_volume", sfx_volume)), 0.0, 1.0)
	fullscreen = bool(parsed.get("fullscreen", fullscreen))
	shake_scale = clampf(float(parsed.get("shake_scale", shake_scale)), 0.0, 1.0)


func save_to_disk() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SettingsStore: cannot write %s" % SETTINGS_PATH)
		return
	file.store_string(JSON.stringify({
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"fullscreen": fullscreen,
		"shake_scale": shake_scale,
	}, "\t"))
	file.close()


## Linear slider position to decibels. A slider at 0 must be true silence, not
## linear_to_db(0) which is -inf and makes the mixer unhappy.
static func linear_to_volume_db(linear: float) -> float:
	if linear <= 0.001:
		return -80.0
	return linear_to_db(linear)


func apply_all() -> void:
	Music.set_volume_db(Balance.MUSIC_DB + linear_to_volume_db(music_volume))
	Sfx.volume_offset_db = linear_to_volume_db(sfx_volume)
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen
		else DisplayServer.WINDOW_MODE_WINDOWED)
	changed.emit()


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	apply_all()
	save_to_disk()


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	apply_all()
	save_to_disk()


func set_fullscreen(value: bool) -> void:
	fullscreen = value
	apply_all()
	save_to_disk()


func set_shake_scale(value: float) -> void:
	shake_scale = clampf(value, 0.0, 1.0)
	apply_all()
	save_to_disk()
