class_name Cosmetics
extends RefCounted

## Cosmetics and titles — catalog and application (8d).
##
## The whole point of this file is that it touches ONLY visual fields. `apply()`
## writes a colour and a shape id onto the player and nothing else; there is no
## code path from here to a stat. That is what lets cosmetics be an endless point
## sink without ever tilting a board (GDD section 22), and cosmetics_test.gd
## verifies the player's stat block is byte-for-byte unchanged across every
## combination.


## Every option across all categories, with its category id attached.
static func all_options() -> Array:
	var out := []
	for category in Balance.COSMETICS:
		for option in Balance.COSMETICS[category]["options"]:
			var entry: Dictionary = option.duplicate()
			entry["category"] = category
			out.append(entry)
	return out


static func option(id: String) -> Dictionary:
	for entry in all_options():
		if entry["id"] == id:
			return entry
	return {}


static func category_of(id: String) -> String:
	return str(option(id).get("category", ""))


## The free, always-owned default for a category — the first listed option.
static func default_id(category: String) -> String:
	return str(Balance.COSMETICS[category]["options"][0]["id"])


static func default_equipped() -> Dictionary:
	var equipped := {}
	for category in Balance.COSMETICS:
		equipped[category] = default_id(category)
	return equipped


## The ids owned from the start: every category's free default.
static func default_owned() -> Array:
	var owned := []
	for category in Balance.COSMETICS:
		owned.append(default_id(category))
	return owned


## Writes the equipped look onto the player. VISUAL FIELDS ONLY — if this ever
## needs to touch a stat, the design has gone wrong.
static func apply(player: Node, equipped: Dictionary) -> void:
	var hull := option(str(equipped.get("hull", default_id("hull"))))
	var shape := option(str(equipped.get("shape", default_id("shape"))))
	var trail := option(str(equipped.get("trail", default_id("trail"))))

	if hull.has("color"):
		player.body_color = hull["color"]
	if shape.has("shape"):
		player.body_shape = str(shape["shape"])
	if trail.has("color"):
		player.trail_color = trail["color"]


# --- Titles ------------------------------------------------------------------

static func title(id: String) -> Dictionary:
	for entry in Balance.TITLES:
		if entry["id"] == id:
			return entry
	return {}


static func title_unlocked(lifetime: Dictionary, id: String) -> bool:
	var entry := title(id)
	if entry.is_empty():
		return false
	return int(lifetime.get(entry["field"], 0)) >= int(entry["min"])


## Titles the profile has earned, in catalog order.
static func unlocked_titles(lifetime: Dictionary) -> Array:
	var out := []
	for entry in Balance.TITLES:
		if title_unlocked(lifetime, str(entry["id"])):
			out.append(entry)
	return out


static func title_text(id: String) -> String:
	return str(title(id).get("name", ""))
