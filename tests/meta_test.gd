extends Node

## Meta-progression (GDD sections 20-21).
##
## The ceiling assertions matter most: the entire fairness argument rests on
## power converging rather than accumulating.

var _ok := true


func _check(label: String, passed: bool) -> void:
	if not passed:
		_ok = false
	print("  %-64s %s" % [label, "OK" if passed else "FAIL"])


func _ready() -> void:
	print("=== the aggregate ceiling is HARD ===")
	var maxed := Meta.profile_max()
	_check("max profile lands exactly on the cap (+%.1f%%)"
		% (Meta.effective_bonus(maxed) * 100.0),
		absf(Meta.effective_bonus(maxed) - Balance.META_AGGREGATE_CAP) < 0.0001)

	# Overspending must dilute, never add. This is the assertion that keeps a
	# veteran from out-powering the ceiling by simply buying more.
	var overfilled := {}
	for stat_id in Balance.META_STATS:
		overfilled[stat_id] = Balance.META_MAX_BUYS
	_check("buying EVERYTHING still yields only +%.1f%%"
		% (Meta.effective_bonus(overfilled) * 100.0),
		absf(Meta.effective_bonus(overfilled) - Balance.META_AGGREGATE_CAP) < 0.0001)
	_check("overspending throttles effects rather than stacking them",
		Meta.throttle(overfilled) < 1.0)

	print("\n=== only a few stats can be maxed ===")
	var budget := Meta.max_total_purchases()
	var fully := float(budget) / float(Balance.META_MAX_BUYS)
	_check("the budget maxes about %.1f of %d stats" % [fully, Balance.META_STATS.size()],
		fully >= 2.0 and fully <= 4.0)

	print("\n=== costs escalate, so spreading beats concentrating ===")
	_check("each purchase costs more than the last (%d -> %d)"
		% [Meta.next_cost(0), Meta.next_cost(5)], Meta.next_cost(5) > Meta.next_cost(0))
	_check("a capped stat refuses further purchases",
		Meta.next_cost(Balance.META_MAX_BUYS) == -1)
	var concentrated := Meta.profile_none()
	concentrated["hp"] = 6
	var spread := Meta.profile_none()
	for stat_id in ["hp", "speed", "pickup", "dash", "xp", "reroll"]:
		spread[stat_id] = 1
	_check("6 spread (%d pts) is cheaper than 6 stacked (%d pts)"
		% [Meta.total_spent(spread), Meta.total_spent(concentrated)],
		Meta.total_spent(spread) < Meta.total_spent(concentrated))

	print("\n=== convergence timing ===")
	var cost_to_cap := Meta.total_spent(maxed)
	var per_day_new := Meta.points_for_run(2)
	var per_day_strong := Meta.points_for_run(8)
	_check("full power costs %d pts = %.0f days new / %.0f days strong"
		% [cost_to_cap, float(cost_to_cap) / per_day_new, float(cost_to_cap) / per_day_strong],
		float(cost_to_cap) / per_day_new <= 45.0)
	# The flattened award curve is what stops the strong pulling away.
	_check("strong earns only %.2fx a newcomer's rate"
		% (float(per_day_strong) / per_day_new),
		float(per_day_strong) / float(per_day_new) < 2.0)
	_check("the stage term is capped", Meta.points_for_run(50) == Meta.points_for_run(
		Balance.META_POINTS_STAGE_CAP))

	print("\n=== effects are player-side and bounded ===")
	var player: Node = load("res://scenes/player.tscn").instantiate()
	add_child(player)
	var base_hp: float = player.max_hp
	var base_speed: float = player.move_speed
	Meta.apply(player, maxed)
	_check("HP rose but by at most 3%% (%.1f -> %.1f)" % [base_hp, player.max_hp],
		player.max_hp > base_hp and player.max_hp <= base_hp * 1.031)
	_check("move speed rose but stayed within 3%%",
		player.move_speed > base_speed and player.move_speed <= base_speed * 1.031)
	_check("pickup radius still respects its own hard cap (%.0f)" % player.pickup_radius,
		player.pickup_radius <= Balance.PLAYER_PICKUP_RADIUS_MAX)

	print("\n=== no meta stat can reach a seeded schedule ===")
	# Structural: every effect targets a player property. If a future stat
	# targeted anything else, this is the assertion that should fail.
	var player_side := true
	for stat_id in Balance.META_STATS:
		var entry: Dictionary = Balance.META_STATS[stat_id]
		if entry["kind"] != "mult":
			continue
		if not player.has_method("take_damage") or entry["target"] not in [
				"max_hp", "move_speed", "pickup_radius", "dash_cooldown_scale",
				"damage_mult", "fire_rate_mult", "area_scale"]:
			player_side = false
	_check("every multiplier targets a player stat, never world state", player_side)
	_check("there is no luck / drop-rate stat",
		not Balance.META_STATS.has("luck") and not Balance.META_STATS.has("drop_rate"))

	print("\n=== rerolls are a discrete milestone ===")
	var almost := Meta.profile_none()
	almost["reroll"] = Balance.META_MAX_BUYS - 1
	_check("no bonus reroll just short of full", Meta.bonus_rerolls(almost) == 0)
	var full := Meta.profile_none()
	full["reroll"] = Balance.META_MAX_BUYS
	_check("+1 reroll at full", Meta.bonus_rerolls(full) == 1)

	print("\n=== the test hook can never be ranked ===")
	var guarded := false
	for entry in RunConfig.TEST_HOOK_ARGS:
		if str(entry) == "--meta-profile=":
			guarded = true
	_check("--meta-profile is in TEST_HOOK_ARGS", guarded)

	player.free()
	print("\nRESULT: %s" % ("PASS" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)
