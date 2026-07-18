class_name Difficulty
extends RefCounted

## Continuous, unbounded difficulty ramp for the endless model (GDD section 7).
##
## Replaces the old fixed 5-tier table. Everything here is a pure function of
## elapsed seconds, which matters for two reasons:
##
##   1. There is no longer a 10:00 ceiling, so the curve must keep climbing
##      forever rather than plateauing at whatever the last tier said.
##   2. A pure function of time is trivially deterministic. Difficulty never
##      reads player state — scaling off player level or kill count would both
##      punish good play and break seed comparability between players.

# --- Spawn rate --------------------------------------------------------------
# Exponential decay toward a floor. The floor exists so the spawn loop cannot
# be driven to zero interval and spin the frame budget away.
const INTERVAL_START := 1.00
const INTERVAL_FLOOR := 0.16
const INTERVAL_TAU := 300.0

# --- Wave size ---------------------------------------------------------------
# Linear and unbounded: +1 enemy per spawn every COUNT_STEP seconds.
const COUNT_STEP := 110.0

# --- Enemy toughness ---------------------------------------------------------
# Superlinear in minutes, so late minutes bite harder than early ones.
const HP_COEFF := 0.115
const HP_EXP := 1.3

# --- Boss cadence ------------------------------------------------------------
const BOSS_FIRST := 180.0
const BOSS_INTERVAL := 180.0
## Steep, because player DPS compounds hard through the upgrade pool. A gentler
## curve makes bosses trivial by the third appearance.
const BOSS_HP_BASE := 700.0
const BOSS_HP_SCALE := 1.9
const BOSS_DAMAGE_BASE := 25.0
const BOSS_DAMAGE_SCALE := 1.22
const BOSS_SPEED_BASE := 78.0
const BOSS_SPEED_CAP := 120.0
const BOSS_SCORE_BASE := 600


static func spawn_interval(elapsed: float) -> float:
	return INTERVAL_FLOOR + (INTERVAL_START - INTERVAL_FLOOR) * exp(-elapsed / INTERVAL_TAU)


static func spawn_count(elapsed: float) -> int:
	return 1 + floori(elapsed / COUNT_STEP)


static func hp_multiplier(elapsed: float) -> float:
	return 1.0 + HP_COEFF * pow(elapsed / 60.0, HP_EXP)


static func _ramp(elapsed: float, start: float, duration: float) -> float:
	return clampf((elapsed - start) / duration, 0.0, 1.0)


## Weighted spawn table as a function of time. Types phase in and their shares
## drift; Drifters never vanish but shrink from the whole table to a fraction.
##
## Always returns all five entries in a FIXED order, including zero-weight ones,
## so the weighted pick consumes the roll identically regardless of elapsed time.
static func type_weights(elapsed: float) -> Array:
	return [
		["drifter", 0.45 + 0.55 * exp(-elapsed / 400.0)],
		["swarmer", _ramp(elapsed, 120.0, 180.0) * 1.40],
		# Deliberately the rarest mid-tier type (~10% of spawns): at higher
		# weights the late game reads as a wall of incoming fire.
		["shooter", _ramp(elapsed, 240.0, 180.0) * 0.42],
		["tank", _ramp(elapsed, 360.0, 240.0) * 1.00],
		["splitter", _ramp(elapsed, 480.0, 240.0) * 0.90],
	]


# --- Bosses ------------------------------------------------------------------

## When boss `index` (1-based) is due. Fixed schedule, never player-dependent.
static func boss_time(index: int) -> float:
	return BOSS_FIRST + float(index - 1) * BOSS_INTERVAL


static func boss_hp(index: int) -> float:
	return BOSS_HP_BASE * pow(BOSS_HP_SCALE, float(index - 1))


static func boss_damage(index: int) -> float:
	return BOSS_DAMAGE_BASE * pow(BOSS_DAMAGE_SCALE, float(index - 1))


static func boss_speed(index: int) -> float:
	return minf(BOSS_SPEED_CAP, BOSS_SPEED_BASE + 4.0 * float(index - 1))


static func boss_score(index: int) -> int:
	return BOSS_SCORE_BASE * index
