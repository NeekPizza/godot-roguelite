extends Node

## Decides WHICH run is about to start: which seed date, and whether it counts.
##
## Phase 5 will drive this from the menu. Until then it is driven by CLI flags
## and a deliberately safe default.
##
## The invariant this file exists to protect (GDD section 2): **a ranked attempt
## is never consumed by accident.** Launching the game, poking a menu, or
## running a test must never burn today's attempt. Ranked has to be asked for.

enum Mode { RANKED, PRACTICE_TODAY, ARCHIVE }

var date_string := ""
var mode := Mode.ARCHIVE
var scripted_input_seed := ""     # test hook; empty means a human is playing


func is_ranked() -> bool:
	return mode == Mode.RANKED


func mode_name() -> String:
	match mode:
		Mode.RANKED: return "RANKED"
		Mode.PRACTICE_TODAY: return "PRACTICE"
		_: return "ARCHIVE"


func _ready() -> void:
	_apply_defaults()
	_parse_args()


## Safe default: yesterday's seed as unranked archive practice.
##
## NOT today-ranked, which would auto-consume the attempt, and not today-practice
## either while the ranked attempt is still unspent — rehearsing the exact ranked
## run defeats the one-attempt rule as thoroughly as unlimited retries would.
func _apply_defaults() -> void:
	var today := GameSeed.today_utc()
	if SaveStore.ranked_available(today):
		date_string = GameSeed.days_before(today, 1)
		mode = Mode.ARCHIVE
	else:
		date_string = today
		mode = Mode.PRACTICE_TODAY


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--ranked":
			# Explicit opt-in only. This is the menu's "Start today's ranked
			# run?" confirmation, in CLI form.
			date_string = GameSeed.today_utc()
			mode = Mode.RANKED
		elif arg == "--practice":
			date_string = GameSeed.today_utc()
			mode = Mode.PRACTICE_TODAY
		elif arg.begins_with("--date="):
			# Any past seed, always unranked. Archive practice is free and
			# unlimited: past seeds are a pure function of the date string, so
			# they cost no storage and no server.
			date_string = arg.split("=")[1]
			mode = Mode.ARCHIVE
		elif arg.begins_with("--scripted-input="):
			scripted_input_seed = arg.split("=")[1]


## Called by the run as it starts. Returns false if a ranked run was requested
## but the day's attempt is already spent, in which case it downgrades to
## practice rather than silently granting a second ranked go.
func begin_run() -> bool:
	if mode != Mode.RANKED:
		return true
	if not SaveStore.ranked_available(date_string):
		push_warning("RunConfig: ranked attempt for %s already used; running as practice"
			% date_string)
		mode = Mode.PRACTICE_TODAY
		return false
	SaveStore.consume_ranked_attempt(date_string)
	return true
