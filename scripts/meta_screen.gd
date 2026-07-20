extends Control

## The upgrade screen.
##
## Two things it has to communicate:
##
## 1. **What a purchase actually does.** Hovering or focusing a buy button
##    projects the resulting total power, so the effect is visible before
##    committing rather than discovered afterwards.
## 2. **Respec is free.** If experimenting is safe, a mispriced choice is a
##    curiosity rather than a trap.
##
## The design deliberately does NOT explain the ceiling, the budget maths, or
## what concentrating costs in points. Those govern the system; the player just
## needs to see what they get.

signal closed

const ROW_HEIGHT := 46

@onready var _power_label: Label = $Center/Panel/Header/Power
@onready var _power_bar: ProgressBar = $Center/Panel/Header/PowerBar
@onready var _budget_label: Label = $Center/Panel/Header/Budget
@onready var _points_label: Label = $Center/Panel/Header/Points
@onready var _rows: VBoxContainer = $Center/Panel/Rows
@onready var _projection: Label = $Center/Panel/Projection
@onready var _respec: Button = $Center/Panel/Buttons/Respec
@onready var _back: Button = $Center/Panel/Buttons/Back

var _buttons := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_rows()
	_respec.pressed.connect(_on_respec)
	_back.pressed.connect(func(): closed.emit())
	refresh()


func focus_first() -> void:
	for stat_id in _buttons:
		var button: Button = _buttons[stat_id]
		if not button.disabled:
			button.grab_focus()
			return
	_back.grab_focus()


## Rows are built in code rather than the scene: seven near-identical blocks of
## .tscn is a lot of duplication for something the data already describes.
func _build_rows() -> void:
	for stat_id in Balance.META_STATS:
		var entry: Dictionary = Balance.META_STATS[stat_id]

		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
		row.add_theme_constant_override("separation", 14)

		var name_label := Label.new()
		name_label.name = "Name"
		name_label.custom_minimum_size = Vector2(150, 0)
		name_label.add_theme_font_size_override("font_size", 19)
		name_label.text = str(entry["name"])
		row.add_child(name_label)

		var effect := Label.new()
		effect.name = "Effect"
		effect.custom_minimum_size = Vector2(230, 0)
		effect.clip_text = true
		effect.add_theme_font_size_override("font_size", 15)
		effect.add_theme_color_override("font_color", Color(0.72, 0.80, 0.92))
		row.add_child(effect)

		# Milestones get their own fixed column. Appended to the effect text they
		# overflowed the row and shunted that one buy button out of alignment.
		var milestone := Label.new()
		milestone.name = "Milestone"
		milestone.custom_minimum_size = Vector2(170, 0)
		milestone.clip_text = true
		milestone.add_theme_font_size_override("font_size", 14)
		milestone.add_theme_color_override("font_color", Color(1.0, 0.82, 0.25))
		row.add_child(milestone)

		var pips := Label.new()
		pips.name = "Pips"
		pips.custom_minimum_size = Vector2(210, 0)
		pips.add_theme_font_size_override("font_size", 17)
		row.add_child(pips)

		var buy := Button.new()
		buy.name = "Buy"
		buy.custom_minimum_size = Vector2(150, 38)
		buy.add_theme_font_size_override("font_size", 16)
		buy.pressed.connect(_on_buy.bind(stat_id))
		# Live projection on hover AND on focus, so the tradeoff is visible to
		# keyboard and pad players too, not just the mouse.
		buy.mouse_entered.connect(_show_projection.bind(stat_id))
		buy.focus_entered.connect(_show_projection.bind(stat_id))
		buy.mouse_exited.connect(_clear_projection)
		row.add_child(buy)

		_buttons[stat_id] = buy
		_rows.add_child(row)


func refresh() -> void:
	var purchases := MetaStore.purchases
	var bonus := Meta.effective_bonus(purchases)
	var used := Meta.total_purchases(purchases)
	var budget := Meta.max_total_purchases()

	_power_label.text = "META POWER   %s  /  +%.1f%%" % [
		MetaStore.bonus_text(), Balance.META_AGGREGATE_CAP * 100.0]
	_power_bar.max_value = Balance.META_AGGREGATE_CAP * 100.0
	_power_bar.value = bonus * 100.0
	_budget_label.text = "Budget  %d / %d purchases" % [used, budget]
	_points_label.text = "Points  %d" % MetaStore.points

	for stat_id in Balance.META_STATS:
		_refresh_row(stat_id)
	_clear_projection()


func _refresh_row(stat_id: String) -> void:
	var entry: Dictionary = Balance.META_STATS[stat_id]
	var owned := int(MetaStore.purchases.get(stat_id, 0))
	var row := _rows.get_child(Balance.META_STATS.keys().find(stat_id))

	row.get_node("Effect").text = str(entry["desc"])
	row.get_node("Milestone").text = Meta.next_milestone_text(MetaStore.purchases, stat_id)

	# Filled pips read faster than "7/12" when scanning seven rows.
	row.get_node("Pips").text = "%s  %d/%d" % [
		"●".repeat(owned) + "·".repeat(Balance.META_MAX_BUYS - owned),
		owned, Balance.META_MAX_BUYS]

	var buy: Button = _buttons[stat_id]
	var cost := Meta.next_cost(owned)
	if cost < 0:
		buy.text = "MAXED"
		buy.disabled = true
	elif Meta.budget_remaining(MetaStore.purchases) <= 0:
		buy.text = "CEILING"
		buy.disabled = true
	else:
		buy.text = "%d pts" % cost
		buy.disabled = MetaStore.points < cost


func _show_projection(stat_id: String) -> void:
	var owned := int(MetaStore.purchases.get(stat_id, 0))
	if owned >= Balance.META_MAX_BUYS or Meta.budget_remaining(MetaStore.purchases) <= 0:
		_projection.text = ""
		return

	var after := Meta.projected_bonus(MetaStore.purchases, stat_id)
	_projection.text = "→ %s becomes +%.2f%%" % [
		str(Balance.META_STATS[stat_id]["name"]), after * 100.0]


func _clear_projection() -> void:
	_projection.text = "Hover an upgrade to preview it."


func _on_buy(stat_id: String) -> void:
	if MetaStore.buy(stat_id):
		Sfx.play("level_up", -8.0)
		refresh()
		_show_projection(stat_id)


func _on_respec() -> void:
	MetaStore.respec()
	Sfx.play("xp_pickup", -4.0)
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		closed.emit()
