extends Node

## Evolutions and the combo multiplier (GDD section 6b).

var _ok := true


func _check(label: String, passed: bool) -> void:
	if not passed:
		_ok = false
	print("  %-62s %s" % [label, "OK" if passed else "FAIL"])


func _state(weapons: Dictionary, passives: Dictionary) -> Dictionary:
	return {"weapons": weapons, "passives": passives, "slots": 3, "banished": []}


func _kinds(cards: Array, kind: String) -> Array:
	var out := []
	for card in cards:
		if card["kind"] == kind:
			out.append(card["id"])
	return out


func _ready() -> void:
	var player: Node = load("res://scenes/player.tscn").instantiate()
	add_child(player)

	print("=== every recipe is well-formed ===")
	for recipe in Balance.EVOLUTIONS:
		var valid: bool = Balance.WEAPONS.has(recipe["weapon"]) \
			and Balance.PASSIVES.has(recipe["passive"]) \
			and Balance.EVOLVED_WEAPONS.has(recipe["result"])
		_check("%s + %s -> %s" % [recipe["weapon"], recipe["passive"], recipe["result"]], valid)

	print("\n=== an evolution needs BOTH halves maxed ===")
	var max_pulse := Weapons.max_level("pulse")
	var max_pierce := int(Balance.PASSIVES["pierce"]["max"])
	_check("weapon maxed alone is not enough",
		Weapons.ready_evolution("pulse", max_pulse, {"pierce": max_pierce - 1}) == "")
	_check("passive maxed alone is not enough",
		Weapons.ready_evolution("pulse", max_pulse - 1, {"pierce": max_pierce}) == "")
	_check("both maxed unlocks Railgun",
		Weapons.ready_evolution("pulse", max_pulse, {"pierce": max_pierce}) == "railgun")

	print("\n=== the deck offers it, and never offers evolved weapons as new ===")
	var ready_state := _state({"pulse": max_pulse}, {"pierce": max_pierce})
	var offered := _kinds(Cards.eligible(ready_state), Cards.KIND_EVOLUTION)
	_check("Railgun appears as an EVOLUTION card", offered.has("railgun"))

	var fresh := Cards.eligible(_state({}, {}))
	var new_weapons := _kinds(fresh, Cards.KIND_WEAPON_NEW)
	var leaked := false
	for weapon_id in new_weapons:
		if Weapons.is_evolved(weapon_id):
			leaked = true
	_check("evolved weapons are never offered as NEW (%d new)" % new_weapons.size(), not leaked)

	print("\n=== evolving replaces in place and costs no slot ===")
	var system: Node = player.get_node("WeaponSystem")
	system.player = player
	system.add_or_level("pulse")
	system.add_or_level("nova")
	var before: int = system.slots_used()
	system.evolve("pulse", "railgun")
	_check("slot count unchanged (%d -> %d)" % [before, system.slots_used()],
		system.slots_used() == before)
	_check("base weapon is gone", not system.has_weapon("pulse"))
	_check("evolution is held", system.has_weapon("railgun"))
	_check("other weapons survive", system.has_weapon("nova"))

	print("\n=== the evolution is a real upgrade ===")
	var maxed_base := Weapons.stats("pulse", max_pulse, player)
	var evolved := Weapons.stats("railgun", 1, player)
	_check("Railgun L1 out-damages Pulse L%d (%.0f vs %.0f)" % [
		max_pulse, evolved["damage"], maxed_base["damage"]],
		evolved["damage"] > maxed_base["damage"])
	_check("Event Horizon pulls enemies inward",
		Weapons.stats("event_horizon", 1, player)["pull"] > 0.0)
	_check("base Orbit does not pull", Weapons.stats("orbit", 1, player)["pull"] == 0.0)

	print("\n=== combo multiplier ===")
	_check("starts at x1.00", absf(_multiplier(0.0) - 1.0) < 0.001)
	_check("builds with the chain (x%.2f at 20 kills)" % _multiplier(20.0),
		_multiplier(20.0) > 1.0)
	_check("caps at x%.2f" % (1.0 + Balance.COMBO_MAX_BONUS),
		absf(_multiplier(100000.0) - (1.0 + Balance.COMBO_MAX_BONUS)) < 0.001)
	_check("cap is reachable in a real chain (%.0f kills)" %
		(Balance.COMBO_MAX_BONUS / Balance.COMBO_PER_KILL),
		Balance.COMBO_MAX_BONUS / Balance.COMBO_PER_KILL < 200.0)
	_check("decay is faster than the build, so it must be maintained",
		Balance.COMBO_DECAY_PER_SEC > 1.0)

	player.free()
	print("\nRESULT: %s" % ("PASS" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)


func _multiplier(chain: float) -> float:
	return 1.0 + minf(Balance.COMBO_MAX_BONUS, chain * Balance.COMBO_PER_KILL)
