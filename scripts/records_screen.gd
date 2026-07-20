extends Control

## Records and lifetime stats (8c).
##
## Read-only, and deliberately so: nothing here spends points or changes state.
## It answers "how am I doing" — the bests that the run-over banner celebrates
## in the moment, and the totals that only make sense accumulated.
##
## The lists come from Balance.META_RECORDS and META_LIFETIME_ROWS rather than
## being spelled out here, so adding a record cannot leave this screen showing a
## stale set.

signal closed

@onready var _records: VBoxContainer = $Center/Panel/Records
@onready var _lifetime: VBoxContainer = $Center/Panel/Lifetime
@onready var _table: VBoxContainer = $Center/Panel/Table
@onready var _empty: Label = $Center/Panel/Empty
@onready var _back: Button = $Center/Panel/Back


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_back.pressed.connect(func(): closed.emit())
	refresh()


func focus_first() -> void:
	_back.grab_focus()


func refresh() -> void:
	_fill(_records, _record_rows())
	_fill(_lifetime, _lifetime_rows())

	var best := SaveStore.top_overall(Balance.RECORDS_TABLE_ROWS)
	_fill(_table, _table_rows(best))
	# A brand-new profile with an empty table would otherwise read as broken.
	_empty.visible = best.is_empty()
	_table.visible = not best.is_empty()


func _record_rows() -> Array:
	var rows := []
	for record in Balance.META_RECORDS:
		var value := int(MetaStore.lifetime.get(record["field"], 0))
		rows.append([str(record["label"]).capitalize(),
			_format_time(value) if record["id"] == "seconds" else _thousands(value)])
	return rows


func _lifetime_rows() -> Array:
	var rows := []
	for row in Balance.META_LIFETIME_ROWS:
		var value := int(MetaStore.lifetime.get(row["field"], 0))
		rows.append([str(row["label"]),
			_format_time(value) if row["format"] == "time" else _thousands(value)])
	return rows


func _table_rows(best: Array) -> Array:
	var rows := []
	for i in best.size():
		var entry: Dictionary = best[i]
		rows.append([
			"%d.  %s" % [i + 1, str(entry.get("date", "?"))],
			"%s   stage %d   %s   %s" % [
				_thousands(int(entry.get("score", 0))),
				int(entry.get("stage", 1)),
				_format_time(int(entry.get("seconds", 0))),
				"ranked" if bool(entry.get("ranked", false)) else "practice",
			]])
	return rows


## Rebuilt rather than updated in place: the row COUNT changes as the score
## table fills up, so reusing children would leave stale trailing rows.
func _fill(container: VBoxContainer, rows: Array) -> void:
	for child in container.get_children():
		child.queue_free()
		container.remove_child(child)
	for row in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 20)

		var label := Label.new()
		label.custom_minimum_size = Vector2(240, 0)
		label.add_theme_font_size_override("font_size", 17)
		label.add_theme_color_override("font_color", Color(0.72, 0.80, 0.92))
		label.text = str(row[0])
		line.add_child(label)

		var value := Label.new()
		value.custom_minimum_size = Vector2(400, 0)
		value.add_theme_font_size_override("font_size", 17)
		value.add_theme_color_override("font_color", Color(1.0, 0.92, 0.35))
		value.text = str(row[1])
		line.add_child(value)

		container.add_child(line)


func _thousands(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return ("-" if value < 0 else "") + out


func _format_time(seconds: int) -> String:
	if seconds >= 3600:
		return "%dh %02dm" % [seconds / 3600, (seconds % 3600) / 60]
	return "%d:%02d" % [seconds / 60, seconds % 60]


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		closed.emit()
