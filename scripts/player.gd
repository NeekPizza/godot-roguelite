extends Area2D

## The player: a neon triangle that moves and auto-fires. All gameplay logic is
## in _physics_process — required by the determinism contract (GDD section 9).

signal died
signal damaged(current_hp: float)
signal xp_collected(amount: int)

const RADIUS := 14.0
const IFRAME_DURATION := 0.5
const SPREAD_RADIANS := 0.18

## Hard ceiling on pickup radius, enforced regardless of how upgrades stack.
##
## Without it, compounding Magnetism grows the radius geometrically until it
## covers the world and XP collection stops being a decision — gems just fall
## in. 200px is a quarter of the screen height and ~6% of the world's shorter
## axis, so collecting still means going and getting it.
const MAX_PICKUP_RADIUS := 200.0

const COLOR_BODY := Color(0.25, 0.95, 1.0)
const COLOR_HURT := Color(1.0, 0.35, 0.45)

# --- Stat block. Upgrades mutate these directly (see upgrades.gd). ---
var max_hp := 100.0
var hp := 100.0
var move_speed := 220.0
# Setter-enforced so the ceiling holds no matter what writes to it — a future
# upgrade, pickup, or debug tweak cannot route around it.
var pickup_radius := 60.0:
	set(value):
		pickup_radius = minf(value, MAX_PICKUP_RADIUS)
var damage := 10.0
var fire_rate := 2.0
var projectile_count := 1
var pierce := 0

var projectile_parent: Node2D
var _facing := Vector2.UP
var _iframes := 0.0
var _fire_cooldown := 0.0

const PROJECTILE_SCENE := preload("res://scenes/projectile.tscn")


func _ready() -> void:
	add_to_group("player")
	position = Arena.center()
	_setup_camera()


## Clamp the camera to the world rect so the view never drifts past the walls
## into empty space. Driven from Arena.RECT rather than hardcoded in the scene,
## so resizing the world stays a one-line change.
func _setup_camera() -> void:
	var camera: Camera2D = $Camera
	camera.limit_left = int(Arena.RECT.position.x)
	camera.limit_top = int(Arena.RECT.position.y)
	camera.limit_right = int(Arena.RECT.end.x)
	camera.limit_bottom = int(Arena.RECT.end.y)


func _physics_process(delta: float) -> void:
	_iframes = maxf(0.0, _iframes - delta)
	_move(delta)
	_collect_pickups()
	_take_contact_damage()
	_fire(delta)
	queue_redraw()


func _move(delta: float) -> void:
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if direction.length_squared() > 0.0:
		_facing = direction.normalized()
		position += _facing * move_speed * delta
		position = Arena.clamp_position(position, RADIUS)


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
		var offset := (float(i) - float(projectile_count - 1) * 0.5) * SPREAD_RADIANS
		var projectile := PROJECTILE_SCENE.instantiate()
		projectile.position = position
		projectile.setup(aim.rotated(offset), damage, pierce)
		projectile_parent.add_child(projectile)


func _nearest_enemy() -> Node2D:
	var nearest: Node2D = null
	var nearest_distance_squared := INF
	for enemy in get_tree().get_nodes_in_group("enemy"):
		var distance_squared: float = position.distance_squared_to(enemy.position)
		if distance_squared < nearest_distance_squared:
			nearest_distance_squared = distance_squared
			nearest = enemy
	if nearest_distance_squared > Projectile.MAX_RANGE * Projectile.MAX_RANGE:
		return null
	return nearest


func _collect_pickups() -> void:
	var radius_squared := pickup_radius * pickup_radius
	for gem in get_tree().get_nodes_in_group("xp_gem"):
		var distance_squared: float = position.distance_squared_to(gem.position)
		if distance_squared <= radius_squared:
			gem.attract_to(self)
		if distance_squared <= RADIUS * RADIUS:
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
	if _iframes > 0.0 or hp <= 0.0:
		return  # Already dead: never emit `died` twice.
	hp -= amount
	_iframes = IFRAME_DURATION
	damaged.emit(hp)
	if hp <= 0.0:
		hp = 0.0
		died.emit()


func heal(amount: float) -> void:
	hp = minf(max_hp, hp + amount)
	damaged.emit(hp)


func _draw() -> void:
	var color := COLOR_HURT if _iframes > 0.0 else COLOR_BODY
	var angle := _facing.angle() + PI * 0.5
	var points := PackedVector2Array([
		Vector2(0.0, -RADIUS).rotated(angle),
		Vector2(-RADIUS * 0.8, RADIUS * 0.7).rotated(angle),
		Vector2(RADIUS * 0.8, RADIUS * 0.7).rotated(angle),
	])
	draw_colored_polygon(points, color)
	# Faked glow: GL Compatibility has no cheap post-process bloom, so we ring
	# the shape with a translucent outline instead.
	draw_polyline(points + PackedVector2Array([points[0]]), Color(color, 0.35), 3.0)
	draw_arc(Vector2.ZERO, pickup_radius, 0.0, TAU, 32, Color(color, 0.10), 1.0)
