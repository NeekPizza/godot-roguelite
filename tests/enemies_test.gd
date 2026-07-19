extends Node

## New enemy types, the seed-selected roster, and elites (GDD section 5).

var _ok := true


func _check(label: String, passed: bool) -> void:
	if not passed:
		_ok = false
	print("  %-62s %s" % [label, "OK" if passed else "FAIL"])


func _ready() -> void:
	print("=== every enemy is well-formed ===")
	for type_id in Balance.ENEMY_TYPES:
		var e: Dictionary = Balance.ENEMY_TYPES[type_id]
		var valid: bool = e["behavior"] in ["chase", "keep_distance", "dash", "weave"]
		for key in ["name", "hp", "speed", "damage", "radius", "score", "xp", "color", "shape"]:
			valid = valid and e.has(key)
		if e["behavior"] == "dash":
			for key in ["dash_telegraph", "dash_speed", "dash_duration", "dash_cooldown"]:
				valid = valid and e.has(key)
		if e["behavior"] == "weave":
			valid = valid and e.has("wave_amplitude") and e.has("wave_frequency")
		_check("'%s' well-formed" % type_id, valid)

	print("\n=== dash and bomber telegraph ===")
	_check("dasher telegraphs before lunging (%.2fs)" %
		float(Balance.ENEMY_TYPES["dasher"]["dash_telegraph"]),
		float(Balance.ENEMY_TYPES["dasher"]["dash_telegraph"]) > 0.2)
	_check("dasher lunges faster than it creeps",
		float(Balance.ENEMY_TYPES["dasher"]["dash_speed"]) >
		float(Balance.ENEMY_TYPES["dasher"]["speed"]) * 3.0)
	_check("bomber blast is depth-capped",
		int(Balance.ENEMY_TYPES["bomber"]["blast_chain_depth"]) <= 3)

	print("\n=== shielded takes directional damage ===")
	var enemy: Node = load("res://scenes/enemy.tscn").instantiate()
	add_child(enemy)
	enemy.setup("shielded", 1.0)
	enemy.position = Vector2.ZERO
	enemy._facing = Vector2.RIGHT       # shield faces +x

	enemy.hp = 1000.0
	enemy.take_damage(100.0, Vector2(500, 0))     # dead ahead: blocked
	var front_loss: float = 1000.0 - enemy.hp
	enemy.hp = 1000.0
	enemy.take_damage(100.0, Vector2(-500, 0))    # from behind: full
	var back_loss: float = 1000.0 - enemy.hp
	_check("front hit is reduced (%.1f dmg)" % front_loss, front_loss < 100.0)
	_check("rear hit lands in full (%.1f dmg)" % back_loss, absf(back_loss - 100.0) < 0.01)
	_check("flanking is strictly better (%.1f vs %.1f)" % [back_loss, front_loss],
		back_loss > front_loss * 2.0)

	print("\n=== other enemies ignore facing ===")
	var plain: Node = load("res://scenes/enemy.tscn").instantiate()
	add_child(plain)
	plain.setup("drifter", 1.0)
	plain.hp = 1000.0
	plain.take_damage(100.0, Vector2(500, 0))
	_check("drifter takes full damage from any side", absf(1000.0 - plain.hp - 100.0) < 0.01)

	print("\n=== elites ===")
	var elite: Node = load("res://scenes/enemy.tscn").instantiate()
	add_child(elite)
	elite.setup("drifter", 1.0)
	var base_hp: float = elite.max_hp
	var base_score: int = elite.score_value()
	elite.make_elite("bomb")
	_check("elite has more HP (%.0f -> %.0f)" % [base_hp, elite.max_hp],
		elite.max_hp > base_hp)
	_check("elite is worth more score (%d -> %d)" % [base_score, elite.score_value()],
		elite.score_value() > base_score)
	_check("elite drop is fixed at SPAWN, not rolled at death",
		elite.elite_drop == "bomb")
	_check("elite chance is rare (%.1f%%)" % (Balance.ELITE_CHANCE * 100.0),
		Balance.ELITE_CHANCE > 0.0 and Balance.ELITE_CHANCE < 0.15)

	print("\n=== daily roster ===")
	var roster := Daily.enemy_roster("2026-01-01")
	_check("same date -> same roster", roster == Daily.enemy_roster("2026-01-01"))
	_check("core types always present",
		roster.has("drifter") and roster.has("swarmer"))
	_check("size is core + pick (%d)" % roster.size(),
		roster.size() == Balance.ENEMY_CORE.size() + Balance.ENEMY_ROSTER_PICK)
	var unique := {}
	for type_id in roster:
		unique[type_id] = true
	_check("no duplicates", unique.size() == roster.size())
	var all_real := true
	for type_id in roster:
		if not Balance.ENEMY_TYPES.has(type_id):
			all_real = false
	_check("every entry exists", all_real)
	var varies := false
	for day in range(2, 25):
		if Daily.enemy_roster("2026-01-%02d" % day) != roster:
			varies = true
	_check("roster varies across dates", varies)

	print("\n=== off-roster types cannot spawn, but still consume a draw ===")
	var table := Difficulty.type_weights_for(600.0, ["drifter", "swarmer"])
	var full := Difficulty.type_weights(600.0)
	_check("table length is unchanged (%d)" % table.size(), table.size() == full.size())
	var zeroed := true
	for entry in table:
		if entry[0] != "drifter" and entry[0] != "swarmer" and entry[1] != 0.0:
			zeroed = false
	_check("off-roster weights are zero", zeroed)

	print("\nRESULT: %s" % ("PASS" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)
