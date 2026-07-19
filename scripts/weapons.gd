class_name Weapons
extends RefCounted

## Weapon stat resolution — LOGIC ONLY. Every number lives in balance.gd.
##
## Effective stats = the weapon's own level scaling, then the player's global
## passives on top. Passives are global by design (GDD section 4): it is what
## keeps them meaningful as the roster grows, and what makes the Overclock /
## Cooldown Core split matter — which of the two helps you depends on which
## weapons you are actually holding.


## Base and evolved weapons share one lookup so every downstream caller —
## stats, the HUD, the digest — treats them identically.
static func definition(weapon_id: String) -> Dictionary:
	if Balance.WEAPONS.has(weapon_id):
		return Balance.WEAPONS[weapon_id]
	return Balance.EVOLVED_WEAPONS.get(weapon_id, {})


static func is_evolved(weapon_id: String) -> bool:
	return Balance.EVOLVED_WEAPONS.has(weapon_id)


## The evolution a (weapon, passives) pair unlocks, or "" if none is ready.
static func ready_evolution(weapon_id: String, level: int, stacks: Dictionary) -> String:
	if level < max_level(weapon_id):
		return ""
	for recipe in Balance.EVOLUTIONS:
		if recipe["weapon"] != weapon_id:
			continue
		var passive_id: String = recipe["passive"]
		if int(stacks.get(passive_id, 0)) >= int(Balance.PASSIVES[passive_id]["max"]):
			return recipe["result"]
	return ""


## What a base weapon needs, for the card hint.
static func recipe_for(weapon_id: String) -> Dictionary:
	for recipe in Balance.EVOLUTIONS:
		if recipe["weapon"] == weapon_id:
			return recipe
	return {}


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
	out["pull"] = float(definition_data.get("pull", 0.0))
	return out


## What the NEXT level actually changes, generated from per_level.
##
## "Level 2" tells the player nothing at the moment they have to choose. This is
## derived from the data, so retuning a weapon updates its card automatically.
static func level_delta_text(weapon_id: String) -> String:
	var definition_data := definition(weapon_id)
	if definition_data.is_empty():
		return ""
	var per_level: Dictionary = definition_data["per_level"]
	var parts := PackedStringArray()

	if float(per_level.get("damage", 0.0)) != 0.0:
		parts.append("+%.0f damage" % float(per_level["damage"]))
	if int(per_level.get("count", 0)) != 0:
		var noun := "orb" if definition_data["behavior"] == "orbit" else "projectile"
		parts.append("+%d %s" % [int(per_level["count"]), noun])
	if int(per_level.get("pierce", 0)) != 0:
		parts.append("+%d pierce" % int(per_level["pierce"]))
	if float(per_level.get("radius", 0.0)) != 0.0:
		parts.append("+%.0f radius" % float(per_level["radius"]))
	var cooldown_mul := float(per_level.get("cooldown_mul", 1.0))
	if cooldown_mul != 1.0:
		parts.append("-%.0f%% cooldown" % ((1.0 - cooldown_mul) * 100.0))
	return "  ·  ".join(parts)


## True when a passive changes at least one number for the weapons held.
static func passive_applies_to(passive_id: String, owned: Dictionary) -> bool:
	var entry := passive(passive_id)
	if not entry.has("applies_to"):
		return true                     # player-affecting: always useful
	var rule: Dictionary = entry["applies_to"]
	for weapon_id in owned:
		var weapon := definition(weapon_id)
		if weapon.is_empty():
			continue
		if rule.has("behavior") and weapon["behavior"] in rule["behavior"]:
			return true
		if rule.has("cooldown_class") and weapon["cooldown_class"] in rule["cooldown_class"]:
			return true
	return false


## The recipe this card is part of, if the player holds the paired weapon.
## Returns {} when there is nothing worth saying.
static func recipe_hint(kind_is_passive: bool, card_id: String,
		owned: Dictionary, stacks: Dictionary) -> Dictionary:
	for recipe in Balance.EVOLUTIONS:
		var matches: bool = (recipe["passive"] == card_id) if kind_is_passive \
			else (recipe["weapon"] == card_id)
		if not matches:
			continue
		# A passive hint is only meaningful once the paired weapon is held;
		# a weapon hint is useful while drafting either way.
		if kind_is_passive and not owned.has(recipe["weapon"]):
			continue
		var weapon_id: String = recipe["weapon"]
		var passive_id: String = recipe["passive"]
		return {
			"result": definition(recipe["result"])["name"],
			"weapon_name": definition(weapon_id)["name"],
			"weapon_level": int(owned.get(weapon_id, 0)),
			"weapon_max": max_level(weapon_id),
			"passive_name": str(Balance.PASSIVES[passive_id]["name"]),
			"passive_stacks": int(stacks.get(passive_id, 0)),
			"passive_max": int(Balance.PASSIVES[passive_id]["max"]),
		}
	return {}


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
