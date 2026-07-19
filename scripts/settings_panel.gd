extends Control

## Settings UI. Instanced by both the main menu and the pause menu so there is
## one implementation rather than two that drift apart.

signal closed

@onready var _music: HSlider = $Center/Panel/Music/Slider
@onready var _music_value: Label = $Center/Panel/Music/Value
@onready var _sfx: HSlider = $Center/Panel/Sfx/Slider
@onready var _sfx_value: Label = $Center/Panel/Sfx/Value
@onready var _shake: HSlider = $Center/Panel/Shake/Slider
@onready var _shake_value: Label = $Center/Panel/Shake/Value
@onready var _fullscreen: CheckBox = $Center/Panel/Fullscreen
@onready var _back: Button = $Center/Panel/Back


func _ready() -> void:
	# Stays live while the tree is paused, so settings work from the pause menu.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_music.value = SettingsStore.music_volume
	_sfx.value = SettingsStore.sfx_volume
	_shake.value = SettingsStore.shake_scale
	_fullscreen.button_pressed = SettingsStore.fullscreen
	_refresh_labels()

	_music.value_changed.connect(func(v): SettingsStore.set_music_volume(v); _refresh_labels())
	_sfx.value_changed.connect(func(v): SettingsStore.set_sfx_volume(v); _refresh_labels())
	_shake.value_changed.connect(func(v): SettingsStore.set_shake_scale(v); _refresh_labels())
	_fullscreen.toggled.connect(func(on): SettingsStore.set_fullscreen(on))
	_back.pressed.connect(func(): closed.emit())


func focus_first() -> void:
	_music.grab_focus()


func _refresh_labels() -> void:
	_music_value.text = "%d%%" % roundi(SettingsStore.music_volume * 100.0)
	_sfx_value.text = "%d%%" % roundi(SettingsStore.sfx_volume * 100.0)
	_shake_value.text = "OFF" if SettingsStore.shake_scale <= 0.001 \
		else "%d%%" % roundi(SettingsStore.shake_scale * 100.0)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		accept_event()
		closed.emit()
