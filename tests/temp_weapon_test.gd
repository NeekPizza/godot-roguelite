extends Node

## Temp weapon drops must ADD to your loadout, never replace it.
##
## Counts projectiles actually spawned rather than inspecting flags: the failure
## this guards against is behavioural — a drop silently suppressing the weapons
## you spent the run building.

var _ok := true


func _check(label: String, passed: bool) -> void:
	if not passed:
		_ok = false
	print("  %-62s %s" % [label, "OK" if passed else "FAIL"])


## Run the weapon system for `seconds` and report how many projectiles it made.
func _fire_for(system: Node, parent: Node2D, seconds: float) -> int:
	for child in parent.get_children():
		child.free()
	var step := 1.0 / 60.0
	var ticks := int(seconds / step)
	for i in ticks:
		system._physics_process(step)
	return parent.get_child_count()


func _ready() -> void:
	var player: Node = load("res://scenes/player.tscn").instantiate()
	add_child(player)
	var parent := Node2D.new()
	add_child(parent)

	# A target, so the weapons have something to aim at.
	var dummy: Node = load("res://scenes/enemy.tscn").instantiate()
	add_child(dummy)
	dummy.setup("drifter", 1000.0)      # tanky enough to survive the test
	dummy.position = player.position + Vector2(120, 0)

	var system: Node = player.get_node("WeaponSystem")
	system.player = player
	system.projectile_parent = parent
	system.add_or_level("pulse")

	print("=== baseline ===")
	var loadout_only := _fire_for(system, parent, 3.0)
	_check("the loadout alone fires (%d projectiles in 3s)" % loadout_only, loadout_only > 0)

	print("\n=== the temp weapon alone ===")
	# Measured, never computed from the nominal cooldown: the sim steps at 60Hz,
	# so a 0.07s cooldown really fires every 5 ticks (~0.083s), not every 0.07s.
	# Predicting the rate instead of measuring it produces an assertion that
	# fails on correct code.
	var owned_backup: Dictionary = system.owned.duplicate()
	system.owned = {}
	system.temp_weapon_id = "machine_gun"
	var temp_only := _fire_for(system, parent, 3.0)
	_check("the temp weapon alone fires (%d)" % temp_only, temp_only > 0)

	print("\n=== both together ===")
	system.owned = owned_backup
	var with_temp := _fire_for(system, parent, 3.0)
	_check("more than the loadout alone (%d > %d)" % [with_temp, loadout_only],
		with_temp > loadout_only)
	_check("more than the temp weapon alone (%d > %d)" % [with_temp, temp_only],
		with_temp > temp_only)
	# The decisive one: additive means the total is roughly the sum. If the drop
	# suppressed the loadout, this would equal temp_only.
	_check("total is the sum, not a replacement (%d ~= %d + %d)" % [
		with_temp, loadout_only, temp_only],
		absi(with_temp - (loadout_only + temp_only)) <= 2)

	print("\n=== the drop ends cleanly ===")
	system.temp_weapon_id = ""
	var after := _fire_for(system, parent, 3.0)
	_check("back to the loadout rate (%d, was %d)" % [after, loadout_only],
		after > 0 and after < with_temp)

	print("\n=== a temp weapon never outclasses a built loadout ===")
	# Every temp weapon is additive, so no drop can be a net downgrade.
	var additive := true
	for drop_id in Balance.DROPS:
		var config: Dictionary = Balance.DROPS[drop_id]
		if config["kind"] != "temp_weapon":
			continue
		# splash is a kill modifier; the rest fire alongside the loadout
		if config.get("modifier", "") == "":
			additive = additive and config.has("cooldown")
	_check("every temp weapon is a firing addition or a modifier", additive)

	player.free()
	print("\nRESULT: %s" % ("PASS" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)
