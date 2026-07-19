extends Area2D

## The player: a neon triangle that moves and auto-fires. All gameplay logic is
## in _physics_process — required by the determinism contract (GDD section 9).
##
## Stat VALUES live in balance.gd; this file only implements behaviour.

signal died
signal damaged(current_hp: float)
signal xp_collected(amount: int)

const COLOR_BODY := Color(0.25, 0.95, 1.0)
const COLOR_HURT := Color(1.0, 0.35, 0.45)

const PROJECTILE_SCENE := preload("res://scenes/projectile.tscn")

# --- Stat block. Upgrades mutate these by name (see upgrades.gd). ---
var max_hp := Balance.PLAYER_MAX_HP
var hp := Balance.PLAYER_MAX_HP
var move_speed := Balance.PLAYER_MOVE_SPEED
# Setter-enforced so the ceiling holds no matter what writes to it — a future
# upgrade, pickup, or debug tweak cannot route around it.
var pickup_radius := Balance.PLAYER_PICKUP_RADIUS:
	set(value):
		pickup_radius = minf(value, Balance.PLAYER_PICKUP_RADIUS_MAX)
var damage := Balance.WEAPON_DAMAGE
var fire_rate := Balance.WEAPON_FIRE_RATE
var projectile_speed := Balance.PROJECTILE_SPEED
var projectile_count := Balance.WEAPON_PROJECTILE_COUNT
var pierce := Balance.WEAPON_PIERCE

var projectile_parent: Node2D
var godmode := false  # test hook only; see docs/TESTING.md
var dash_cooldown_scale := 1.0   # Guard passive hooks in here at 6b
var dash_iframe_scale := 1.0

var _facing := Vector2.UP
var _scripted_elapsed := 0.0
var _iframes := 0.0
var _fire_cooldown := 0.0

# --- Dash state ---
var dashes_used := 0             # exposed for the determinism digest
var _dash_time_left := 0.0       # >0 while the burst is moving
var _dash_iframes := 0.0         # tracked apart from damage i-frames so the
                                 # hurt tint and the dash tell stay distinct
var _dash_cooldown_left := 0.0
var _dash_direction := Vector2.UP
var _afterimages: Array[Dictionary] = []


func _ready() -> void:
	add_to_group("player")
	position = Arena.center()
	_setup_camera()


## Clamp the camera to the world rect so the view never drifts past the walls
## into empty space. Driven from the world size, so resizing stays a one-line
## change in balance.gd.
func _setup_camera() -> void:
	var camera: Camera2D = $Camera
	var bounds := Arena.rect()
	camera.limit_left = int(bounds.position.x)
	camera.limit_top = int(bounds.position.y)
	camera.limit_right = int(bounds.end.x)
	camera.limit_bottom = int(bounds.end.y)


func _physics_process(delta: float) -> void:
	_iframes = maxf(0.0, _iframes - delta)
	_dash_iframes = maxf(0.0, _dash_iframes - delta)
	_dash_cooldown_left = maxf(0.0, _dash_cooldown_left - delta)
	_scripted_elapsed += delta

	_age_afterimages(delta)
	_try_dash()
	_move(delta)
	_collect_pickups()
	_take_contact_damage()
	_fire(delta)
	queue_redraw()


func _move(delta: float) -> void:
	# A dash overrides steering for its duration: committing to the burst is the
	# cost that makes the invulnerability a decision rather than a free dodge.
	if _dash_time_left > 0.0:
		var step := minf(delta, _dash_time_left)
		_dash_time_left -= delta
		position += _dash_direction * (Balance.DASH_DISTANCE / Balance.DASH_DURATION) * step
		position = Arena.clamp_position(position, Balance.PLAYER_RADIUS)
		return

	var direction := _input_direction()
	if direction.length_squared() > 0.0:
		_facing = direction.normalized()
		position += _facing * move_speed * delta
		position = Arena.clamp_position(position, Balance.PLAYER_RADIUS)


# --- Dash --------------------------------------------------------------------

func can_dash() -> bool:
	return _dash_cooldown_left <= 0.0 and _dash_time_left <= 0.0


func dash_cooldown_fraction() -> float:
	var total := Balance.DASH_COOLDOWN * dash_cooldown_scale
	if total <= 0.0:
		return 0.0
	return clampf(_dash_cooldown_left / total, 0.0, 1.0)


func is_dashing() -> bool:
	return _dash_time_left > 0.0 or _dash_iframes > 0.0


func _try_dash() -> void:
	if not _dash_requested() or not can_dash():
		return
	# Dash along current steering if there is any, otherwise along facing, so a
	# standing player still gets a usable escape rather than nothing.
	var steer := _input_direction()
	_dash_direction = steer.normalized() if steer.length_squared() > 0.0 else _facing
	_facing = _dash_direction
	_dash_time_left = Balance.DASH_DURATION
	_dash_iframes = Balance.DASH_IFRAMES * dash_iframe_scale
	_dash_cooldown_left = Balance.DASH_COOLDOWN * dash_cooldown_scale
	dashes_used += 1

	for i in Balance.DASH_AFTERIMAGES:
		_afterimages.append({
			"pos": position,
			"angle": _facing.angle(),
			"life": Balance.DASH_AFTERIMAGE_LIFETIME * (1.0 - float(i) * 0.22),
			"max_life": Balance.DASH_AFTERIMAGE_LIFETIME,
		})
	Sfx.play("dash")


func _dash_requested() -> bool:
	if RunConfig.scripted_input_seed != "":
		return ScriptedInput.wants_dash(RunConfig.scripted_input_seed, _scripted_elapsed)
	return Input.is_action_just_pressed("dash")


## Cosmetic only — afterimages never touch gameplay state.
func _age_afterimages(delta: float) -> void:
	var index := _afterimages.size() - 1
	while index >= 0:
		_afterimages[index]["life"] -= delta
		if _afterimages[index]["life"] <= 0.0:
			_afterimages.remove_at(index)
		index -= 1


## Real input, unless a test has installed a synthetic player.
##
## Three ways to move, all equivalent: WASD/arrows, left stick, or hold left
## mouse and steer toward the cursor.
func _input_direction() -> Vector2:
	if RunConfig.scripted_input_seed != "":
		return ScriptedInput.direction(RunConfig.scripted_input_seed, _scripted_elapsed)

	return Steering.direction(
		Input.get_vector("move_left", "move_right", "move_up", "move_down"),
		Input.is_action_pressed("move_pointer"),
		get_global_mouse_position(),
		position,
	)


func _fire(delta: float) -> void:
	_fire_cooldown -= delta
	if _fire_cooldown > 0.0:
		return

	var target := _nearest_enemy()
	if target == null:
		return  # Nothing in range: hold fire rather than waste the volley.

	_fire_cooldown = 1.0 / fire_rate
	var aim := (target.position - position).normalized()

	# Spread the volley symmetrically around the aim vector.
	for i in projectile_count:
		var offset := (float(i) - float(projectile_count - 1) * 0.5) * Balance.WEAPON_SPREAD_RADIANS
		var projectile := PROJECTILE_SCENE.instantiate()
		projectile.position = position
		projectile.setup(aim.rotated(offset), damage, pierce, projectile_speed)
		projectile_parent.add_child(projectile)

	Sfx.play("shoot")


func _nearest_enemy() -> Node2D:
	var nearest: Node2D = null
	var nearest_distance_squared := INF
	for enemy in get_tree().get_nodes_in_group("enemy"):
		var distance_squared: float = position.distance_squared_to(enemy.position)
		if distance_squared < nearest_distance_squared:
			nearest_distance_squared = distance_squared
			nearest = enemy
	if nearest_distance_squared > Balance.PROJECTILE_RANGE * Balance.PROJECTILE_RANGE:
		return null
	return nearest


func _collect_pickups() -> void:
	var radius_squared := pickup_radius * pickup_radius
	var body_squared := Balance.PLAYER_RADIUS * Balance.PLAYER_RADIUS
	for gem in get_tree().get_nodes_in_group("xp_gem"):
		var distance_squared: float = position.distance_squared_to(gem.position)
		if distance_squared <= radius_squared:
			gem.attract_to(self)
		if distance_squared <= body_squared:
			xp_collected.emit(gem.value)
			gem.queue_free()


func _take_contact_damage() -> void:
	if _iframes > 0.0:
		return
	for area in get_overlapping_areas():
		if area.is_in_group("enemy"):
			take_damage(area.contact_damage)
			return


func take_damage(amount: float) -> void:
	if godmode:
		return
	if _dash_iframes > 0.0:
		return  # Dashing through it — the whole point of the dash.
	if _iframes > 0.0 or hp <= 0.0:
		return  # Already dead: never emit `died` twice.
	hp -= amount
	_iframes = Balance.PLAYER_IFRAMES
	Sfx.play("player_hurt")
	damaged.emit(hp)
	if hp <= 0.0:
		hp = 0.0
		died.emit()


func heal(amount: float) -> void:
	hp = minf(max_hp, hp + amount)
	damaged.emit(hp)


func _body_points(radius: float, angle: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, -radius).rotated(angle),
		Vector2(-radius * 0.8, radius * 0.7).rotated(angle),
		Vector2(radius * 0.8, radius * 0.7).rotated(angle),
	])


func _draw() -> void:
	var radius := Balance.PLAYER_RADIUS
	var color := COLOR_HURT if _iframes > 0.0 else COLOR_BODY

	# Afterimages trail behind the dash, drawn in this node's local space.
	for image in _afterimages:
		var fade: float = clampf(image["life"] / image["max_life"], 0.0, 1.0)
		var local: Vector2 = image["pos"] - position
		var ghost := _body_points(radius, image["angle"] + PI * 0.5)
		for i in ghost.size():
			ghost[i] += local
		draw_colored_polygon(ghost, Color(COLOR_BODY, 0.30 * fade))

	var angle := _facing.angle() + PI * 0.5
	var points := _body_points(radius, angle)
	# Translucent while invulnerable: the tell has to be legible at a glance,
	# because an unseen i-frame window is indistinguishable from luck.
	var body_alpha := Balance.DASH_ALPHA if is_dashing() else 1.0
	draw_colored_polygon(points, Color(color, body_alpha))
	# Faked glow: GL Compatibility has no cheap post-process bloom, so we ring
	# the shape with a translucent outline instead.
	draw_polyline(points + PackedVector2Array([points[0]]), Color(color, 0.35 * body_alpha), 3.0)
	draw_arc(Vector2.ZERO, pickup_radius, 0.0, TAU, 32, Color(color, 0.10), 1.0)

	_draw_dash_ring()


## Cooldown as a ring that fills back around the player, so readiness is visible
## without looking away from the fight.
func _draw_dash_ring() -> void:
	var ring := Balance.DASH_COOLDOWN_RING_RADIUS
	if can_dash():
		draw_arc(Vector2.ZERO, ring, 0.0, TAU, 28, Color(COLOR_BODY, 0.30), 2.0)
		return
	var ready_fraction := 1.0 - dash_cooldown_fraction()
	draw_arc(Vector2.ZERO, ring, 0.0, TAU, 28, Color(COLOR_BODY, 0.10), 2.0)
	draw_arc(Vector2.ZERO, ring, -PI * 0.5, -PI * 0.5 + TAU * ready_fraction, 28,
		Color(COLOR_BODY, 0.55), 2.0)
