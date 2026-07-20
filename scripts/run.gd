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
const PICKUP_SCENE := preload("res://scenes/pickup.tscn")
const PORTAL_SCENE := preload("res://scenes/portal.tscn")

enum State { RUNNING, LEVEL_UP, PAUSED, OVER }
## Within RUNNING, the stage runs through these in order.
enum StagePhase { COMBAT, BOSS, CLEAR, PORTAL }

@onready var _player: Area2D = $Player
@onready var _enemies: Node2D = $Enemies
@onready var _projectiles: Node2D = $Projectiles
@onready var _enemy_shots: Node2D = $EnemyShots
@onready var _gems: Node2D = $Gems
@onready var _pickups: Node2D = $Pickups
@onready var _fx: Node2D = $Fx
@onready var _world_bounds: Node2D = $WorldBounds
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
@onready var _buff_list: VBoxContainer = $HUD/Root/BuffList

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
@onready var _stage_card_layer: CanvasLayer = $StageCardLayer
@onready var _stage_card_title: Label = $StageCardLayer/Root/Center/Panel/Title
@onready var _stage_card_body: Label = $StageCardLayer/Root/Center/Panel/Body
@onready var _stage_card_button: Button = $StageCardLayer/Root/Center/Panel/Continue
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

# --- Drops (6d) ---
var _drop_schedule: Array = []
var _next_drop := 0
var _buff_id := ""            # instant/buff effect currently running
var _buff_time := 0.0
var _splash_time := 0.0       # splash is a modifier, so it runs alongside
var _drops_taken := 0
var _pickups_scheduled := 0
var _pickups_elite := 0
var _pickups_boss := 0
var _spawn_ordinal := 0
var _elites_spawned := 0
var _roster: Array = []
var _boss_log: Array = []

# --- Stages (7a) ---
var _stage := 1
var _stage_elapsed := 0.0          # resets on stage entry; drives all schedules
var _stage_phase := StagePhase.COMBAT
var _stage_clear_timer := 0.0
var _boss_alive := false
var _stages_cleared := 0
var _boss_hp_mult := 1.0           # test hook only
var _meta_bonus := 0.0
var _boss_death_position := Vector2.ZERO

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
		elif arg.begins_with("--boss-hp-mult="):
			# Test-only: the determinism check has to CROSS stages, and a
			# scripted player cannot out-damage scaling boss HP. Listed in
			# RunConfig.TEST_HOOK_ARGS, so a run using it can never be ranked.
			_boss_hp_mult = float(arg.split("=")[1])
			print("[run] test override: boss-hp-mult=%.3f" % _boss_hp_mult)
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
	for node in [_player, _enemies, _projectiles, _enemy_shots, _gems, _pickups, _fx]:
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

	# The entire run's drops, decided now: what, when, and at which absolute
	# world position. Nothing is rolled during play.
	_weapons = _player.get_node("WeaponSystem")
	_weapons.player = _player
	_weapons.projectile_parent = _projectiles
	_weapons.add_or_level(Balance.STARTING_WEAPON)

	# Meta-progression: player-side stats only, applied once, before anything
	# else reads them. Nothing here can reach a seeded schedule.
	Meta.apply(_player, MetaStore.purchases)
	_rerolls_left += Meta.bonus_rerolls(MetaStore.purchases)
	_xp_into_level = Meta.starting_xp(MetaStore.purchases, _xp_needed(1))
	_meta_bonus = Meta.effective_bonus(MetaStore.purchases)
	if _meta_bonus > 0.0:
		print("[meta] applied %s (rerolls +%d, starting xp %d)" % [
			MetaStore.bonus_text(), Meta.bonus_rerolls(MetaStore.purchases),
			_xp_into_level])

	_player.hp = _player.max_hp
	_player.godmode = _godmode
	_player.projectile_parent = _projectiles
	_player.died.connect(_on_player_died)
	_player.damaged.connect(_on_player_damaged)
	_player.xp_collected.connect(_on_xp_collected)

	Music.start()

	_stage_card_button.pressed.connect(_dismiss_stage_card)
	_reroll_button.pressed.connect(_on_reroll_pressed)
	_banish_button.pressed.connect(_on_banish_pressed)

	_pause_resume.pressed.connect(_close_pause)
	_pause_restart.pressed.connect(_restart)
	_pause_settings.pressed.connect(_open_pause_settings)
	_pause_menu.pressed.connect(_to_menu)
	_pause_settings_panel.closed.connect(_close_pause_settings)

	_apply_bar_colours()

	_enter_stage(1)

	_levelup_layer.hide()
	_pause_layer.hide()
	_stage_card_layer.hide()
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

	_stage_elapsed += step
	_tick_combo(step)
	_tick_buffs(step)
	_tick_stage(step)
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


## Active buffs as a stacked list down the left, BELOW the EXP bar.
##
## They previously sat on the same row as the bar and were drawn over by it. A
## timed effect the player cannot see running is one they cannot play around.
func _refresh_buff_list() -> void:
	var active := []
	if _buff_time > 0.0 and _buff_id != "":
		active.append([_buff_id, _buff_time])
	if _splash_time > 0.0:
		active.append(["splash", _splash_time])

	# Reuse rows rather than rebuilding: this runs every physics frame.
	while _buff_list.get_child_count() < active.size():
		var row := Label.new()
		row.add_theme_font_size_override("font_size", 16)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_buff_list.add_child(row)

	for i in _buff_list.get_child_count():
		var row: Label = _buff_list.get_child(i)
		if i >= active.size():
			row.visible = false
			continue
		var drop_id: String = active[i][0]
		var remaining: float = active[i][1]
		row.visible = true
		row.text = "%s  %.0fs" % [Balance.DROPS[drop_id]["name"], ceil(remaining)]
		row.add_theme_color_override("font_color", Balance.DROPS[drop_id]["color"])


# --- Drops -------------------------------------------------------------------

func _check_drop_schedule() -> void:
	# Against the STAGE clock, not the run clock: the schedule is rebuilt per
	# stage with times relative to entry, so comparing it to absolute elapsed
	# dumped every remaining entry at once from stage 2 onward.
	while _next_drop < _drop_schedule.size() \
			and _stage_elapsed >= float(_drop_schedule[_next_drop]["time"]):
		var entry: Dictionary = _drop_schedule[_next_drop]
		_pickups_scheduled += 1
		_spawn_pickup(entry["id"], entry["position"])
		_next_drop += 1


func _spawn_pickup(drop_id: String, at: Vector2) -> void:
	var pickup := PICKUP_SCENE.instantiate()
	pickup.position = at
	pickup.setup(drop_id)
	pickup.collected.connect(_on_pickup_collected)
	_pickups.add_child.call_deferred(pickup)


func _on_pickup_collected(drop_id: String, _pickup: Area2D) -> void:
	_drops_taken += 1
	var config: Dictionary = Balance.DROPS[drop_id]
	Sfx.play("xp_pickup", -4.0)
	_fx.burst(_player.position, config.get("color", Color.WHITE), 22, 240.0)

	match config["kind"]:
		"instant":
			_apply_instant(drop_id, config)
		"buff":
			_buff_id = drop_id
			_buff_time = float(config["duration"])
			_player.invuln_time = float(config["duration"])
		"temp_weapon":
			if config.get("modifier", "") == "splash":
				_splash_time = float(config["duration"])
			else:
				_weapons.temp_weapon_id = drop_id
				_buff_id = drop_id
				_buff_time = float(config["duration"])


func _apply_instant(drop_id: String, config: Dictionary) -> void:
	match config["effect"]:
		"heal":
			_player.heal(float(config["amount"]))
		"sweep_xp":
			for gem in get_tree().get_nodes_in_group("xp_gem"):
				gem.attract_to(_player)
		"blast":
			_detonate(config)
	if drop_id == "bomb":
		_fx.add_shake(Balance.SHAKE_ON_BOSS_KILL)


## Bomb. Radius is WORLD-space, never the viewport: screen size varies with
## resolution and fullscreen, so a viewport-based blast would clear a different
## set of enemies for different players on the same seed.
func _detonate(config: Dictionary) -> void:
	var radius := float(config["world_radius"])
	var damage := float(config["damage"])
	var boss_fraction := float(config["boss_damage_fraction"])
	# Snapshot the child list: take_damage frees nodes as we iterate.
	for enemy in _enemies.get_children():
		if not is_instance_valid(enemy):
			continue
		if _player.position.distance_to(enemy.position) > radius:
			continue
		if enemy.is_in_group("boss"):
			enemy.take_damage(enemy.max_hp * boss_fraction)   # capped, never an instakill
		else:
			enemy.take_damage(damage)


func _tick_buffs(delta: float) -> void:
	_splash_time = maxf(0.0, _splash_time - delta)
	if _buff_time > 0.0:
		_buff_time = maxf(0.0, _buff_time - delta)
		if _buff_time <= 0.0:
			if _weapons.temp_weapon_id == _buff_id:
				_weapons.temp_weapon_id = ""
			_buff_id = ""


## Splash: a killed enemy detonates for a fraction of its max HP.
##
## Iterates the enemy container in CHILD ORDER — that is, spawn order — and is
## depth-capped. instance_id and dictionary order are not stable across runs, so
## either would let a chain branch differently on two machines from identical
## state, which is exactly the class of bug the seed contract exists to prevent.
func _splash_from(origin: Vector2, source_max_hp: float, depth: int) -> void:
	var config: Dictionary = Balance.DROPS["splash"]
	if depth >= int(config["chain_depth_max"]):
		return
	var radius := float(config["radius"])
	var damage := source_max_hp * float(config["hp_fraction"])

	for enemy in _enemies.get_children():
		if not is_instance_valid(enemy) or enemy.is_in_group("boss"):
			continue
		if origin.distance_to(enemy.position) > radius:
			continue
		var victim_hp: float = enemy.max_hp
		var victim_position: Vector2 = enemy.position
		var lethal: bool = enemy.hp <= damage
		enemy.take_damage(damage)
		if lethal:
			_splash_from(victim_position, victim_hp, depth + 1)
	_fx.burst(origin, Balance.DROPS["splash"]["color"], 14, 200.0)


## Bomber detonates on death, hurting the player AND nearby enemies. Same
## ordering and depth rules as splash: child order, capped, no RNG.
func _bomber_blast(source: Area2D, depth := 0) -> void:
	var blast_radius: float = source.stats["blast_radius"]
	var blast_damage: float = source.stats["blast_damage"]
	var origin: Vector2 = source.position
	if _player.position.distance_to(origin) <= blast_radius:
		_player.take_damage(blast_damage)
	_fx.burst(origin, source.stats["color"], 26, 260.0)
	_fx.add_shake(2.0)

	if depth >= int(source.stats.get("blast_chain_depth", 1)):
		return
	for enemy in _enemies.get_children():
		if not is_instance_valid(enemy) or enemy == source or enemy.is_in_group("boss"):
			continue
		if origin.distance_to(enemy.position) <= blast_radius:
			enemy.take_damage(blast_damage, origin)


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


# --- Stages ------------------------------------------------------------------

## Everything a stage owns is rebuilt here: clocks, streams, schedules, roster,
## palette, arena. Called on run start and on every portal entry.
func _enter_stage(stage: int) -> void:
	_stage = stage
	_stage_elapsed = 0.0
	_spawn_timer = 0.0
	_stage_phase = StagePhase.COMBAT
	_boss_alive = false
	_next_drop = 0

	# Per-stage streams, keyed by stage index. This is what contains
	# divergence: how long the player took on the last boss is
	# player-dependent, and a shared running stream would let that reshape
	# this stage for them alone.
	_spawn_rng = GameSeed.make_stage_rng(_date_string, stage, "spawn")
	_roster = Stages.roster(_date_string, stage)
	_drop_schedule = Drops.build_stage_schedule(_date_string, stage)

	_clear_field()
	# Always the arena centre — NEVER a position derived from the portal, which
	# is player-dependent and must not influence anything.
	_player.position = Arena.center()
	_world_bounds.apply_palette(Stages.palette(stage))

	print("[run] === STAGE %d === roster=%s hp=x%.2f dmg=x%.2f score=x%.2f" % [
		stage, ", ".join(PackedStringArray(_roster)),
		Stages.hp_mult(stage), Stages.damage_mult(stage), Stages.score_mult(stage)])


## Remove everything that belongs to the previous stage. The player, their
## weapons and their levels persist; the arena does not.
func _clear_field() -> void:
	for container in [_enemies, _projectiles, _enemy_shots, _gems, _pickups]:
		for child in container.get_children():
			child.queue_free()
	for portal in get_tree().get_nodes_in_group("portal"):
		portal.queue_free()


func _tick_stage(step: float) -> void:
	match _stage_phase:
		StagePhase.COMBAT:
			_check_drop_schedule()
			_schedule_waves(step)
			if _stage_elapsed >= Stages.combat_duration(_stage):
				_begin_boss()
		StagePhase.BOSS:
			# Regular spawns STOP during the boss fight. Focus, and it also
			# fixes the stage's spawn-draw count so "identical Stage N" is
			# exact rather than merely contained.
			_check_drop_schedule()
		StagePhase.CLEAR:
			_stage_clear_timer -= step
			if _stage_clear_timer <= 0.0:
				_show_stage_card()
		StagePhase.PORTAL:
			pass


func _begin_boss() -> void:
	_stage_phase = StagePhase.BOSS
	_boss_alive = true
	# Position from the stage spawn stream at this fixed moment.
	var edge := _spawn_rng.randi_range(0, 3)
	var along := _spawn_rng.randf()
	_spawn_boss(_stage, Arena.edge_position(edge, along))


## Boss down: clear the field and give the player a real breather. The run has
## no other breathing point.
func _begin_stage_clear() -> void:
	_stage_phase = StagePhase.CLEAR
	_stage_clear_timer = Balance.STAGE_CALM_DURATION
	_stages_cleared += 1

	# The shockwave awards NOTHING — no score, no drops, no kill handlers. It
	# is a removal, which also closes the "pile up trash, then kill the boss for
	# a free screen-clear" exploit.
	for enemy in _enemies.get_children():
		if is_instance_valid(enemy) and not enemy.is_in_group("boss"):
			enemy.queue_free()
	for shot in _enemy_shots.get_children():
		shot.queue_free()
	_fx.add_shake(Balance.SHAKE_ON_BOSS_KILL)


func _show_stage_card() -> void:
	_stage_phase = StagePhase.PORTAL
	var next_stage := _stage + 1
	_stage_card_title.text = "STAGE %d COMPLETE" % _stage
	_stage_card_body.text = "\n".join(PackedStringArray(
		Stages.escalation_lines(next_stage, _roster, _date_string)))
	_spawn_portal(next_stage)

	# Unattended runs step through on their own. Skipping the walk is sound:
	# the portal's position feeds nothing, so entering it early changes no
	# seeded state — only when the next stage's clock starts.
	if _auto_pick:
		_dismiss_stage_card()
		_on_portal_entered.call_deferred()
		return

	_stage_card_layer.show()
	_stage_card_button.grab_focus()
	get_tree().paused = true


func _dismiss_stage_card() -> void:
	_stage_card_layer.hide()
	get_tree().paused = false


func _spawn_portal(next_stage: int) -> void:
	var portal := PORTAL_SCENE.instantiate()
	portal.position = _boss_death_position
	portal.setup(Stages.palette(next_stage)["accent"])
	portal.entered.connect(_on_portal_entered)
	_pickups.add_child.call_deferred(portal)


func _on_portal_entered() -> void:
	_enter_stage(_stage + 1)


# --- Waves -------------------------------------------------------------------

func _schedule_waves(delta: float) -> void:
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer += maxf(Balance.STAGE_INTERVAL_FLOOR,
		Difficulty.spawn_interval(_stage_elapsed) * Stages.interval_mult(_stage))

	var weights := Difficulty.stage_type_weights(_stage, _stage_elapsed, _roster)
	var hp_multiplier := Difficulty.hp_multiplier(_stage_elapsed) * Stages.hp_mult(_stage)
	var damage_multiplier := Stages.damage_mult(_stage)
	for i in Difficulty.spawn_count(_stage_elapsed) + Stages.count_bonus(_stage):
		# Draw from spawn_rng UNCONDITIONALLY, before the cap check, and always
		# draw exactly three values regardless of tier.
		#
		# This ordering is load-bearing for determinism: how many enemies are
		# alive depends on how well the player is fighting, so if a skipped
		# spawn also skipped its RNG draws, a good player and a bad player would
		# desync the shared stream and stop playing the same daily run.
		# EXACTLY FIVE DRAWS per spawn, always, whatever the outcome: edge,
		# position, type, elite, elite-drop. The elite's drop is decided HERE,
		# at spawn, and only read back when it dies — never rolled at death,
		# which happens on player-dependent timing.
		var edge := _spawn_rng.randi_range(0, 3)
		var along := _spawn_rng.randf()
		var roll := _spawn_rng.randf()
		var elite_roll := _spawn_rng.randf()
		var drop_roll := _spawn_rng.randf()
		if _enemies.get_child_count() >= Balance.ENEMY_CAP:
			continue
		_spawn_enemy(Difficulty.pick_type(weights, roll),
			Arena.edge_position(edge, along), hp_multiplier,
			elite_roll < Balance.ELITE_CHANCE, Drops.pick(drop_roll),
			damage_multiplier)


## Bosses arrive on a FIXED time schedule (difficulty.gd), never a player-driven
## one, and draw their position from spawn_rng like any other spawn. A `while`
## rather than an `if` so a large --time-scale step cannot skip an appearance
## and desync the stream.
func _check_boss_schedule() -> void:
	while _elapsed >= Difficulty.boss_time(_next_boss):
		# Position comes from the spawn stream at this fixed moment; WHICH boss
		# and WHAT it drops come from the indexed boss stream, so a boss killed
		# early, late or not at all cannot change who shows up next.
		var edge := _spawn_rng.randi_range(0, 3)
		var along := _spawn_rng.randf()
		_spawn_boss(_next_boss, Arena.edge_position(edge, along))
		_next_boss += 1


func _spawn_boss(boss_index: int, at: Vector2) -> void:
	var archetype := Difficulty.boss_archetype(_date_string, boss_index)
	var drop_id := Difficulty.boss_drop(_date_string, boss_index)
	_boss_log.append("%d:%s" % [boss_index, archetype])

	var boss := BOSS_SCENE.instantiate()
	boss.position = at
	boss.setup(boss_index, archetype, drop_id, _boss_hp_mult)
	boss.shot_parent = _enemy_shots
	boss.killed.connect(_on_boss_killed)
	_enemies.add_child(boss)
	Sfx.play("boss_spawn")
	_fx.add_shake(Balance.SHAKE_ON_BOSS_SPAWN)
	print("[run] BOSS %d %s at %s (hp %.0f, drops %s)" % [
		boss_index, archetype, _format_time(_elapsed),
		Difficulty.boss_hp(boss_index), drop_id])


func _spawn_enemy(type_id: String, at: Vector2, hp_multiplier: float,
		elite := false, drop_id := "", damage_multiplier := 1.0) -> void:
	_type_counts[type_id] = _type_counts.get(type_id, 0) + 1
	var enemy := ENEMY_SCENE.instantiate()
	enemy.position = at
	enemy.setup(type_id, hp_multiplier, damage_multiplier)
	enemy.spawn_ordinal = _spawn_ordinal
	_spawn_ordinal += 1
	if elite:
		enemy.make_elite(drop_id)
		_elites_spawned += 1
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
		var lines := button.get_node("Body/Lines")
		lines.get_node("Tag").text = _card_tag(card)
		lines.get_node("Name").text = str(card["name"])
		lines.get_node("Desc").text = str(card["desc"])
		lines.get_node("Evolve").text = _recipe_text(card.get("hint", {}))
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


## The gold line: what this card builds toward, and how close both halves are.
## An evolution the player cannot see coming is one they will never assemble
## on purpose.
func _recipe_text(hint: Dictionary) -> String:
	if hint.is_empty():
		return ""
	return "EVOLVES → %s\n%s %d/%d  ·  %s %d/%d" % [
		hint["result"],
		hint["weapon_name"], hint["weapon_level"], hint["weapon_max"],
		hint["passive_name"], hint["passive_stacks"], hint["passive_max"],
	]


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
	_kill_score += int(round(float(enemy.score_value()) * combo_multiplier()
		* Stages.score_mult(_stage)))

	var gem := XP_GEM_SCENE.instantiate()
	gem.position = enemy.position
	gem.value = enemy.xp_value()
	# Deferred: this fires from an area_entered signal, i.e. mid physics-query
	# flush, and adding an Area2D right then throws "Can't change this state
	# while flushing queries". Deferring is still deterministic — the adds run
	# in a fixed order at the end of the same frame.
	_gems.add_child.call_deferred(gem)

	_fx.burst(enemy.position, enemy.stats["color"],
		Balance.PARTICLES_ON_KILL, Balance.PARTICLE_SPEED_KILL)
	_fx.add_shake(Balance.SHAKE_ON_KILL)
	Sfx.play("enemy_death")

	# Elites guarantee a drop. The id was fixed at spawn; this only reads it.
	if enemy.is_elite and enemy.elite_drop != "":
		_pickups_elite += 1
		_spawn_pickup(enemy.elite_drop, enemy.position)

	if enemy.stats.has("blast_radius"):
		_bomber_blast(enemy)

	if _splash_time > 0.0:
		_splash_from(enemy.position, enemy.max_hp, 0)

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
	_boss_alive = false
	# Remembered for the portal. Player-dependent, and therefore allowed to
	# influence PRESENTATION only — never any seeded schedule.
	_boss_death_position = boss.position
	_register_combo_kill()
	_kill_score += int(round(float(boss.score_value) * combo_multiplier()
		* Stages.score_mult(_stage)))

	# Guaranteed XP at fixed offsets, so the payout cannot vary between players.
	for i in Balance.BOSS_GEM_COUNT:
		var angle := TAU * float(i) / float(Balance.BOSS_GEM_COUNT)
		var gem := XP_GEM_SCENE.instantiate()
		gem.position = Arena.clamp_position(
			boss.position + Vector2(Balance.BOSS_GEM_RADIUS, 0.0).rotated(angle), 12.0)
		gem.value = Balance.BOSS_GEM_VALUE
		_gems.add_child.call_deferred(gem)

	# The drop was decided when the slot was assigned; this only reads it.
	if boss.drop_id != "":
		_pickups_boss += 1
		_spawn_pickup(boss.drop_id, boss.position)

	_fx.burst(boss.position, boss.colour(),
		Balance.PARTICLES_ON_BOSS_KILL, Balance.PARTICLE_SPEED_BOSS)
	_fx.add_shake(Balance.SHAKE_ON_BOSS_KILL)
	Sfx.play("boss_death")
	_begin_stage_clear()
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
	_gameover_label.text = "YOU DIED\n\nREACHED  STAGE %d\nSURVIVED  %s\nSCORE  %d\n\nkills %d = %d\ntime %s  x%d = %d\nxp %d  x%d = %d\nbosses felled  %d\n\npress R to replay   ·   ESC for menu" % [
		_stage, _format_time(_elapsed), _score(),
		_kills, _kill_score,
		_format_time(_elapsed), Score.PER_SECOND, int(_elapsed) * Score.PER_SECOND,
		_xp_collected, Score.PER_XP, _xp_collected * Score.PER_XP,
		_bosses_killed,
	]
	if _meta_bonus > 0.0:
		_gameover_label.text += "\n\nmeta bonus  %s" % MetaStore.bonus_text()
	_gameover_label.text += "\n\n%s" % _score_table_text()
	_gameover_layer.show()
	Sfx.play("run_over")
	if _quit_on_end:
		_quit_cleanly.call_deferred()
	print("[run] spawned by type: %s" % _type_counts)
	print("[digest] %s" % _state_digest())
	print("[run] over mode=%s date=%s stage=%d time=%s score=%d kills=%d xp=%d level=%d bosses=%d plausible=%s" % [
		RunConfig.mode_name(), _date_string, _stage,
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
		# Stored alongside score so it is ready for the Steam submission's
		# detail field when Phase 4 lands.
		"stage": _stage,
		"kills": _kills,
		"seconds": int(_elapsed),
		"level": _level,
		"bosses": _bosses_killed,
	})
	if _ranked:
		SaveStore.finish_ranked_attempt(_date_string, final_score)
		# RANKED ONLY. Practice and archive earn nothing.
		var earned := Meta.points_for_run(_stage)
		MetaStore.award_points(earned)
		print("[meta] +%d points (stage %d)" % [earned, _stage])

	MetaStore.record_run(_ranked, _stage, final_score, _kills, _bosses_killed)


func _score_table_text() -> String:
	var rows := SaveStore.top_for_date(_date_string, Balance.SCORE_TABLE_ROWS)
	if rows.is_empty():
		return ""
	var lines := PackedStringArray(["BEST ON %s" % _date_string])
	for i in rows.size():
		var row: Dictionary = rows[i]
		lines.append("%d.  %7d   stage %d   %s   lv%d   %s" % [
			i + 1, int(row.get("score", 0)),
			int(row.get("stage", 1)),
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
	] + " slots=%d weapons=%s passives=%s banished=%s rerolls=%d banishes=%d combo=%.3f drops_taken=%d dropped(sched/elite/boss)=%d/%d/%d scheduled=%d schedule=%s roster=%s elites=%d bosses_seen=%s stage=%d phase=%d stage_t=%.2f cleared=%d meta=%.4f" % [
		_weapon_slots, _weapons.digest(), JSON.stringify(_stacks),
		JSON.stringify(_banished), _rerolls_left, _banishes_left, _combo_chain,
		_drops_taken, _pickups_scheduled, _pickups_elite, _pickups_boss,
		_next_drop, Drops.schedule_digest(_drop_schedule),
		",".join(PackedStringArray(_roster)), _elites_spawned,
		",".join(PackedStringArray(_boss_log)),
		_stage, _stage_phase, _stage_elapsed, _stages_cleared, _meta_bonus,
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
	_level_label.text = "LV %d   ·   STAGE %d   %s  %s" % [
		_level, _stage, RunConfig.mode_name(), _date_string]
	_refresh_buff_list()
	_weapons_label.text = "%s     [%d/%d slots]" % [
		_weapons.summary(), _weapons.slots_used(), _weapon_slots]
	_hp_bar.value = _player.hp
	_xp_bar.max_value = _xp_needed(_level)
	_xp_bar.value = _xp_into_level
