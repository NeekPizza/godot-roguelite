extends Node2D

## Cosmetic effects: hit sparks and screen shake.
##
## DETERMINISM: everything here draws from fx_rng, the unseeded stream, and must
## never write to gameplay state. That is exactly why particle randomness is
## safe — it cannot shift the spawn or upgrade streams. See GDD section 9.
##
## Sparks are plain dictionaries drawn in one _draw pass rather than particle
## nodes. Hundreds of enemies die per run, and spawning a node per burst would
## churn the scene tree for something purely decorative.

const GRAVITY := 220.0
const DRAG := 2.4
const MAX_SPARKS := 600

const SHAKE_DECAY := 9.0
const SHAKE_MAX := 14.0

var camera: Camera2D

var _rng := GameSeed.make_fx_rng()
var _sparks: Array[Dictionary] = []
var _shake := 0.0


func burst(at: Vector2, color: Color, count: int, speed: float = 150.0) -> void:
	for i in count:
		if _sparks.size() >= MAX_SPARKS:
			return
		var angle := _rng.randf() * TAU
		var magnitude := speed * _rng.randf_range(0.35, 1.0)
		_sparks.append({
			"pos": at,
			"vel": Vector2(magnitude, 0.0).rotated(angle),
			"life": _rng.randf_range(0.22, 0.5),
			"max_life": 0.5,
			"color": color,
			"size": _rng.randf_range(1.5, 3.2),
		})


func add_shake(amount: float) -> void:
	_shake = minf(SHAKE_MAX, _shake + amount)


func _process(delta: float) -> void:
	var index := _sparks.size() - 1
	while index >= 0:
		var spark: Dictionary = _sparks[index]
		spark["life"] -= delta
		if spark["life"] <= 0.0:
			_sparks.remove_at(index)
		else:
			spark["vel"] += Vector2(0.0, GRAVITY) * delta
			spark["vel"] = spark["vel"].lerp(Vector2.ZERO, minf(1.0, DRAG * delta))
			spark["pos"] += spark["vel"] * delta
		index -= 1

	_shake = maxf(0.0, _shake - SHAKE_DECAY * delta)
	if camera != null and is_instance_valid(camera):
		if _shake > 0.01:
			camera.offset = Vector2(
				_rng.randf_range(-_shake, _shake),
				_rng.randf_range(-_shake, _shake)
			)
		else:
			camera.offset = Vector2.ZERO

	queue_redraw()


func _draw() -> void:
	for spark in _sparks:
		var fade: float = clampf(spark["life"] / spark["max_life"], 0.0, 1.0)
		draw_circle(spark["pos"], spark["size"] * fade, Color(spark["color"], fade))
