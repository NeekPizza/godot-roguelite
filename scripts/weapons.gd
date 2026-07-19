class_name Weapons
extends RefCounted

## Weapon stat resolution — LOGIC ONLY. Every number lives in balance.gd.
##
## Effective stats = the weapon's own level scaling, then the player's global
## passives on top. Passives are global by design (GDD section 4): it is what
## keeps them meaningful as the roster grows, and what makes the Overclock /
## Cooldown Core split matter — which of the two helps you depends on which
## weapons you are actually holding.


static func definition(weapon_id: String) -> Dictionary:
	return Balance.WEAPONS.get(weapon_id, {})


static func max_level(weapon_id: String) -> int:
	return int(definition(weapon_id).get("max_level", 1))


## Resolve a weapon at `level` against a player's passive multipliers.
static func stats(weapon_id: String, level: int, player: Node) -> Dictionary:
	var definition_data := definition(weapon_id)
	if definition_data.is_empty():
		return {}

	var base: Dictionary = definition_data["base"]
	var per_level: Dictionary = definition_data["per_level"]
	var steps := float(maxi(0, level - 1))

	var out := base.duplicate()
	out["damage"] = base["damage"] + float(per_level.get("damage", 0.0)) * steps
	out["count"] = int(base["count"]) + int(per_level.get("count", 0)) * int(steps)
	out["pierce"] = int(base["pierce"]) + int(per_level.get("pierce", 0)) * int(steps)
	out["radius"] = base["radius"] + float(per_level.get("radius", 0.0)) * steps
	out["cooldown"] = base["cooldown"] * pow(float(per_level.get("cooldown_mul", 1.0)), steps)

	# --- global passives -----------------------------------------------------
	out["damage"] *= player.damage_mult
	out["speed"] = float(base.get("speed", 0.0)) * player.projectile_speed_mult
	out["pierce"] = int(out["pierce"]) + player.pierce_bonus
	out["radius"] *= player.area_scale

	# Split Shot adds projectiles to anything that fires them, and orbs to Orbit.
	if definition_data["behavior"] != "nova":
		out["count"] = int(out["count"]) + player.projectile_bonus

	# The split the loadout hinges on.
	if definition_data["cooldown_class"] == "shot":
		out["cooldown"] /= maxf(0.01, player.fire_rate_mult)
	else:
		out["cooldown"] *= player.volley_cooldown_mult

	out["cooldown"] = maxf(0.05, out["cooldown"])
	out["behavior"] = definition_data["behavior"]
	return out


# --- Passives ----------------------------------------------------------------

static func passive(passive_id: String) -> Dictionary:
	return Balance.PASSIVES.get(passive_id, {})


## Apply one stack. Effects are declared data, so a new passive touching an
## existing stat needs no code change at all.
static func apply_passive(passive_id: String, player: Node) -> void:
	var entry := passive(passive_id)
	if entry.is_empty():
		push_error("Weapons.apply_passive: unknown passive '%s'" % passive_id)
		return
	for effect in entry["effects"]:
		var stat: String = effect["stat"]
		var value = effect["value"]
		match effect["op"]:
			"mul":
				player.set(stat, player.get(stat) * value)
			"add":
				player.set(stat, player.get(stat) + value)
			"add_max_hp":
				player.max_hp += value
				player.heal(value)   # grant the headroom now, not on the next pickup
			_:
				push_error("Weapons.apply_passive: unknown op '%s'" % effect["op"])
