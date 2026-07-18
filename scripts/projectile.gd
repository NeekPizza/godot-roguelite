class_name Projectile
extends Area2D

## Pulse round. Values live in balance.gd.

const COLOR := Color(1.0, 1.0, 1.0)

var _direction := Vector2.UP
var _damage := Balance.WEAPON_DAMAGE
var _pierce_left := 0
var _speed := Balance.PROJECTILE_SPEED
var _travelled := 0.0
var _already_hit: Array[int] = []


func setup(direction: Vector2, damage: float, pierce: int,
		speed: float = Balance.PROJECTILE_SPEED) -> void:
	_direction = direction
	_damage = damage
	_pierce_left = pierce
	_speed = speed


func _ready() -> void:
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	var step := _speed * delta
	position += _direction * step
	_travelled += step
	if _travelled >= Balance.PROJECTILE_RANGE:
		queue_free()


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
	var radius := Balance.PROJECTILE_RADIUS
	draw_circle(Vector2.ZERO, radius, COLOR)
	draw_circle(Vector2.ZERO, radius * 2.0, Color(COLOR, 0.18))
