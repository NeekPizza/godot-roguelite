class_name Arena
extends RefCounted

## The playfield is a large FINITE world with hard walls, viewed through a
## camera that follows the player. Roughly 2.5x the 1280x720 screen on each
## axis, so there is room to run without the world ever becoming unbounded.
##
## Why finite rather than the genre-typical infinite field: a fixed world lets
## enemy spawn points be absolute world coordinates rather than player-relative,
## so two players on the same daily seed get byte-identical spawn positions —
## not merely identical spawn *timings*. That makes the determinism contract in
## GDD section 9 hold literally, and it is non-negotiable.

const RECT := Rect2(0.0, 0.0, 3200.0, 1800.0)

## Enemies spawn this far outside the arena edge and walk inward, so nothing
## ever materialises on top of the player.
const SPAWN_MARGIN := 48.0


static func center() -> Vector2:
	return RECT.size * 0.5


static func clamp_position(position: Vector2, radius: float) -> Vector2:
	return Vector2(
		clampf(position.x, RECT.position.x + radius, RECT.end.x - radius),
		clampf(position.y, RECT.position.y + radius, RECT.end.y - radius)
	)


## True once an enemy has wandered far enough out to be worth despawning.
static func is_far_outside(position: Vector2) -> bool:
	var slack := SPAWN_MARGIN * 4.0
	return not RECT.grow(slack).has_point(position)
