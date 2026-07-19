class_name Balance
extends RefCounted

## THE SINGLE TUNING SURFACE FOR THE WHOLE GAME.
##
## Every number a designer would want to change lives here and nowhere else.
## Gameplay scripts contain formulas and behaviour; this file contains values.
## If you find yourself editing a literal number anywhere else in scripts/,
## that number belongs here instead.
##
## This file contains NO logic — only named data. Rebalancing means editing
## this one file; the formulas that consume it live in difficulty.gd (ramp),
## score.gd (scoring) and upgrades.gd (upgrade application).
##
## Adding content is meant to be cheap:
##   - a new enemy   -> add a row to ENEMY_TYPES, add its id to TYPE_SCHEDULE
##   - a new upgrade -> add a row to UPGRADES (no code change; effects are
##                      declared as stat/op/value, not written as branches)

# =============================================================================
# WORLD
# =============================================================================
const WORLD_SIZE := Vector2(3200.0, 1800.0)
## How far outside the walls enemies appear, so nothing spawns on the player.
const SPAWN_MARGIN := 48.0
## Enemies further than SPAWN_MARGIN * this outside the world are culled.
const DESPAWN_SLACK := 4.0

# =============================================================================
# PLAYER
# =============================================================================
const PLAYER_MAX_HP := 100.0
const PLAYER_MOVE_SPEED := 220.0
const PLAYER_RADIUS := 14.0
const PLAYER_IFRAMES := 0.5
const PLAYER_PICKUP_RADIUS := 60.0
## Hard ceiling on pickup radius however upgrades stack. Without it, collection
## stops being a movement decision and becomes an automatic sweep.
const PLAYER_PICKUP_RADIUS_MAX := 200.0

# --- Dash (v1.2, 6a) ---------------------------------------------------------
## The one active verb in a game otherwise about positioning, and the answer to
## being cornered.
const DASH_DISTANCE := 190.0
const DASH_DURATION := 0.16
## Outlasts the movement so it also covers the landing — an i-frame window that
## ends mid-dash would read as the dash "not working".
const DASH_IFRAMES := 0.32
const DASH_COOLDOWN := 3.0
## The tell. Invulnerability the player cannot see is indistinguishable from
## luck, and a dodge that reads as luck teaches nothing.
const DASH_ALPHA := 0.45
const DASH_AFTERIMAGES := 3
const DASH_AFTERIMAGE_LIFETIME := 0.26
const DASH_COOLDOWN_RING_RADIUS := 22.0

# =============================================================================
# WEAPONS (6b)
# =============================================================================
## Shared projectile geometry.
const PROJECTILE_RADIUS := 4.0
## Also the auto-target range for weapons that seek.
const PROJECTILE_RANGE := 500.0
const WEAPON_SPREAD_RADIANS := 0.18

## cooldown_class decides WHICH passive speeds a weapon up, so the passive
## choice depends on your loadout:
##   "shot"   -> Overclock (per-shot fire rate)
##   "volley" -> Cooldown Core (between-volley cooldown)
##
## Level scaling: additive per level for damage/count/pierce/radius,
## multiplicative for cooldown, applied (level - 1) times.
const WEAPONS := {
	"pulse": {
		"name": "Pulse", "desc": "Seeking shot at the nearest enemy",
		"behavior": "seek", "cooldown_class": "shot", "max_level": 5,
		"base": {"damage": 10.0, "cooldown": 0.50, "speed": 400.0, "count": 1,
				 "pierce": 0, "radius": 4.0, "lifetime": 1.4},
		"per_level": {"damage": 4.0, "count": 0, "pierce": 0, "radius": 0.0,
					  "cooldown_mul": 0.88},
	},
	"orbit": {
		"name": "Orbit", "desc": "Orbs circle you, damaging on contact",
		"behavior": "orbit", "cooldown_class": "volley", "max_level": 5,
		"base": {"damage": 8.0, "cooldown": 0.35, "speed": 2.2, "count": 2,
				 "pierce": 0, "radius": 78.0, "lifetime": 0.0},
		"per_level": {"damage": 3.0, "count": 1, "pierce": 0, "radius": 8.0,
					  "cooldown_mul": 0.94},
	},
	"curveball": {
		"name": "Curveball", "desc": "Shots arc outward, sweeping an area",
		"behavior": "curve", "cooldown_class": "shot", "max_level": 5,
		"base": {"damage": 9.0, "cooldown": 0.85, "speed": 330.0, "count": 2,
				 "pierce": 1, "radius": 5.0, "lifetime": 1.8, "curve": 2.6},
		"per_level": {"damage": 3.0, "count": 1, "pierce": 0, "radius": 0.0,
					  "cooldown_mul": 0.90},
	},
	"boomerang": {
		"name": "Boomerang", "desc": "Flies out and returns, hitting both ways",
		"behavior": "boomerang", "cooldown_class": "volley", "max_level": 5,
		"base": {"damage": 14.0, "cooldown": 1.30, "speed": 420.0, "count": 1,
				 "pierce": 3, "radius": 8.0, "lifetime": 1.6},
		"per_level": {"damage": 5.0, "count": 1, "pierce": 1, "radius": 1.0,
					  "cooldown_mul": 0.90},
	},
	"nova": {
		"name": "Nova", "desc": "Expanding ring that knocks enemies back",
		"behavior": "nova", "cooldown_class": "volley", "max_level": 5,
		"base": {"damage": 12.0, "cooldown": 2.60, "speed": 420.0, "count": 1,
				 "pierce": 0, "radius": 190.0, "lifetime": 0.45,
				 "knockback": 180.0},
		"per_level": {"damage": 5.0, "count": 0, "pierce": 0, "radius": 26.0,
					  "cooldown_mul": 0.90},
	},
}

## Everyone starts with Pulse so the first minute is never weaponless.
const STARTING_WEAPON := "pulse"

## CAPPED AT 3. Kept as a weight table rather than a bare constant so re-opening
## day-to-day variance stays a data change.
##
## The draw from the `daily` stream is deliberately still made even though the
## outcome is fixed: 6e adds the enemy-roster draw to that same stream, and
## dropping this draw later would shift the roster draw and silently change what
## every past seed means.
const WEAPON_SLOT_WEIGHTS := [[3, 1.0]]

# =============================================================================
# PASSIVES (global — they apply to every held weapon at once)
# =============================================================================
## A passive may carry several effects; `guard` needs two, and forcing it into
## one would mean a special case in the apply path.
##
## Ops: "mul" / "add" on a player property, plus "add_max_hp" and "heal".
const PASSIVES := {
	"overclock": {"name": "Overclock", "desc": "+25% fire rate (shot weapons)", "max": 5,
		"effects": [{"stat": "fire_rate_mult", "op": "mul", "value": 1.25}]},
	"cooldown_core": {"name": "Cooldown Core", "desc": "-10% volley cooldown", "max": 5,
		"effects": [{"stat": "volley_cooldown_mult", "op": "mul", "value": 0.90}]},
	"hollow": {"name": "Hollow Point", "desc": "+15% damage", "max": 8,
		"effects": [{"stat": "damage_mult", "op": "mul", "value": 1.15}]},
	"split": {"name": "Split Shot", "desc": "+1 projectile", "max": 3,
		"effects": [{"stat": "projectile_bonus", "op": "add", "value": 1}]},
	"pierce": {"name": "Piercing", "desc": "+1 pierce", "max": 3,
		"effects": [{"stat": "pierce_bonus", "op": "add", "value": 1}]},
	"velocity": {"name": "Velocity Coil", "desc": "+20% projectile speed", "max": 3,
		"effects": [{"stat": "projectile_speed_mult", "op": "mul", "value": 1.20}]},
	"amplifier": {"name": "Amplifier", "desc": "+15% area and size", "max": 4,
		"effects": [{"stat": "area_scale", "op": "mul", "value": 1.15}]},
	"kinetics": {"name": "Kinetics", "desc": "+15% move speed", "max": 4,
		"effects": [{"stat": "move_speed", "op": "mul", "value": 1.15}]},
	"magnetism": {"name": "Magnetism", "desc": "+30 pickup range", "max": 4,
		"effects": [{"stat": "pickup_radius", "op": "add", "value": 30.0}]},
	"vitality": {"name": "Vitality", "desc": "+20 max HP", "max": 4,
		"effects": [{"stat": "max_hp", "op": "add_max_hp", "value": 20.0}]},
	"guard": {"name": "Guard", "desc": "-15% dash cooldown, +10% i-frames", "max": 3,
		"effects": [{"stat": "dash_cooldown_scale", "op": "mul", "value": 0.85},
					{"stat": "dash_iframe_scale", "op": "mul", "value": 1.10}]},
	## XP only. The roster's "+drop luck" is deliberately absent: the drop
	## schedule is precomputed from the seed at run start, so a passive that
	## changed drop rates would make drops depend on the player's build and
	## forfeit the strongest determinism guarantee in the design.
	"greed": {"name": "Greed", "desc": "+15% XP gained", "max": 4,
		"effects": [{"stat": "xp_gain_mult", "op": "mul", "value": 1.15}]},
}

## Offered when nothing else is available, so there is always a choice to make.
const CARD_FALLBACK := {"id": "heal", "name": "Repair", "desc": "+25 HP", "heal": 25.0}

# =============================================================================
# XP AND LEVELLING
# =============================================================================
## XP needed for level N = XP_BASE + (N - 1) * XP_STEP
const XP_BASE := 6
const XP_STEP := 5

const LEVEL_UP_CHOICES := 3
const REROLLS_PER_RUN := 3
const BANISHES_PER_RUN := 2

# =============================================================================
# ENEMIES
# =============================================================================
## behavior: "chase" walks straight at the player.
##           "keep_distance" holds `preferred_range` and fires every
##           `shot_interval` seconds.
## Optional: splits_into / split_count for enemies that break apart on death.
const ENEMY_TYPES := {
	"drifter": {
		"hp": 20.0, "speed": 90.0, "damage": 10.0, "radius": 12.0,
		"score": 10, "xp": 1, "color": Color(1.0, 0.28, 0.85),
		"behavior": "chase", "shape": "square",
	},
	"swarmer": {
		"hp": 8.0, "speed": 175.0, "damage": 6.0, "radius": 8.0,
		"score": 6, "xp": 1, "color": Color(1.0, 0.55, 0.15),
		"behavior": "chase", "shape": "triangle",
	},
	"tank": {
		"hp": 90.0, "speed": 45.0, "damage": 20.0, "radius": 22.0,
		"score": 30, "xp": 3, "color": Color(0.65, 0.35, 1.0),
		"behavior": "chase", "shape": "hexagon",
	},
	"shooter": {
		"hp": 25.0, "speed": 70.0, "damage": 8.0, "radius": 13.0,
		"score": 20, "xp": 2, "color": Color(1.0, 0.25, 0.3),
		"behavior": "keep_distance", "shape": "diamond",
		"preferred_range": 340.0, "shot_interval": 3.2,
	},
	"splitter": {
		"hp": 40.0, "speed": 70.0, "damage": 12.0, "radius": 16.0,
		"score": 20, "xp": 2, "color": Color(0.3, 1.0, 0.6),
		"behavior": "chase", "shape": "nested_square",
		"splits_into": "swarmer", "split_count": 2,
	},
}

## Where split children appear, relative to the parent. Fixed offsets, never
## random: splitters die on player-dependent timing, so an RNG draw here would
## desync the shared spawn stream.
const SPLIT_OFFSETS := [Vector2(-26.0, -14.0), Vector2(26.0, 14.0)]

const ENEMY_SHOT_SPEED := 260.0
const ENEMY_SHOT_RANGE := 700.0
const ENEMY_SHOT_RADIUS := 5.0

# =============================================================================
# DIFFICULTY RAMP  (endless and unbounded — see difficulty.gd for the formulas)
# =============================================================================
## interval = SPAWN_INTERVAL_FLOOR + (START - FLOOR) * e^(-t / TAU)
const SPAWN_INTERVAL_START := 1.00
const SPAWN_INTERVAL_FLOOR := 0.16
const SPAWN_INTERVAL_TAU := 300.0

## count = 1 + floor(t / SPAWN_COUNT_STEP)
const SPAWN_COUNT_STEP := 110.0

## hp multiplier = 1 + HP_COEFF * (t / 60) ^ HP_EXP
const ENEMY_HP_COEFF := 0.115
const ENEMY_HP_EXP := 1.3

## Performance guard rail. When hit, spawns are skipped but their RNG draws
## still happen, so a strong player cannot desync the stream.
const ENEMY_CAP := 300

## Composition over time. Drifters decay from the whole table toward a floor;
## every other type phases in over `ramp` seconds after `unlock`.
const DRIFTER_WEIGHT_FLOOR := 0.45
const DRIFTER_WEIGHT_HEAD := 0.55
const DRIFTER_WEIGHT_TAU := 400.0
## Order is FIXED and every entry is always returned, including zero-weight
## ones, so a spawn consumes the same number of RNG draws at any elapsed time.
const TYPE_SCHEDULE := [
	{"id": "swarmer",  "unlock": 120.0, "ramp": 180.0, "weight": 1.40},
	# Deliberately the rarest mid-tier type (~10% of spawns): at higher weights
	# the late game reads as a wall of incoming fire.
	{"id": "shooter",  "unlock": 240.0, "ramp": 180.0, "weight": 0.42},
	{"id": "tank",     "unlock": 360.0, "ramp": 240.0, "weight": 1.00},
	{"id": "splitter", "unlock": 480.0, "ramp": 240.0, "weight": 0.90},
]

# =============================================================================
# BOSS  (one scaling archetype — GDD section 5b)
# =============================================================================
const BOSS_FIRST_TIME := 180.0
const BOSS_INTERVAL := 180.0
## Steep on purpose: player DPS compounds through fire rate x damage x
## projectile count x pierce, so a gentler curve makes bosses trivial by the
## third appearance.
const BOSS_HP_BASE := 700.0
const BOSS_HP_SCALE := 1.9
const BOSS_DAMAGE_BASE := 25.0
const BOSS_DAMAGE_SCALE := 1.22
const BOSS_SPEED_BASE := 78.0
const BOSS_SPEED_STEP := 4.0
const BOSS_SPEED_CAP := 120.0
const BOSS_SCORE_BASE := 600
const BOSS_RADIUS := 46.0
const BOSS_BURST_INTERVAL := 3.4
const BOSS_BURST_SHOTS := 8
## Radians added per burst so the gaps in the ring move between volleys.
const BOSS_BURST_ROTATION := 0.21
## Fraction of contact damage each burst projectile deals.
const BOSS_SHOT_DAMAGE_SCALE := 0.35
const BOSS_COLOR := Color(1.0, 0.30, 0.55)
## Guaranteed payout on death, at fixed ring offsets (no RNG).
const BOSS_GEM_COUNT := 12
const BOSS_GEM_VALUE := 3
const BOSS_GEM_RADIUS := 62.0

# =============================================================================
# SCORING
# =============================================================================
const SCORE_PER_SECOND := 5
const SCORE_PER_XP := 2
## Plausibility bound for submitted scores — far above any legitimate run.
## See score.gd for the int32 headroom argument.
const SCORE_CEILING := 50_000_000
## How many run records to keep locally, and how many to show on the run-over
## screen.
const SCORE_HISTORY_MAX := 200
const SCORE_TABLE_ROWS := 5

# =============================================================================
# PICKUPS
# =============================================================================
## Single source of truth: the EXP bar reads this so the bar and the gems on the
## field are provably the same colour.
const GEM_COLOR := Color(1.0, 0.92, 0.25)
const HEALTH_COLOR := Color(0.30, 0.95, 0.45)
const GEM_RADIUS := 5.0
const GEM_ATTRACT_SPEED := 420.0

# =============================================================================
# GAME FEEL  (cosmetic only — never affects gameplay state)
# =============================================================================
const SHAKE_ON_KILL := 1.2
const SHAKE_ON_PLAYER_HURT := 7.0
const SHAKE_ON_BOSS_SPAWN := 6.0
const SHAKE_ON_BOSS_KILL := 12.0
const SHAKE_MAX := 14.0
const SHAKE_DECAY := 9.0

const PARTICLES_ON_KILL := 10
const PARTICLES_ON_PLAYER_HURT := 16
const PARTICLES_ON_BOSS_KILL := 90
const PARTICLE_SPEED_KILL := 170.0
const PARTICLE_SPEED_HURT := 210.0
const PARTICLE_SPEED_BOSS := 340.0
const PARTICLE_MAX := 600
## Spark physics.
const PARTICLE_GRAVITY := 220.0
const PARTICLE_DRAG := 2.4
## Background grid spacing (motion cue for the scrolling camera).
const GRID_STEP := 160.0

# =============================================================================
# AUDIO  (decibels; Phase 5 exposes music/SFX as settings sliders)
# =============================================================================
const MUSIC_DB := -17.0
const SFX_DB := {
	"shoot": -12.0,
	"hit": -6.0,
	"enemy_death": -10.0,
	"xp_pickup": -14.0,
	"level_up": -4.0,
	"player_hurt": 0.0,
	"run_over": 0.0,
	"dash": -14.0,
	"boss_spawn": -2.0,
	"boss_death": -2.0,
}
## Minimum gap between two plays of the SAME sound. Dozens of enemies can die
## in one frame; without this the mix turns to mush.
const DEFAULT_MUSIC_VOLUME := 0.7
const DEFAULT_SFX_VOLUME := 0.8
const SFX_RETRIGGER_GAP := 0.035
const SFX_VOICES := 16

# =============================================================================
# INPUT
# =============================================================================
const STICK_DEADZONE := 0.25
## Radius around the player where a held pointer stops steering. Without it the
## direction flips every frame when the cursor sits on the ship.
const POINTER_DEADZONE := 18.0
