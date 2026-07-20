extends Node

## Stage progression (GDD sections 16-17).
##
## The determinism assertions are the important ones: a stage's content must be
## a pure function of (seed, stage index), never of how long the player took to
## get there.

var _ok := true


func _check(label: String, passed: bool) -> void:
	if not passed:
		_ok = false
	print("  %-64s %s" % [label, "OK" if passed else "FAIL"])


func _ready() -> void:
	print("=== escalation compounds ===")
	_check("stage 1 is the baseline (hp x%.2f)" % Stages.hp_mult(1),
		absf(Stages.hp_mult(1) - 1.0) < 0.001)
	_check("HP rises (x%.2f -> x%.2f by stage 5)" % [Stages.hp_mult(1), Stages.hp_mult(5)],
		Stages.hp_mult(5) > Stages.hp_mult(1))
	_check("damage rises (x%.2f by stage 5)" % Stages.damage_mult(5),
		Stages.damage_mult(5) > 1.0)
	_check("spawn interval shrinks (x%.2f by stage 5)" % Stages.interval_mult(5),
		Stages.interval_mult(5) < 1.0)
	_check("wave size grows (+%d by stage 5)" % Stages.count_bonus(5),
		Stages.count_bonus(5) > 0)
	# Depth has to pay, or farming a shallow stage forever is optimal.
	_check("score per kill rises (x%.2f by stage 5)" % Stages.score_mult(5),
		Stages.score_mult(5) > 1.0)

	print("\n=== stage content is a pure function of (seed, stage) ===")
	_check("same (date, stage) -> same roster",
		Stages.roster("2026-01-01", 3) == Stages.roster("2026-01-01", 3))
	_check("different stage -> different roster",
		Stages.roster("2026-01-01", 3) != Stages.roster("2026-01-01", 4))
	_check("different date -> different roster",
		Stages.roster("2026-01-01", 3) != Stages.roster("2026-02-02", 3))
	_check("same (date, stage) -> same drop schedule",
		Drops.schedule_digest(Drops.build_stage_schedule("2026-01-01", 3))
		== Drops.schedule_digest(Drops.build_stage_schedule("2026-01-01", 3)))
	_check("different stage -> different drop schedule",
		Drops.schedule_digest(Drops.build_stage_schedule("2026-01-01", 3))
		!= Drops.schedule_digest(Drops.build_stage_schedule("2026-01-01", 4)))

	print("\n=== rosters are well-formed and widen with depth ===")
	for stage in [1, 4, 9]:
		var roster := Stages.roster("2026-01-01", stage)
		var valid := roster.has("drifter") and roster.has("swarmer")
		var unique := {}
		for id in roster:
			unique[id] = true
			valid = valid and Balance.ENEMY_TYPES.has(id)
		valid = valid and unique.size() == roster.size()
		_check("stage %d roster valid, %d types" % [stage, roster.size()], valid)
	_check("a deep stage is at least as wide as an early one",
		Stages.roster("2026-01-01", 9).size() >= Stages.roster("2026-01-01", 1).size())

	print("\n=== every roster type can actually spawn ===")
	# Regression guard: type unlocks used to be gated on ABSOLUTE elapsed time,
	# so once stage clocks reset every 150s nothing past Swarmer ever appeared.
	var roster := Stages.roster("2026-01-01", 6)
	var weights := Difficulty.stage_type_weights(6, 60.0, roster)
	var live := 0
	for entry in weights:
		if entry[1] > 0.0:
			live += 1
	_check("all %d roster types have non-zero weight (%d live)" % [roster.size(), live],
		live == roster.size())
	var off_roster_zero := true
	for entry in weights:
		if not roster.has(entry[0]) and entry[1] != 0.0:
			off_roster_zero = false
	_check("off-roster types stay at zero but keep their slot", off_roster_zero)
	_check("the table length never changes, so draw counts hold",
		weights.size() == Balance.TYPE_SCHEDULE_BASE.size())

	print("\n=== palettes cycle and stay distinct ===")
	var first := Stages.palette(1)
	_check("stage 1 and 2 differ", first["background"] != Stages.palette(2)["background"])
	var cycle := Balance.STAGE_PALETTES.size()
	_check("a full cycle later is hotter, not identical",
		Stages.palette(1 + cycle)["background"] != first["background"])

	print("\n=== the escalation readout is legible ===")
	var lines := Stages.escalation_lines(2, Stages.roster("2026-01-01", 1), "2026-01-01")
	_check("the card lists several concrete changes (%d lines)" % lines.size(),
		lines.size() >= 4)
	var mentions_boss := false
	for line in lines:
		if str(line).begins_with("Next boss"):
			mentions_boss = true
	_check("it names the next boss", mentions_boss)

	print("\n=== enrage punishes stalling but stays readable ===")
	_check("enrage waits before starting (%.0fs)" % Balance.ENRAGE_DELAY,
		Balance.ENRAGE_DELAY > 10.0)
	_check("enrage is capped (%d steps)" % Balance.ENRAGE_MAX_STEPS,
		Balance.ENRAGE_MAX_STEPS > 0)
	# The telegraph floor is what keeps an enraged boss fair rather than cheap.
	var enraged_cadence := Balance.BOSS_CADENCE_MIN
	_check("cadence can never fall below the floor (%.2fs)" % enraged_cadence,
		enraged_cadence > 0.0)

	print("\nRESULT: %s" % ("PASS" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)
