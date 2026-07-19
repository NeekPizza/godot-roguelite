extends Node

## Drop scheduling and effects (GDD section 5c).
##
## The scheduling assertions matter most: a drop resolves at a moment nobody
## controls, so if any of it were rolled then, two players on one seed would
## diverge.

var _ok := true


func _check(label: String, passed: bool) -> void:
	if not passed:
		_ok = false
	print("  %-62s %s" % [label, "OK" if passed else "FAIL"])


func _ready() -> void:
	print("=== every drop is well-formed ===")
	for drop_id in Balance.DROPS:
		var config: Dictionary = Balance.DROPS[drop_id]
		var valid: bool = config["kind"] in ["instant", "buff", "temp_weapon"]
		valid = valid and config.has("name") and config.has("weight") and config.has("color")
		if config["kind"] == "temp_weapon" and config.get("modifier", "") == "":
			for key in ["duration", "damage", "cooldown", "count", "spread", "speed"]:
				valid = valid and config.has(key)
		_check("'%s' well-formed" % drop_id, valid)

	print("\n=== the schedule is precomputed and deterministic ===")
	var a := Drops.build_schedule("2026-01-01")
	var b := Drops.build_schedule("2026-01-01")
	_check("same date -> identical schedule",
		Drops.schedule_digest(a) == Drops.schedule_digest(b))
	_check("different date -> different schedule",
		Drops.schedule_digest(a) != Drops.schedule_digest(Drops.build_schedule("2026-01-02")))
	_check("covers %d entries" % Balance.DROP_SCHEDULE_COUNT,
		a.size() == Balance.DROP_SCHEDULE_COUNT)

	var ascending := true
	for i in range(1, a.size()):
		if float(a[i]["time"]) < float(a[i - 1]["time"]):
			ascending = false
	_check("times are ascending", ascending)

	print("\n=== positions are absolute and inside the world ===")
	var bounds := Arena.rect()
	var inside := true
	for entry in a:
		var position: Vector2 = entry["position"]
		if not bounds.has_point(position):
			inside = false
	_check("every drop lands inside the world", inside)
	_check("first drop is not immediate (%.1fs)" % float(a[0]["time"]),
		float(a[0]["time"]) > 5.0)

	print("\n=== drop mix ===")
	var seen := {}
	for entry in a:
		seen[entry["id"]] = int(seen.get(entry["id"], 0)) + 1
	_check("more than one kind appears (%d kinds)" % seen.size(), seen.size() >= 4)
	var all_known := true
	for drop_id in seen:
		if not Balance.DROPS.has(drop_id):
			all_known = false
	_check("every scheduled id exists in the table", all_known)

	print("\n=== weighted pick is a pure function of the roll ===")
	_check("roll 0.0 is stable", Drops.pick(0.0) == Drops.pick(0.0))
	_check("roll 0.99 is stable", Drops.pick(0.99) == Drops.pick(0.99))

	print("\n=== bomb uses a world radius, not the screen ===")
	var bomb: Dictionary = Balance.DROPS["bomb"]
	_check("world_radius is declared", bomb.has("world_radius"))
	_check("radius (%.0f) is smaller than the world (%.0f)" % [
		float(bomb["world_radius"]), Balance.WORLD_SIZE.x],
		float(bomb["world_radius"]) < Balance.WORLD_SIZE.x)
	_check("bosses take a capped fraction, never an instakill",
		float(bomb["boss_damage_fraction"]) > 0.0 and float(bomb["boss_damage_fraction"]) < 1.0)

	print("\n=== splash chains are bounded ===")
	var splash: Dictionary = Balance.DROPS["splash"]
	_check("chain depth is capped (%d)" % int(splash["chain_depth_max"]),
		int(splash["chain_depth_max"]) > 0 and int(splash["chain_depth_max"]) <= 5)
	_check("damage is a fraction of max HP, so it cannot grow unbounded",
		float(splash["hp_fraction"]) > 0.0 and float(splash["hp_fraction"]) <= 1.0)

	print("\nRESULT: %s" % ("PASS" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)
