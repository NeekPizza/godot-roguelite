extends Node

## Local persistence: ranked-attempt bookkeeping and the high-score table.
##
## Stored as JSON in user:// so it survives reinstalls of the game data but
## stays per-machine. Deliberately plain text and trivially editable — the
## anti-cheat posture (GDD section 10) is minimal on purpose, and pretending
## otherwise with obfuscation would only cost us debuggability.

const DEFAULT_FILE := "save.json"
const VERSION := 1

## Tests pass --save-file=... so they never clobber a real player's ledger.
var _file_name := DEFAULT_FILE
var _data := {}


func save_path() -> String:
	return "user://" + _file_name


func temp_path() -> String:
	return "user://" + _file_name + ".tmp"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save-file="):
			_file_name = arg.split("=")[1]
	load_from_disk()


func _default_data() -> Dictionary:
	return {
		"version": VERSION,
		# date string -> {"consumed": bool, "score": int, "finished": bool}
		"ranked": {},
		# newest-first list of run records
		"scores": [],
	}


func load_from_disk() -> void:
	_data = _default_data()
	if not FileAccess.file_exists(save_path()):
		return

	var file := FileAccess.open(save_path(), FileAccess.READ)
	if file == null:
		push_warning("SaveStore: cannot open %s" % save_path())
		return
	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		# Corrupt or hand-mangled: start clean rather than crash on every read.
		push_warning("SaveStore: save file unreadable, starting fresh")
		return
	# Merge onto defaults so a save written by an older build is still usable.
	for key in _default_data():
		if parsed.has(key):
			_data[key] = parsed[key]
	_normalise_numbers()


## JSON has no integer type, so every number comes back as a float: a score
## written as 10114 reloads as 10114.0. Display paths coerce anyway, but Steam
## leaderboards take an int32 and float drift is not something to discover at
## submission time. Coerce once, here, at the boundary.
const _INT_FIELDS := ["score", "kills", "seconds", "level", "bosses", "stage"]


func _normalise_numbers() -> void:
	for entry in _data["scores"]:
		for field in _INT_FIELDS:
			if entry.has(field):
				entry[field] = int(entry[field])
	for date_string in _data["ranked"]:
		var record: Dictionary = _data["ranked"][date_string]
		if record.has("score"):
			record["score"] = int(record["score"])


func save_to_disk() -> void:
	# Write to a temp file and rename. A crash mid-write would otherwise leave a
	# truncated save, and losing the ranked-attempt ledger would hand players a
	# free retry on the day's run.
	var file := FileAccess.open(temp_path(), FileAccess.WRITE)
	if file == null:
		push_error("SaveStore: cannot write %s" % temp_path())
		return
	file.store_string(JSON.stringify(_data, "\t"))
	file.close()

	var dir := DirAccess.open("user://")
	if dir == null:
		push_error("SaveStore: cannot open user:// to finalise save")
		return
	if dir.file_exists(_file_name):
		dir.remove(_file_name)
	dir.rename(_file_name + ".tmp", _file_name)


# --- Ranked attempts ---------------------------------------------------------

func ranked_available(date_string: String) -> bool:
	var ranked: Dictionary = _data["ranked"]
	if not ranked.has(date_string):
		return true
	return not bool(ranked[date_string].get("consumed", false))


## Burn the day's ranked attempt and flush immediately.
##
## Called when the run STARTS, never when it ends. If it were charged on death,
## quitting mid-run would hand back a free retry — which is exactly the exploit
## the one-attempt-per-day rule exists to prevent (GDD section 2).
func consume_ranked_attempt(date_string: String) -> void:
	var ranked: Dictionary = _data["ranked"]
	ranked[date_string] = {"consumed": true, "score": 0, "finished": false}
	save_to_disk()


func finish_ranked_attempt(date_string: String, score: int) -> void:
	var ranked: Dictionary = _data["ranked"]
	if not ranked.has(date_string):
		ranked[date_string] = {"consumed": true}
	ranked[date_string]["score"] = score
	ranked[date_string]["finished"] = true
	save_to_disk()


func ranked_record(date_string: String) -> Dictionary:
	return _data["ranked"].get(date_string, {})


# --- Score table -------------------------------------------------------------

func record_score(entry: Dictionary) -> void:
	var scores: Array = _data["scores"]
	scores.push_front(entry)
	if scores.size() > Balance.SCORE_HISTORY_MAX:
		scores.resize(Balance.SCORE_HISTORY_MAX)
	save_to_disk()


## Highest scores for one seed date, best first.
func top_for_date(date_string: String, limit: int) -> Array:
	var matching := []
	for entry in _data["scores"]:
		if entry.get("date", "") == date_string:
			matching.append(entry)
	matching.sort_custom(func(a, b): return int(a.get("score", 0)) > int(b.get("score", 0)))
	return matching.slice(0, limit)


## Highest scores across every date, best first.
func top_overall(limit: int) -> Array:
	var all: Array = _data["scores"].duplicate()
	all.sort_custom(func(a, b): return int(a.get("score", 0)) > int(b.get("score", 0)))
	return all.slice(0, limit)


## Deepest stage reached on a seed, shown alongside score.
func best_stage_for_date(date_string: String) -> int:
	var deepest := 0
	for entry in _data["scores"]:
		if entry.get("date", "") == date_string:
			deepest = maxi(deepest, int(entry.get("stage", 1)))
	return deepest


func best_score_for_date(date_string: String) -> int:
	var top := top_for_date(date_string, 1)
	return int(top[0].get("score", 0)) if not top.is_empty() else 0


## Test hook: wipe local state so a test run starts from a known slate.
func reset_all() -> void:
	_data = _default_data()
	save_to_disk()
