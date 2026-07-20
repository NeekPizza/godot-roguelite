class_name Meta
extends RefCounted

## Meta-progression maths — LOGIC ONLY; every number is in balance.gd.
##
## Two rules hold the design together (GDD sections 20-21):
##   1. Power CONVERGES. The aggregate ceiling is hard, so spending more can
##      never buy more than +10% total.
##   2. Effects are PLAYER-SIDE ONLY. Nothing here may reach a seeded schedule.


static func stat_ids() -> Array:
	return Balance.META_STATS.keys()


## Cost of the next purchase in a stat, given how many are already owned.
static func next_cost(owned: int) -> int:
	if owned >= Balance.META_MAX_BUYS:
		return -1                       # capped: nothing left to buy
	return int(round(Balance.META_COST_BASE * pow(Balance.META_COST_GROWTH, owned)))


static func total_spent(purchases: Dictionary) -> int:
	var total := 0
	for stat_id in purchases:
		for i in int(purchases[stat_id]):
			total += int(round(Balance.META_COST_BASE * pow(Balance.META_COST_GROWTH, i)))
	return total


static func total_purchases(purchases: Dictionary) -> int:
	var total := 0
	for stat_id in purchases:
		total += int(purchases[stat_id])
	return total


## How many purchases the aggregate ceiling allows in total.
static func max_total_purchases() -> int:
	return int(round(Balance.META_AGGREGATE_CAP / Balance.META_PER_BUY_WEIGHT))


## Raw aggregate weight before the ceiling is applied.
static func raw_weight(purchases: Dictionary) -> float:
	return float(total_purchases(purchases)) * Balance.META_PER_BUY_WEIGHT


## Scale applied to every effect once the ceiling binds. Buying past the cap
## dilutes rather than adds, so overspending can never out-power the ceiling.
static func throttle(purchases: Dictionary) -> float:
	var raw := raw_weight(purchases)
	if raw <= Balance.META_AGGREGATE_CAP or raw <= 0.0:
		return 1.0
	return Balance.META_AGGREGATE_CAP / raw


## Total meta power actually in effect, for the transparency readout.
static func effective_bonus(purchases: Dictionary) -> float:
	return minf(Balance.META_AGGREGATE_CAP, raw_weight(purchases))


## A stat's effect strength, 0..1 of its at_cap value, after throttling.
static func stat_fraction(purchases: Dictionary, stat_id: String) -> float:
	var owned := int(purchases.get(stat_id, 0))
	var fraction := float(owned) / float(Balance.META_MAX_BUYS)
	return clampf(fraction, 0.0, 1.0) * throttle(purchases)


## Apply every purchased effect to the player. Called once, at run start.
static func apply(player: Node, purchases: Dictionary) -> void:
	for stat_id in Balance.META_STATS:
		var entry: Dictionary = Balance.META_STATS[stat_id]
		var fraction := stat_fraction(purchases, stat_id)
		if fraction <= 0.0:
			continue
		if entry["kind"] != "mult":
			continue                    # headstart and rerolls are read by run.gd
		var target: String = entry["target"]
		var scale := 1.0 + float(entry["at_cap"]) * fraction
		player.set(target, player.get(target) * scale)
	# pickup_radius has a setter that clamps to its own hard cap, so Lodestone
	# cannot push it past the ceiling the in-run passive already respects.


## Extra rerolls, as a milestone LADDER. The highest threshold reached wins.
static func bonus_rerolls(purchases: Dictionary) -> int:
	var owned := int(purchases.get("reroll", 0))
	var granted := 0
	var milestones: Dictionary = Balance.META_STATS["reroll"].get("milestones", {})
	for threshold in milestones:
		if owned >= int(threshold):
			granted = maxi(granted, int(milestones[threshold]))
	return granted


## Purchases still available before the aggregate ceiling binds.
static func budget_remaining(purchases: Dictionary) -> int:
	return maxi(0, max_total_purchases() - total_purchases(purchases))


## What the total power WOULD be after one more purchase in `stat_id`.
## Drives the live projection on the upgrade screen: the tradeoff has to be
## visible before committing, not discovered afterwards.
static func projected_bonus(purchases: Dictionary, stat_id: String) -> float:
	var next := purchases.duplicate()
	next[stat_id] = int(next.get(stat_id, 0)) + 1
	return effective_bonus(next)


## Next milestone description for a stat, or "" if it has none pending.
static func next_milestone_text(purchases: Dictionary, stat_id: String) -> String:
	var entry: Dictionary = Balance.META_STATS[stat_id]
	if not entry.has("milestones"):
		return ""
	var owned := int(purchases.get(stat_id, 0))
	var best := -1
	var thresholds: Array = entry["milestones"].keys()
	thresholds.sort()
	for threshold in thresholds:
		if owned < int(threshold):
			best = int(threshold)
			break
	if best < 0:
		return "all milestones reached"
	return "%d more → milestone" % (best - owned)


## Starting XP, as a fraction of the level-2 requirement.
static func starting_xp(purchases: Dictionary, level_two_requirement: int) -> int:
	var fraction := stat_fraction(purchases, "xp")
	return int(floor(float(level_two_requirement) * fraction
		* float(Balance.META_STATS["xp"]["at_cap"])))


## Points earned by a finished RANKED run. Practice and archive earn nothing —
## that check lives in run.gd, which knows the mode.
static func points_for_run(stage_reached: int) -> int:
	return Balance.META_POINTS_BASE + Balance.META_POINTS_PER_STAGE \
		* mini(stage_reached, Balance.META_POINTS_STAGE_CAP)


# --- Test profiles -----------------------------------------------------------

static func profile_none() -> Dictionary:
	var out := {}
	for stat_id in Balance.META_STATS:
		out[stat_id] = 0
	return out


## Fills round-robin until the aggregate ceiling is reached, which is also the
## cheapest way to reach it — escalating per-stat costs make spreading cheaper
## than concentrating.
static func profile_max() -> Dictionary:
	var out := profile_none()
	var ids := stat_ids()
	var budget := max_total_purchases()
	var placed := 0
	while placed < budget:
		var moved := false
		for stat_id in ids:
			if placed >= budget:
				break
			if int(out[stat_id]) < Balance.META_MAX_BUYS:
				out[stat_id] = int(out[stat_id]) + 1
				placed += 1
				moved = true
		if not moved:
			break                       # every stat capped before the budget ran out
	return out
