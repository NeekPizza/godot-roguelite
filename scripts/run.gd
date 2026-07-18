extends Node2D

## Run orchestrator: wave scheduling, XP/levelling, scoring, run end.
## See docs/GDD.md sections 6-9.

## ENDLESS: there is no run duration and no win state. A run ends only on
## death. Difficulty is a continuous function of elapsed time (difficulty.gd)
## and keeps climbing without bound.
const ENEMY_CAP := 300

const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const XP_GEM_SCENE := preload("res://scenes/xp_gem.tscn")
const BOSS_SCENE := preload("res://scenes/boss.tscn")

## Guaranteed XP payout when a boss dies, dropped at fixed ring offsets — no
## RNG, because bosses die on player-dependent timing.
const BOSS_GEM_COUNT := 12
const BOSS_GEM_VALUE := 3
const BOSS_GEM_RADIUS := 62.0

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
var _next_boss := 1
var _bosses_killed := 0

## Headless test hooks, passed after a `--` separator. See docs/TESTING.md.
## `--run-seconds` is gone: with no fixed run length there is nothing to shorten.
## `--time-scale` compresses the ramp instead, and `--max-seconds` ends the run.
var _time_scale := 1.0
var _max_seconds := 0.0
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
		elif arg.begins_with("--time-scale="):
			# Compresses the difficulty ramp so late-game content is reachable
			# unattended. Enemy movement stays real-time, so this distorts feel;
			# it is for exercising spawn/boss logic, not for judging balance.
			_time_scale = float(arg.split("=")[1])
			print("[run] test override: time-scale=%.2fx" % _time_scale)
		elif arg.begins_with("--max-seconds="):
			_max_seconds = float(arg.split("=")[1])
			print("[run] test override: max-seconds=%.1f" % _max_seconds)
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

	# Endless: the only exit from RUNNING is death. --max-seconds is a test
	# harness lever, not a game rule.
	var step := delta * _time_scale
	_elapsed += step
	if _max_seconds > 0.0 and _elapsed >= _max_seconds:
		_end_run()
		return

	_check_boss_schedule()
	_schedule_waves(step)
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


## Release audio, then quit. Stopping playback first is correct hygiene and is
## the path Phase 5's menu quit will reuse. It does not suppress the exit-time
## "resources still in use" message — see the note in sfx.gd stop_all().
func _quit_cleanly() -> void:
	Music.stop()
	Sfx.stop_all()
	await get_tree().process_frame
	get_tree().quit()


func _capture_screenshot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(path)
	print("[run] screenshot -> %s (err %d)" % [path, error])


# --- Waves -------------------------------------------------------------------

func _schedule_waves(delta: float) -> void:
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer += Difficulty.spawn_interval(_elapsed)

	var weights := Difficulty.type_weights(_elapsed)
	var hp_multiplier := Difficulty.hp_multiplier(_elapsed)
	for i in Difficulty.spawn_count(_elapsed):
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
		_spawn_enemy(_pick_type(weights, roll), _edge_position(edge, along), hp_multiplier)


## Bosses arrive on a FIXED time schedule (difficulty.gd), never a player-driven
## one, and draw their position from spawn_rng like any other spawn. A `while`
## rather than an `if` so a large --time-scale step cannot skip an appearance
## and desync the stream.
func _check_boss_schedule() -> void:
	while _elapsed >= Difficulty.boss_time(_next_boss):
		var edge := _spawn_rng.randi_range(0, 3)
		var along := _spawn_rng.randf()
		_spawn_boss(_next_boss, _edge_position(edge, along))
		_next_boss += 1


func _spawn_boss(boss_index: int, at: Vector2) -> void:
	var boss := BOSS_SCENE.instantiate()
	boss.position = at
	boss.setup(boss_index)
	boss.shot_parent = _enemy_shots
	boss.killed.connect(_on_boss_killed)
	_enemies.add_child(boss)
	Sfx.play("level_up", -2.0)   # stand-in sting until Phase 5 audio pass
	_fx.add_shake(6.0)
	print("[run] BOSS %d at %s (hp %.0f, dmg %.0f)" % [
		boss_index, _format_time(_elapsed),
		Difficulty.boss_hp(boss_index), Difficulty.boss_damage(boss_index)])


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

## Per-type kill values (a Tank is 30, a Swarmer 6) plus survival and XP. No
## clear bonus: there is no clear. See score.gd for the int32 headroom analysis.
func _score() -> int:
	return Score.total(_kill_score, _elapsed, _xp_collected)


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


## Killing a boss does NOT end the run — it is a pace break and a depth marker.
func _on_boss_killed(boss: Area2D) -> void:
	_bosses_killed += 1
	_kill_score += int(boss.score_value)

	# Guaranteed XP at fixed offsets, so the payout cannot vary between players.
	for i in BOSS_GEM_COUNT:
		var angle := TAU * float(i) / float(BOSS_GEM_COUNT)
		var gem := XP_GEM_SCENE.instantiate()
		gem.position = Arena.clamp_position(
			boss.position + Vector2(BOSS_GEM_RADIUS, 0.0).rotated(angle), 12.0)
		gem.value = BOSS_GEM_VALUE
		_gems.add_child.call_deferred(gem)

	_fx.burst(boss.position, boss.COLOR, 90, 340.0)
	_fx.add_shake(12.0)
	Sfx.play("enemy_death", -2.0)
	print("[run] boss %d down at %s (+%d score)" % [
		boss.index, _format_time(_elapsed), boss.score_value])


func _on_player_died() -> void:
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

	_gameover_label.text = "YOU DIED\n\nSURVIVED  %s\nSCORE  %d\n\nkills %d = %d\ntime %s  x%d = %d\nxp %d  x%d = %d\nbosses felled  %d\n\npress R to restart" % [
		_format_time(_elapsed), _score(),
		_kills, _kill_score,
		_format_time(_elapsed), Score.PER_SECOND, int(_elapsed) * Score.PER_SECOND,
		_xp_collected, Score.PER_XP, _xp_collected * Score.PER_XP,
		_bosses_killed,
	]
	_gameover_layer.show()
	Sfx.play("run_over")
	if _quit_on_end:
		_quit_cleanly.call_deferred()
	print("[run] spawned by type: %s" % _type_counts)
	print("[run] over time=%s score=%d kills=%d xp=%d level=%d bosses=%d plausible=%s" % [
		_format_time(_elapsed), _score(), _kills, _xp_collected, _level,
		_bosses_killed, Score.is_plausible(_score())])


# --- HUD ---------------------------------------------------------------------

func _format_time(seconds: float) -> String:
	return "%d:%02d" % [floori(seconds / 60.0), int(seconds) % 60]


func _update_hud() -> void:
	_timer_label.text = _format_time(_elapsed)   # counts UP; endless
	_score_label.text = "SCORE %d" % _score()
	_level_label.text = "LV %d" % _level
	_hp_bar.value = _player.hp
	_xp_bar.max_value = _xp_needed(_level)
	_xp_bar.value = _xp_into_level
