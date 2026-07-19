class_name Projectile
extends Area2D

## Player projectile for the seek / curve / boomerang weapons.
##
## One script with a movement mode rather than three near-identical scenes: the
## weapons differ in how the direction evolves, not in what a projectile *is*.

const COLOR_SEEK := Color(1.0, 1.0, 1.0)
const COLOR_CURVE := Color(0.55, 0.95, 1.0)
const COLOR_BOOMERANG := Color(1.0, 0.80, 0.45)

var _mode := "seek"
var _direction := Vector2.UP
var _damage := 10.0
var _pierce_left := 0
var _speed := 400.0
var _radius := 4.0
var _lifetime := 1.4
var _curve := 0.0
var _age := 0.0
var _spin := 0.0
var _origin: Node2D          # boomerang returns to whoever threw it
var _already_hit: Array[int] = []


func setup(config: Dictionary) -> void:
	_mode = config.get("mode", "seek")
	_direction = config.get("direction", Vector2.UP)
	_damage = config.get("damage", 10.0)
	_pierce_left = config.get("pierce", 0)
	_speed = config.get("speed", 400.0)
	_radius = config.get("radius", 4.0)
	_lifetime = config.get("lifetime", 1.4)
	_curve = config.get("curve", 0.0)
	_origin = config.get("origin", null)

	var shape := CircleShape2D.new()
	shape.radius = _radius
	$Shape.shape = shape


func _ready() -> void:
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	_age += delta
	_spin += delta * 12.0

	match _mode:
		"curve":
			# A constant turn rate: the shot sweeps an arc rather than a line,
			# which is what lets it catch enemies a straight shot would miss.
			_direction = _direction.rotated(_curve * delta)
		"boomerang":
			var half := _lifetime * 0.5
			if _age >= half and is_instance_valid(_origin):
				# Home back to the thrower, so the return leg is a second
				# damage window rather than a miss.
				_direction = (_origin.position - position).normalized()

	position += _direction * _speed * delta

	if _mode == "boomerang":
		# Caught, not expired: the pierce list resets nothing, it simply ends.
		if _age > _lifetime * 0.5 and is_instance_valid(_origin) \
				and position.distance_to(_origin.position) < 18.0:
			queue_free()
			return

	if _age >= _lifetime or Arena.is_far_outside(position):
		queue_free()
		return
	queue_redraw()


func _on_area_entered(area: Area2D) -> void:
	if not area.is_in_group("enemy"):
		return
	# A pierced round overlaps the same enemy across several frames; without
	# this guard it would deal damage every frame it stayed inside.
	var enemy_id := area.get_instance_id()
	if enemy_id in _already_hit:
		return
	_already_hit.append(enemy_id)

	area.take_damage(_damage)
	Sfx.play("hit")
	if _pierce_left <= 0:
		queue_free()
	else:
		_pierce_left -= 1


func _draw() -> void:
	match _mode:
		"boomerang":
			var colour := COLOR_BOOMERANG
			var points := PackedVector2Array()
			for i in 4:
				points.append(Vector2(_radius, 0.0).rotated(_spin + TAU * float(i) / 4.0))
			draw_colored_polygon(points, colour)
			draw_circle(Vector2.ZERO, _radius * 2.0, Color(colour, 0.16))
		"curve":
			draw_circle(Vector2.ZERO, _radius, COLOR_CURVE)
			draw_circle(Vector2.ZERO, _radius * 2.0, Color(COLOR_CURVE, 0.18))
		_:
			draw_circle(Vector2.ZERO, _radius, COLOR_SEEK)
			draw_circle(Vector2.ZERO, _radius * 2.0, Color(COLOR_SEEK, 0.18))
