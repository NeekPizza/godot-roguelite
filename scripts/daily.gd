class_name Daily
extends RefCounted

## Per-day rules derived from the date alone.
##
## Deliberately STATIC and side-effect free so the menu can show today's rules
## before a run exists — the ranked confirmation has to display the weapon-slot
## count, and a player must be able to see it before spending their attempt.

## How many weapons the day allows. The single biggest lever the seed has on how
## a day plays: three slots forces specialisation and early evolutions, five
## invites a generalist sprawl.
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


## Human-readable summary for the menu.
static func summary(date_string: String) -> String:
	return "Weapon slots today: %d" % weapon_slots(date_string)
