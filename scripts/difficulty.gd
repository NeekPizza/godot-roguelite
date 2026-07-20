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


## Composition for a stage (v1.3).
##
## The old table gated types behind ABSOLUTE unlock times (shooters at 4:00,
## tanks at 6:00). Stages reset the clock every 150 s, so nothing past Swarmer
## ever appeared — a stage-6 roster of seven types still spawned only Drifters.
##
## Now the stage's roster decides WHAT can appear and this decides the mix:
## every roster type is live from the start of the stage, eased in over the
## first few seconds, with Drifters ceding share as stages go deeper.
static func stage_type_weights(stage: int, stage_elapsed: float,
		roster: Array) -> Array:
	var ease := clampf(stage_elapsed / Balance.STAGE_MIX_EASE, 0.25, 1.0)
	var table := []
	for entry in Balance.TYPE_SCHEDULE_BASE:
		var id: String = entry["id"]
		if not roster.has(id):
			table.append([id, 0.0])          # keep the slot so draw counts hold
			continue
		if id == "drifter":
			table.append([id, Balance.DRIFTER_WEIGHT_FLOOR
				+ Balance.DRIFTER_WEIGHT_HEAD * exp(-float(stage - 1) / 2.0)])
		else:
			table.append([id, float(entry["weight"]) * ease])
	return table


## Restricted to today's roster. Types not active today keep their entry at a
## zero weight rather than being removed, so a spawn consumes exactly the same
## number of draws whatever the roster happens to be.
static func type_weights_for(elapsed: float, roster: Array) -> Array:
	var table := type_weights(elapsed)
	for entry in table:
		if not roster.has(entry[0]):
			entry[1] = 0.0
	return table


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


## Which archetype fills a slot. INDEXED, not a running stream: a boss killed
## early, late, or not at all cannot change who shows up next.
static func boss_archetype(date_string: String, slot: int) -> String:
	var rng := GameSeed.make_boss_rng(date_string, slot)
	var ids := Balance.BOSS_ARCHETYPES.keys()
	return ids[rng.randi_range(0, ids.size() - 1)]


## The drop a boss slot carries, decided WITH the slot assignment rather than at
## death, which is player-timed.
static func boss_drop(date_string: String, slot: int) -> String:
	var rng := GameSeed.make_boss_rng(date_string, slot)
	rng.randi()                       # consumed by boss_archetype; keep in step
	return Drops.pick(rng.randf())


## Pattern parameters for a boss at `index`, with escalation applied and the
## telegraph and cadence floors enforced.
static func boss_pattern(pattern_id: String, index: int) -> Dictionary:
	var base: Dictionary = Balance.BOSS_PATTERNS[pattern_id]
	var steps := float(maxi(0, index - 1))
	var out := base.duplicate(true)
	var per_index: Dictionary = base["per_index"]

	for key in per_index:
		var value: float = per_index[key]
		if key.ends_with("+"):
			var field: String = key.substr(0, key.length() - 1)
			out[field] = float(out[field]) + value * steps
		elif key.ends_with(" x"):
			var field_mul: String = key.substr(0, key.length() - 2)
			out[field_mul] = float(out[field_mul]) * pow(value, steps)

	out["bullets"] = maxi(3, int(round(float(out["bullets"]))))
	out["telegraph"] = maxf(Balance.BOSS_TELEGRAPH_MIN, float(out["telegraph"]))
	out["cadence"] = maxf(Balance.BOSS_CADENCE_MIN, float(out["cadence"]))
	out["spread_deg"] = maxf(8.0, float(out["spread_deg"]))
	if out.has("gap_deg"):
		out["gap_deg"] = maxf(10.0, float(out["gap_deg"]))
	return out
