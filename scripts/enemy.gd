extends Area2D

## Drifter: a neon square that walks straight at the player (GDD section 5).

signal killed(enemy: Node2D)

const RADIUS := 12.0
const SCORE_VALUE := 10
const XP_VALUE := 1
const COLOR := Color(1.0, 0.28, 0.85)

var max_hp := 20.0
var hp := 20.0
var move_speed := 90.0
var contact_damage := 10.0

var _player: Node2D
var _flash := 0.0


func _ready() -> void:
	add_to_group("enemy")


func setup(hp_multiplier: float) -> void:
	max_hp = 20.0 * hp_multiplier
	hp = max_hp


func _physics_process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)

	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player != null:
		position += (_player.position - position).normalized() * move_speed * delta

	if Arena.is_far_outside(position):
		queue_free()

	queue_redraw()


func take_damage(amount: float) -> void:
	hp -= amount
	_flash = 0.08
	if hp <= 0.0:
		killed.emit(self)
		queue_free()


func _draw() -> void:
	var color := Color.WHITE if _flash > 0.0 else COLOR
	var size := RADIUS * 2.0
	var rect := Rect2(-RADIUS, -RADIUS, size, size)
	draw_rect(rect, color)
	draw_rect(rect.grow(3.0), Color(color, 0.25), false, 2.0)

	if hp < max_hp:
		var fraction := hp / max_hp
		draw_rect(Rect2(-RADIUS, -RADIUS - 7.0, size, 3.0), Color(0.0, 0.0, 0.0, 0.6))
		draw_rect(Rect2(-RADIUS, -RADIUS - 7.0, size * fraction, 3.0), Color(0.4, 1.0, 0.5))
