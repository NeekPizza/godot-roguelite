extends Node2D

## Run orchestrator: wave scheduling, XP/levelling, scoring, run end.
## See docs/GDD.md sections 6-9.

const RUN_DURATION := 600.0  # 10 minutes
const ENEMY_CAP := 300
const CLEAR_BONUS := 2000

const SCORE_PER_SECOND := 5
const SCORE_PER_XP := 2

const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const XP_GEM_SCENE := preload("res://scenes/xp_gem.tscn")

## Difficulty tiers (GDD section 7). Ramps on elapsed time, never on player
## level. "types" is a weighted table; new enemy kinds phase in as the run goes.
const TIERS := [
	{"until": 120.0, "interval": 1.00, "count": 1, "hp_mult": 1.0,
	 "types": [["drifter", 1.00]]},
	{"until": 240.0, "interval": 0.80, "count": 2, "hp_mult": 1.25,
	 "types": [["drifter", 0.60], ["swarmer", 0.40]]},
	{"until": 360.0, "interval": 0.62, "count": 3, "hp_mult": 1.6,
	 "types": [["drifter", 0.46], ["swarmer", 0.42], ["shooter", 0.12]]},
	{"until": 480.0, "interval": 0.48, "count": 4, "hp_mult": 2.1,
	 "types": [["drifter", 0.28], ["swarmer", 0.32], ["shooter", 0.12], ["tank", 0.28]]},
	{"until": 600.0, "interval": 0.34, "count": 5, "hp_mult": 2.8,
	 "types": [["drifter", 0.20], ["swarmer", 0.30], ["shooter", 0.10],
			   ["tank", 0.22], ["splitter", 0.18]]},
]

## A splitter bursts into this many children, at fixed offsets. Deliberately
## NOT random: splitters die on player-dependent timing, so drawing from
## spawn_rng here would let a skilled player desync the shared wave stream.
const SPLIT_OFFSETS := [Vector2(-26.0, -14.0), Vector2(26.0, 14.0)]

enum State { RUNNING, LEVEL_UP, OVER }

@onready var _player: Area2D = $Player
@onready var _enemies: Node2D = $Enemies
@onready var _projectiles: Node2D = $Projectiles
@onready var _enemy_shots: Node2D = $EnemyShots
@onready var _gems: Node2D = $Gems
@onready var _fx: Node2D = $Fx

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
var _kill_score := 0
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
var _godmode := false
var _quit_on_end := false
var _type_counts := {}


func _parse_test_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--auto-pick":
			_auto_pick = true
		elif arg == "--quit-on-end":
			# Clean engine shutdown when the run finishes, instead of the abrupt
			# --quit-after frame kill. Also the right exit path for CI.
			_quit_on_end = true
		elif arg == "--godmode":
			# Lets an unattended run survive the whole difficulty ramp, which is
			# the only way to exercise the late-tier enemy types headlessly.
			_godmode = true
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
	for node in [_player, _enemies, _projectiles, _enemy_shots, _gems, _fx]:
		node.process_mode = Node.PROCESS_MODE_PAUSABLE

	_fx.camera = _player.get_node("Camera")

	_date_string = GameSeed.today_utc()
	_spawn_rng = GameSeed.make_spawn_rng(_date_string)
	print("[run] seed date=%s seed=%d" % [_date_string, GameSeed.for_date(_date_string)])

	_player.godmode = _godmode
	_player.projectile_parent = _projectiles
	_player.died.connect(_on_player_died)
	_player.damaged.connect(_on_player_damaged)
	_player.xp_collected.connect(_on_xp_collected)

	Music.start()

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
		# Draw from spawn_rng UNCONDITIONALLY, before the cap check, and always
		# draw exactly three values regardless of tier.
		#
		# This ordering is load-bearing for determinism: how many enemies are
		# alive depends on how well the player is fighting, so if a skipped
		# spawn also skipped its RNG draws, a good player and a bad player would
		# desync the shared stream and stop playing the same daily run.
		var edge := _spawn_rng.randi_range(0, 3)
		var along := _spawn_rng.randf()
		var roll := _spawn_rng.randf()
		if _enemies.get_child_count() >= ENEMY_CAP:
			continue
		_spawn_enemy(_pick_type(tier["types"], roll), _edge_position(edge, along), tier["hp_mult"])


## Weighted pick driven by an already-drawn roll, so the caller controls exactly
## how much RNG each spawn consumes.
func _pick_type(table: Array, roll: float) -> String:
	var total := 0.0
	for entry in table:
		total += entry[1]
	var target := roll * total
	for entry in table:
		target -= entry[1]
		if target <= 0.0:
			return entry[0]
	return table[table.size() - 1][0]


func _spawn_enemy(type_id: String, at: Vector2, hp_multiplier: float) -> void:
	_type_counts[type_id] = _type_counts.get(type_id, 0) + 1
	var enemy := ENEMY_SCENE.instantiate()
	enemy.position = at
	enemy.setup(type_id, hp_multiplier)
	enemy.shot_parent = _enemy_shots
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
	# Steeper than Phase 1's 5 + 4(N-1). With the denser waves below, the old
	# curve handed out levels faster than upgrades stayed meaningful.
	return 6 + (level - 1) * 5


func _on_xp_collected(amount: int) -> void:
	Sfx.play("xp_pickup", -14.0)
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
	Sfx.play("level_up", -4.0)
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
	# Per-type score values, not a flat rate: a tank is worth 30 and a swarmer 6,
	# so the board rewards fighting the dangerous things.
	var score := _kill_score
	score += int(_elapsed) * SCORE_PER_SECOND
	score += _xp_collected * SCORE_PER_XP
	if _survived:
		score += CLEAR_BONUS
	return score


func _on_enemy_killed(enemy: Area2D) -> void:
	_kills += 1
	_kill_score += int(enemy.stats["score"])

	var gem := XP_GEM_SCENE.instantiate()
	gem.position = enemy.position
	gem.value = int(enemy.stats["xp"])
	# Deferred: this fires from an area_entered signal, i.e. mid physics-query
	# flush, and adding an Area2D right then throws "Can't change this state
	# while flushing queries". Deferring is still deterministic — the adds run
	# in a fixed order at the end of the same frame.
	_gems.add_child.call_deferred(gem)

	_fx.burst(enemy.position, enemy.stats["color"], 10, 170.0)
	_fx.add_shake(1.2)
	Sfx.play("enemy_death", -10.0)

	if enemy.stats.has("splits_into"):
		_split(enemy)


func _split(parent_enemy: Area2D) -> void:
	var child_type: String = parent_enemy.stats["splits_into"]
	var count: int = mini(int(parent_enemy.stats["split_count"]), SPLIT_OFFSETS.size())
	if _enemies.get_child_count() + count > ENEMY_CAP:
		return
	for i in count:
		var at: Vector2 = Arena.clamp_position(parent_enemy.position + SPLIT_OFFSETS[i], 24.0)
		_spawn_enemy.call_deferred(child_type, at, 1.0)


func _on_player_died() -> void:
	_survived = false
	_end_run()


func _on_player_damaged(current_hp: float) -> void:
	_hp_bar.value = current_hp
	_fx.burst(_player.position, Color(1.0, 0.35, 0.45), 16, 210.0)
	_fx.add_shake(7.0)


func _end_run() -> void:
	if _state == State.OVER:
		return  # A run ends exactly once, whatever fires first.
	_state = State.OVER
	get_tree().paused = true

	var headline := "RUN CLEARED" if _survived else "YOU DIED"
	_gameover_label.text = "%s\n\nSCORE  %d\n\nkills %d = %d\ntime %s  x%d = %d\nxp %d  x%d = %d\nclear bonus  %d\n\npress R to restart" % [
		headline, _score(),
		_kills, _kill_score,
		_format_time(_elapsed), SCORE_PER_SECOND, int(_elapsed) * SCORE_PER_SECOND,
		_xp_collected, SCORE_PER_XP, _xp_collected * SCORE_PER_XP,
		CLEAR_BONUS if _survived else 0,
	]
	_gameover_layer.show()
	Sfx.play("run_over")
	if _quit_on_end:
		get_tree().quit.call_deferred()
	print("[run] spawned by type: %s" % _type_counts)
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
