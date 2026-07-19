extends Node

## Weapons, slots, and the card deck (GDD sections 4, 6).
##
## The determinism assertions here matter more than the stat ones: reroll and
## banish happen on player-dependent timing, so if their draws were not indexed
## the whole daily seed would come apart.

var _ok := true


func _check(label: String, passed: bool) -> void:
	if not passed:
		_ok = false
	print("  %-60s %s" % [label, "OK" if passed else "FAIL"])


func _state(weapons: Dictionary, passives: Dictionary, slots: int,
		banished: Array = []) -> Dictionary:
	return {"weapons": weapons, "passives": passives, "slots": slots,
			"banished": banished}


func _ready() -> void:
	var player: Node = load("res://scenes/player.tscn").instantiate()
	add_child(player)

	print("=== weapon data is well-formed ===")
	for weapon_id in Balance.WEAPONS:
		var definition: Dictionary = Balance.WEAPONS[weapon_id]
		var valid: bool = definition["cooldown_class"] in ["shot", "volley"]
		for key in ["name", "desc", "behavior", "max_level", "base", "per_level"]:
			valid = valid and definition.has(key)
		_check("'%s' well-formed" % weapon_id, valid)

	print("\n=== level scaling and passives ===")
	var low := Weapons.stats("pulse", 1, player)
	var high := Weapons.stats("pulse", 5, player)
	_check("levelling raises damage (%.1f -> %.1f)" % [low["damage"], high["damage"]],
		high["damage"] > low["damage"])
	_check("levelling shortens cooldown (%.2f -> %.2f)" % [low["cooldown"], high["cooldown"]],
		high["cooldown"] < low["cooldown"])

	print("\n=== Overclock vs Cooldown Core split by loadout ===")
	var base_shot := Weapons.stats("pulse", 1, player)
	var base_volley := Weapons.stats("nova", 1, player)
	Weapons.apply_passive("overclock", player)
	var oc_shot := Weapons.stats("pulse", 1, player)
	var oc_volley := Weapons.stats("nova", 1, player)
	_check("Overclock speeds up a SHOT weapon", oc_shot["cooldown"] < base_shot["cooldown"])
	_check("Overclock leaves a VOLLEY weapon alone",
		absf(oc_volley["cooldown"] - base_volley["cooldown"]) < 0.001)

	Weapons.apply_passive("cooldown_core", player)
	var cc_volley := Weapons.stats("nova", 1, player)
	_check("Cooldown Core speeds up a VOLLEY weapon", cc_volley["cooldown"] < base_volley["cooldown"])

	print("\n=== slot limit gates NEW weapons only ===")
	var free_slot := Cards.eligible(_state({"pulse": 1}, {}, 3))
	var new_offers := 0
	for card in free_slot:
		if card["kind"] == Cards.KIND_WEAPON_NEW:
			new_offers += 1
	_check("slot free -> new weapons offered (%d)" % new_offers, new_offers > 0)

	var full := Cards.eligible(_state({"pulse": 1, "nova": 1, "orbit": 1}, {}, 3))
	var offers_when_full := 0
	for card in full:
		if card["kind"] == Cards.KIND_WEAPON_NEW:
			offers_when_full += 1
	_check("slots full -> NO new weapons offered", offers_when_full == 0)
	var levels_when_full := 0
	for card in full:
		if card["kind"] == Cards.KIND_WEAPON_LEVEL:
			levels_when_full += 1
	_check("slots full -> levels offered instead (%d)" % levels_when_full, levels_when_full > 0)

	print("\n=== maxed weapons leave the deck ===")
	var maxed := Cards.eligible(_state({"pulse": Weapons.max_level("pulse")}, {}, 3))
	var pulse_offers := 0
	for card in maxed:
		if card["id"] == "pulse":
			pulse_offers += 1
	_check("a max-level weapon is not offered again", pulse_offers == 0)

	print("\n=== card draws are deterministic and indexed ===")
	var st := _state({"pulse": 1}, {}, 4)
	var a := Cards.draw("2026-01-01", 5, 0, st)
	var b := Cards.draw("2026-01-01", 5, 0, st)
	_check("same (date, level, action) -> identical offer", _ids(a) == _ids(b))

	var rerolled := Cards.draw("2026-01-01", 5, 1, st)
	_check("a reroll (action 1) gives a different offer", _ids(a) != _ids(rerolled))
	_check("that reroll is itself reproducible",
		_ids(rerolled) == _ids(Cards.draw("2026-01-01", 5, 1, st)))

	_check("a different level differs", _ids(a) != _ids(Cards.draw("2026-01-01", 6, 0, st)))
	_check("a different date differs", _ids(a) != _ids(Cards.draw("2026-01-02", 5, 0, st)))

	print("\n=== banish removes an option for good ===")
	var banished := Cards.eligible(_state({"pulse": 1}, {}, 4, ["orbit", "greed"]))
	var leaked := false
	for card in banished:
		if card["id"] == "orbit" or card["id"] == "greed":
			leaked = true
	_check("banished ids never reappear in the pool", not leaked)

	print("\n=== always three cards, even with nothing left ===")
	var everything: Dictionary = {}
	for weapon_id in Balance.WEAPONS:
		everything[weapon_id] = Weapons.max_level(weapon_id)
	var maxed_passives: Dictionary = {}
	for passive_id in Balance.PASSIVES:
		maxed_passives[passive_id] = int(Balance.PASSIVES[passive_id]["max"])
	var empty := Cards.draw("2026-01-01", 9, 0, _state(everything, maxed_passives, 5))
	_check("still offers %d cards" % Balance.LEVEL_UP_CHOICES,
		empty.size() == Balance.LEVEL_UP_CHOICES)

	print("\n=== daily slot count ===")
	var slots := Daily.weapon_slots("2026-01-01")
	_check("in the 3-5 band (%d)" % slots, slots >= 3 and slots <= 5)
	_check("same date -> same count", slots == Daily.weapon_slots("2026-01-01"))
	var varies := false
	for day in range(1, 40):
		if Daily.weapon_slots("2026-02-%02d" % day) != slots:
			varies = true
	_check("varies across dates", varies)

	player.free()
	print("\nRESULT: %s" % ("PASS" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)


func _ids(cards: Array) -> Array:
	var out := []
	for card in cards:
		out.append("%s/%s" % [card["kind"], card["id"]])
	return out
