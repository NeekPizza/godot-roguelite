extends Node2D

## Run orchestrator: wave scheduling, XP/levelling, scoring, run end.
## See docs/GDD.md sections 6-9.

const RUN_DURATION := 600.0  # 10 minutes
const ENEMY_CAP := 300
const CLEAR_BONUS := 2000

const SCORE_PER_KILL := 10
const SCORE_PER_SECOND := 5
const SCORE_PER_XP := 2

const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const XP_GEM_SCENE := preload("res://scenes/xp_gem.tscn")

## Difficulty tiers (GDD section 7): {until_seconds, interval, count, hp_mult}.
## Ramps on elapsed time, never on player level.
const TIERS := [
	{"until": 120.0, "interval": 1.20, "count": 1, "hp_mult": 1.0},
	{"until": 240.0, "interval": 0.90, "count": 2, "hp_mult": 1.2},
	{"until": 360.0, "interval": 0.70, "count": 2, "hp_mult": 1.5},
	{"until": 480.0, "interval": 0.55, "count": 3, "hp_mult": 1.9},
	{"until": 600.0, "interval": 0.40, "count": 4, "hp_mult": 2.4},
]

enum State { RUNNING, LEVEL_UP, OVER }

@onready var _player: Area2D = $Player
@onready var _enemies: Node2D = $Enemies
@onready var _projectiles: Node2D = $Projectiles
@onready var _gems: Node2D = $Gems

@onready var _timer_label: Label = $HUD/Root/TimerLabel
@onready var _score_label: Label = $HUD/Root/ScoreLabel
@onready var _level_label: Label = $HUD/Root/LevelLabel
@onready var _hp_bar: ProgressBar = $HUD/Root/HPBar
@onready var _xp_bar: ProgressBar = $HUD/Root/XPBar

@onready var _levelup_layer: CanvasLayer = $LevelUpLayer
@onready var _levelup_buttons: HBoxContainer = $LevelUpLayer/Root/Center/Panel/Cards
@onready var _gameover_layer: CanvasLayer = $GameOverLayer
@onready var _gameover_label: Label = $GameOverLayer/Root/Center/Breakdown

var _state := State.RUNNING
var _date_string := ""
var _spawn_rng: RandomNumberGenerator

var _elapsed := 0.0
var _spawn_timer := 0.0
var _level := 1
var _xp := 0
var _xp_into_level := 0
var _pending_levels := 0
var _stacks := {}

var _kills := 0
var _xp_collected := 0
var _survived := false

## Headless test hooks, passed after a `--` separator:
##   godot --headless -- --run-seconds=20 --auto-pick
## `--auto-pick` always takes card 0, which keeps a headless run deterministic
## and unattended. Phase 3's determinism test builds on these.
var _run_duration := RUN_DURATION
var _auto_pick := false
var _screenshot_path := ""
var _screenshot_after := 0.0


func _parse_test_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--auto-pick":
			_auto_pick = true
		elif arg.begins_with("--run-seconds="):
			_run_duration = float(arg.split("=")[1])
			print("[run] test override: duration=%.1fs" % _run_duration)
		elif arg.begins_with("--screenshot="):
			# "--screenshot=/tmp/shot.png@12" -> capture 12s in.
			var parts := arg.split("=")[1].split("@")
			_screenshot_path = parts[0]
			_screenshot_after = float(parts[1]) if parts.size() > 1 else 5.0


func _ready() -> void:
	_parse_test_args()
	# Run stays awake while the tree is paused so it can poll for restart and
	# drive the level-up screen. Gameplay is gated on _state instead.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# ...but process_mode is INHERITED FROM THE PARENT, not from the tree root,
	# so the line above would silently hand ALWAYS to every gameplay node and
	# make get_tree().paused a no-op — enemies would keep advancing while the
	# player reads upgrade cards. Pin the gameplay subtrees back to PAUSABLE.
	for node in [_player, _enemies, _projectiles, _gems]:
		node.process_mode = Node.PROCESS_MODE_PAUSABLE

	_date_string = GameSeed.today_utc()
	_spawn_rng = GameSeed.make_spawn_rng(_date_string)
	print("[run] seed date=%s seed=%d" % [_date_string, GameSeed.for_date(_date_string)])

	_player.projectile_parent = _projectiles
	_player.died.connect(_on_player_died)
	_player.damaged.connect(_on_player_damaged)
	_player.xp_collected.connect(_on_xp_collected)

	_levelup_layer.hide()
	_gameover_layer.hide()
	_hp_bar.max_value = _player.max_hp
	_update_hud()


func _physics_process(delta: float) -> void:
	if _state != State.RUNNING:
		return

	_elapsed += delta
	if _elapsed >= _run_duration:
		_survived = true
		_end_run()
		return

	_schedule_waves(delta)
	_update_hud()


func _process(delta: float) -> void:
	if _state == State.OVER and Input.is_action_just_pressed("restart"):
		get_tree().paused = false
		get_tree().reload_current_scene()

	if _screenshot_path != "":
		_screenshot_after -= delta
		if _screenshot_after <= 0.0:
			var path := _screenshot_path
			_screenshot_path = ""
			_capture_screenshot(path)


func _capture_screenshot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(path)
	print("[run] screenshot -> %s (err %d)" % [path, error])


# --- Waves -------------------------------------------------------------------

func _current_tier() -> Dictionary:
	# Scaled by run length so a shortened test run still walks the whole ramp.
	var progress := _elapsed / _run_duration * RUN_DURATION
	for tier in TIERS:
		if progress < tier["until"]:
			return tier
	return TIERS[TIERS.size() - 1]


func _schedule_waves(delta: float) -> void:
	var tier := _current_tier()
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer += tier["interval"]

	for i in tier["count"]:
		# Draw from spawn_rng UNCONDITIONALLY, before the cap check.
		#
		# This ordering is load-bearing for determinism: how many enemies are
		# alive depends on how well the player is fighting, so if a skipped
		# spawn also skipped its RNG draws, a good player and a bad player would
		# desync the shared stream and stop playing the same daily run.
		var edge := _spawn_rng.randi_range(0, 3)
		var along := _spawn_rng.randf()
		if _enemies.get_child_count() >= ENEMY_CAP:
			continue
		_spawn_enemy(edge, along, tier["hp_mult"])


func _spawn_enemy(edge: int, along: float, hp_multiplier: float) -> void:
	var enemy := ENEMY_SCENE.instantiate()
	enemy.position = _edge_position(edge, along)
	enemy.setup(hp_multiplier)
	enemy.killed.connect(_on_enemy_killed)
	_enemies.add_child(enemy)


## Absolute spawn point just outside one of the four arena edges. Independent of
## player position, so every player on a seed gets identical spawn coordinates.
func _edge_position(edge: int, along: float) -> Vector2:
	var rect := Arena.RECT
	var margin := Arena.SPAWN_MARGIN
	match edge:
		0:  return Vector2(rect.position.x + rect.size.x * along, rect.position.y - margin)
		1:  return Vector2(rect.end.x + margin, rect.position.y + rect.size.y * along)
		2:  return Vector2(rect.position.x + rect.size.x * along, rect.end.y + margin)
		_:  return Vector2(rect.position.x - margin, rect.position.y + rect.size.y * along)


# --- XP and levelling --------------------------------------------------------

func _xp_needed(level: int) -> int:
	return 5 + (level - 1) * 4


func _on_xp_collected(amount: int) -> void:
	_xp += amount
	_xp_collected += amount
	_xp_into_level += amount

	while _xp_into_level >= _xp_needed(_level):
		_xp_into_level -= _xp_needed(_level)
		_level += 1
		_pending_levels += 1

	if _pending_levels > 0 and _state == State.RUNNING:
		_open_level_up()


func _open_level_up() -> void:
	_state = State.LEVEL_UP
	get_tree().paused = true

	var choices := Upgrades.draw_choices(_date_string, _level, _stacks)
	for i in _levelup_buttons.get_child_count():
		var button: Button = _levelup_buttons.get_child(i)
		var choice: Dictionary = choices[i]
		button.text = "%s\n\n%s" % [choice["name"], choice["desc"]]
		for connection in button.pressed.get_connections():
			button.pressed.disconnect(connection["callable"])
		button.pressed.connect(_on_upgrade_chosen.bind(choice["id"]))

	print("[run] level up -> %d  (xp %d, kills %d)" % [_level, _xp_collected, _kills])
	_update_hud()  # Otherwise the HUD still shows the pre-level-up level.
	_levelup_layer.show()
	_levelup_buttons.get_child(0).grab_focus()

	if _auto_pick:
		_on_upgrade_chosen.call_deferred(choices[0]["id"])


func _on_upgrade_chosen(upgrade_id: String) -> void:
	Upgrades.apply(upgrade_id, _player)
	if upgrade_id != Upgrades.HEAL_ID:
		_stacks[upgrade_id] = _stacks.get(upgrade_id, 0) + 1

	_pending_levels -= 1
	_hp_bar.max_value = _player.max_hp

	if _pending_levels > 0:
		_open_level_up()  # Stacked level-ups: present the next card set.
		return

	_levelup_layer.hide()
	get_tree().paused = false
	_state = State.RUNNING
	_update_hud()


# --- Scoring and run end -----------------------------------------------------

func _score() -> int:
	var score := _kills * SCORE_PER_KILL
	score += int(_elapsed) * SCORE_PER_SECOND
	score += _xp_collected * SCORE_PER_XP
	if _survived:
		score += CLEAR_BONUS
	return score


func _on_enemy_killed(enemy: Node2D) -> void:
	_kills += 1
	var gem := XP_GEM_SCENE.instantiate()
	gem.position = enemy.position
	gem.value = 1
	# Deferred: this fires from an area_entered signal, i.e. mid physics-query
	# flush, and adding an Area2D right then throws "Can't change this state
	# while flushing queries". Deferring is still deterministic — the adds run
	# in a fixed order at the end of the same frame.
	_gems.add_child.call_deferred(gem)


func _on_player_died() -> void:
	_survived = false
	_end_run()


func _on_player_damaged(current_hp: float) -> void:
	_hp_bar.value = current_hp


func _end_run() -> void:
	if _state == State.OVER:
		return  # A run ends exactly once, whatever fires first.
	_state = State.OVER
	get_tree().paused = true

	var headline := "RUN CLEARED" if _survived else "YOU DIED"
	_gameover_label.text = "%s\n\nSCORE  %d\n\nkills %d  x%d = %d\ntime %s  x%d = %d\nxp %d  x%d = %d\nclear bonus  %d\n\npress R to restart" % [
		headline, _score(),
		_kills, SCORE_PER_KILL, _kills * SCORE_PER_KILL,
		_format_time(_elapsed), SCORE_PER_SECOND, int(_elapsed) * SCORE_PER_SECOND,
		_xp_collected, SCORE_PER_XP, _xp_collected * SCORE_PER_XP,
		CLEAR_BONUS if _survived else 0,
	]
	_gameover_layer.show()
	print("[run] over survived=%s score=%d kills=%d xp=%d level=%d" % [_survived, _score(), _kills, _xp_collected, _level])


# --- HUD ---------------------------------------------------------------------

func _format_time(seconds: float) -> String:
	return "%d:%02d" % [floori(seconds / 60.0), int(seconds) % 60]


func _update_hud() -> void:
	_timer_label.text = _format_time(maxf(0.0, _run_duration - _elapsed))
	_score_label.text = "SCORE %d" % _score()
	_level_label.text = "LV %d" % _level
	_hp_bar.value = _player.hp
	_xp_bar.max_value = _xp_needed(_level)
	_xp_bar.value = _xp_into_level
