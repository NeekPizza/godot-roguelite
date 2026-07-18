extends Node2D

## Draws the world's hard walls and a faint grid.
##
## Purely cosmetic, but not optional: once the camera scrolls, an unlit black
## field gives no sense of speed or position. The grid supplies parallax-free
## motion cues and the border tells the player where the walls actually are.

const COLOR_GRID := Color(0.30, 0.85, 1.0, 0.055)
const COLOR_WALL := Color(0.35, 0.90, 1.0, 0.55)


func _draw() -> void:
	var rect := Arena.rect()

	var x := rect.position.x
	while x <= rect.end.x:
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), COLOR_GRID, 1.0)
		x += Balance.GRID_STEP

	var y := rect.position.y
	while y <= rect.end.y:
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), COLOR_GRID, 1.0)
		y += Balance.GRID_STEP

	# Drawn INSET, not on the rect itself. The camera is limited to exactly the
	# world rect, so a border stroked on the boundary would sit half-off-screen
	# and read as nothing. Insetting keeps the wall fully visible from inside.
	draw_rect(rect.grow(-3.0), COLOR_WALL, false, 5.0)
	draw_rect(rect.grow(-12.0), Color(COLOR_WALL, 0.15), false, 16.0)
