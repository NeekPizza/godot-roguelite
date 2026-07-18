class_name Upgrades
extends RefCounted

## The Phase 1 upgrade pool (GDD section 6). Effects are applied to the player's
## stat block in `apply()`.

const HEAL_ID := "heal"

const POOL := [
	{"id": "overclock", "name": "Overclock",   "desc": "+25% fire rate",   "max": 5},
	{"id": "hollow",    "name": "Hollow Point","desc": "+5 damage",        "max": 8},
	{"id": "split",     "name": "Split Shot",  "desc": "+1 projectile",    "max": 3},
	{"id": "pierce",    "name": "Piercing",    "desc": "+1 pierce",        "max": 3},
	{"id": "kinetics",  "name": "Kinetics",    "desc": "+15% move speed",  "max": 4},
	# Additive, not multiplicative. A percentage compounds: 60px * 1.4^4 = 230px
	# and it only got worse with more stacks. Flat +30 caps out at 60+120=180,
	# which sits under MAX_PICKUP_RADIUS by design rather than by luck.
	{"id": "magnetism", "name": "Magnetism",   "desc": "+30 pickup range", "max": 4},
]

const HEAL_CARD := {"id": HEAL_ID, "name": "Repair", "desc": "+10 HP", "max": -1}


## Draw 3 distinct cards for `level_index`, excluding maxed-out upgrades.
## Backfills with Repair so there are always exactly 3 choices (GDD section 6).
static func draw_choices(date_string: String, level_index: int, stacks: Dictionary) -> Array:
	var rng := GameSeed.make_upgrade_rng(date_string, level_index)

	var available := []
	for entry in POOL:
		if stacks.get(entry["id"], 0) < entry["max"]:
			available.append(entry)

	var choices := []
	while choices.size() < 3 and not available.is_empty():
		var index := rng.randi_range(0, available.size() - 1)
		choices.append(available[index])
		available.remove_at(index)

	while choices.size() < 3:
		choices.append(HEAL_CARD)

	return choices


static func apply(upgrade_id: String, player: Node) -> void:
	match upgrade_id:
		"overclock":
			player.fire_rate *= 1.25
		"hollow":
			player.damage += 5.0
		"split":
			player.projectile_count += 1
		"pierce":
			player.pierce += 1
		"kinetics":
			player.move_speed *= 1.15
		"magnetism":
			player.pickup_radius += 30.0
		HEAL_ID:
			player.heal(10.0)
