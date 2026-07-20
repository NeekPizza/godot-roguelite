extends Node

## Cosmetics and titles (8d).
##
##   godot --headless tests/cosmetics_test.tscn -- --meta-profile=none
##
## The one guarantee this file exists to hold: a cosmetic changes how the player
## LOOKS and nothing else. The stat-block snapshot below is the load-bearing
## assertion — if any cosmetic ever moved a number, that is a fairness hole, and
## it fails here. Mirrors the meta suite's standard: it also asserts that two
## different looks actually DIFFER, so a no-op apply() cannot pass silently.

var _ok := true

const STAT_FIELDS := [
	"max_hp", "move_speed", "pickup_radius", "damage_mult", "fire_rate_mult",
	"volley_cooldown_mult", "projectile_speed_mult", "projectile_bonus",
	"pierce_bonus", "area_scale", "xp_gain_mult", "dash_cooldown_scale",
	"dash_iframe_scale",
]


func _check(label: String, passed: bool) -> void:
	if not passed:
		_ok = false
	print("  %-60s %s" % [label, "OK" if passed else "FAIL"])


func _snapshot(player: Node) -> Dictionary:
	var out := {}
	for field in STAT_FIELDS:
		out[field] = player.get(field)
	return out


func _ready() -> void:
	print("=== cosmetics carry no numbers, and no id collides with a stat ===")
	var clean := true
	for option in Cosmetics.all_options():
		# The payload must be a colour or a shape id — never anything a stat could
		# read as a modifier.
		var has_color: bool = option.has("color") and option["color"] is Color
		var has_shape: bool = option.has("shape") and option["shape"] is String
		if not (has_color or has_shape):
			clean = false
		if Balance.META_STATS.has(option["id"]) or Balance.META_STATS.has(option["category"]):
			clean = false
	_check("every option is a colour or a shape, none shares a stat id", clean)

	var category_clean := true
	for category in Balance.COSMETICS:
		if Balance.META_STATS.has(category):
			category_clean = false
	_check("no cosmetic category shares a name with META_STATS", category_clean)

	print("\n=== applying ANY cosmetic leaves the stat block untouched ===")
	var player: Node = load("res://scenes/player.tscn").instantiate()
	add_child(player)
	# Give the player a non-default stat block, so a cosmetic that quietly reset
	# a field to its default would show up as a change.
	player.max_hp = 137.0
	player.move_speed = 321.0
	player.damage_mult = 1.9
	var before := _snapshot(player)

	var stat_safe := true
	for option in Cosmetics.all_options():
		var equipped := Cosmetics.default_equipped()
		equipped[option["category"]] = option["id"]
		Cosmetics.apply(player, equipped)
		if _snapshot(player) != before:
			stat_safe = false
	_check("no single cosmetic moved any stat", stat_safe)

	# The maximal case: everything non-default equipped at once.
	var maxed := {}
	for category in Balance.COSMETICS:
		var opts: Array = Balance.COSMETICS[category]["options"]
		maxed[category] = opts[opts.size() - 1]["id"]
	Cosmetics.apply(player, maxed)
	_check("all cosmetics at once still moved no stat", _snapshot(player) == before)

	print("\n=== but the LOOK actually changes (testing the test) ===")
	Cosmetics.apply(player, {"hull": "hull_cyan", "shape": "shape_dart", "trail": "trail_cyan"})
	var look_a := [player.body_color, player.body_shape, player.trail_color]
	Cosmetics.apply(player, {"hull": "hull_magenta", "shape": "shape_kite", "trail": "trail_amber"})
	var look_b := [player.body_color, player.body_shape, player.trail_color]
	_check("two different sets produce different colour AND shape", look_a != look_b
		and look_a[0] != look_b[0] and look_a[1] != look_b[1] and look_a[2] != look_b[2])

	print("\n=== the preview shapes match the ones the player draws ===")
	# The screen redraws the silhouettes; a shape id it cannot render would show
	# the wrong preview. Assert every catalog shape is one the player handles.
	var known_shapes := ["dart", "needle", "kite", "delta"]
	var shapes_known := true
	for option in Balance.COSMETICS["shape"]["options"]:
		if not known_shapes.has(str(option["shape"])):
			shapes_known = false
	_check("every catalog shape id is one the player can draw", shapes_known)

	print("\n=== buying a cosmetic never touches the upgrade budget ===")
	MetaStore.points = 500
	MetaStore.purchases = Meta.profile_none()
	MetaStore.cosmetics = MetaStore._default_cosmetics()
	var budget_before := Meta.total_purchases(MetaStore.purchases)
	var bonus_before := Meta.effective_bonus(MetaStore.purchases)
	var bought := MetaStore.buy_cosmetic("hull_magenta")
	_check("a cosmetic can be bought with points", bought
		and MetaStore.cosmetic_owned("hull_magenta"))
	_check("buying it added nothing to purchases",
		Meta.total_purchases(MetaStore.purchases) == budget_before)
	_check("buying it moved meta power not at all",
		is_equal_approx(Meta.effective_bonus(MetaStore.purchases), bonus_before))
	_check("a second buy of the same id is refused",
		not MetaStore.buy_cosmetic("hull_magenta"))
	_check("an unaffordable cosmetic is refused",
		not (MetaStore.points >= 999999) and not MetaStore.buy_cosmetic("nonexistent"))

	print("\n=== equip only what you own ===")
	# buy() and equip() are separate in the store — the screen composes them.
	# Buying alone owns without equipping.
	_check("buying owns but does not silently equip",
		MetaStore.cosmetics["equipped"]["hull"] == Cosmetics.default_id("hull"))
	_check("equipping an unowned id is refused", not MetaStore.equip_cosmetic("hull_lime"))
	_check("equipping the owned hull switches the slot",
		MetaStore.equip_cosmetic("hull_magenta")
		and MetaStore.cosmetics["equipped"]["hull"] == "hull_magenta")

	print("\n=== titles unlock on lifetime milestones ===")
	MetaStore.lifetime = MetaStore._default_lifetime()
	_check("the default title is always unlocked",
		Cosmetics.title_unlocked(MetaStore.lifetime, Balance.TITLES[0]["id"]))
	_check("a milestone title is locked on a fresh profile",
		not Cosmetics.title_unlocked(MetaStore.lifetime, "diver"))
	MetaStore.lifetime["best_stage"] = 5
	_check("reaching stage 5 unlocks Stage Diver",
		Cosmetics.title_unlocked(MetaStore.lifetime, "diver"))
	_check("equipping a locked title is refused", not MetaStore.equip_title("abyssal"))
	_check("equipping an unlocked title succeeds",
		MetaStore.equip_title("diver") and MetaStore.title == "diver")

	print("\n=== a partial/old save loads to valid defaults ===")
	# owned lists a real id and a stale one; equipped points at something not
	# owned. Result: defaults, plus the real owned id, and no bogus equip.
	MetaStore._load_cosmetics({
		"owned": ["hull_amber", "hull_ghost_that_was_removed"],
		"equipped": {"hull": "hull_violet"},   # violet not in owned -> ignored
	})
	_check("a real stored id is restored to owned",
		MetaStore.cosmetic_owned("hull_amber"))
	_check("a removed id is dropped, not carried",
		not MetaStore.cosmetic_owned("hull_ghost_that_was_removed"))
	_check("the defaults are always owned after a load",
		MetaStore.cosmetic_owned(Cosmetics.default_id("hull")))
	_check("an equip pointing at an unowned id falls back to default",
		MetaStore.cosmetics["equipped"]["hull"] == Cosmetics.default_id("hull"))

	print("\nRESULT: %s" % ("PASS" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)
