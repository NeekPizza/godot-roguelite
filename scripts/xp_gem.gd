extends Area2D

## XP gem. Persists for the whole run — no despawn timer, so uncollected XP on
## the field is a risk/reward decision rather than a punishment for looking
## away (GDD section 6). Values live in balance.gd.

var value := 1
var _target: Node2D


func _ready() -> void:
	add_to_group("xp_gem")


func attract_to(target: Node2D) -> void:
	_target = target


func _physics_process(delta: float) -> void:
	if _target != null and is_instance_valid(_target):
		position += (_target.position - position).normalized() \
			* Balance.GEM_ATTRACT_SPEED * delta


func _draw() -> void:
	var radius := Balance.GEM_RADIUS
	var points := PackedVector2Array([
		Vector2(0.0, -radius), Vector2(radius, 0.0),
		Vector2(0.0, radius), Vector2(-radius, 0.0),
	])
	draw_colored_polygon(points, Balance.GEM_COLOR)
	draw_circle(Vector2.ZERO, radius * 2.2, Color(Balance.GEM_COLOR, 0.12))
