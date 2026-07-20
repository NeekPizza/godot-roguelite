class_name Stages
extends RefCounted

## Stage configuration — derived from (daily_seed, stage index), never authored.
##
## Everything is a pure function of the stage number, so the ladder is endless.
## The fairness model this enables (GDD section 16): every player gets identical
## Stage N content, and reaches it at their own pace. Skill is depth.


static func _steps(stage: int) -> float:
	return float(maxi(0, stage - 1))


static func combat_duration(_stage: int) -> float:
	return Balance.STAGE_COMBAT_DURATION


static func hp_mult(stage: int) -> float:
	return pow(Balance.STAGE_HP_MULT, _steps(stage))


static func damage_mult(stage: int) -> float:
	return pow(Balance.STAGE_DAMAGE_MULT, _steps(stage))


static func score_mult(stage: int) -> float:
	return pow(Balance.STAGE_SCORE_MULT, _steps(stage))


static func interval_mult(stage: int) -> float:
	return pow(Balance.STAGE_INTERVAL_MULT, _steps(stage))


static func count_bonus(stage: int) -> int:
	return int(_steps(stage)) / Balance.STAGE_COUNT_BONUS_EVERY


## How many optional enemy types are live this stage — widens with depth.
static func roster_pick(stage: int) -> int:
	var extra := int(_steps(stage)) / Balance.STAGE_ROSTER_PICK_EVERY
	return mini(Balance.STAGE_ROSTER_PICK_BASE + extra, Balance.ENEMY_POOL.size())


## The stage's active enemy types: the core two plus a seeded selection.
## Keyed on the stage index, so Stage 4 is the same for everyone regardless of
## when they arrive.
static func roster(date_string: String, stage: int) -> Array:
	var rng := GameSeed.make_stage_rng(date_string, stage, "roster")
	var pool := Balance.ENEMY_POOL.duplicate()
	var out := Balance.ENEMY_CORE.duplicate()
	for i in mini(roster_pick(stage), pool.size()):
		var index := rng.randi_range(0, pool.size() - 1)
		out.append(pool[index])
		pool.remove_at(index)
	return out


## Arena palette. Cycles, and each full cycle returns slightly hotter so deep
## stages read as more intense rather than merely repeating.
static func palette(stage: int) -> Dictionary:
	var palettes: Array = Balance.STAGE_PALETTES
	var index := int(_steps(stage)) % palettes.size()
	var cycle := int(_steps(stage)) / palettes.size()
	var heat := clampf(float(cycle) * Balance.STAGE_PALETTE_INTENSITY, 0.0, 0.5)

	var base: Dictionary = palettes[index]
	var out := {}
	for key in base:
		var colour: Color = base[key]
		# Lift toward the accent as cycles stack; alpha is preserved so the
		# grid and walls keep their intended weight.
		out[key] = Color(
			minf(1.0, colour.r + heat * 0.35),
			colour.g * (1.0 - heat * 0.10),
			colour.b * (1.0 - heat * 0.10),
			colour.a)
	return out


## One-line escalation summary for the STAGE COMPLETE card.
static func escalation_lines(next_stage: int, previous_roster: Array,
		date_string: String) -> Array:
	var lines := []
	lines.append("Enemy health  +%d%%" % roundi((Balance.STAGE_HP_MULT - 1.0) * 100.0))
	lines.append("Enemy damage  +%d%%" % roundi((Balance.STAGE_DAMAGE_MULT - 1.0) * 100.0))
	lines.append("Spawn rate  +%d%%" % roundi((1.0 / Balance.STAGE_INTERVAL_MULT - 1.0) * 100.0))
	lines.append("Score per kill  +%d%%" % roundi((Balance.STAGE_SCORE_MULT - 1.0) * 100.0))

	var incoming := []
	for type_id in roster(date_string, next_stage):
		if not previous_roster.has(type_id):
			incoming.append(str(Balance.ENEMY_TYPES[type_id]["name"]))
	if not incoming.is_empty():
		lines.append("New enemies  %s" % ", ".join(PackedStringArray(incoming)))

	var boss_id := Difficulty.boss_archetype(date_string, next_stage)
	lines.append("Next boss  %s" % str(Balance.BOSS_ARCHETYPES[boss_id]["name"]))
	return lines
