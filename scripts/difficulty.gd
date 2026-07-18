class_name Difficulty
extends RefCounted

## The endless difficulty ramp — FORMULAS ONLY. Every number comes from
## balance.gd; tune there, not here (GDD section 7).
##
## Everything is a pure function of elapsed seconds, which matters twice over:
##
##   1. There is no 10:00 ceiling, so the curve must keep climbing forever
##      rather than plateauing at whatever a last tier said.
##   2. A pure function of time is trivially deterministic. Difficulty never
##      reads player state — scaling off level or kill count would both punish
##      good play and break seed comparability between players.

static func spawn_interval(elapsed: float) -> float:
	var floor_value := Balance.SPAWN_INTERVAL_FLOOR
	var head := Balance.SPAWN_INTERVAL_START - floor_value
	return floor_value + head * exp(-elapsed / Balance.SPAWN_INTERVAL_TAU)


static func spawn_count(elapsed: float) -> int:
	return 1 + floori(elapsed / Balance.SPAWN_COUNT_STEP)


static func hp_multiplier(elapsed: float) -> float:
	return 1.0 + Balance.ENEMY_HP_COEFF * pow(elapsed / 60.0, Balance.ENEMY_HP_EXP)


static func _ramp(elapsed: float, start: float, duration: float) -> float:
	return clampf((elapsed - start) / duration, 0.0, 1.0)


## Weighted spawn table as a function of time. Drifters decay from the whole
## table toward a floor; every other type phases in on its own schedule.
##
## Always returns every entry in a FIXED order, including zero-weight ones, so a
## spawn consumes the same number of RNG draws at any elapsed time.
static func type_weights(elapsed: float) -> Array:
	var table := [[
		"drifter",
		Balance.DRIFTER_WEIGHT_FLOOR
			+ Balance.DRIFTER_WEIGHT_HEAD * exp(-elapsed / Balance.DRIFTER_WEIGHT_TAU),
	]]
	for entry in Balance.TYPE_SCHEDULE:
		var weight: float = _ramp(elapsed, entry["unlock"], entry["ramp"]) * entry["weight"]
		table.append([entry["id"], weight])
	return table


## Weighted pick driven by an already-drawn roll, so the caller controls exactly
## how much RNG each spawn consumes.
static func pick_type(table: Array, roll: float) -> String:
	var total := 0.0
	for entry in table:
		total += entry[1]
	var target := roll * total
	for entry in table:
		target -= entry[1]
		if target <= 0.0:
			return entry[0]
	return table[table.size() - 1][0]


# --- Bosses ------------------------------------------------------------------

## When boss `index` (1-based) is due. Fixed schedule, never player-dependent.
static func boss_time(index: int) -> float:
	return Balance.BOSS_FIRST_TIME + float(index - 1) * Balance.BOSS_INTERVAL


static func boss_hp(index: int) -> float:
	return Balance.BOSS_HP_BASE * pow(Balance.BOSS_HP_SCALE, float(index - 1))


static func boss_damage(index: int) -> float:
	return Balance.BOSS_DAMAGE_BASE * pow(Balance.BOSS_DAMAGE_SCALE, float(index - 1))


static func boss_speed(index: int) -> float:
	return minf(Balance.BOSS_SPEED_CAP,
		Balance.BOSS_SPEED_BASE + Balance.BOSS_SPEED_STEP * float(index - 1))


static func boss_score(index: int) -> int:
	return Balance.BOSS_SCORE_BASE * index
