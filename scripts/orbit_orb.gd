extends Area2D

## One orb of the Orbit weapon. Persistent for the run — it is repositioned each
## frame rather than respawned, because spawning N orbs per tick would churn the
## scene tree for something that never actually leaves.
##
## Damage is gated per enemy by a re-hit cooldown, so an orb resting inside a
## slow enemy does not delete it instantly.

const COLOR := Color(0.55, 1.0, 0.85)

var damage := 8.0
var radius := 8.0
var _cooldowns := {}      # enemy instance id -> seconds until it can be hit again
var _rehit := 0.35


func _ready() -> void:
	var shape := CircleShape2D.new()
	shape.radius = radius
	$Shape.shape = shape


func configure(new_damage: float, new_radius: float) -> void:
	damage = new_damage
	radius = new_radius
	if $Shape.shape is CircleShape2D:
		$Shape.shape.radius = radius


func _physics_process(delta: float) -> void:
	for key in _cooldowns.keys():
		_cooldowns[key] -= delta
		if _cooldowns[key] <= 0.0:
			_cooldowns.erase(key)

	for area in get_overlapping_areas():
		if not area.is_in_group("enemy"):
			continue
		var id := area.get_instance_id()
		if _cooldowns.has(id):
			continue
		_cooldowns[id] = _rehit
		area.take_damage(damage)
		Sfx.play("hit")
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, COLOR)
	draw_circle(Vector2.ZERO, radius * 1.9, Color(COLOR, 0.18))
