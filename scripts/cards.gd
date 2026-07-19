class_name Cards
extends RefCounted

## The level-up card pool: new weapons, weapon levels and passive levels drawn
## from one deck.
##
## DETERMINISM. Two indexed streams, never a running one:
##   - the initial three cards come from `hash(date, level)`
##   - each reroll/banish comes from `hash(date, level, action_index)`
##
## That is the whole trick. Whether the player rerolls, how many times, and how
## long they deliberate cannot shift any other stream — so two players who draft
## completely differently still face identical waves.

const KIND_WEAPON_NEW := "weapon_new"
const KIND_WEAPON_LEVEL := "weapon_level"
const KIND_PASSIVE := "passive"
const KIND_HEAL := "heal"
const KIND_EVOLUTION := "evolution"


## Everything currently offerable, in a FIXED order.
##
## Order matters: the draw indexes into this array, so an unstable order (a
## Dictionary's iteration order, say) would make the same seed produce different
## cards on different machines.
static func eligible(state: Dictionary) -> Array:
	var pool := []
	var owned: Dictionary = state["weapons"]        # id -> level
	var stacks: Dictionary = state["passives"]      # id -> stacks
	var banished: Array = state["banished"]
	var slots: int = state["slots"]

	# Evolutions first: an unlocked recipe should be visible the moment it is
	# available, not buried behind a level card for the same weapon.
	for weapon_id in owned:
		var evolution := Weapons.ready_evolution(weapon_id, int(owned[weapon_id]), stacks)
		if evolution == "":
			continue
		pool.append({
			"kind": KIND_EVOLUTION, "id": evolution, "base": weapon_id,
			"name": Weapons.definition(evolution)["name"],
			"desc": Weapons.definition(evolution)["desc"],
			"level": 1, "hint": {},
		})

	for weapon_id in Balance.WEAPONS:
		if banished.has(weapon_id):
			continue
		if owned.has(weapon_id):
			if int(owned[weapon_id]) < Weapons.max_level(weapon_id):
				pool.append(_weapon_level_card(weapon_id, owned, stacks))
		elif owned.size() < slots:
			# Only offer new weapons while a slot is free; once full, the deck
			# is levels for what you hold.
			pool.append({
				"kind": KIND_WEAPON_NEW, "id": weapon_id,
				"name": Balance.WEAPONS[weapon_id]["name"],
				"desc": Balance.WEAPONS[weapon_id]["desc"],
				"level": 1,
				"hint": Weapons.recipe_hint(false, weapon_id, owned, stacks),
			})

	for weapon_id in owned:
		if not Weapons.is_evolved(weapon_id):
			continue
		if int(owned[weapon_id]) < Weapons.max_level(weapon_id):
			pool.append(_weapon_level_card(weapon_id, owned, stacks))

	for passive_id in Balance.PASSIVES:
		if banished.has(passive_id):
			continue
		var entry: Dictionary = Balance.PASSIVES[passive_id]
		var held := int(stacks.get(passive_id, 0))
		if held >= int(entry["max"]):
			continue

		var hint := Weapons.recipe_hint(true, passive_id, owned, stacks)
		# Skip passives that change no number for the weapons held — UNLESS the
		# passive is the evolution ingredient for one of them. Without that
		# carve-out, filtering would quietly make evolutions unreachable, which
		# is a worse bug than the wasted card it fixes.
		if hint.is_empty() and not Weapons.passive_applies_to(passive_id, owned):
			continue

		pool.append({
			"kind": KIND_PASSIVE, "id": passive_id,
			"name": entry["name"], "desc": entry["desc"],
			"level": held + 1, "hint": hint,
		})

	return pool


static func _weapon_level_card(weapon_id: String, owned: Dictionary,
		stacks: Dictionary) -> Dictionary:
	return {
		"kind": KIND_WEAPON_LEVEL, "id": weapon_id,
		"name": Weapons.definition(weapon_id)["name"],
		"desc": Weapons.level_delta_text(weapon_id),
		"level": int(owned[weapon_id]) + 1,
		"hint": Weapons.recipe_hint(false, weapon_id, owned, stacks),
	}


## Draw N distinct cards. `action_index` is 0 for the level's first offer and
## increments per reroll/banish, so every draw is reproducible in isolation.
static func draw(date_string: String, level_index: int, action_index: int,
		state: Dictionary) -> Array:
	var rng := GameSeed.make_card_rng(date_string, level_index, action_index)
	var pool := eligible(state)

	var chosen := []
	while chosen.size() < Balance.LEVEL_UP_CHOICES and not pool.is_empty():
		var index := rng.randi_range(0, pool.size() - 1)
		chosen.append(pool[index])
		pool.remove_at(index)

	# Everything maxed or banished: still give the player something to take.
	while chosen.size() < Balance.LEVEL_UP_CHOICES:
		chosen.append({
			"kind": KIND_HEAL, "id": Balance.CARD_FALLBACK["id"],
			"name": Balance.CARD_FALLBACK["name"],
			"desc": Balance.CARD_FALLBACK["desc"], "level": 0, "hint": {},
		})
	return chosen
