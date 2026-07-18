extends Node

## Ranked-attempt bookkeeping and score table (GDD section 2).
##
##   godot --headless tests/save_test.tscn -- --save-file=test_save.json
##
## Always pass --save-file so a test run cannot destroy a real player's ledger.

var _ok := true


func _check(label: String, passed: bool) -> void:
	if not passed:
		_ok = false
	print("  %-58s %s" % [label, "OK" if passed else "FAIL"])


func _ready() -> void:
	SaveStore.reset_all()
	var today := GameSeed.today_utc()
	var yesterday := GameSeed.days_before(today, 1)

	print("=== ranked attempts ===")
	_check("a fresh day has its ranked attempt available",
		SaveStore.ranked_available(today))

	SaveStore.consume_ranked_attempt(today)
	_check("consuming marks it unavailable", not SaveStore.ranked_available(today))

	# The mid-run-quit case: the attempt is burned at run START, so reloading
	# from disk (as a relaunch would) must still show it spent.
	SaveStore.load_from_disk()
	_check("still spent after reload (quitting mid-run grants no retry)",
		not SaveStore.ranked_available(today))

	_check("a different day is unaffected", SaveStore.ranked_available(yesterday))

	SaveStore.finish_ranked_attempt(today, 4321)
	var record := SaveStore.ranked_record(today)
	_check("finished attempt stores its score",
		int(record.get("score", 0)) == 4321 and bool(record.get("finished", false)))

	print("\n=== date arithmetic for the archive ===")
	_check("2026-01-01 minus 1 day = 2025-12-31",
		GameSeed.days_before("2026-01-01", 1) == "2025-12-31")
	_check("2024-03-01 minus 1 day = 2024-02-29 (leap year)",
		GameSeed.days_before("2024-03-01", 1) == "2024-02-29")
	_check("2023-03-01 minus 1 day = 2023-02-28 (non-leap)",
		GameSeed.days_before("2023-03-01", 1) == "2023-02-28")
	_check("past dates validate", GameSeed.is_valid_past_or_today("2020-05-05"))
	_check("future dates are rejected",
		not GameSeed.is_valid_past_or_today("2999-01-01"))
	_check("malformed dates are rejected",
		not GameSeed.is_valid_past_or_today("not-a-date"))

	print("\n=== seeds are a pure function of the date ===")
	_check("same date -> same seed",
		GameSeed.for_date("2026-01-01") == GameSeed.for_date("2026-01-01"))
	_check("different dates -> different seeds",
		GameSeed.for_date("2026-01-01") != GameSeed.for_date("2026-01-02"))

	print("\n=== score table ===")
	SaveStore.reset_all()
	for entry in [
		{"date": today, "score": 500, "ranked": true, "seconds": 120, "level": 5, "kills": 40, "bosses": 0},
		{"date": today, "score": 900, "ranked": false, "seconds": 200, "level": 8, "kills": 90, "bosses": 1},
		{"date": today, "score": 300, "ranked": false, "seconds": 90, "level": 3, "kills": 20, "bosses": 0},
		{"date": yesterday, "score": 7000, "ranked": false, "seconds": 600, "level": 20, "kills": 400, "bosses": 3},
	]:
		SaveStore.record_score(entry)

	var top_today := SaveStore.top_for_date(today, 5)
	_check("today's table holds only today's runs", top_today.size() == 3)
	_check("sorted best first (%d, %d, %d)" % [
		int(top_today[0]["score"]), int(top_today[1]["score"]), int(top_today[2]["score"])],
		int(top_today[0]["score"]) == 900 and int(top_today[2]["score"]) == 300)
	_check("best_score_for_date returns the max",
		SaveStore.best_score_for_date(today) == 900)
	_check("overall table spans dates and leads with 7000",
		int(SaveStore.top_overall(1)[0]["score"]) == 7000)
	_check("scores survive a reload", _survives_reload(today))

	print("\nRESULT: %s" % ("PASS" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)


func _survives_reload(today: String) -> bool:
	SaveStore.load_from_disk()
	return SaveStore.best_score_for_date(today) == 900
