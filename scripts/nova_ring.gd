extends Area2D

## Nova's expanding shockwave. Grows from nothing to its full radius over its
## lifetime, damaging and knocking back each enemy once.

const COLOR := Color(0.65, 0.75, 1.0)

var damage := 12.0
var max_radius := 190.0
var lifetime := 0.45
var knockback := 180.0

var _age := 0.0
var _hit: Array[int] = []
var _shape: CircleShape2D


func setup(new_damage: float, new_max_radius: float, new_lifetime: float,
		new_knockback: float) -> void:
	damage = new_damage
	max_radius = new_max_radius
	lifetime = new_lifetime
	knockback = new_knockback


func _ready() -> void:
	_shape = CircleShape2D.new()
	_shape.radius = 1.0
	$Shape.shape = _shape


func _physics_process(delta: float) -> void:
	_age += delta
	var progress := clampf(_age / lifetime, 0.0, 1.0)
	_shape.radius = maxf(1.0, max_radius * progress)

	for area in get_overlapping_areas():
		if not area.is_in_group("enemy"):
			continue
		var id := area.get_instance_id()
		if id in _hit:
			continue
		_hit.append(id)
		area.take_damage(damage, global_position)
		# Knockback is a position nudge, not a physics impulse: enemies drive
		# their own movement, so an impulse would simply be ignored next frame.
		if knockback > 0.0 and area.has_method("push_away_from"):
			area.push_away_from(global_position, knockback)

	if _age >= lifetime:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var progress := clampf(_age / lifetime, 0.0, 1.0)
	var radius := maxf(1.0, max_radius * progress)
	var fade := 1.0 - progress
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(COLOR, 0.75 * fade), 4.0)
	draw_arc(Vector2.ZERO, radius * 0.94, 0.0, TAU, 48, Color(COLOR, 0.25 * fade), 8.0)
