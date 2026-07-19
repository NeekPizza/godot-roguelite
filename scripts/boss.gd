extends Area2D

## Boss — four archetypes, all telegraphed (GDD section 5b).
##
## Killing one does not end the run; it is a pace break and a depth marker.
##
## EVERY attack winds up visibly before it fires, and the windup has a floor
## that escalation never crosses. Dense patterns are only fair if they are
## readable: without a tell, a hard pattern and a cheap one feel identical to
## the player, and the player is right to be annoyed.
##
## Determinism: archetype, drop and pattern all come from the INDEXED `boss`
## stream at slot assignment. Nothing here draws at runtime — the rotation
## advances by a constant, because the boss fires on player-dependent timing.

signal killed(boss: Area2D)

const ENEMY_SHOT_SCENE := preload("res://scenes/enemy_shot.tscn")

var index := 1
var archetype := "spinner"
var drop_id := ""
var max_hp := Balance.BOSS_HP_BASE
var hp := Balance.BOSS_HP_BASE
var contact_damage := Balance.BOSS_DAMAGE_BASE
var move_speed := Balance.BOSS_SPEED_BASE
var score_value := Balance.BOSS_SCORE_BASE

var shot_parent: Node2D
var _config := {}
var _pattern := {}
var _player: Node2D
var _flash := 0.0
var _spin := 0.0
var _volleys := 0

# telegraph -> fire -> recover
var _phase := "recover"
var _phase_timer := 0.0
var _aim := Vector2.RIGHT
var _dash_left := 0.0


func _ready() -> void:
	# Same group as regular enemies so targeting, projectile collision and
	# contact damage need no special-casing.
	add_to_group("enemy")
	add_to_group("boss")


func setup(boss_index: int, archetype_id: String, boss_drop: String) -> void:
	index = boss_index
	archetype = archetype_id
	drop_id = boss_drop
	_config = Balance.BOSS_ARCHETYPES[archetype]
	_pattern = Difficulty.boss_pattern(_config["pattern"], index)

	max_hp = Difficulty.boss_hp(index)
	hp = max_hp
	contact_damage = Difficulty.boss_damage(index)
	move_speed = Difficulty.boss_speed(index) * float(_config["speed_mult"])
	score_value = Difficulty.boss_score(index)
	_phase_timer = float(_pattern["cadence"])

	var shape := CircleShape2D.new()
	shape.radius = Balance.BOSS_RADIUS
	$Shape.shape = shape


func colour() -> Color:
	return _config.get("color", Balance.BOSS_COLOR)


## Bosses are immovable by design — one that could be shoved out of its
## telegraphed pattern would make the pattern unreadable.
func push_away_from(_origin: Vector2, _distance: float) -> void:
	pass


func _physics_process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	_spin += delta * 0.6

	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		return

	_advance_phase(delta)
	_move(delta)
	position = Arena.clamp_position(position, Balance.BOSS_RADIUS)
	queue_redraw()


func _move(delta: float) -> void:
	# The Charger commits to a straight line while firing, so the safe lane
	# keeps moving; everyone else closes on the player.
	if _dash_left > 0.0:
		_dash_left -= delta
		position += _aim * float(_config.get("dash_speed", 500.0)) * delta
		return

	var to_player := _player.position - position
	if to_player.length() > 1.0:
		position += to_player.normalized() * move_speed * delta


func _advance_phase(delta: float) -> void:
	_phase_timer -= delta
	if _phase_timer > 0.0:
		return

	match _phase:
		"recover":
			# Lock the aim as the windup STARTS, so what the tell shows is what
			# actually fires. Re-aiming during the telegraph would make the
			# warning a lie.
			_aim = (_player.position - position).normalized()
			_phase = "telegraph"
			_phase_timer = float(_pattern["telegraph"])
		"telegraph":
			_fire()
			_phase = "recover"
			_phase_timer = float(_pattern["cadence"])
			if archetype == "charger":
				_dash_left = float(_config.get("dash_duration", 0.9))


func telegraph_progress() -> float:
	if _phase != "telegraph":
		return 0.0
	return 1.0 - clampf(_phase_timer / maxf(0.001, float(_pattern["telegraph"])), 0.0, 1.0)


func _fire() -> void:
	if shot_parent == null:
		return
	var bullets := int(_pattern["bullets"])
	var spread := deg_to_rad(float(_pattern["spread_deg"]))
	var speed := float(_pattern["speed"])
	# Rotation advances by a CONSTANT per volley, never a draw: the boss fires
	# on player-dependent timing, so any RNG here would desync the seed.
	var base_angle := _aim.angle() + float(_volleys) * float(_pattern["rotation_step"])
	_volleys += 1

	var gaps := int(_pattern.get("gaps", 0))
	var gap_span := deg_to_rad(float(_pattern.get("gap_deg", 0.0)))

	for i in bullets:
		var offset := spread * (float(i) / float(bullets) - 0.5) if spread < TAU \
			else TAU * float(i) / float(bullets)
		var angle := base_angle + offset
		if gaps > 0 and _in_gap(angle - base_angle, gaps, gap_span):
			continue    # Ring Master's weaving lanes
		var shot := ENEMY_SHOT_SCENE.instantiate()
		shot.position = position + Vector2(Balance.BOSS_RADIUS * 0.85, 0.0).rotated(angle)
		shot.setup(Vector2.RIGHT.rotated(angle),
			contact_damage * Balance.BOSS_SHOT_DAMAGE_SCALE, speed)
		shot_parent.add_child(shot)
	Sfx.play("boss_spawn", -12.0)


## True inside one of the evenly spaced gaps in a ring.
func _in_gap(relative_angle: float, gaps: int, gap_span: float) -> bool:
	var wrapped := fposmod(relative_angle, TAU)
	var segment := TAU / float(gaps)
	return fposmod(wrapped, segment) < gap_span


func take_damage(amount: float, _from_position := Vector2.INF) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	_flash = 0.06
	if hp <= 0.0:
		killed.emit(self)
		queue_free()


func _draw() -> void:
	var radius := Balance.BOSS_RADIUS
	var base_colour := colour()
	var body := Color.WHITE if _flash > 0.0 else base_colour

	_draw_shape(radius, body)
	draw_arc(Vector2.ZERO, radius + 14.0, 0.0, TAU, 40, Color(base_colour, 0.30), 3.0)

	_draw_telegraph(radius, base_colour)
	if archetype == "charger":
		if _dash_left > 0.0:
			_draw_dash_lane(radius, 1.0)
		elif telegraph_progress() > 0.0:
			_draw_dash_lane(radius, 0.35 + 0.65 * telegraph_progress())

	# Health bar, wider than a regular enemy's so it reads as a milestone.
	var fraction := clampf(hp / max_hp, 0.0, 1.0)
	var width := radius * 2.6
	var top := -radius - 20.0
	draw_rect(Rect2(-width * 0.5, top, width, 6.0), Color(0.0, 0.0, 0.0, 0.65))
	draw_rect(Rect2(-width * 0.5, top, width * fraction, 6.0), Color(1.0, 0.85, 0.3))


func _draw_shape(radius: float, body: Color) -> void:
	var points := PackedVector2Array()
	match _config.get("shape", "octagon"):
		"diamond":
			points = PackedVector2Array([
				Vector2(0.0, -radius), Vector2(radius * 0.8, 0.0),
				Vector2(0.0, radius), Vector2(-radius * 0.8, 0.0)])
		"arrowhead":
			points = PackedVector2Array([
				Vector2(radius, 0.0), Vector2(-radius * 0.7, radius * 0.85),
				Vector2(-radius * 0.25, 0.0), Vector2(-radius * 0.7, -radius * 0.85)])
			for i in points.size():
				points[i] = points[i].rotated(_aim.angle())
		"star":
			for i in 10:
				var reach := radius if i % 2 == 0 else radius * 0.5
				points.append(Vector2(reach, 0.0).rotated(_spin + TAU * float(i) / 10.0))
		_:
			for i in 8:
				points.append(Vector2(radius, 0.0).rotated(_spin + TAU * float(i) / 8.0))
	draw_colored_polygon(points, body)
	draw_polyline(points + PackedVector2Array([points[0]]), Color(body, 0.5), 4.0)


## The tell. A ring closes in as the windup completes, and the aimed archetypes
## also draw the lane the volley will take — so the warning shows the actual
## attack rather than merely announcing that one is coming.
func _draw_telegraph(radius: float, base_colour: Color) -> void:
	var progress := telegraph_progress()
	if progress <= 0.0:
		return

	var warn := Color(1.0, 0.95, 0.5)
	var reach := radius + 46.0 * (1.0 - progress)
	draw_arc(Vector2.ZERO, reach, 0.0, TAU, 44, Color(warn, 0.35 + 0.5 * progress), 3.0)

	# Cone edges only make sense for a NARROW spread. lane_dash is 360 degrees,
	# so half of it is 180 and both "edges" rendered directly BEHIND the boss —
	# pointing away from where it was about to charge.
	if archetype == "aimed_volley":
		var spread := deg_to_rad(float(_pattern["spread_deg"])) * 0.5
		for side in [-spread, spread]:
			var direction := _aim.rotated(side)
			draw_line(direction * radius, direction * 520.0,
				Color(warn, 0.20 + 0.35 * progress), 2.0)


## The Charger gets its own tell: the lane it is about to travel, drawn FORWARD
## along the dash vector. Shown during the windup and again while the dash is
## live, so the lane is visible for as long as it is dangerous.
func _draw_dash_lane(radius: float, intensity: float) -> void:
	var warn := Color(1.0, 0.95, 0.5)
	var length := float(_config.get("dash_speed", 620.0)) \
		* float(_config.get("dash_duration", 0.9))
	var lane_half := radius * 0.85
	var forward := _aim
	var side := forward.orthogonal()

	draw_line(forward * radius, forward * length, Color(warn, 0.25 * intensity), 3.0)
	for edge in [-lane_half, lane_half]:
		draw_line(forward * radius + side * edge, forward * length + side * edge,
			Color(warn, 0.45 * intensity), 2.0)

	# Arrowhead at the far end, so the direction reads instantly.
	var tip := forward * length
	draw_line(tip, tip - forward * 34.0 + side * 20.0, Color(warn, 0.7 * intensity), 3.0)
	draw_line(tip, tip - forward * 34.0 - side * 20.0, Color(warn, 0.7 * intensity), 3.0)
