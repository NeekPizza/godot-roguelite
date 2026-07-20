extends Control

## Customise screen (8d): buy and equip cosmetics, equip earned titles.
##
## Everything here spends points on LOOKS. It shares no code with the upgrade
## screen and cannot reach `purchases`, which is the whole design guarantee —
## a player can pour every point into colours without ever touching the board.
##
## Options and titles are built from Balance.COSMETICS / Balance.TITLES rather
## than hand-listed, so adding a colour or a milestone surfaces here for free.

signal closed

const OWNED := Color(0.72, 0.80, 0.92)
const EQUIPPED := Color(0.25, 0.95, 1.0)
const LOCKED := Color(0.45, 0.5, 0.62)

@onready var _points: Label = $Center/Panel/Points
@onready var _preview: Control = $Center/Panel/Top/Preview
@onready var _categories: VBoxContainer = $Center/Panel/Categories
@onready var _titles: VBoxContainer = $Center/Panel/Titles
@onready var _back: Button = $Center/Panel/Back

var _first_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_preview.draw.connect(_draw_preview)
	_back.pressed.connect(func(): closed.emit())
	refresh()


func focus_first() -> void:
	if _first_button != null and is_instance_valid(_first_button):
		_first_button.grab_focus()
	else:
		_back.grab_focus()


func refresh() -> void:
	_points.text = "Points  %d" % MetaStore.points
	_first_button = null
	_build_categories()
	_build_titles()
	_preview.queue_redraw()


func _build_categories() -> void:
	_clear(_categories)
	for category in Balance.COSMETICS:
		var data: Dictionary = Balance.COSMETICS[category]

		var heading := Label.new()
		heading.add_theme_font_size_override("font_size", 16)
		heading.add_theme_color_override("font_color", Color(1.0, 0.28, 0.85))
		heading.text = str(data["label"]).to_upper()
		_categories.add_child(heading)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		for option in data["options"]:
			row.add_child(_option_button(str(category), option))
		_categories.add_child(row)


func _option_button(category: String, option: Dictionary) -> Button:
	var id: String = option["id"]
	var owned := MetaStore.cosmetic_owned(id)
	var equipped: bool = MetaStore.cosmetics["equipped"].get(category, "") == id

	var button := Button.new()
	button.custom_minimum_size = Vector2(150, 40)
	button.add_theme_font_size_override("font_size", 15)
	button.toggle_mode = false
	if option.has("color"):
		# A swatch dot next to the name, so colour options read without reading.
		button.add_theme_color_override("font_color", option["color"])

	if equipped:
		button.text = "◉ %s" % option["name"]
		button.disabled = true
	elif owned:
		button.text = "%s" % option["name"]
		button.pressed.connect(_on_equip.bind(id))
	else:
		button.text = "%s — %d" % [option["name"], int(option["cost"])]
		button.disabled = MetaStore.points < int(option["cost"])
		button.pressed.connect(_on_buy.bind(id))

	if _first_button == null and not button.disabled:
		_first_button = button
	return button


func _build_titles() -> void:
	_clear(_titles)

	var heading := Label.new()
	heading.add_theme_font_size_override("font_size", 16)
	heading.add_theme_color_override("font_color", Color(1.0, 0.28, 0.85))
	heading.text = "TITLE"
	_titles.add_child(heading)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for entry in Balance.TITLES:
		var id: String = entry["id"]
		var unlocked := Cosmetics.title_unlocked(MetaStore.lifetime, id)
		var equipped: bool = MetaStore.title == id

		var button := Button.new()
		button.custom_minimum_size = Vector2(150, 40)
		button.add_theme_font_size_override("font_size", 15)
		if equipped:
			button.text = "◉ %s" % entry["name"]
			button.add_theme_color_override("font_color", EQUIPPED)
			button.disabled = true
		elif unlocked:
			button.text = str(entry["name"])
			button.add_theme_color_override("font_color", OWNED)
			button.pressed.connect(_on_equip_title.bind(id))
		else:
			button.text = "🔒 %s" % _requirement(entry)
			button.add_theme_color_override("font_color", LOCKED)
			button.disabled = true
		row.add_child(button)
	_titles.add_child(row)


## What a locked title needs, phrased as a goal rather than a field name.
func _requirement(entry: Dictionary) -> String:
	match str(entry["field"]):
		"best_stage": return "Reach stage %d" % int(entry["min"])
		"best_seconds": return "Survive %d:%02d" % [int(entry["min"]) / 60, int(entry["min"]) % 60]
		"bosses": return "Fell %d bosses" % int(entry["min"])
		"kills": return "%d kills" % int(entry["min"])
		"runs": return "Play %d runs" % int(entry["min"])
		_: return str(entry["name"])


func _draw_preview() -> void:
	var equipped: Dictionary = MetaStore.cosmetics["equipped"]
	var hull := Cosmetics.option(str(equipped.get("hull", "")))
	var shape := Cosmetics.option(str(equipped.get("shape", "")))
	var colour: Color = hull.get("color", EQUIPPED)
	var shape_id: String = str(shape.get("shape", "dart"))

	var centre := _preview.size * 0.5
	var points := _preview_points(shape_id, 30.0)
	for i in points.size():
		points[i] += centre
	_preview.draw_colored_polygon(points, colour)
	_preview.draw_polyline(points + PackedVector2Array([points[0]]),
		Color(colour, 0.4), 3.0)
	_preview.draw_arc(centre, 46.0, 0.0, TAU, 40, Color(colour, 0.18), 2.0)


## Mirrors player.gd's silhouettes so the preview matches what you'll play.
## Kept in step by hand; cosmetics_test asserts the shape ids line up.
func _preview_points(shape_id: String, r: float) -> PackedVector2Array:
	match shape_id:
		"needle":
			return PackedVector2Array([Vector2(0, -r * 1.35), Vector2(-r * 0.45, r * 0.75), Vector2(r * 0.45, r * 0.75)])
		"kite":
			return PackedVector2Array([Vector2(0, -r), Vector2(-r * 0.7, r * 0.15), Vector2(0, r * 1.15), Vector2(r * 0.7, r * 0.15)])
		"delta":
			return PackedVector2Array([Vector2(0, -r), Vector2(-r, r * 0.85), Vector2(0, r * 0.35), Vector2(r, r * 0.85)])
		_:
			return PackedVector2Array([Vector2(0, -r), Vector2(-r * 0.8, r * 0.7), Vector2(r * 0.8, r * 0.7)])


func _clear(container: VBoxContainer) -> void:
	for child in container.get_children():
		child.queue_free()
		container.remove_child(child)


func _on_buy(id: String) -> void:
	if MetaStore.buy_cosmetic(id):
		MetaStore.equip_cosmetic(id)     # buying equips immediately; you bought it to wear it
		Sfx.play("level_up", -8.0)
		refresh()


func _on_equip(id: String) -> void:
	if MetaStore.equip_cosmetic(id):
		Sfx.play("xp_pickup", -4.0)
		refresh()


func _on_equip_title(id: String) -> void:
	if MetaStore.equip_title(id):
		Sfx.play("xp_pickup", -4.0)
		refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		closed.emit()
