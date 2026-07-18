extends Area2D

## Projectile fired by the shooter enemy. Monitors for the player rather than
## the player monitoring for it, so the player's overlap scan stays limited to
## enemy bodies.

const SPEED := 260.0
const RADIUS := 5.0
const MAX_RANGE := 700.0
const COLOR := Color(1.0, 0.35, 0.4)

var _direction := Vector2.RIGHT
var _damage := 8.0
var _travelled := 0.0


func setup(direction: Vector2, damage: float) -> void:
	_direction = direction
	_damage = damage


func _ready() -> void:
	add_to_group("enemy_shot")
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	var step := SPEED * delta
	position += _direction * step
	_travelled += step
	if _travelled >= MAX_RANGE or Arena.is_far_outside(position):
		queue_free()
	queue_redraw()


func _on_area_entered(area: Area2D) -> void:
	if not area.is_in_group("player"):
		return
	area.take_damage(_damage)
	queue_free()


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, COLOR)
	draw_circle(Vector2.ZERO, RADIUS * 2.0, Color(COLOR, 0.2))
