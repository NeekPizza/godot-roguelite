extends Control

## Main menu and run selection.
##
## This screen is where GDD section 2's core fairness rule is actually enforced
## for players: **a ranked attempt is never consumed by accident.** Starting
## today's ranked run requires an explicit confirmation, and every other entry
## point here is unranked.

const RUN_SCENE := "res://scenes/run.tscn"

@onready var _menu_root: Control = $Center
@onready var _status: Label = $Center/Root/Status
@onready var _buttons: VBoxContainer = $Center/Root/Buttons
@onready var _ranked_button: Button = $Center/Root/Buttons/Ranked
@onready var _practice_button: Button = $Center/Root/Buttons/Practice
@onready var _archive_button: Button = $Center/Root/Buttons/Archive
@onready var _upgrades_button: Button = $Center/Root/Buttons/Upgrades
@onready var _records_button: Button = $Center/Root/Buttons/Records
@onready var _settings_button: Button = $Center/Root/Buttons/Settings
@onready var _quit_button: Button = $Center/Root/Buttons/Quit

@onready var _confirm: Control = $Confirm
@onready var _confirm_text: Label = $Confirm/Center/Panel/Text
@onready var _confirm_yes: Button = $Confirm/Center/Panel/Row/Yes
@onready var _confirm_no: Button = $Confirm/Center/Panel/Row/No

@onready var _archive: Control = $Archive
@onready var _archive_date: Label = $Archive/Center/Panel/Row/Date
@onready var _archive_prev: Button = $Archive/Center/Panel/Row/Prev
@onready var _archive_next: Button = $Archive/Center/Panel/Row/Next
@onready var _archive_best: Label = $Archive/Center/Panel/Best
@onready var _archive_play: Button = $Archive/Center/Panel/Play
@onready var _archive_back: Button = $Archive/Center/Panel/Back

@onready var _settings: Control = $Settings
@onready var _meta: Control = $Meta
@onready var _records: Control = $Records

var _archive_date_string := ""


func _ready() -> void:
	# A run that was launched straight from the command line (tests, or a
	# --ranked/--date launch) should not stop at the menu.
	if RunConfig.auto_start:
		_start_run()
		return

	Music.start()
	_archive_date_string = GameSeed.days_before(GameSeed.today_utc(), 1)

	_ranked_button.pressed.connect(_on_ranked_pressed)
	_practice_button.pressed.connect(_launch_practice)
	_archive_button.pressed.connect(_open_archive)
	_upgrades_button.pressed.connect(_open_upgrades)
	_records_button.pressed.connect(_open_records)
	_settings_button.pressed.connect(_open_settings)
	_quit_button.pressed.connect(_quit)

	_confirm_yes.pressed.connect(_launch_ranked)
	_confirm_no.pressed.connect(func(): _close_overlay(_confirm, _ranked_button))

	_archive_prev.pressed.connect(func(): _shift_archive(1))
	_archive_next.pressed.connect(func(): _shift_archive(-1))
	_archive_play.pressed.connect(_launch_archive)
	_archive_back.pressed.connect(func(): _close_overlay(_archive, _archive_button))
	_settings.closed.connect(func(): _close_overlay(_settings, _settings_button))
	_meta.closed.connect(func(): _close_overlay(_meta, _upgrades_button))
	_records.closed.connect(func(): _close_overlay(_records, _records_button))

	_confirm.hide()
	_archive.hide()
	_settings.hide()
	_meta.hide()
	_records.hide()
	_refresh()
	_focus_first_available()
	_open_requested_overlay()


## Test hook: `--open=confirm|archive|settings` jumps straight to an overlay.
## UI states are otherwise only reachable by clicking, which makes them
## impossible to screenshot or smoke-test unattended.
func _open_requested_overlay() -> void:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--open="):
			continue
		match arg.split("=")[1]:
			"confirm": _on_ranked_pressed()
			"archive": _open_archive()
			"settings": _open_settings()
			"upgrades": _open_upgrades()
			"records": _open_records()


func _refresh() -> void:
	var today := GameSeed.today_utc()
	var available := SaveStore.ranked_available(today)
	var record := SaveStore.ranked_record(today)

	var lines := PackedStringArray()
	lines.append("Today's seed (UTC): %s" % today)
	if available:
		lines.append("Ranked attempt: AVAILABLE")
	elif bool(record.get("finished", false)):
		lines.append("Ranked attempt: used — scored %d" % int(record.get("score", 0)))
	else:
		lines.append("Ranked attempt: used")
	lines.append(Daily.summary(today))
	lines.append("Meta bonus: %s   ·   %d points" % [
		MetaStore.bonus_text(), MetaStore.points])
	var best := SaveStore.best_score_for_date(today)
	if best > 0:
		lines.append("Best on today's seed: %d  (stage %d)" % [
			best, SaveStore.best_stage_for_date(today)])
	_status.text = "\n".join(lines)

	_ranked_button.disabled = not available
	_ranked_button.text = "TODAY — RANKED" if available else "TODAY — RANKED (used)"
	# Practice on today's seed unlocks only once the ranked attempt is spent.
	# Before that it would be a rehearsal of the exact ranked run, which defeats
	# the one-attempt rule as thoroughly as unlimited retries would.
	_practice_button.disabled = available
	_practice_button.text = "TODAY — PRACTICE" if not available \
		else "TODAY — PRACTICE (after ranked)"


func _focus_first_available() -> void:
	for button in _buttons.get_children():
		if button is Button and not button.disabled:
			button.grab_focus()
			return


# --- Ranked confirmation -----------------------------------------------------

func _on_ranked_pressed() -> void:
	var today := GameSeed.today_utc()
	_confirm_text.text = "Start today's ranked run?\n\nSeed %s\n%s\n\nYou get one ranked attempt per day.\nQuitting mid-run still uses it." % [
		today, Daily.summary(today)]
	_open_overlay(_confirm)
	_confirm_no.grab_focus()   # default to the safe choice


# --- Archive -----------------------------------------------------------------

func _open_archive() -> void:
	_refresh_archive()
	_open_overlay(_archive)
	_archive_play.grab_focus()


func _shift_archive(days: int) -> void:
	var candidate := GameSeed.days_before(_archive_date_string, days)
	# Never allow today or the future: today's seed is reachable only through
	# the ranked gate (or practice once ranked is spent).
	if days < 0 and candidate >= GameSeed.today_utc():
		return
	_archive_date_string = candidate
	_refresh_archive()


func _refresh_archive() -> void:
	_archive_date.text = _archive_date_string
	var best := SaveStore.best_score_for_date(_archive_date_string)
	_archive_best.text = "%s\n%s" % [
		Daily.summary(_archive_date_string),
		"Your best: %d" % best if best > 0 else "Not played yet"]
	_archive_next.disabled = GameSeed.days_before(_archive_date_string, -1) >= GameSeed.today_utc()


# --- Overlays ----------------------------------------------------------------

## Hide the WHOLE menu, not just the buttons: the dim is translucent by design,
## and the title showing through an overlay reads as a rendering glitch.
func _open_overlay(overlay: Control) -> void:
	_menu_root.hide()
	overlay.show()


func _close_overlay(overlay: Control, focus_target: Button) -> void:
	overlay.hide()
	_menu_root.show()
	_refresh()
	focus_target.grab_focus()


func _open_upgrades() -> void:
	_meta.refresh()
	_open_overlay(_meta)
	_meta.focus_first()


func _open_records() -> void:
	_records.refresh()
	_open_overlay(_records)
	_records.focus_first()


func _open_settings() -> void:
	_open_overlay(_settings)
	_settings.focus_first()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _confirm.visible:
			_close_overlay(_confirm, _ranked_button)
		elif _archive.visible:
			_close_overlay(_archive, _archive_button)


# --- Launch ------------------------------------------------------------------

func _launch_ranked() -> void:
	RunConfig.select_ranked(GameSeed.today_utc())
	_start_run()


func _launch_practice() -> void:
	RunConfig.select_practice(GameSeed.today_utc())
	_start_run()


func _launch_archive() -> void:
	RunConfig.select_archive(_archive_date_string)
	_start_run()


func _start_run() -> void:
	# Deferred: on the CLI auto-start path this is reached from _ready(), and
	# swapping scenes while the tree is still adding this one's children throws
	# "Parent node is busy adding/removing children".
	get_tree().change_scene_to_file.call_deferred(RUN_SCENE)


func _quit() -> void:
	Music.stop()
	Sfx.stop_all()
	get_tree().quit()
