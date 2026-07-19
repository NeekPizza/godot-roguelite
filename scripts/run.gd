extends Node2D

## Run orchestrator: wave scheduling, XP/levelling, scoring, run end.
## See docs/GDD.md sections 6-9.

## ENDLESS: there is no run duration and no win state. A run ends only on
## death. Difficulty is a continuous function of elapsed time (difficulty.gd)
## and keeps climbing without bound.
##
## ORCHESTRATION ONLY — every tunable number comes from balance.gd.

const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const XP_GEM_SCENE := preload("res://scenes/xp_gem.tscn")
const BOSS_SCENE := preload("res://scenes/boss.tscn")

enum State { RUNNING, LEVEL_UP, PAUSED, OVER }

@onready var _player: Area2D = $Player
@onready var _enemies: Node2D = $Enemies
@onready var _projectiles: Node2D = $Projectiles
@onready var _enemy_shots: Node2D = $EnemyShots
@onready var _gems: Node2D = $Gems
@onready var _fx: Node2D = $Fx
var _weapons: Node2D

@onready var _timer_label: Label = $HUD/Root/TimerLabel
@onready var _score_label: Label = $HUD/Root/ScoreLabel
@onready var _level_label: Label = $HUD/Root/LevelLabel
@onready var _hp_bar: ProgressBar = $HUD/Root/HPBar
@onready var _xp_bar: ProgressBar = $HUD/Root/XPBar
@onready var _exp_label: Label = $HUD/Root/ExpLabel
@onready var _health_label: Label = $HUD/Root/HealthLabel
@onready var _weapons_label: Label = $HUD/Root/WeaponsLabel
@onready var _combo_label: Label = $HUD/Root/ComboLabel

@onready var _levelup_layer: CanvasLayer = $LevelUpLayer
@onready var _levelup_buttons: HBoxContainer = $LevelUpLayer/Root/Center/Panel/Cards
@onready var _levelup_hint: Label = $LevelUpLayer/Root/Center/Panel/Hint
@onready var _reroll_button: Button = $LevelUpLayer/Root/Center/Panel/Controls/Reroll
@onready var _banish_button: Button = $LevelUpLayer/Root/Center/Panel/Controls/Banish
@onready var _pause_layer: CanvasLayer = $PauseLayer
@onready var _pause_info: Label = $PauseLayer/Root/Center/Panel/Info
@onready var _pause_resume: Button = $PauseLayer/Root/Center/Panel/Resume
@onready var _pause_restart: Button = $PauseLayer/Root/Center/Panel/Restart
@onready var _pause_settings: Button = $PauseLayer/Root/Center/Panel/Settings
@onready var _pause_menu: Button = $PauseLayer/Root/Center/Panel/Menu
@onready var _pause_settings_panel: Control = $PauseLayer/Root/SettingsPanel
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
var _stacks := {}                # passive id -> stacks
var _banished: Array = []        # ids removed from the deck for the rest of the run
var _card_action := 0            # reroll/banish counter WITHIN the current level
var _rerolls_left := Balance.REROLLS_PER_RUN
var _banishes_left := Balance.BANISHES_PER_RUN
var _banish_armed := false
var _current_cards: Array = []
var _weapon_slots := 3

# --- Combo (6c) ---
var _combo_chain := 0.0
var _combo_idle := 0.0        # seconds since the last kill

var _kills := 0
var _kill_score := 0
var _xp_collected := 0
var _next_boss := 1
var _bosses_killed := 0
var _ranked := false

## Headless test hooks, passed after a `--` separator. See docs/TESTING.md.
## `--run-seconds` is gone: with no fixed run length there is nothing to shorten.
## `--time-scale` compresses the ramp instead, and `--max-seconds` ends the run.
var _time_scale := 1.0
var _max_seconds := 0.0
var _auto_pick := false
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

	# Which run this is (seed date + whether it counts) is decided by RunConfig,
	# never here. begin_run() burns the ranked attempt AT START, so quitting
	# mid-run cannot buy a retry.
	RunConfig.begin_run()
	_date_string = RunConfig.date_string
	_ranked = RunConfig.is_ranked()
	_spawn_rng = GameSeed.make_spawn_rng(_date_string)
	print("[run] %s seed date=%s seed=%d" % [
		RunConfig.mode_name(), _date_string, GameSeed.for_date(_date_string)])

	# Today's weapon-slot count, from the `daily` stream: the same for everyone
	# on this seed, and shown on the ranked confirmation before the attempt is
	# spent because it changes how you draft.
	_weapon_slots = Daily.weapon_slots(_date_string)
	print("[run] weapon slots today: %d" % _weapon_slots)

	_weapons = _player.get_node("WeaponSystem")
	_weapons.player = _player
	_weapons.projectile_parent = _projectiles
	_weapons.add_or_level(Balance.STARTING_WEAPON)

	_player.godmode = _godmode
	_player.projectile_parent = _projectiles
	_player.died.connect(_on_player_died)
	_player.damaged.connect(_on_player_damaged)
	_player.xp_collected.connect(_on_xp_collected)

	Music.start()

	_reroll_button.pressed.connect(_on_reroll_pressed)
	_banish_button.pressed.connect(_on_banish_pressed)

	_pause_resume.pressed.connect(_close_pause)
	_pause_restart.pressed.connect(_restart)
	_pause_settings.pressed.connect(_open_pause_settings)
	_pause_menu.pressed.connect(_to_menu)
	_pause_settings_panel.closed.connect(_close_pause_settings)

	_apply_bar_colours()

	_levelup_layer.hide()
	_pause_layer.hide()
	_pause_settings_panel.hide()
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

	_tick_combo(step)
	_check_boss_schedule()
	_schedule_waves(step)
	_update_hud()


func _process(_delta: float) -> void:
	if _state == State.OVER:
		if Input.is_action_just_pressed("restart"):
			_restart()
		elif Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("ui_cancel"):
			_to_menu()
	elif Input.is_action_just_pressed("pause"):
		if _state == State.RUNNING:
			_open_pause()
		elif _state == State.PAUSED and not _pause_settings_panel.visible:
			_close_pause()


## Release audio, then quit. Stopping playback first is correct hygiene and is
## the path Phase 5's menu quit will reuse. It does not suppress the exit-time
## "resources still in use" message — see the note in sfx.gd stop_all().
func _quit_cleanly() -> void:
	Music.stop()
	Sfx.stop_all()
	await get_tree().process_frame
	get_tree().quit()


## Drive the bar colours from balance.gd at runtime.
##
## The scene file carries matching values so the editor preview looks right, but
## a StyleBoxFlat in a .tscn cannot reference a GDScript constant — so without
## this the two could silently drift and the EXP bar would stop matching the gems
## it represents. Styleboxes are Resources and shared by default, hence the
## duplicate().
func _apply_bar_colours() -> void:
	_tint_bar(_xp_bar, Balance.GEM_COLOR)
	_tint_bar(_hp_bar, Balance.HEALTH_COLOR)
	_exp_label.add_theme_color_override("font_color", Balance.GEM_COLOR)
	_health_label.add_theme_color_override("font_color", Balance.HEALTH_COLOR)


func _tint_bar(bar: ProgressBar, colour: Color) -> void:
	var fill := bar.get_theme_stylebox("fill")
	if fill is StyleBoxFlat:
		var styled: StyleBoxFlat = fill.duplicate()
		styled.bg_color = colour
		bar.add_theme_stylebox_override("fill", styled)


# --- Combo -------------------------------------------------------------------

## Kills inside COMBO_WINDOW of each other build a chain; it bleeds away once
## you stop. Multiplies KILL SCORE ONLY — multiplying survival time would reward
## turtling with a full bar, which is the play the scoring exists to discourage.
func _tick_combo(delta: float) -> void:
	_combo_idle += delta
	if _combo_idle > Balance.COMBO_WINDOW:
		_combo_chain = maxf(0.0, _combo_chain - Balance.COMBO_DECAY_PER_SEC * delta)


func combo_multiplier() -> float:
	return 1.0 + minf(Balance.COMBO_MAX_BONUS, _combo_chain * Balance.COMBO_PER_KILL)


func _register_combo_kill() -> void:
	_combo_idle = 0.0
	_combo_chain += 1.0


# --- Pause -------------------------------------------------------------------

func _open_pause() -> void:
	_state = State.PAUSED
	get_tree().paused = true
	# Restarting a RANKED run cannot grant a second ranked attempt: the attempt
	# was burned at run start, so a reload comes back as practice. Say so
	# plainly rather than letting the player discover it after committing.
	if _ranked:
		_pause_info.text = "RANKED — %s\nYour attempt is already used.\nRestarting replays this seed as practice." % _date_string
		_pause_restart.text = "RESTART (as practice)"
	else:
		_pause_info.text = "%s — %s" % [RunConfig.mode_name(), _date_string]
		_pause_restart.text = "RESTART"
	_pause_layer.show()
	_pause_resume.grab_focus()


func _close_pause() -> void:
	_pause_layer.hide()
	_pause_settings_panel.hide()
	get_tree().paused = false
	_state = State.RUNNING


func _open_pause_settings() -> void:
	_pause_settings_panel.show()
	_pause_settings_panel.focus_first()


func _close_pause_settings() -> void:
	_pause_settings_panel.hide()
	_pause_resume.grab_focus()


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


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
		if _enemies.get_child_count() >= Balance.ENEMY_CAP:
			continue
		_spawn_enemy(Difficulty.pick_type(weights, roll),
			Arena.edge_position(edge, along), hp_multiplier)


## Bosses arrive on a FIXED time schedule (difficulty.gd), never a player-driven
## one, and draw their position from spawn_rng like any other spawn. A `while`
## rather than an `if` so a large --time-scale step cannot skip an appearance
## and desync the stream.
func _check_boss_schedule() -> void:
	while _elapsed >= Difficulty.boss_time(_next_boss):
		var edge := _spawn_rng.randi_range(0, 3)
		var along := _spawn_rng.randf()
		_spawn_boss(_next_boss, Arena.edge_position(edge, along))
		_next_boss += 1


func _spawn_boss(boss_index: int, at: Vector2) -> void:
	var boss := BOSS_SCENE.instantiate()
	boss.position = at
	boss.setup(boss_index)
	boss.shot_parent = _enemy_shots
	boss.killed.connect(_on_boss_killed)
	_enemies.add_child(boss)
	Sfx.play("boss_spawn")
	_fx.add_shake(Balance.SHAKE_ON_BOSS_SPAWN)
	print("[run] BOSS %d at %s (hp %.0f, dmg %.0f)" % [
		boss_index, _format_time(_elapsed),
		Difficulty.boss_hp(boss_index), Difficulty.boss_damage(boss_index)])


func _spawn_enemy(type_id: String, at: Vector2, hp_multiplier: float) -> void:
	_type_counts[type_id] = _type_counts.get(type_id, 0) + 1
	var enemy := ENEMY_SCENE.instantiate()
	enemy.position = at
	enemy.setup(type_id, hp_multiplier)
	enemy.shot_parent = _enemy_shots
	enemy.killed.connect(_on_enemy_killed)
	_enemies.add_child(enemy)


# --- XP and levelling --------------------------------------------------------

func _xp_needed(level: int) -> int:
	return Balance.XP_BASE + (level - 1) * Balance.XP_STEP


func _on_xp_collected(amount: int) -> void:
	Sfx.play("xp_pickup")
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
	_card_action = 0
	_banish_armed = false
	_deal_cards()

	print("[run] level up -> %d  (xp %d, kills %d)" % [_level, _xp_collected, _kills])
	_update_hud()  # Otherwise the HUD still shows the pre-level-up level.
	Sfx.play("level_up")
	_levelup_layer.show()
	_levelup_buttons.get_child(0).grab_focus()

	if _auto_pick:
		_on_card_chosen.call_deferred(0)


## Draw and render the current offer. `_card_action` indexes the draw, so the
## initial offer and every reroll are each reproducible in isolation.
func _deal_cards() -> void:
	_current_cards = Cards.draw(_date_string, _level, _card_action, {
		"weapons": _weapons.owned,
		"passives": _stacks,
		"banished": _banished,
		"slots": _weapon_slots,
	})

	for i in _levelup_buttons.get_child_count():
		var button: Button = _levelup_buttons.get_child(i)
		var card: Dictionary = _current_cards[i]
		button.text = "%s\n%s\n\n%s" % [_card_tag(card), card["name"], card["desc"]]
		for connection in button.pressed.get_connections():
			button.pressed.disconnect(connection["callable"])
		button.pressed.connect(_on_card_chosen.bind(i))

	_refresh_card_controls()


## Cards compete for attention under pressure, so each says what KIND it is.
func _card_tag(card: Dictionary) -> String:
	match card["kind"]:
		Cards.KIND_EVOLUTION:    return "EVOLUTION"
		Cards.KIND_WEAPON_NEW:   return "NEW WEAPON"
		Cards.KIND_WEAPON_LEVEL: return "WEAPON  Lv%d" % int(card["level"])
		Cards.KIND_PASSIVE:      return "PASSIVE  Lv%d" % int(card["level"])
		_:                       return "RECOVER"


func _refresh_card_controls() -> void:
	_reroll_button.text = "REROLL (%d)" % _rerolls_left
	_reroll_button.disabled = _rerolls_left <= 0
	_banish_button.text = "BANISH (%d)" % _banishes_left
	_banish_button.disabled = _banishes_left <= 0
	_levelup_hint.text = "Pick a card to banish it" if _banish_armed \
		else "Slots %d/%d   ·   %s" % [_weapons.slots_used(), _weapon_slots, _weapons.summary()]


func _on_reroll_pressed() -> void:
	if _rerolls_left <= 0:
		return
	_rerolls_left -= 1
	_card_action += 1
	_banish_armed = false
	_deal_cards()
	_levelup_buttons.get_child(0).grab_focus()


func _on_banish_pressed() -> void:
	if _banishes_left <= 0:
		return
	_banish_armed = not _banish_armed
	_refresh_card_controls()


func _on_card_chosen(index: int) -> void:
	var card: Dictionary = _current_cards[index]

	if _banish_armed:
		# Banish removes the option from the deck permanently, then redraws.
		_banish_armed = false
		_banishes_left -= 1
		if card["kind"] != Cards.KIND_HEAL:
			_banished.append(card["id"])
		_card_action += 1
		_deal_cards()
		_levelup_buttons.get_child(0).grab_focus()
		return

	_take_card(card)

	_pending_levels -= 1
	_hp_bar.max_value = _player.max_hp

	if _pending_levels > 0:
		_open_level_up()  # Stacked level-ups: present the next offer.
		return

	_levelup_layer.hide()
	get_tree().paused = false
	_state = State.RUNNING
	_update_hud()


func _take_card(card: Dictionary) -> void:
	match card["kind"]:
		Cards.KIND_EVOLUTION:
			_weapons.evolve(card["base"], card["id"])
			Sfx.play("level_up")
		Cards.KIND_WEAPON_NEW, Cards.KIND_WEAPON_LEVEL:
			_weapons.add_or_level(card["id"])
		Cards.KIND_PASSIVE:
			Weapons.apply_passive(card["id"], _player)
			_stacks[card["id"]] = int(_stacks.get(card["id"], 0)) + 1
		_:
			_player.heal(float(Balance.CARD_FALLBACK["heal"]))


# --- Scoring and run end -----------------------------------------------------

## Per-type kill values (a Tank is 30, a Swarmer 6) plus survival and XP. No
## clear bonus: there is no clear. See score.gd for the int32 headroom analysis.
func _score() -> int:
	return Score.total(_kill_score, _elapsed, _xp_collected)


func _on_enemy_killed(enemy: Area2D) -> void:
	_kills += 1
	_register_combo_kill()
	_kill_score += int(round(float(enemy.stats["score"]) * combo_multiplier()))

	var gem := XP_GEM_SCENE.instantiate()
	gem.position = enemy.position
	gem.value = int(enemy.stats["xp"])
	# Deferred: this fires from an area_entered signal, i.e. mid physics-query
	# flush, and adding an Area2D right then throws "Can't change this state
	# while flushing queries". Deferring is still deterministic — the adds run
	# in a fixed order at the end of the same frame.
	_gems.add_child.call_deferred(gem)

	_fx.burst(enemy.position, enemy.stats["color"],
		Balance.PARTICLES_ON_KILL, Balance.PARTICLE_SPEED_KILL)
	_fx.add_shake(Balance.SHAKE_ON_KILL)
	Sfx.play("enemy_death")

	if enemy.stats.has("splits_into"):
		_split(enemy)


func _split(parent_enemy: Area2D) -> void:
	var child_type: String = parent_enemy.stats["splits_into"]
	var count: int = mini(int(parent_enemy.stats["split_count"]), Balance.SPLIT_OFFSETS.size())
	if _enemies.get_child_count() + count > Balance.ENEMY_CAP:
		return
	for i in count:
		var at: Vector2 = Arena.clamp_position(
			parent_enemy.position + Balance.SPLIT_OFFSETS[i], 24.0)
		_spawn_enemy.call_deferred(child_type, at, 1.0)


## Killing a boss does NOT end the run — it is a pace break and a depth marker.
func _on_boss_killed(boss: Area2D) -> void:
	_bosses_killed += 1
	_register_combo_kill()
	_kill_score += int(round(float(boss.score_value) * combo_multiplier()))

	# Guaranteed XP at fixed offsets, so the payout cannot vary between players.
	for i in Balance.BOSS_GEM_COUNT:
		var angle := TAU * float(i) / float(Balance.BOSS_GEM_COUNT)
		var gem := XP_GEM_SCENE.instantiate()
		gem.position = Arena.clamp_position(
			boss.position + Vector2(Balance.BOSS_GEM_RADIUS, 0.0).rotated(angle), 12.0)
		gem.value = Balance.BOSS_GEM_VALUE
		_gems.add_child.call_deferred(gem)

	_fx.burst(boss.position, Balance.BOSS_COLOR,
		Balance.PARTICLES_ON_BOSS_KILL, Balance.PARTICLE_SPEED_BOSS)
	_fx.add_shake(Balance.SHAKE_ON_BOSS_KILL)
	Sfx.play("boss_death")
	print("[run] boss %d down at %s (+%d score)" % [
		boss.index, _format_time(_elapsed), boss.score_value])


func _on_player_died() -> void:
	_end_run()


func _on_player_damaged(current_hp: float) -> void:
	_hp_bar.value = current_hp
	_fx.burst(_player.position, Color(1.0, 0.35, 0.45),
		Balance.PARTICLES_ON_PLAYER_HURT, Balance.PARTICLE_SPEED_HURT)
	_fx.add_shake(Balance.SHAKE_ON_PLAYER_HURT)


func _end_run() -> void:
	if _state == State.OVER:
		return  # A run ends exactly once, whatever fires first.
	_state = State.OVER
	get_tree().paused = true

	_record_result()
	_gameover_label.text = "YOU DIED\n\nSURVIVED  %s\nSCORE  %d\n\nkills %d = %d\ntime %s  x%d = %d\nxp %d  x%d = %d\nbosses felled  %d\n\npress R to replay   ·   ESC for menu" % [
		_format_time(_elapsed), _score(),
		_kills, _kill_score,
		_format_time(_elapsed), Score.PER_SECOND, int(_elapsed) * Score.PER_SECOND,
		_xp_collected, Score.PER_XP, _xp_collected * Score.PER_XP,
		_bosses_killed,
	]
	_gameover_label.text += "\n\n%s" % _score_table_text()
	_gameover_layer.show()
	Sfx.play("run_over")
	if _quit_on_end:
		_quit_cleanly.call_deferred()
	print("[run] spawned by type: %s" % _type_counts)
	print("[digest] %s" % _state_digest())
	print("[run] over mode=%s date=%s time=%s score=%d kills=%d xp=%d level=%d bosses=%d plausible=%s" % [
		RunConfig.mode_name(), _date_string,
		_format_time(_elapsed), _score(), _kills, _xp_collected, _level,
		_bosses_killed, Score.is_plausible(_score())])


## Persist the run. Scores are bounded before storage so a corrupted or edited
## value cannot poison the local table (and, in Phase 4, the Steam submission).
func _record_result() -> void:
	var final_score := Score.bounded(_score())
	SaveStore.record_score({
		"date": _date_string,
		"ranked": _ranked,
		"score": final_score,
		"kills": _kills,
		"seconds": int(_elapsed),
		"level": _level,
		"bosses": _bosses_killed,
	})
	if _ranked:
		SaveStore.finish_ranked_attempt(_date_string, final_score)


func _score_table_text() -> String:
	var rows := SaveStore.top_for_date(_date_string, Balance.SCORE_TABLE_ROWS)
	if rows.is_empty():
		return ""
	var lines := PackedStringArray(["BEST ON %s" % _date_string])
	for i in rows.size():
		var row: Dictionary = rows[i]
		lines.append("%d.  %7d   %s   lv%d   %s" % [
			i + 1, int(row.get("score", 0)),
			_format_time(float(row.get("seconds", 0))),
			int(row.get("level", 1)),
			"ranked" if bool(row.get("ranked", false)) else "practice",
		])
	return "\n".join(lines)


## End-of-run fingerprint for the determinism check.
##
## The important field is spawn_rng.state: it encodes exactly how many draws the
## wave scheduler made over the whole run. Two runs matching on score alone could
## still have consumed the stream differently; matching on RNG state cannot.
func _state_digest() -> String:
	return "rng=%d pos=(%.3f,%.3f) hp=%.3f dashes=%d elapsed=%.3f kills=%d killscore=%d xp=%d level=%d bosses=%d nextboss=%d alive=%d gems=%d spawned=%s" % [
		_spawn_rng.state,
		_player.position.x, _player.position.y, _player.hp, _player.dashes_used,
		_elapsed, _kills, _kill_score, _xp_collected, _level,
		_bosses_killed, _next_boss,
		_enemies.get_child_count(), _gems.get_child_count(),
		JSON.stringify(_type_counts),
	] + " slots=%d weapons=%s passives=%s banished=%s rerolls=%d banishes=%d combo=%.3f" % [
		_weapon_slots, _weapons.digest(), JSON.stringify(_stacks),
		JSON.stringify(_banished), _rerolls_left, _banishes_left, _combo_chain,
	]


# --- HUD ---------------------------------------------------------------------

func _format_time(seconds: float) -> String:
	return "%d:%02d" % [floori(seconds / 60.0), int(seconds) % 60]


func _update_hud() -> void:
	_timer_label.text = _format_time(_elapsed)   # counts UP; endless
	_score_label.text = "SCORE %d" % _score()
	var multiplier := combo_multiplier()
	if multiplier > 1.001:
		_combo_label.text = "x%.2f" % multiplier
		_combo_label.modulate = Color(1.0, 0.92, 0.25).lerp(
			Color(1.0, 0.35, 0.45),
			clampf((multiplier - 1.0) / maxf(0.001, Balance.COMBO_MAX_BONUS), 0.0, 1.0))
	else:
		_combo_label.text = ""
	_level_label.text = "LV %d   %s  %s" % [_level, RunConfig.mode_name(), _date_string]
	_weapons_label.text = "%s     [%d/%d slots]" % [
		_weapons.summary(), _weapons.slots_used(), _weapon_slots]
	_hp_bar.value = _player.hp
	_xp_bar.max_value = _xp_needed(_level)
	_xp_bar.value = _xp_into_level
