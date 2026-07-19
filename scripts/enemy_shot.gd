extends Area2D

## Projectile fired by ranged enemies and the boss. Monitors for the player
## rather than the player monitoring for it, so the player's overlap scan stays
## limited to enemy bodies. Values live in balance.gd.

const COLOR := Color(1.0, 0.35, 0.4)

var _direction := Vector2.RIGHT
var _damage := 8.0
var _speed := Balance.ENEMY_SHOT_SPEED
var _travelled := 0.0


func setup(direction: Vector2, damage: float,
		speed := Balance.ENEMY_SHOT_SPEED) -> void:
	_direction = direction
	_damage = damage
	_speed = speed


func _ready() -> void:
	add_to_group("enemy_shot")
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	var step := _speed * delta
	position += _direction * step
	_travelled += step
	if _travelled >= Balance.ENEMY_SHOT_RANGE or Arena.is_far_outside(position):
		queue_free()
	queue_redraw()


func _on_area_entered(area: Area2D) -> void:
	if not area.is_in_group("player"):
		return
	area.take_damage(_damage)
	queue_free()


func _draw() -> void:
	var radius := Balance.ENEMY_SHOT_RADIUS
	draw_circle(Vector2.ZERO, radius, COLOR)
	draw_circle(Vector2.ZERO, radius * 2.0, Color(COLOR, 0.2))
