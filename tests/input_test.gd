extends Node

## Asserts every action is reachable on BOTH keyboard and gamepad.
##
## Controller support fails silently: the game still runs, the player just
## cannot do one particular thing, and it is usually found by a reviewer rather
## than by us. Checking the map directly is cheap and catches it.

var _ok := true


func _check(label: String, passed: bool) -> void:
	if not passed:
		_ok = false
	print("  %-52s %s" % [label, "OK" if passed else "FAIL"])


func _kinds(action: String) -> Dictionary:
	var found := {"key": false, "pad": false, "mouse": false}
	if not InputMap.has_action(action):
		return found
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			found["key"] = true
		elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
			found["pad"] = true
		elif event is InputEventMouseButton:
			found["mouse"] = true
	return found


func _ready() -> void:
	print("=== gameplay actions work on keyboard AND gamepad ===")
	for action in ["move_left", "move_right", "move_up", "move_down", "pause", "restart"]:
		var kinds := _kinds(action)
		_check("%s (key=%s pad=%s)" % [action, kinds["key"], kinds["pad"]],
			kinds["key"] and kinds["pad"])

	print("\n=== mouse steering ===")
	var pointer := _kinds("move_pointer")
	_check("move_pointer bound to a mouse button", pointer["mouse"])

	print("\n=== menu navigation is possible on a gamepad ===")
	# Godot's built-in ui_* actions carry the menu. If these lose their joypad
	# bindings the menus become keyboard/mouse only and a pad player is stuck.
	for action in ["ui_accept", "ui_cancel", "ui_up", "ui_down", "ui_left", "ui_right"]:
		var kinds := _kinds(action)
		_check("%s reachable on a pad" % action, kinds["pad"])

	print("\n=== pause and restart do not collide on the pad ===")
	var pause_pad := []
	var restart_pad := []
	for event in InputMap.action_get_events("pause"):
		if event is InputEventJoypadButton:
			pause_pad.append(event.button_index)
	for event in InputMap.action_get_events("restart"):
		if event is InputEventJoypadButton:
			restart_pad.append(event.button_index)
	var overlap := false
	for button in pause_pad:
		if button in restart_pad:
			overlap = true
	_check("pause %s vs restart %s share no button" % [pause_pad, restart_pad], not overlap)

	print("\nRESULT: %s" % ("PASS" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)
