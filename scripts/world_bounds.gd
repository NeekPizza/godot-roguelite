extends Node2D

## Draws the world's hard walls and a faint grid.
##
## Purely cosmetic, but not optional: once the camera scrolls, an unlit black
## field gives no sense of speed or position. The grid supplies parallax-free
## motion cues and the border tells the player where the walls actually are.

## Set by the run on stage entry. The palette recolours the arena only; enemy
## colours stay fixed so shape-based identity survives the change.
var grid_color := Color(0.30, 0.85, 1.0, 0.055)
var wall_color := Color(0.35, 0.90, 1.0, 0.55)


func apply_palette(palette: Dictionary) -> void:
	grid_color = palette["grid"]
	wall_color = palette["wall"]
	queue_redraw()


func _draw() -> void:
	var rect := Arena.rect()

	var x := rect.position.x
	while x <= rect.end.x:
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), grid_color, 1.0)
		x += Balance.GRID_STEP

	var y := rect.position.y
	while y <= rect.end.y:
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), grid_color, 1.0)
		y += Balance.GRID_STEP

	# Drawn INSET, not on the rect itself. The camera is limited to exactly the
	# world rect, so a border stroked on the boundary would sit half-off-screen
	# and read as nothing. Insetting keeps the wall fully visible from inside.
	draw_rect(rect.grow(-3.0), wall_color, false, 5.0)
	draw_rect(rect.grow(-12.0), Color(wall_color, 0.15), false, 16.0)
