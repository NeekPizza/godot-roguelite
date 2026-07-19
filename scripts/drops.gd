class_name Drops
extends RefCounted

## Drop scheduling — the whole run's drops decided up front.
##
## DETERMINISM (GDD section 9): a drop resolves at a moment nobody controls, so
## none of it may be rolled then. The schedule is built at run start from the
## `drops` stream; boss and elite drops are chosen when the boss slot is
## assigned or the elite spawns, and merely read back on death.


## Weighted pick from an already-drawn roll, so callers control exactly how much
## RNG each decision consumes. Iterates Balance.DROPS in its declared order,
## which is fixed.
static func pick(roll: float) -> String:
	var total := 0.0
	for drop_id in Balance.DROPS:
		total += float(Balance.DROPS[drop_id]["weight"])
	var target := roll * total
	for drop_id in Balance.DROPS:
		target -= float(Balance.DROPS[drop_id]["weight"])
		if target <= 0.0:
			return drop_id
	return Balance.DROPS.keys()[0]


## [{time, position, id}, ...] in ascending time. Absolute world positions:
## never relative to the player, who is somewhere different for everyone.
static func build_schedule(date_string: String) -> Array:
	var rng := GameSeed.make_drops_rng(date_string)
	var bounds := Arena.rect()
	var margin := Balance.DROP_EDGE_MARGIN

	var schedule := []
	var time := Balance.DROP_FIRST_TIME
	for i in Balance.DROP_SCHEDULE_COUNT:
		var jitter := rng.randf_range(-Balance.DROP_JITTER, Balance.DROP_JITTER)
		var position := Vector2(
			rng.randf_range(bounds.position.x + margin, bounds.end.x - margin),
			rng.randf_range(bounds.position.y + margin, bounds.end.y - margin))
		schedule.append({
			"time": maxf(1.0, time + jitter),
			"position": position,
			"id": pick(rng.randf()),
		})
		time += Balance.DROP_INTERVAL
	return schedule


## Short stable fingerprint of a schedule, for the determinism digest.
static func schedule_digest(schedule: Array) -> String:
	var accumulator := 1469598103934665603
	for entry in schedule:
		accumulator = accumulator ^ GameSeed.hash_string("%s@%.2f@%.1f,%.1f" % [
			entry["id"], entry["time"],
			entry["position"].x, entry["position"].y])
		accumulator *= 1099511628211
	return "%d" % accumulator
