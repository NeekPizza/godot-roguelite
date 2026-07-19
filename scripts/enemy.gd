extends Area2D

## All enemy types, driven from Balance.ENEMY_TYPES — BEHAVIOUR ONLY.
##
## One script rather than one per type: types differ in numbers and in which of
## two movement behaviours they use, which is far less code than N near-identical
## scenes. Adding a type is a row in balance.gd plus, if it needs a new
## silhouette, a case in _draw_body().

signal killed(enemy: Area2D)

const ENEMY_SHOT_SCENE := preload("res://scenes/enemy_shot.tscn")

var type_id := "drifter"
var stats: Dictionary = Balance.ENEMY_TYPES["drifter"]

var max_hp := 20.0
var hp := 20.0
var move_speed := 90.0
var contact_damage := 10.0
var radius := 12.0

var shot_parent: Node2D
var is_elite := false
var elite_drop := ""          # decided at SPAWN, read back on death
var spawn_ordinal := 0        # stable tie-break for chain ordering

var _player: Node2D
var _flash := 0.0
var _shot_cooldown := 0.0
var _facing := Vector2.RIGHT  # Shielded blocks from this direction
var _age := 0.0
var _dash_timer := 0.0
var _dash_state := "idle"     # idle -> telegraph -> lunge


func _ready() -> void:
	add_to_group("enemy")


func setup(new_type_id: String, hp_multiplier: float) -> void:
	type_id = new_type_id
	stats = Balance.ENEMY_TYPES[type_id]

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

	_dash_timer = float(stats.get("dash_cooldown", 0.0))

	# Stagger the first shot so a wave of shooters does not volley in unison.
	# Derived from the type's own cadence, not from RNG: a random offset would
	# have to come from a stream, and this fires on player-dependent timing.
	_shot_cooldown = float(stats.get("shot_interval", 0.0)) * 0.5


## Applied at spawn from the spawn block's elite roll.
func make_elite(drop_id: String) -> void:
	is_elite = true
	elite_drop = drop_id
	max_hp *= Balance.ELITE_HP_MULT
	hp = max_hp
	contact_damage *= Balance.ELITE_DAMAGE_MULT
	radius *= Balance.ELITE_SCALE
	if $Shape.shape is CircleShape2D:
		$Shape.shape.radius = radius


func score_value() -> int:
	var base := int(stats["score"])
	return int(round(float(base) * Balance.ELITE_SCORE_MULT)) if is_elite else base


func xp_value() -> int:
	return int(stats["xp"]) * (2 if is_elite else 1)


func _physics_process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	_age += delta

	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player != null:
		_move(delta)
		if stats["behavior"] == "keep_distance":
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
	_facing = direction

	match stats["behavior"]:
		"dash":
			_move_dash(delta, direction)
			return
		"weave":
			# Sine offset perpendicular to the approach, so leading it wrong
			# misses entirely.
			var sideways := direction.orthogonal() * sin(
				_age * float(stats["wave_frequency"])) * float(stats["wave_amplitude"])
			position += (direction * move_speed + sideways) * delta
			return

	if stats["behavior"] == "keep_distance":
		var preferred: float = stats["preferred_range"]
		# Close in when far, back off when too close, hold station in the band.
		if distance > preferred * 1.15:
			position += direction * move_speed * delta
		elif distance < preferred * 0.85:
			position -= direction * move_speed * delta
		return

	position += direction * move_speed * delta


## Creep, telegraph, lunge. The windup is the point: an unsignalled charge is
## not a positioning test, it is a coin flip.
func _move_dash(delta: float, direction: Vector2) -> void:
	_dash_timer -= delta
	match _dash_state:
		"idle":
			position += direction * move_speed * delta
			if _dash_timer <= 0.0:
				_dash_state = "telegraph"
				_dash_timer = float(stats["dash_telegraph"])
		"telegraph":
			if _dash_timer <= 0.0:
				_dash_state = "lunge"
				_dash_timer = float(stats["dash_duration"])
		"lunge":
			position += _facing * float(stats["dash_speed"]) * delta
			if _dash_timer <= 0.0:
				_dash_state = "idle"
				_dash_timer = float(stats["dash_cooldown"])


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


## Nova knockback. Enemies move themselves every frame, so a physics impulse
## would simply be overwritten; nudging the position is the honest way to do it.
func push_away_from(origin: Vector2, distance: float) -> void:
	var away := position - origin
	if away.length() < 0.001:
		return
	position = Arena.clamp_position(position + away.normalized() * distance, radius)


## SINGLE DAMAGE ENTRY POINT. Everything — projectiles, orbs, Nova rings, splash
## chains, bombs — routes through here, which is what lets Shielded's directional
## armour apply uniformly instead of only to whichever sources remembered it.
func take_damage(amount: float, from_position := Vector2.INF) -> void:
	if hp <= 0.0:
		return  # Already dead this frame; never emit `killed` twice.
	hp -= amount * _damage_scale(from_position)
	_flash = 0.08
	if hp <= 0.0:
		killed.emit(self)
		queue_free()


## Shielded takes almost nothing through its front arc. Pure geometry against
## its own facing — no RNG, so it cannot desync.
func _damage_scale(from_position: Vector2) -> float:
	if not stats.has("shield_arc_deg") or from_position == Vector2.INF:
		return 1.0
	var incoming := (from_position - position).normalized()
	var angle := rad_to_deg(absf(_facing.angle_to(incoming)))
	if angle <= float(stats["shield_arc_deg"]) * 0.5:
		return float(stats["shield_mult"])
	return 1.0


func _draw() -> void:
	var color: Color = Color.WHITE if _flash > 0.0 else stats["color"]
	if _dash_state == "telegraph":
		color = Color.WHITE   # the tell
	_draw_body(color)

	if is_elite:
		draw_arc(Vector2.ZERO, radius + 7.0, 0.0, TAU, 26, Balance.ELITE_RING_COLOR, 2.5)
		draw_arc(Vector2.ZERO, radius + 12.0, 0.0, TAU, 26,
			Color(Balance.ELITE_RING_COLOR, 0.35), 2.0)

	if hp < max_hp:
		var fraction := hp / max_hp
		var width := radius * 2.0
		draw_rect(Rect2(-radius, -radius - 7.0, width, 3.0), Color(0.0, 0.0, 0.0, 0.6))
		draw_rect(Rect2(-radius, -radius - 7.0, width * fraction, 3.0), Color(0.4, 1.0, 0.5))


## Distinct silhouettes per shape id. Shape carries the identity, not just
## colour — GDD section 11 requires the game stay readable without relying on
## hue, both for colourblind players and on a crowded screen.
func _draw_body(color: Color) -> void:
	match stats.get("shape", "square"):
		"triangle":
			var points := PackedVector2Array([
				Vector2(0.0, -radius), Vector2(radius, radius), Vector2(-radius, radius),
			])
			draw_colored_polygon(points, color)
			draw_polyline(points + PackedVector2Array([points[0]]), Color(color, 0.3), 2.0)
		"hexagon":
			var points := PackedVector2Array()
			for i in 6:
				points.append(Vector2(radius, 0.0).rotated(TAU * float(i) / 6.0))
			draw_colored_polygon(points, color)
			draw_polyline(points + PackedVector2Array([points[0]]), Color(color, 0.35), 3.0)
		"diamond":
			var points := PackedVector2Array([
				Vector2(0.0, -radius), Vector2(radius, 0.0),
				Vector2(0.0, radius), Vector2(-radius, 0.0),
			])
			draw_colored_polygon(points, color)
			draw_arc(Vector2.ZERO, radius + 5.0, 0.0, TAU, 20, Color(color, 0.3), 1.5)
		"chevron":
			var points := PackedVector2Array([
				Vector2(radius, 0.0), Vector2(-radius * 0.6, radius * 0.9),
				Vector2(-radius * 0.2, 0.0), Vector2(-radius * 0.6, -radius * 0.9),
			])
			for i in points.size():
				points[i] = points[i].rotated(_facing.angle())
			draw_colored_polygon(points, color)
		"shield":
			var rect := Rect2(-radius, -radius, radius * 2.0, radius * 2.0)
			draw_rect(rect, color)
			# The armoured face, drawn on the side it actually protects.
			var start := _facing.angle() - deg_to_rad(float(stats["shield_arc_deg"]) * 0.5)
			var finish := _facing.angle() + deg_to_rad(float(stats["shield_arc_deg"]) * 0.5)
			draw_arc(Vector2.ZERO, radius + 6.0, start, finish, 20,
				Color(0.9, 0.95, 1.0), 4.0)
		"fuse":
			draw_circle(Vector2.ZERO, radius, color)
			draw_arc(Vector2.ZERO, radius + 5.0, 0.0,
				TAU * (0.5 + 0.5 * sin(_age * 6.0)), 22, Color(1.0, 0.9, 0.4), 2.5)
		"ribbon":
			var points := PackedVector2Array([
				Vector2(0.0, -radius), Vector2(radius * 0.75, 0.0),
				Vector2(0.0, radius), Vector2(-radius * 0.75, 0.0),
			])
			draw_colored_polygon(points, color)
			draw_polyline(points + PackedVector2Array([points[0]]), Color(color, 0.4), 2.0)
		"nested_square":
			var rect := Rect2(-radius, -radius, radius * 2.0, radius * 2.0)
			draw_rect(rect, color)
			draw_rect(rect.grow(-radius * 0.45), Color(0.02, 0.02, 0.05, 0.85), false, 2.0)
		_:
			var rect := Rect2(-radius, -radius, radius * 2.0, radius * 2.0)
			draw_rect(rect, color)
			draw_rect(rect.grow(3.0), Color(color, 0.25), false, 2.0)
