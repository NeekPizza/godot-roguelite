extends Area2D

## The gate between stages. Stands where the boss fell.
##
## DETERMINISM: this position is player-dependent — it depends on where the
## player happened to kill the boss — so it feeds NOTHING. It is presentation
## only. The next stage is keyed on (date, N+1) alone, and the player always
## re-enters at the arena centre.

signal entered

var accent := Color(0.35, 0.90, 1.0)

var _spin := 0.0
var _claimed := false


func setup(next_accent: Color) -> void:
	# Tinted with the NEXT stage's accent, as a teaser for where it leads.
	accent = next_accent
	var shape := CircleShape2D.new()
	shape.radius = Balance.PORTAL_RADIUS
	$Shape.shape = shape


func _ready() -> void:
	add_to_group("portal")
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	_spin += delta * Balance.PORTAL_SPIN
	queue_redraw()


func _on_area_entered(area: Area2D) -> void:
	if _claimed or not area.is_in_group("player"):
		return
	_claimed = true
	entered.emit()


func _draw() -> void:
	var radius := Balance.PORTAL_RADIUS
	draw_circle(Vector2.ZERO, radius * 1.6, Color(accent, 0.10))
	# Counter-rotating rings: unmistakably a doorway rather than a pickup.
	for i in 3:
		var scale := 1.0 - float(i) * 0.22
		var direction := 1.0 if i % 2 == 0 else -1.0
		var start := _spin * direction + float(i)
		draw_arc(Vector2.ZERO, radius * scale, start, start + TAU * 0.72, 32,
			Color(accent, 0.85 - float(i) * 0.2), 3.0)
	draw_circle(Vector2.ZERO, radius * 0.22, Color(accent, 0.9))

	var font := ThemeDB.fallback_font
	var label := "ENTER"
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	draw_string(font, Vector2(-width * 0.5, radius + 26.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, accent)
