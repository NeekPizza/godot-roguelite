extends Area2D

## All five enemy types (GDD section 5), driven from one stat table.
##
## One script rather than five: the types differ in numbers and in one of three
## movement behaviours, which is far less code than five near-identical scenes.

signal killed(enemy: Area2D)

const ENEMY_SHOT_SCENE := preload("res://scenes/enemy_shot.tscn")

enum Behavior { CHASE, KEEP_DISTANCE }

const TYPES := {
	"drifter": {
		"hp": 20.0, "speed": 90.0, "damage": 10.0, "radius": 12.0,
		"score": 10, "xp": 1, "color": Color(1.0, 0.28, 0.85),
		"behavior": Behavior.CHASE,
	},
	"swarmer": {
		"hp": 8.0, "speed": 175.0, "damage": 6.0, "radius": 8.0,
		"score": 6, "xp": 1, "color": Color(1.0, 0.55, 0.15),
		"behavior": Behavior.CHASE,
	},
	"tank": {
		"hp": 90.0, "speed": 45.0, "damage": 20.0, "radius": 22.0,
		"score": 30, "xp": 3, "color": Color(0.65, 0.35, 1.0),
		"behavior": Behavior.CHASE,
	},
	"shooter": {
		"hp": 25.0, "speed": 70.0, "damage": 8.0, "radius": 13.0,
		"score": 20, "xp": 2, "color": Color(1.0, 0.25, 0.3),
		"behavior": Behavior.KEEP_DISTANCE,
		"preferred_range": 320.0, "shot_interval": 2.2,
	},
	"splitter": {
		"hp": 40.0, "speed": 70.0, "damage": 12.0, "radius": 16.0,
		"score": 20, "xp": 2, "color": Color(0.3, 1.0, 0.6),
		"behavior": Behavior.CHASE,
		"splits_into": "swarmer", "split_count": 2,
	},
}

var type_id := "drifter"
var stats: Dictionary = TYPES["drifter"]

var max_hp := 20.0
var hp := 20.0
var move_speed := 90.0
var contact_damage := 10.0
var radius := 12.0

var shot_parent: Node2D
var _player: Node2D
var _flash := 0.0
var _shot_cooldown := 0.0


func _ready() -> void:
	add_to_group("enemy")


func setup(new_type_id: String, hp_multiplier: float) -> void:
	type_id = new_type_id
	stats = TYPES[type_id]

	max_hp = stats["hp"] * hp_multiplier
	hp = max_hp
	move_speed = stats["speed"]
	contact_damage = stats["damage"]
	radius = stats["radius"]

	# A fresh shape per instance. Shapes are Resources, so reusing the one from
	# the scene file would make every enemy share it and resizing one would
	# resize all of them.
	var shape := CircleShape2D.new()
	shape.radius = radius
	$Shape.shape = shape

	# Stagger the first shot so a wave of shooters does not volley in unison.
	# Derived from the type's cadence, not from RNG: a random offset here would
	# have to come from a stream, and this fires on player-dependent timing.
	_shot_cooldown = stats.get("shot_interval", 0.0) * 0.5


func _physics_process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)

	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player != null:
		_move(delta)
		if stats["behavior"] == Behavior.KEEP_DISTANCE:
			_try_shoot(delta)

	if Arena.is_far_outside(position):
		queue_free()

	queue_redraw()


func _move(delta: float) -> void:
	var to_player := _player.position - position
	var distance := to_player.length()
	if distance < 0.001:
		return
	var direction := to_player / distance

	if stats["behavior"] == Behavior.KEEP_DISTANCE:
		var preferred: float = stats["preferred_range"]
		# Close in when far, back off when too close, hold station in the band.
		if distance > preferred * 1.15:
			position += direction * move_speed * delta
		elif distance < preferred * 0.85:
			position -= direction * move_speed * delta
		return

	position += direction * move_speed * delta


func _try_shoot(delta: float) -> void:
	_shot_cooldown -= delta
	if _shot_cooldown > 0.0:
		return
	_shot_cooldown = stats["shot_interval"]

	if shot_parent == null:
		return
	var shot := ENEMY_SHOT_SCENE.instantiate()
	shot.position = position
	shot.setup((_player.position - position).normalized(), contact_damage)
	shot_parent.add_child(shot)


func take_damage(amount: float) -> void:
	if hp <= 0.0:
		return  # Already dead this frame; never emit `killed` twice.
	hp -= amount
	_flash = 0.08
	if hp <= 0.0:
		killed.emit(self)
		queue_free()


func _draw() -> void:
	var color: Color = Color.WHITE if _flash > 0.0 else stats["color"]
	_draw_body(color)

	if hp < max_hp:
		var fraction := hp / max_hp
		var width := radius * 2.0
		draw_rect(Rect2(-radius, -radius - 7.0, width, 3.0), Color(0.0, 0.0, 0.0, 0.6))
		draw_rect(Rect2(-radius, -radius - 7.0, width * fraction, 3.0), Color(0.4, 1.0, 0.5))


## Distinct silhouettes per type. Shape carries the identity, not just colour —
## GDD section 11 requires the game stay readable without relying on hue.
func _draw_body(color: Color) -> void:
	match type_id:
		"swarmer":  # small triangle
			var points := PackedVector2Array([
				Vector2(0.0, -radius), Vector2(radius, radius), Vector2(-radius, radius),
			])
			draw_colored_polygon(points, color)
			draw_polyline(points + PackedVector2Array([points[0]]), Color(color, 0.3), 2.0)
		"tank":  # heavy hexagon
			var points := PackedVector2Array()
			for i in 6:
				points.append(Vector2(radius, 0.0).rotated(TAU * float(i) / 6.0))
			draw_colored_polygon(points, color)
			draw_polyline(points + PackedVector2Array([points[0]]), Color(color, 0.35), 3.0)
		"shooter":  # diamond
			var points := PackedVector2Array([
				Vector2(0.0, -radius), Vector2(radius, 0.0),
				Vector2(0.0, radius), Vector2(-radius, 0.0),
			])
			draw_colored_polygon(points, color)
			draw_arc(Vector2.ZERO, radius + 5.0, 0.0, TAU, 20, Color(color, 0.3), 1.5)
		"splitter":  # square with an inner square, hinting it comes apart
			var rect := Rect2(-radius, -radius, radius * 2.0, radius * 2.0)
			draw_rect(rect, color)
			draw_rect(rect.grow(-radius * 0.45), Color(0.02, 0.02, 0.05, 0.85), false, 2.0)
		_:  # drifter: plain square
			var rect := Rect2(-radius, -radius, radius * 2.0, radius * 2.0)
			draw_rect(rect, color)
			draw_rect(rect.grow(3.0), Color(color, 0.25), false, 2.0)
