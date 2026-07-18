class_name Arena
extends RefCounted

## The playfield: a large FINITE world with hard walls, viewed through a camera
## that follows the player.
##
## Why finite rather than the genre-typical infinite field: a fixed world lets
## enemy spawn points be absolute world coordinates rather than player-relative,
## so two players on the same daily seed get byte-identical spawn positions —
## not merely identical spawn *timings*. That makes the determinism contract in
## GDD section 9 hold literally, and it is non-negotiable.
##
## Dimensions live in balance.gd.

static func rect() -> Rect2:
	return Rect2(Vector2.ZERO, Balance.WORLD_SIZE)


static func center() -> Vector2:
	return Balance.WORLD_SIZE * 0.5


static func clamp_position(position: Vector2, radius: float) -> Vector2:
	var bounds := rect()
	return Vector2(
		clampf(position.x, bounds.position.x + radius, bounds.end.x - radius),
		clampf(position.y, bounds.position.y + radius, bounds.end.y - radius)
	)


## True once an enemy has wandered far enough out to be worth despawning.
static func is_far_outside(position: Vector2) -> bool:
	return not rect().grow(Balance.SPAWN_MARGIN * Balance.DESPAWN_SLACK).has_point(position)


## Absolute spawn point just outside one of the four walls. Independent of
## player position, so every player on a seed gets identical spawn coordinates.
static func edge_position(edge: int, along: float) -> Vector2:
	var bounds := rect()
	var margin := Balance.SPAWN_MARGIN
	match edge:
		0:  return Vector2(bounds.position.x + bounds.size.x * along, bounds.position.y - margin)
		1:  return Vector2(bounds.end.x + margin, bounds.position.y + bounds.size.y * along)
		2:  return Vector2(bounds.position.x + bounds.size.x * along, bounds.end.y + margin)
		_:  return Vector2(bounds.position.x - margin, bounds.position.y + bounds.size.y * along)
