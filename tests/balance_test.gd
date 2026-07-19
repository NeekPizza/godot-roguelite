extends Node

## Data-integrity and upgrade-application checks.
##
## Runs as a SCENE, not via --script: `godot --headless --script` does not load
## autoloads, so any script referencing Sfx/Music fails to compile and every
## player property reads back null. Booting a scene loads the full environment.
##
##   godot --headless tests/balance_test.tscn

var _ok := true


func _check(label: String, passed: bool) -> void:
	if not passed:
		_ok = false
	print("  %-46s %s" % [label, "OK" if passed else "FAIL"])


func _ready() -> void:
	print("=== upgrades apply through the declared data path ===")
	var player: Node = load("res://scenes/player.tscn").instantiate()
	add_child(player)

	for entry in Balance.UPGRADES:
		var stat: String = entry["stat"]
		var before = player.get(stat)
		Upgrades.apply(entry["id"], player)
		var after = player.get(stat)
		_check("%s -> %s (%s -> %s)" % [entry["id"], stat, str(before), str(after)],
			after != before)

	print("\n=== effects and guards ===")
	player.hp = 10.0
	Upgrades.apply(Balance.UPGRADE_FALLBACK["id"], player)
	_check("fallback Repair heals (hp now %.0f)" % player.hp, player.hp > 10.0)

	for i in 30:
		Upgrades.apply("magnetism", player)
	_check("pickup radius capped at %.0f (is %.0f)" % [
		Balance.PLAYER_PICKUP_RADIUS_MAX, player.pickup_radius],
		player.pickup_radius <= Balance.PLAYER_PICKUP_RADIUS_MAX)

	print("\n=== content integrity ===")
	for entry in Balance.TYPE_SCHEDULE:
		_check("schedule '%s' defined in ENEMY_TYPES" % entry["id"],
			Balance.ENEMY_TYPES.has(entry["id"]))

	for id in Balance.ENEMY_TYPES:
		var e: Dictionary = Balance.ENEMY_TYPES[id]
		var valid: bool = e["behavior"] in ["chase", "keep_distance"]
		if e["behavior"] == "keep_distance":
			valid = valid and e.has("preferred_range") and e.has("shot_interval")
		if e.has("splits_into"):
			valid = valid and Balance.ENEMY_TYPES.has(e["splits_into"])
		for key in ["hp", "speed", "damage", "radius", "score", "xp", "color", "shape"]:
			valid = valid and e.has(key)
		_check("enemy '%s' well-formed" % id, valid)

	# Cross-check BOTH directions. The earlier version only asserted that a
	# hardcoded list of names had mix levels in SFX_DB — which passed happily
	# while boss_spawn and boss_death had no audio file at all, so the boss
	# arrived in silence and only a runtime warning ever said so. A test that
	# validates one half of a pair against the other half's absence is worse
	# than no test, because it reads as coverage.
	for key in Balance.SFX_DB:
		_check("SFX_DB '%s' has a loaded sound file" % key, Sfx.has_sound(key))
	for key in Sfx.sound_names():
		_check("loaded sound '%s' has a mix level" % key, Balance.SFX_DB.has(key))

	print("\n=== ramp stays unbounded and monotonic ===")
	var previous_hp := 0.0
	var previous_count := 0
	for minutes in [0, 5, 10, 20, 45, 90]:
		var t := float(minutes) * 60.0
		var hp_mult := Difficulty.hp_multiplier(t)
		var count := Difficulty.spawn_count(t)
		_check("%2d min: interval %.3f count %2d hp %.2fx" % [
			minutes, Difficulty.spawn_interval(t), count, hp_mult],
			hp_mult >= previous_hp and count >= previous_count
				and Difficulty.spawn_interval(t) >= Balance.SPAWN_INTERVAL_FLOOR)
		previous_hp = hp_mult
		previous_count = count

	print("\n=== scoring ===")
	var absurd := Score.total(6_500_000, 3600.0, 200_000)
	_check("absurd 1h run %d stays inside int32" % absurd, absurd < 2147483647)
	_check("ceiling rejects fabricated scores", not Score.is_plausible(Balance.SCORE_CEILING + 1))
	_check("bounded() clamps to ceiling", Score.bounded(999_999_999) == Balance.SCORE_CEILING)

	print("\nRESULT: %s" % ("PASS" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)
