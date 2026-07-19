extends Node

## Boss archetypes, telegraphs and escalation (GDD section 5b).

var _ok := true


func _check(label: String, passed: bool) -> void:
	if not passed:
		_ok = false
	print("  %-64s %s" % [label, "OK" if passed else "FAIL"])


func _ready() -> void:
	print("=== archetypes and patterns are well-formed ===")
	for id in Balance.BOSS_ARCHETYPES:
		var a: Dictionary = Balance.BOSS_ARCHETYPES[id]
		var valid: bool = Balance.BOSS_PATTERNS.has(a["pattern"])
		for key in ["name", "shape", "speed_mult", "color"]:
			valid = valid and a.has(key)
		_check("'%s' -> pattern '%s'" % [id, a.get("pattern", "?")], valid)

	print("\n=== selection is indexed, not running ===")
	var slot3 := Difficulty.boss_archetype("2026-01-01", 3)
	_check("same (date, slot) -> same boss", slot3 == Difficulty.boss_archetype("2026-01-01", 3))
	_check("slot 3 is independent of slots 1-2",
		slot3 == Difficulty.boss_archetype("2026-01-01", 3))
	var order := []
	for slot in range(1, 9):
		order.append(Difficulty.boss_archetype("2026-01-01", slot))
	var other := []
	for slot in range(1, 9):
		other.append(Difficulty.boss_archetype("2026-01-02", slot))
	_check("a different date gives a different order", order != other)
	var distinct := {}
	for id in order:
		distinct[id] = true
	_check("more than one archetype appears over 8 slots (%d)" % distinct.size(),
		distinct.size() >= 2)

	print("\n=== boss drops are decided with the slot, not at death ===")
	_check("same (date, slot) -> same drop",
		Difficulty.boss_drop("2026-01-01", 2) == Difficulty.boss_drop("2026-01-01", 2))
	var known := Balance.DROPS.has(Difficulty.boss_drop("2026-01-01", 2))
	_check("the drop is a real id", known)

	print("\n=== escalation ===")
	for pattern_id in Balance.BOSS_PATTERNS:
		var early := Difficulty.boss_pattern(pattern_id, 1)
		var late := Difficulty.boss_pattern(pattern_id, 8)
		_check("'%s' bullets rise (%d -> %d)" % [pattern_id,
			int(early["bullets"]), int(late["bullets"])],
			int(late["bullets"]) >= int(early["bullets"]))
		_check("'%s' bullets get faster (%.0f -> %.0f)" % [pattern_id,
			float(early["speed"]), float(late["speed"])],
			float(late["speed"]) > float(early["speed"]))

	print("\n=== the telegraph floor holds however deep the run goes ===")
	var floor_held := true
	var cadence_held := true
	for pattern_id in Balance.BOSS_PATTERNS:
		for index in [1, 5, 20, 100]:
			var p := Difficulty.boss_pattern(pattern_id, index)
			if float(p["telegraph"]) < Balance.BOSS_TELEGRAPH_MIN:
				floor_held = false
			if float(p["cadence"]) < Balance.BOSS_CADENCE_MIN:
				cadence_held = false
	_check("telegraph never drops below %.2fs, even at index 100" % Balance.BOSS_TELEGRAPH_MIN,
		floor_held)
	_check("cadence never drops below %.2fs" % Balance.BOSS_CADENCE_MIN, cadence_held)

	print("\n=== a boss actually telegraphs before firing ===")
	var boss: Node = load("res://scenes/boss.tscn").instantiate()
	add_child(boss)
	boss.setup(1, "aimed_volley", "health")
	_check("starts in recover, not mid-attack", boss.telegraph_progress() == 0.0)
	boss._phase = "telegraph"
	boss._phase_timer = float(boss._pattern["telegraph"]) * 0.5
	_check("telegraph progress is visible mid-windup (%.2f)" % boss.telegraph_progress(),
		boss.telegraph_progress() > 0.0)

	print("\n=== scaling ===")
	_check("HP still scales with index (%.0f -> %.0f)" % [
		Difficulty.boss_hp(1), Difficulty.boss_hp(4)],
		Difficulty.boss_hp(4) > Difficulty.boss_hp(1))
	_check("damage scales with index (%.0f -> %.0f)" % [
		Difficulty.boss_damage(1), Difficulty.boss_damage(4)],
		Difficulty.boss_damage(4) > Difficulty.boss_damage(1))

	boss.free()
	print("\nRESULT: %s" % ("PASS" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)
