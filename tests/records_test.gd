extends Node

## Lifetime records and the personal-best moment (8c).
##
##   godot --headless tests/records_test.tscn -- --save-file=test_save.json
##
## The failure this suite is built around: record detection that runs AFTER the
## lifetime update compares every value against itself and reports a personal
## best on every single run. A test that only asserts "a better run sets a
## record" passes happily against that bug, so the negative cases below (a worse
## run, an equal run) are the ones doing the real work.

var _ok := true


func _check(label: String, passed: bool) -> void:
	if not passed:
		_ok = false
	print("  %-58s %s" % [label, "OK" if passed else "FAIL"])


func _play(score: int, stage: int, kills: int, seconds: int, ranked := false) -> Array:
	return MetaStore.record_run(ranked, stage, score, kills, 0, seconds)


func _ready() -> void:
	MetaStore.lifetime = MetaStore._default_lifetime()

	print("=== the first run sets baselines without celebrating ===")
	var first := _play(1000, 2, 50, 120)
	_check("first run breaks nothing (it would beat zero at everything)",
		first.is_empty())
	_check("but the bests are stored", int(MetaStore.lifetime["best_score"]) == 1000
		and int(MetaStore.lifetime["best_stage"]) == 2)

	print("\n=== a better run breaks exactly the records it beat ===")
	var better := _play(2000, 2, 40, 100)
	_check("beating score alone reports only SCORE (got %s)" % str(better),
		better == ["SCORE"])

	var deeper := _play(1500, 5, 40, 100)
	_check("beating depth alone reports only DEPTH (got %s)" % str(deeper),
		deeper == ["DEPTH"])

	var sweep := _play(9000, 9, 900, 999)
	_check("a run that beats everything reports all %d (got %s)"
		% [Balance.META_RECORDS.size(), str(sweep)],
		sweep.size() == Balance.META_RECORDS.size())

	print("\n=== the cases that catch detect-after-update ===")
	var worse := _play(10, 1, 1, 5)
	_check("a strictly worse run breaks nothing", worse.is_empty())

	# Equal is not better. If this reports a record, the comparison is >= (or is
	# reading the value it just wrote).
	var equal := _play(9000, 9, 900, 999)
	_check("repeating your best exactly breaks nothing", equal.is_empty())

	print("\n=== lifetime totals accumulate, bests do not ===")
	MetaStore.lifetime = MetaStore._default_lifetime()
	_play(100, 1, 10, 60)
	_play(200, 2, 20, 90)
	_play(50, 1, 5, 30)
	_check("runs counted (%d)" % int(MetaStore.lifetime["runs"]),
		int(MetaStore.lifetime["runs"]) == 3)
	_check("kills SUM to 35 (%d)" % int(MetaStore.lifetime["kills"]),
		int(MetaStore.lifetime["kills"]) == 35)
	_check("seconds SUM to 180 (%d)" % int(MetaStore.lifetime["seconds"]),
		int(MetaStore.lifetime["seconds"]) == 180)
	_check("best_score MAXES at 200, not the 350 of a sum (%d)"
		% int(MetaStore.lifetime["best_score"]),
		int(MetaStore.lifetime["best_score"]) == 200)
	_check("a later worse run cannot lower a best (%d)"
		% int(MetaStore.lifetime["best_stage"]),
		int(MetaStore.lifetime["best_stage"]) == 2)

	print("\n=== ranked is counted separately ===")
	MetaStore.lifetime = MetaStore._default_lifetime()
	_play(100, 1, 1, 10, false)
	_play(100, 1, 1, 10, true)
	_check("2 runs, 1 ranked", int(MetaStore.lifetime["runs"]) == 2
		and int(MetaStore.lifetime["ranked_runs"]) == 1)

	print("\n=== every record has somewhere to live ===")
	var defaults := MetaStore._default_lifetime()
	var wired := true
	for record in Balance.META_RECORDS:
		if not defaults.has(record["field"]):
			wired = false
	for row in Balance.META_LIFETIME_ROWS:
		if not defaults.has(row["field"]):
			wired = false
	_check("every META_RECORDS/META_LIFETIME_ROWS field exists in the profile",
		wired)

	print("\n=== an old profile loads without losing the new fields ===")
	# A save written before 8c has no best_seconds/best_kills/seconds. Those must
	# come back as 0 rather than missing, or the screen reads a null.
	var survived := _survives_partial_load()
	_check("fields absent from an older save default to 0", survived)

	print("\nRESULT: %s" % ("PASS" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)


func _survives_partial_load() -> bool:
	var path := "user://records_test_profile.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"points": 5,
		"purchases": {},
		"lifetime": {"runs": 3, "kills": 10},     # pre-8c shape
	}))
	file.close()

	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	var loaded := MetaStore._default_lifetime()
	var stored: Dictionary = parsed.get("lifetime", {})
	for key in loaded:
		loaded[key] = int(stored.get(key, 0))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	return int(loaded["runs"]) == 3 and int(loaded["kills"]) == 10 \
		and int(loaded["best_seconds"]) == 0 and int(loaded["seconds"]) == 0
