class_name Upgrades
extends RefCounted

## Level-up card draw and effect application — LOGIC ONLY. The pool and every
## effect value live in balance.gd (GDD section 6).
##
## Effects are data, not branches: an upgrade declares a stat, an op and a
## value, so adding one is a single row in Balance.UPGRADES with no code change.

const HEAL_ID := "heal"


## Draw N distinct cards for `level_index`, excluding maxed-out upgrades.
## Backfills with the fallback card so there are always exactly N choices.
static func draw_choices(date_string: String, level_index: int, stacks: Dictionary) -> Array:
	var rng := GameSeed.make_upgrade_rng(date_string, level_index)

	var available := []
	for entry in Balance.UPGRADES:
		if stacks.get(entry["id"], 0) < entry["max"]:
			available.append(entry)

	var choices := []
	while choices.size() < Balance.LEVEL_UP_CHOICES and not available.is_empty():
		var index := rng.randi_range(0, available.size() - 1)
		choices.append(available[index])
		available.remove_at(index)

	while choices.size() < Balance.LEVEL_UP_CHOICES:
		choices.append(Balance.UPGRADE_FALLBACK)

	return choices


static func find(upgrade_id: String) -> Dictionary:
	for entry in Balance.UPGRADES:
		if entry["id"] == upgrade_id:
			return entry
	return Balance.UPGRADE_FALLBACK


## Apply a declared effect. Unknown ops are a data error, not a silent no-op.
static func apply(upgrade_id: String, player: Node) -> void:
	var entry := find(upgrade_id)
	var stat: String = entry["stat"]
	var value = entry["value"]

	match entry["op"]:
		"mul":
			player.set(stat, player.get(stat) * value)
		"add":
			player.set(stat, player.get(stat) + value)
		"add_max_hp":
			player.max_hp += value
			player.heal(value)   # grant the headroom now, not on the next pickup
		"heal":
			player.heal(value)
		_:
			push_error("Upgrades.apply: unknown op '%s' on '%s'" % [entry["op"], upgrade_id])
