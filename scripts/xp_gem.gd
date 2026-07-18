extends Area2D

## XP gem. Persists for the whole run — no despawn timer (GDD section 6).

const RADIUS := 5.0
const ATTRACT_SPEED := 420.0
const COLOR := Color(1.0, 0.92, 0.25)

var value := 1
var _target: Node2D


func _ready() -> void:
	add_to_group("xp_gem")


func attract_to(target: Node2D) -> void:
	_target = target


func _physics_process(delta: float) -> void:
	if _target != null and is_instance_valid(_target):
		position += (_target.position - position).normalized() * ATTRACT_SPEED * delta


func _draw() -> void:
	var points := PackedVector2Array([
		Vector2(0.0, -RADIUS), Vector2(RADIUS, 0.0),
		Vector2(0.0, RADIUS), Vector2(-RADIUS, 0.0),
	])
	draw_colored_polygon(points, COLOR)
	draw_circle(Vector2.ZERO, RADIUS * 2.2, Color(COLOR, 0.12))
