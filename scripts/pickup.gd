extends Area2D

## A drop sitting on the ground, waiting to be walked into.
##
## It never moves toward the player: drops exist to pull you somewhere you would
## rather not go, and one that comes to you is a reward for nothing.

signal collected(drop_id: String, pickup: Area2D)

var drop_id := "health"
var _config := {}
var _pulse := 0.0
var _claimed := false


func setup(new_drop_id: String) -> void:
	drop_id = new_drop_id
	_config = Balance.DROPS.get(drop_id, {})
	var shape := CircleShape2D.new()
	shape.radius = Balance.DROP_PICKUP_RADIUS
	$Shape.shape = shape


func _ready() -> void:
	add_to_group("pickup")
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	_pulse += delta
	queue_redraw()


func _on_area_entered(area: Area2D) -> void:
	if _claimed or not area.is_in_group("player"):
		return
	_claimed = true          # a drop can only ever be taken once
	collected.emit(drop_id, self)
	queue_free()


func _draw() -> void:
	var colour: Color = _config.get("color", Color.WHITE)
	var radius := Balance.DROP_MARKER_RADIUS
	var breathe := 1.0 + 0.12 * sin(_pulse * 3.4)

	draw_circle(Vector2.ZERO, radius * 1.9 * breathe, Color(colour, 0.14))
	# A ring rather than a disc: it reads as "collectable" instead of "enemy",
	# which matters on a screen already full of solid shapes.
	draw_arc(Vector2.ZERO, radius * breathe, 0.0, TAU, 28, colour, 3.0)
	draw_arc(Vector2.ZERO, radius * 0.55 * breathe, 0.0, TAU, 20, Color(colour, 0.75), 2.5)
