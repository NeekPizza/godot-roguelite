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

## --- Evolved weapons -------------------------------------------------------
## Marked `evolved` so the deck never offers them as a new weapon: the only way
## in is the recipe. They reuse existing behaviours with much stronger numbers
## rather than introducing new systems — Railgun is a very fast, very long-lived,
## high-pierce projectile rather than a swept beam, which is the same reason
## Lance was held back from v1.2.
const EVOLVED_WEAPONS := {
	"railgun": {
		"name": "Railgun", "desc": "Punches a line through everything",
		"behavior": "seek", "cooldown_class": "shot", "max_level": 3,
		"evolved": true,
		"base": {"damage": 46.0, "cooldown": 0.70, "speed": 1250.0, "count": 1,
				 "pierce": 40, "radius": 7.0, "lifetime": 1.2},
		"per_level": {"damage": 18.0, "count": 0, "pierce": 0, "radius": 1.0,
					  "cooldown_mul": 0.86},
	},
	"event_horizon": {
		"name": "Event Horizon", "desc": "A vast ring that drags enemies inward",
		"behavior": "orbit", "cooldown_class": "volley", "max_level": 3,
		"evolved": true, "pull": 60.0,
		"base": {"damage": 22.0, "cooldown": 0.22, "speed": 1.7, "count": 6,
				 "pierce": 0, "radius": 150.0, "lifetime": 0.0},
		"per_level": {"damage": 8.0, "count": 2, "pierce": 0, "radius": 16.0,
					  "cooldown_mul": 0.94},
	},
	"blade_storm": {
		"name": "Blade Storm", "desc": "A returning fan of blades",
		"behavior": "boomerang", "cooldown_class": "volley", "max_level": 3,
		"evolved": true,
		"base": {"damage": 34.0, "cooldown": 0.85, "speed": 520.0, "count": 5,
				 "pierce": 12, "radius": 11.0, "lifetime": 1.7},
		"per_level": {"damage": 12.0, "count": 2, "pierce": 2, "radius": 1.0,
					  "cooldown_mul": 0.88},
	},
	"supernova": {
		"name": "Supernova", "desc": "Near-constant expanding shockwaves",
		"behavior": "nova", "cooldown_class": "volley", "max_level": 3,
		"evolved": true,
		"base": {"damage": 40.0, "cooldown": 0.90, "speed": 520.0, "count": 1,
				 "pierce": 0, "radius": 300.0, "lifetime": 0.50,
				 "knockback": 240.0},
		"per_level": {"damage": 14.0, "count": 0, "pierce": 0, "radius": 40.0,
					  "cooldown_mul": 0.90},
	},
}

## Base weapon at MAX LEVEL + paired passive at MAX STACKS -> evolution.
## Taking it replaces the base weapon in place and does not cost a slot.
const EVOLUTIONS := [
	{"weapon": "pulse",     "passive": "pierce",        "result": "railgun"},
	{"weapon": "orbit",     "passive": "amplifier",     "result": "event_horizon"},
	{"weapon": "boomerang", "passive": "split",         "result": "blade_storm"},
	{"weapon": "nova",      "passive": "cooldown_core", "result": "supernova"},
]

# =============================================================================
# COMBO (6c)
# =============================================================================
## Multiplies KILL SCORE ONLY — not survival, not XP. Multiplying survival would
## reward turtling with a full bar, which is exactly the play the scoring exists
## to discourage.
const COMBO_WINDOW := 2.5          # seconds since the last kill before it decays
const COMBO_PER_KILL := 0.02
const COMBO_MAX_BONUS := 1.5       # so x2.5 at the cap
const COMBO_DECAY_PER_SEC := 6.7   # chain units lost per second once it lapses

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
##
## `applies_to` gates whether the card is even OFFERED. A passive that does
## nothing for the weapons you hold is a wasted card at a moment the player is
## under pressure — Overclock with an Orbit/Nova/Boomerang build changes
## literally no number. Omitting the key means "always relevant" (the
## player-affecting ones). A passive is ALSO always offered when it is the
## evolution ingredient for a weapon you hold — see cards.gd, without which
## filtering would quietly make evolutions unreachable.
const PASSIVES := {
	"overclock": {"applies_to": {"cooldown_class": ["shot"]}, "name": "Overclock", "desc": "+25% fire rate (shot weapons)", "max": 5,
		"effects": [{"stat": "fire_rate_mult", "op": "mul", "value": 1.25}]},
	"cooldown_core": {"applies_to": {"cooldown_class": ["volley"]}, "name": "Cooldown Core", "desc": "-10% volley cooldown", "max": 5,
		"effects": [{"stat": "volley_cooldown_mult", "op": "mul", "value": 0.90}]},
	"hollow": {"name": "Hollow Point", "desc": "+15% damage", "max": 8,
		"effects": [{"stat": "damage_mult", "op": "mul", "value": 1.15}]},
	"split": {"applies_to": {"behavior": ["seek", "curve", "boomerang", "orbit"]}, "name": "Split Shot", "desc": "+1 projectile", "max": 3,
		"effects": [{"stat": "projectile_bonus", "op": "add", "value": 1}]},
	"pierce": {"applies_to": {"behavior": ["seek", "curve", "boomerang"]}, "name": "Piercing", "desc": "+1 pierce", "max": 3,
		"effects": [{"stat": "pierce_bonus", "op": "add", "value": 1}]},
	"velocity": {"applies_to": {"behavior": ["seek", "curve", "boomerang"]}, "name": "Velocity Coil", "desc": "+20% projectile speed", "max": 3,
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
		"name": "Drifter",
		"hp": 20.0, "speed": 90.0, "damage": 10.0, "radius": 12.0,
		"score": 10, "xp": 1, "color": Color(1.0, 0.28, 0.85),
		"behavior": "chase", "shape": "square",
	},
	"swarmer": {
		"name": "Swarmer",
		"hp": 8.0, "speed": 175.0, "damage": 6.0, "radius": 8.0,
		"score": 6, "xp": 1, "color": Color(1.0, 0.55, 0.15),
		"behavior": "chase", "shape": "triangle",
	},
	"tank": {
		"name": "Tank",
		"hp": 90.0, "speed": 45.0, "damage": 20.0, "radius": 22.0,
		"score": 30, "xp": 3, "color": Color(0.65, 0.35, 1.0),
		"behavior": "chase", "shape": "hexagon",
	},
	"shooter": {
		"name": "Shooter",
		"hp": 25.0, "speed": 70.0, "damage": 8.0, "radius": 13.0,
		"score": 20, "xp": 2, "color": Color(1.0, 0.25, 0.3),
		"behavior": "keep_distance", "shape": "diamond",
		"preferred_range": 340.0, "shot_interval": 3.2,
	},
	"splitter": {
		"name": "Splitter",
		"hp": 40.0, "speed": 70.0, "damage": 12.0, "radius": 16.0,
		"score": 20, "xp": 2, "color": Color(0.3, 1.0, 0.6),
		"behavior": "chase", "shape": "nested_square",
		"splits_into": "swarmer", "split_count": 2,
	},

	"dasher": {
		"name": "Dasher",
		"hp": 26.0, "speed": 74.0, "damage": 14.0, "radius": 13.0,
		"score": 18, "xp": 2, "color": Color(0.45, 0.85, 1.0),
		"behavior": "dash", "shape": "chevron",
		## Telegraphed on purpose: a lunge with no windup is not a skill test.
		"dash_telegraph": 0.55, "dash_speed": 620.0, "dash_duration": 0.35,
		"dash_cooldown": 2.6,
	},
	"shielded": {
		"name": "Shielded",
		"hp": 55.0, "speed": 62.0, "damage": 16.0, "radius": 16.0,
		"score": 26, "xp": 2, "color": Color(0.55, 0.62, 0.95),
		"behavior": "chase", "shape": "shield",
		## Damage from within this arc of its facing is reduced to shield_mult.
		## The first enemy where WHERE YOU STAND is the whole problem.
		"shield_arc_deg": 150.0, "shield_mult": 0.15,
	},
	"bomber": {
		"name": "Bomber",
		"hp": 30.0, "speed": 118.0, "damage": 10.0, "radius": 14.0,
		"score": 22, "xp": 2, "color": Color(1.0, 0.42, 0.2),
		"behavior": "chase", "shape": "fuse",
		"blast_radius": 130.0, "blast_damage": 26.0, "blast_chain_depth": 2,
	},
	"weaver": {
		"name": "Weaver",
		"hp": 22.0, "speed": 132.0, "damage": 9.0, "radius": 11.0,
		"score": 16, "xp": 1, "color": Color(0.95, 0.45, 0.95),
		"behavior": "weave", "shape": "ribbon",
		"wave_amplitude": 110.0, "wave_frequency": 2.1,
	},
}

## Always active; the day's roster is these plus a seed-picked selection.
const ENEMY_CORE := ["drifter", "swarmer"]
## Picked from this pool by the `daily` stream. With slots capped at 3, the
## roster is now the seed's main lever on how a day actually plays.
const ENEMY_POOL := ["tank", "shooter", "splitter", "dasher", "shielded",
					 "bomber", "weaver"]
const ENEMY_ROSTER_PICK := 4

# =============================================================================
# ELITES (6e)
# =============================================================================
## Rolled as part of the spawn block, so an elite's drop is fixed the moment it
## appears and merely read back when it dies — never rolled at death, which is
## player-timed.
## Cut alongside DROP_INTERVAL: elites are the DOMINANT drop source, so drop
## frequency cannot be tuned without this number. Side effect worth knowing —
## it also reduces how often you MEET an elite, not merely how often one pays
## out. Left deliberately, since elites guarantee a drop by design (GDD 5) and
## making that payout unreliable would be a worse trade.
const ELITE_CHANCE := 0.030
const ELITE_HP_MULT := 6.0
const ELITE_DAMAGE_MULT := 1.5
const ELITE_SCORE_MULT := 5.0
const ELITE_SCALE := 1.45
const ELITE_RING_COLOR := Color(1.0, 0.9, 0.35)

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
## Relative spawn weights once a type is in the stage roster. Unlock TIMES are
## gone: which types can appear is now the stage roster's job (v1.3).
const TYPE_SCHEDULE_BASE := [
	{"id": "drifter",  "weight": 1.00},
	{"id": "swarmer",  "weight": 1.40},
	## Deliberately the rarest mid-tier type: at higher weights the late game
	## reads as a wall of incoming fire.
	{"id": "shooter",  "weight": 0.42},
	{"id": "tank",     "weight": 1.00},
	{"id": "splitter", "weight": 0.90},
	{"id": "dasher",   "weight": 0.75},
	{"id": "weaver",   "weight": 0.70},
	{"id": "bomber",   "weight": 0.55},
	{"id": "shielded", "weight": 0.60},
]
## Seconds over which a new stage's mix eases in from a Drifter-led opening.
const STAGE_MIX_EASE := 12.0

const TYPE_SCHEDULE := [
	{"id": "swarmer",  "unlock": 120.0, "ramp": 180.0, "weight": 1.40},
	# Deliberately the rarest mid-tier type (~10% of spawns): at higher weights
	# the late game reads as a wall of incoming fire.
	{"id": "shooter",  "unlock": 240.0, "ramp": 180.0, "weight": 0.42},
	{"id": "tank",     "unlock": 360.0, "ramp": 240.0, "weight": 1.00},
	{"id": "splitter", "unlock": 480.0, "ramp": 240.0, "weight": 0.90},
	{"id": "dasher",   "unlock": 180.0, "ramp": 180.0, "weight": 0.75},
	{"id": "weaver",   "unlock": 210.0, "ramp": 180.0, "weight": 0.70},
	{"id": "bomber",   "unlock": 330.0, "ramp": 240.0, "weight": 0.55},
	{"id": "shielded", "unlock": 420.0, "ramp": 240.0, "weight": 0.60},
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

## Four archetypes. Which one fills a 3-minute slot comes from the INDEXED
## `boss` stream, so slot 3 cannot be shifted by what happened at slot 1.
const BOSS_ARCHETYPES := {
	"spinner": {"name": "Spinner", "shape": "octagon", "pattern": "rotating_spray",
		"speed_mult": 1.0, "color": Color(1.0, 0.30, 0.55)},
	"aimed_volley": {"name": "Volley", "shape": "diamond", "pattern": "shotgun_burst",
		"speed_mult": 1.15, "color": Color(1.0, 0.45, 0.30)},
	"charger": {"name": "Charger", "shape": "arrowhead", "pattern": "lane_dash",
		"speed_mult": 1.30, "color": Color(1.0, 0.25, 0.35),
		"dash_speed": 620.0, "dash_duration": 0.9},
	"ring_master": {"name": "Ring Master", "shape": "star", "pattern": "gapped_ring",
		"speed_mult": 0.45, "color": Color(0.85, 0.40, 1.0)},
}

## Patterns escalate with the boss index. `per_index` is applied (index - 1)
## times: "+" keys add, "x" keys multiply.
const BOSS_PATTERNS := {
	"rotating_spray": {"telegraph": 0.70, "bullets": 8, "spread_deg": 360.0,
		"speed": 210.0, "cadence": 3.2, "rotation_step": 0.21,
		"per_index": {"bullets+": 1.5, "speed x": 1.07, "cadence x": 0.94}},
	"shotgun_burst": {"telegraph": 0.60, "bullets": 7, "spread_deg": 46.0,
		"speed": 300.0, "cadence": 2.4, "rotation_step": 0.0,
		"per_index": {"bullets+": 1.0, "speed x": 1.08, "spread_deg+": -2.5,
					  "cadence x": 0.93}},
	"lane_dash": {"telegraph": 0.85, "bullets": 10, "spread_deg": 360.0,
		"speed": 190.0, "cadence": 3.6, "rotation_step": 0.37,
		"per_index": {"bullets+": 2.0, "speed x": 1.06, "cadence x": 0.92}},
	"gapped_ring": {"telegraph": 0.80, "bullets": 30, "spread_deg": 360.0,
		"speed": 175.0, "cadence": 3.8, "rotation_step": 0.13, "gaps": 3,
		"gap_deg": 40.0,
		"per_index": {"bullets+": 3.0, "speed x": 1.05, "gap_deg+": -3.5,
					  "cadence x": 0.95}},
}

## The floor escalation may never cross. Dense patterns are only fair if they
## are readable; without a tell, a hard pattern and a cheap one feel identical
## to the player, and the player is right to be annoyed.
const BOSS_TELEGRAPH_MIN := 0.45
const BOSS_CADENCE_MIN := 1.1
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
# STAGES (7a) — every value here is applied (N-1) times, so the ladder is
# endless without a hand-authored list.
# =============================================================================
const STAGE_COMBAT_DURATION := 150.0    # seconds of fighting before the boss
const STAGE_HP_MULT := 1.40
const STAGE_DAMAGE_MULT := 1.20
const STAGE_INTERVAL_MULT := 0.90
const STAGE_INTERVAL_FLOOR := 0.12
const STAGE_COUNT_BONUS_EVERY := 2      # +1 enemy per spawn every N stages
## Depth has to pay, or the optimal play is farming a shallow stage forever.
const STAGE_SCORE_MULT := 1.20
const STAGE_ROSTER_PICK_BASE := 4       # roster widens as you go deeper
const STAGE_ROSTER_PICK_EVERY := 3

## Recolours the ARENA only — background, grid, walls, portal.
##
## Enemy colours deliberately do NOT change per stage: section 11 makes shape
## carry identity, and re-hueing enemies every stage would discard the
## recognition a player has built up exactly as the screen gets busiest.
const STAGE_PALETTES := [
	{"background": Color(0.043, 0.047, 0.078), "grid": Color(0.30, 0.85, 1.0, 0.055),
	 "wall": Color(0.35, 0.90, 1.0, 0.55), "accent": Color(0.35, 0.90, 1.0)},
	{"background": Color(0.075, 0.035, 0.070), "grid": Color(1.0, 0.45, 0.85, 0.055),
	 "wall": Color(1.0, 0.45, 0.85, 0.55), "accent": Color(1.0, 0.45, 0.85)},
	{"background": Color(0.030, 0.065, 0.055), "grid": Color(0.35, 1.0, 0.65, 0.055),
	 "wall": Color(0.35, 1.0, 0.65, 0.55), "accent": Color(0.35, 1.0, 0.65)},
	{"background": Color(0.070, 0.055, 0.025), "grid": Color(1.0, 0.80, 0.30, 0.055),
	 "wall": Color(1.0, 0.80, 0.30, 0.55), "accent": Color(1.0, 0.80, 0.30)},
	{"background": Color(0.050, 0.035, 0.085), "grid": Color(0.70, 0.55, 1.0, 0.055),
	 "wall": Color(0.70, 0.55, 1.0, 0.55), "accent": Color(0.70, 0.55, 1.0)},
	{"background": Color(0.080, 0.030, 0.030), "grid": Color(1.0, 0.40, 0.35, 0.055),
	 "wall": Color(1.0, 0.40, 0.35, 0.55), "accent": Color(1.0, 0.40, 0.35)},
]
## Each cycle through the palettes comes back slightly hotter.
const STAGE_PALETTE_INTENSITY := 0.06

# --- Boss gate and anti-stall ------------------------------------------------
## A boss the player cannot kill must not become a camping spot.
const ENRAGE_DELAY := 40.0
const ENRAGE_STEP := 10.0
const ENRAGE_DAMAGE_MULT := 1.20
const ENRAGE_CADENCE_MULT := 0.92       # still floored by BOSS_CADENCE_MIN
const ENRAGE_SPEED_MULT := 1.08
const ENRAGE_TINT := Color(1.0, 0.35, 0.35)
const ENRAGE_MAX_STEPS := 20

# --- Stage clear -------------------------------------------------------------
const STAGE_SHOCKWAVE_DELAY := 0.35
const STAGE_CALM_DURATION := 2.2
## The shockwave awards NOTHING. It creates the breather, and it closes the
## "let trash pile up, then kill the boss for a free screen-clear" exploit.
const STAGE_SHOCKWAVE_AWARDS_SCORE := false

const PORTAL_RADIUS := 34.0
const PORTAL_SPIN := 1.4

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
# DROPS (6d)
# =============================================================================
## Every drop's WHAT, WHEN and WHERE is precomputed from the `drops` stream at
## run start. Nothing here is ever rolled during play, and nothing is placed
## relative to the player — drops exist to pull you somewhere you would rather
## not go, and a drop that walks to you is a reward for nothing.
const DROPS := {
	"bomb": {"kind": "instant", "effect": "blast", "name": "Bomb", "weight": 0.16,
		## World-space radius, NEVER the viewport. Screen size varies with
		## resolution and fullscreen, so a viewport-based blast would clear a
		## different set of enemies for different players on the same seed.
		"world_radius": 900.0, "damage": 9999.0,
		"boss_damage_fraction": 0.25,
		"color": Color(1.0, 0.55, 0.15)},
	"magnet": {"kind": "instant", "effect": "sweep_xp", "name": "Magnet",
		"weight": 0.20, "color": Color(1.0, 0.92, 0.25)},
	"health": {"kind": "instant", "effect": "heal", "name": "Repair",
		"weight": 0.22, "amount": 35.0, "color": Color(0.3, 0.95, 0.45)},
	"invuln": {"kind": "buff", "effect": "invuln", "name": "Shield",
		"weight": 0.12, "duration": 6.0, "color": Color(0.55, 0.85, 1.0)},
	## Temp weapons fire IN ADDITION to your loadout (see weapon_system.gd), so
	## they stay an upgrade however strong your own weapons get.
	"shotgun": {"kind": "temp_weapon", "name": "Shotgun", "weight": 0.10,
		"duration": 25.0, "damage": 11.0, "cooldown": 0.55, "count": 7,
		"spread": 0.62, "speed": 520.0, "pierce": 1, "lifetime": 0.45,
		"color": Color(1.0, 0.45, 0.35)},
	"machine_gun": {"kind": "temp_weapon", "name": "Machine Gun", "weight": 0.10,
		"duration": 25.0, "damage": 5.0, "cooldown": 0.07, "count": 1,
		"spread": 0.10, "speed": 780.0, "pierce": 0, "lifetime": 1.1,
		"color": Color(1.0, 0.85, 0.35)},
	"splash": {"kind": "temp_weapon", "name": "Splash", "weight": 0.10,
		"duration": 25.0, "modifier": "splash",
		## Chains are depth-capped and RNG-free. Uncapped, one kill could
		## cascade across the whole field — and a cascade that branched
		## differently between machines would break the seed outright.
		"hp_fraction": 0.50, "radius": 150.0, "chain_depth_max": 3,
		"color": Color(0.75, 0.55, 1.0)},
}

## Absolute times and absolute world positions, generated up front.
## Tuned WITH ELITE_CHANCE, because the two together set the drop rate.
##
## Measured over a 15-minute run, drops arrived 26 scheduled / 64 elite / 4 boss
## — elites were 68% of them. Halving this interval alone would have cut total
## drops by about a seventh, not half. Both were moved together, remeasured at
## 16 / 33 / 2, i.e. 51 against the previous 94.
const DROP_FIRST_TIME := 40.0
const DROP_INTERVAL := 56.0
const DROP_JITTER := 12.0
const DROP_SCHEDULE_COUNT := 80        # far past any survivable run length
const DROP_EDGE_MARGIN := 160.0
const DROP_PICKUP_RADIUS := 26.0
const DROP_MARKER_RADIUS := 13.0

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
