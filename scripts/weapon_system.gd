extends Node2D

## Fires every weapon the player holds.
##
## Lives on the player so orbit orbs inherit its transform for free. All
## gameplay runs in _physics_process — the determinism contract (GDD section 9)
## does not care that this is a weapon rather than an enemy.

const PROJECTILE_SCENE := preload("res://scenes/projectile.tscn")
const ORB_SCENE := preload("res://scenes/orbit_orb.tscn")
const NOVA_SCENE := preload("res://scenes/nova_ring.tscn")

var player: Node2D
var projectile_parent: Node2D

## weapon id -> level. Insertion order is the acquisition order and is stable,
## which matters: the digest and the HUD both read it.
var owned := {}

var _cooldowns := {}          # weapon id -> seconds until next fire
var _orbit_angle := 0.0
var _orbs: Array[Node2D] = []


func slots_used() -> int:
	return owned.size()


func has_weapon(weapon_id: String) -> bool:
	return owned.has(weapon_id)


func level_of(weapon_id: String) -> int:
	return int(owned.get(weapon_id, 0))


func add_or_level(weapon_id: String) -> void:
	if owned.has(weapon_id):
		owned[weapon_id] = mini(int(owned[weapon_id]) + 1, Weapons.max_level(weapon_id))
	else:
		owned[weapon_id] = 1
		_cooldowns[weapon_id] = 0.0
	if Weapons.definition(weapon_id)["behavior"] == "orbit":
		_rebuild_orbs()


## Replace a base weapon with its evolution IN PLACE, preserving acquisition
## order so the HUD and digest stay stable, and costing no slot.
func evolve(base_id: String, evolved_id: String) -> void:
	var rebuilt := {}
	for weapon_id in owned:
		if weapon_id == base_id:
			rebuilt[evolved_id] = 1
		else:
			rebuilt[weapon_id] = owned[weapon_id]
	owned = rebuilt
	_cooldowns.erase(base_id)
	_cooldowns[evolved_id] = 0.0
	if Weapons.definition(evolved_id)["behavior"] == "orbit" \
			or Balance.WEAPONS.get(base_id, {}).get("behavior", "") == "orbit":
		_rebuild_orbs()


func summary() -> String:
	var parts := PackedStringArray()
	for weapon_id in owned:
		parts.append("%s %d" % [Weapons.definition(weapon_id)["name"], int(owned[weapon_id])])
	return "  ".join(parts)


## Stable "id:level" list for the determinism digest.
func digest() -> String:
	var parts := PackedStringArray()
	for weapon_id in owned:
		parts.append("%s:%d" % [weapon_id, int(owned[weapon_id])])
	return ",".join(parts)


func _physics_process(delta: float) -> void:
	if player == null or projectile_parent == null:
		return

	for weapon_id in owned:
		var stats := Weapons.stats(weapon_id, int(owned[weapon_id]), player)
		if stats.is_empty():
			continue

		if stats["behavior"] == "orbit":
			_tick_orbit(stats, delta)
			continue

		_cooldowns[weapon_id] = float(_cooldowns.get(weapon_id, 0.0)) - delta
		if _cooldowns[weapon_id] > 0.0:
			continue
		_cooldowns[weapon_id] = stats["cooldown"]
		_fire(stats)


# --- Firing ------------------------------------------------------------------

func _fire(stats: Dictionary) -> void:
	match stats["behavior"]:
		"seek":      _fire_spread(stats, "seek", _aim_at_nearest())
		"curve":     _fire_curve(stats)
		"boomerang": _fire_spread(stats, "boomerang", _aim_at_nearest())
		"nova":      _fire_nova(stats)


## Nothing in range: hold fire rather than waste the volley. Returns a zero
## vector when there is no target.
func _aim_at_nearest() -> Vector2:
	var target := _nearest_enemy()
	if target == null:
		return Vector2.ZERO
	return (target.position - player.position).normalized()


func _nearest_enemy() -> Node2D:
	var nearest: Node2D = null
	var nearest_distance := INF
	for enemy in get_tree().get_nodes_in_group("enemy"):
		var distance: float = player.position.distance_squared_to(enemy.position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = enemy
	if nearest_distance > Balance.PROJECTILE_RANGE * Balance.PROJECTILE_RANGE:
		return null
	return nearest


func _fire_spread(stats: Dictionary, mode: String, aim: Vector2) -> void:
	if aim == Vector2.ZERO:
		return
	var count: int = maxi(1, int(stats["count"]))
	for i in count:
		var offset := (float(i) - float(count - 1) * 0.5) * Balance.WEAPON_SPREAD_RADIANS
		_spawn_projectile(stats, mode, aim.rotated(offset))


## Curveball fans out around the aim and each shot then arcs, alternating turn
## direction so the volley sweeps outward rather than all bending one way.
func _fire_curve(stats: Dictionary) -> void:
	var aim := _aim_at_nearest()
	if aim == Vector2.ZERO:
		return
	var count: int = maxi(1, int(stats["count"]))
	for i in count:
		var offset := (float(i) - float(count - 1) * 0.5) * 0.30
		var sign := 1.0 if i % 2 == 0 else -1.0
		_spawn_projectile(stats, "curve", aim.rotated(offset),
			float(stats.get("curve", 0.0)) * sign)


func _spawn_projectile(stats: Dictionary, mode: String, direction: Vector2,
		curve: float = 0.0) -> void:
	var projectile := PROJECTILE_SCENE.instantiate()
	projectile.position = player.position
	projectile.setup({
		"mode": mode, "direction": direction,
		"damage": stats["damage"], "pierce": int(stats["pierce"]),
		"speed": stats["speed"], "radius": stats["radius"],
		"lifetime": stats["lifetime"], "curve": curve, "origin": player,
	})
	projectile_parent.add_child(projectile)
	Sfx.play("shoot")


func _fire_nova(stats: Dictionary) -> void:
	var ring := NOVA_SCENE.instantiate()
	ring.position = player.position
	ring.setup(stats["damage"], stats["radius"], stats["lifetime"],
		float(stats.get("knockback", 0.0)))
	projectile_parent.add_child(ring)
	Sfx.play("shoot")


# --- Orbit -------------------------------------------------------------------

func _orbit_weapon_id() -> String:
	for weapon_id in owned:
		if Weapons.definition(weapon_id)["behavior"] == "orbit":
			return weapon_id
	return ""


func _tick_orbit(stats: Dictionary, delta: float) -> void:
	if _orbs.size() != int(stats["count"]):
		_rebuild_orbs()
	_orbit_angle += float(stats["speed"]) * delta
	for i in _orbs.size():
		var angle := _orbit_angle + TAU * float(i) / float(maxi(1, _orbs.size()))
		_orbs[i].position = Vector2(stats["radius"], 0.0).rotated(angle)
		_orbs[i].configure(stats["damage"], 8.0 * player.area_scale)

	# Event Horizon drags enemies inward. Pure geometry, no RNG, and it uses the
	# same position-nudge as knockback because enemies drive their own movement.
	var pull := float(stats.get("pull", 0.0))
	if pull > 0.0:
		var reach: float = stats["radius"] * 1.6
		for enemy in get_tree().get_nodes_in_group("enemy"):
			var offset: Vector2 = player.position - enemy.position
			if offset.length() <= reach and enemy.has_method("push_away_from"):
				enemy.push_away_from(player.position, -pull * delta)


func _rebuild_orbs() -> void:
	for orb in _orbs:
		if is_instance_valid(orb):
			orb.queue_free()
	_orbs.clear()
	var orbit_id := _orbit_weapon_id()
	if orbit_id == "":
		return
	var stats := Weapons.stats(orbit_id, int(owned[orbit_id]), player)
	for i in int(stats["count"]):
		var orb := ORB_SCENE.instantiate()
		add_child(orb)
		_orbs.append(orb)
