class_name Daily
extends RefCounted

## Per-day rules derived from the date alone.
##
## Deliberately STATIC and side-effect free so the menu can show today's rules
## before a run exists.

## How many weapons the day allows — currently a flat 3 for every seed
## (WEAPON_SLOT_WEIGHTS), so it is no longer surfaced in the UI. The RNG draw
## STAYS regardless: enemy_roster() burns a matching randf() to stay in step,
## so dropping this draw would silently change what every past seed means.
static func weapon_slots(date_string: String) -> int:
	var rng := GameSeed.make_daily_rng(date_string)
	var roll := rng.randf()

	var total := 0.0
	for entry in Balance.WEAPON_SLOT_WEIGHTS:
		total += entry[1]
	var target := roll * total
	for entry in Balance.WEAPON_SLOT_WEIGHTS:
		target -= entry[1]
		if target <= 0.0:
			return int(entry[0])
	return int(Balance.WEAPON_SLOT_WEIGHTS[0][0])


## Which enemy types are live today: the core two plus a seed-picked selection.
##
## Drawn from the SAME `daily` stream as the slot count, immediately after it.
## The order of these two draws is load-bearing — swapping them would change
## what every past date means.
static func enemy_roster(date_string: String) -> Array:
	var rng := GameSeed.make_daily_rng(date_string)
	rng.randf()                      # consumed by weapon_slots; keep in step

	var pool := Balance.ENEMY_POOL.duplicate()
	var roster := Balance.ENEMY_CORE.duplicate()
	for i in mini(Balance.ENEMY_ROSTER_PICK, pool.size()):
		var index := rng.randi_range(0, pool.size() - 1)
		roster.append(pool[index])
		pool.remove_at(index)
	return roster


## Human-readable summary for the menu. Weapon slots are a flat 3 every day, so
## stating the count here said nothing; the roster is the part that varies.
static func summary(date_string: String) -> String:
	var names := PackedStringArray()
	for type_id in enemy_roster(date_string):
		names.append(str(Balance.ENEMY_TYPES[type_id]["name"]))
	return "Today: %s" % ", ".join(names)
