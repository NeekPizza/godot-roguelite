extends Area2D

## The boss — ONE scaling archetype, deliberately (GDD section 5b).
## BEHAVIOUR ONLY; every number comes from balance.gd via difficulty.gd.
##
## It is not a win condition. Killing it does not end the run; it is a pace
## break and a depth marker worth a large score chunk and guaranteed XP.
##
## Determinism: everything runs on fixed cadences. The burst rotation advances
## by a constant per burst rather than being randomised, because the boss fires
## on player-dependent timing and any RNG draw here would desync the shared
## spawn stream (same rule as Splitter children).

signal killed(boss: Area2D)

const ENEMY_SHOT_SCENE := preload("res://scenes/enemy_shot.tscn")

var index := 1
var max_hp := Balance.BOSS_HP_BASE
var hp := Balance.BOSS_HP_BASE
var contact_damage := Balance.BOSS_DAMAGE_BASE
var move_speed := Balance.BOSS_SPEED_BASE
var score_value := Balance.BOSS_SCORE_BASE

var shot_parent: Node2D
var _player: Node2D
var _flash := 0.0
var _burst_cooldown := Balance.BOSS_BURST_INTERVAL
var _bursts_fired := 0
var _spin := 0.0


func _ready() -> void:
	# Same group as regular enemies so player targeting, projectile collision
	# and contact damage all work without special-casing the boss.
	add_to_group("enemy")
	add_to_group("boss")


func setup(boss_index: int) -> void:
	index = boss_index
	max_hp = Difficulty.boss_hp(index)
	hp = max_hp
	contact_damage = Difficulty.boss_damage(index)
	move_speed = Difficulty.boss_speed(index)
	score_value = Difficulty.boss_score(index)

	var shape := CircleShape2D.new()
	shape.radius = Balance.BOSS_RADIUS
	$Shape.shape = shape


func _physics_process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	_spin += delta * 0.6

	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player != null:
		var to_player := _player.position - position
		if to_player.length() > 1.0:
			position += to_player.normalized() * move_speed * delta
		_fire(delta)

	position = Arena.clamp_position(position, Balance.BOSS_RADIUS)
	queue_redraw()


func _fire(delta: float) -> void:
	_burst_cooldown -= delta
	if _burst_cooldown > 0.0 or shot_parent == null:
		return
	_burst_cooldown = Balance.BOSS_BURST_INTERVAL

	var shots := Balance.BOSS_BURST_SHOTS
	var base_angle := float(_bursts_fired) * Balance.BOSS_BURST_ROTATION
	_bursts_fired += 1
	for i in shots:
		var angle := base_angle + TAU * float(i) / float(shots)
		var shot := ENEMY_SHOT_SCENE.instantiate()
		shot.position = position + Vector2(Balance.BOSS_RADIUS * 0.8, 0.0).rotated(angle)
		shot.setup(Vector2.RIGHT.rotated(angle),
			contact_damage * Balance.BOSS_SHOT_DAMAGE_SCALE)
		shot_parent.add_child(shot)


func take_damage(amount: float) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	_flash = 0.06
	if hp <= 0.0:
		killed.emit(self)
		queue_free()


func _draw() -> void:
	var radius := Balance.BOSS_RADIUS
	var color := Color.WHITE if _flash > 0.0 else Balance.BOSS_COLOR

	# Rotating octagon, ringed — reads as distinct from every regular silhouette
	# at a glance, which matters when the screen is crowded.
	var points := PackedVector2Array()
	for i in 8:
		points.append(Vector2(radius, 0.0).rotated(_spin + TAU * float(i) / 8.0))
	draw_colored_polygon(points, color)
	draw_polyline(points + PackedVector2Array([points[0]]), Color(color, 0.5), 4.0)
	draw_arc(Vector2.ZERO, radius + 14.0, 0.0, TAU, 40, Color(color, 0.30), 3.0)
	draw_arc(Vector2.ZERO, radius + 22.0, 0.0, TAU, 40, Color(color, 0.12), 2.0)

	# Health bar, wider than a regular enemy's so it reads as a milestone.
	var fraction := clampf(hp / max_hp, 0.0, 1.0)
	var width := radius * 2.6
	var top := -radius - 18.0
	draw_rect(Rect2(-width * 0.5, top, width, 6.0), Color(0.0, 0.0, 0.0, 0.65))
	draw_rect(Rect2(-width * 0.5, top, width * fraction, 6.0), Color(1.0, 0.85, 0.3))
