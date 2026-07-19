extends Node

## Registers input actions in code rather than in project.godot.
##
## Why: the project.godot input map format is a wall of serialized Object(...)
## literals whose properties drift between engine versions. Declaring actions
## here is version-robust, readable, and diffable. Controller bindings are set
## up now so Phase 5 controller support is mostly free.

const DEADZONE := Balance.STICK_DEADZONE

const ACTIONS := {
	"move_left":  {"keys": [KEY_A, KEY_LEFT],  "axis": [JOY_AXIS_LEFT_X, -1.0], "buttons": [JOY_BUTTON_DPAD_LEFT]},
	"move_right": {"keys": [KEY_D, KEY_RIGHT], "axis": [JOY_AXIS_LEFT_X,  1.0], "buttons": [JOY_BUTTON_DPAD_RIGHT]},
	"move_up":    {"keys": [KEY_W, KEY_UP],    "axis": [JOY_AXIS_LEFT_Y, -1.0], "buttons": [JOY_BUTTON_DPAD_UP]},
	"move_down":  {"keys": [KEY_S, KEY_DOWN],  "axis": [JOY_AXIS_LEFT_Y,  1.0], "buttons": [JOY_BUTTON_DPAD_DOWN]},
	"restart":    {"keys": [KEY_R],            "axis": [],                      "buttons": [JOY_BUTTON_Y]},
	# Start/Escape pauses. Restart moved to Y so the two never clash on a pad.
	"pause":      {"keys": [KEY_ESCAPE],       "axis": [],                      "buttons": [JOY_BUTTON_START]},
	# Hold to steer toward the cursor. Registered as an action rather than
	# polled directly so Phase 5's remapping screen can reach it.
	"move_pointer": {"keys": [], "axis": [], "buttons": [], "mouse": [MOUSE_BUTTON_LEFT]},
	"dash": {"keys": [KEY_SPACE, KEY_SHIFT], "axis": [], "buttons": [JOY_BUTTON_RIGHT_SHOULDER],
			 "mouse": [MOUSE_BUTTON_RIGHT]},
}


## Godot's built-in ui_* actions ship WITHOUT gamepad face buttons for accept
## and cancel: ui_up/ui_down get the d-pad and stick, but ui_accept is only
## Enter/Space. A pad player can therefore move the menu focus and never
## activate anything. These are appended, not replaced, so the keyboard and
## mouse defaults survive.
const UI_PAD_BINDINGS := {
	"ui_accept": JOY_BUTTON_A,
	"ui_cancel": JOY_BUTTON_B,
}


func _enter_tree() -> void:
	for action_name in ACTIONS:
		_register(action_name, ACTIONS[action_name])
	for action_name in UI_PAD_BINDINGS:
		_add_pad_button(action_name, UI_PAD_BINDINGS[action_name])


func _add_pad_button(action_name: String, button: JoyButton) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name, DEADZONE)
	for event in InputMap.action_get_events(action_name):
		if event is InputEventJoypadButton and event.button_index == button:
			return
	var pad_event := InputEventJoypadButton.new()
	pad_event.button_index = button
	InputMap.action_add_event(action_name, pad_event)


func _register(action_name: String, cfg: Dictionary) -> void:
	if InputMap.has_action(action_name):
		InputMap.erase_action(action_name)
	InputMap.add_action(action_name, DEADZONE)

	for keycode in cfg["keys"]:
		var key_event := InputEventKey.new()
		key_event.physical_keycode = keycode as Key
		InputMap.action_add_event(action_name, key_event)

	if not cfg["axis"].is_empty():
		var motion := InputEventJoypadMotion.new()
		motion.axis = cfg["axis"][0] as JoyAxis
		motion.axis_value = cfg["axis"][1]
		InputMap.action_add_event(action_name, motion)

	for button in cfg["buttons"]:
		var button_event := InputEventJoypadButton.new()
		button_event.button_index = button as JoyButton
		InputMap.action_add_event(action_name, button_event)

	for mouse_button in cfg.get("mouse", []):
		var mouse_event := InputEventMouseButton.new()
		mouse_event.button_index = mouse_button as MouseButton
		InputMap.action_add_event(action_name, mouse_event)
