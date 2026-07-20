extends Node

## Decides WHICH run is about to start: which seed date, and whether it counts.
##
## The invariant this file exists to protect (GDD section 2): **a ranked attempt
## is never consumed by accident.** Launching the game, opening a menu, or
## running a test must never burn today's attempt. Ranked has to be asked for,
## explicitly, every time.
##
## Selection is exposed as methods rather than an exported enum: reaching into
## an autoload for a nested type is fragile, and `select_ranked()` reads better
## at the call site than assigning a mode constant.

const MODE_RANKED := 0
const MODE_PRACTICE := 1
const MODE_ARCHIVE := 2

## CLI args that mean "skip the menu and start a run" — tests and direct
## launches. Anything else (like --save-file) leaves the menu in charge.
## Flags that alter the simulation or make the player invulnerable. These ship
## in the release build — Godot exposes user args to any binary — so rather than
## trying to strip them, a run using ANY of them is forbidden from being ranked.
## The anti-cheat posture is deliberately minimal (GDD section 10), but letting
## `--godmode --ranked` submit a score is a step too far for free.
const TEST_HOOK_ARGS := [
	"--godmode", "--auto-pick",
	"--time-scale=", "--max-seconds=", "--scripted-input=", "--boss-hp-mult=",
]

const AUTO_START_ARGS := [
	"--ranked", "--practice", "--godmode", "--auto-pick",
	"--date=", "--max-seconds=", "--time-scale=", "--scripted-input=",
	"--boss-hp-mult=",
]

var date_string := ""
var mode := MODE_ARCHIVE
var scripted_input_seed := ""     # test hook; empty means a human is playing
var auto_start := false
## True if ANY test hook was passed on the command line.
var test_hooks_active := false


func is_ranked() -> bool:
	return mode == MODE_RANKED


func mode_name() -> String:
	match mode:
		MODE_RANKED: return "RANKED"
		MODE_PRACTICE: return "PRACTICE"
		_: return "ARCHIVE"


func select_ranked(new_date: String) -> void:
	date_string = new_date
	mode = MODE_RANKED


func select_practice(new_date: String) -> void:
	date_string = new_date
	mode = MODE_PRACTICE


func select_archive(new_date: String) -> void:
	date_string = new_date
	mode = MODE_ARCHIVE


func _ready() -> void:
	_apply_defaults()
	_parse_args()


## Safe default for a direct launch: yesterday's seed as unranked practice.
##
## NOT today-ranked, which would auto-consume the attempt, and not today-practice
## while the attempt is unspent — rehearsing the exact ranked run defeats the
## one-attempt rule as thoroughly as unlimited retries would.
func _apply_defaults() -> void:
	var today := GameSeed.today_utc()
	if SaveStore.ranked_available(today):
		select_archive(GameSeed.days_before(today, 1))
	else:
		select_practice(today)


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		for prefix in AUTO_START_ARGS:
			if arg == prefix or (prefix.ends_with("=") and arg.begins_with(prefix)):
				auto_start = true

		if arg in TEST_HOOK_ARGS or (arg.contains("=") and (arg.split("=")[0] + "=") in TEST_HOOK_ARGS):
			test_hooks_active = true

		if arg == "--ranked":
			# Explicit opt-in. This is the menu's confirmation prompt in CLI form.
			select_ranked(GameSeed.today_utc())
		elif arg == "--practice":
			select_practice(GameSeed.today_utc())
		elif arg.begins_with("--date="):
			# Any past seed, always unranked. Archive practice is free and
			# unlimited: past seeds are a pure function of the date string, so
			# they cost no storage and no server.
			select_archive(arg.split("=")[1])
		elif arg.begins_with("--scripted-input="):
			scripted_input_seed = arg.split("=")[1]


## Called by the run as it starts. Returns false if a ranked run was requested
## but the day's attempt is already spent, in which case it downgrades to
## practice rather than silently granting a second ranked go.
func begin_run() -> bool:
	if mode != MODE_RANKED:
		return true
	if test_hooks_active:
		push_warning("RunConfig: test hooks active; refusing to run ranked")
		print("[run] test hooks active -> forced to practice, ranked attempt untouched")
		mode = MODE_PRACTICE
		return false
	if not SaveStore.ranked_available(date_string):
		push_warning("RunConfig: ranked attempt for %s already used; running as practice"
			% date_string)
		mode = MODE_PRACTICE
		return false
	SaveStore.consume_ranked_attempt(date_string)
	return true
