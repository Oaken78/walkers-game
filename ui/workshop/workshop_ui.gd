class_name WorkshopUI
extends CanvasLayer
## The workshop screen (GDD 12): banked scrap and the part list on the left, the stat panel with the exit button on
## the right, a tip that follows the cursor. Built in code from WorkshopTheme. It only shows what Workshop tells it
## and reports clicks with signals; it holds no build state. The two panels are 250 px wide each at the 1280 px base,
## 39 % of the screen width together (task T09: at most 40 %), so the walker keeps the centre.

signal part_selected(part_id: StringName)
signal buy_pressed(part_id: StringName)
signal exit_pressed

## Parts in list order. The chassis is not a shop item.
const PART_ORDER: Array[StringName] = [
	PartCatalog.LEG_SHORT,
	PartCatalog.LEG_MEDIUM,
	PartCatalog.LEG_LONG,
	PartCatalog.PULSE_CANNON,
	PartCatalog.ARMOR_PLATE,
]
const VALUE_COLUMN_WIDTH: float = 56.0
const DELTA_COLUMN_WIDTH: float = 70.0

## Width of each panel (px at the 1280 base).
@export var panel_width: float = 250.0
## Gap between a panel and the screen edge.
@export var panel_margin: float = 10.0
## Where the hover tip sits relative to the cursor.
@export var tip_offset: Vector2 = Vector2(24.0, 20.0)

var _inventory: Inventory
var _economy: Economy
var _root: Control
var _left_panel: PanelContainer
var _right_panel: PanelContainer
var _scrap_value: Label
var _part_rows: Dictionary = {}  # part id -> {panel, select, owned, spare, buy}
var _stat_rows: Dictionary = {}  # stats key -> {panel, value, delta, mark}
var _load_detail: Label
var _preview_line: Label
var _after_line: Label
var _exit_button: Button
var _exit_reason: Label
var _tip: PanelContainer
var _tip_label: Label


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = WorkshopTheme.build()
	add_child(_root)
	_build_left()
	_build_right()
	_build_tip()


## Fills the part list. Call once, after the node is in the tree.
func setup(inventory: Inventory, economy: Economy) -> void:
	_inventory = inventory
	_economy = economy
	refresh_scrap()


# --- Shown state -------------------------------------------------------------------------------------------------


func refresh_scrap() -> void:
	if _economy != null:
		_scrap_value.text = str(_economy.banked_scrap)


## Owned and spare counts, Buy buttons and the armed highlight.
func refresh_parts(build: WalkerBuild, armed: StringName) -> void:
	if _inventory == null:
		return
	for part_id: StringName in PART_ORDER:
		var row: Dictionary = _part_rows[part_id]
		var data: Dictionary = PartCatalog.PARTS[part_id]
		(row["owned"] as Label).text = "Own %d" % _inventory.owned(part_id)
		(row["spare"] as Label).text = "Spare %d" % _inventory.spare(build, part_id)
		var buy := row["buy"] as Button
		var blocker := _inventory.buy_blocker(part_id, _economy)
		var pair := int(data["units_per_purchase"]) > 1
		buy.disabled = blocker != ""
		if blocker == "":
			buy.text = "Buy pair" if pair else "Buy"
		else:
			buy.text = blocker
		var price := row["price"] as Label
		price.visible = bool(data["for_sale"])
		price.text = "%d per pair" % data["price"] if pair else str(data["price"])
		(row["panel"] as PanelContainer).theme_type_variation = (
			WorkshopTheme.ARMED_ROW if part_id == armed else WorkshopTheme.PART_ROW
		)


## The current stats of the build (a PartCatalog/WalkerBuild stats dictionary plus climb) with no change marked.
func show_stats(stats: Dictionary) -> void:
	for entry in StatFormat.ROWS:
		var key: String = entry["key"]
		var row: Dictionary = _stat_rows[key]
		(row["value"] as Label).text = StatFormat.value_text(float(stats[key]))
		_set_delta(key, 0.0)
	_load_detail.text = StatFormat.load_detail(stats)


## Marks every changed stat with its delta. `caption` says what the preview is; `after_reason` is the invalid
## reason the build would have afterwards ("" when valid).
func show_deltas(delta: Dictionary, caption: String, after_reason: String) -> void:
	for entry in StatFormat.ROWS:
		var key: String = entry["key"]
		_set_delta(key, float(delta.get(key, 0.0)))
	_preview_line.text = caption
	_after_line.text = "" if after_reason == "" else "Then blocked: " + after_reason
	_after_line.visible = after_reason != ""


## No preview: all deltas off, with a hint line.
func clear_deltas(caption: String) -> void:
	for entry in StatFormat.ROWS:
		_set_delta(entry["key"], 0.0)
	_preview_line.text = caption
	_after_line.text = ""
	_after_line.visible = false


func set_exit(valid: bool, reason: String) -> void:
	_exit_button.disabled = not valid
	_exit_reason.text = reason
	_exit_reason.visible = not valid


## Shows `text` next to the cursor, or hides the tip when it is empty.
func show_tip(text: String, mouse_pos: Vector2) -> void:
	if text == "":
		_tip.visible = false
		return
	_tip_label.text = text
	_tip.visible = true
	_tip.reset_size()
	var screen := _root.get_viewport_rect().size
	var spot := mouse_pos + tip_offset
	spot.x = minf(spot.x, screen.x - _tip.size.x - panel_margin)
	spot.y = minf(spot.y, screen.y - _tip.size.y - panel_margin)
	_tip.position = spot


func is_over_panel(pos: Vector2) -> bool:
	var on_left := _left_panel.get_global_rect().has_point(pos)
	return on_left or _right_panel.get_global_rect().has_point(pos)


# --- Read back (tests and scenarios read what is on screen, not the model) --------------------------------------


func shown_value(key: String) -> String:
	return (_stat_rows[key]["value"] as Label).text


func shown_delta(key: String) -> String:
	return (_stat_rows[key]["delta"] as Label).text


## 1 for ▲, -1 for ▼, 0 for none.
func shown_delta_direction(key: String) -> int:
	return (_stat_rows[key]["mark"] as DeltaMark).direction


func shown_load_detail() -> String:
	return _load_detail.text


func shown_scrap() -> String:
	return _scrap_value.text


func shown_price(part_id: StringName) -> String:
	var label := _part_rows[part_id]["price"] as Label
	return label.text if label.visible else ""


func shown_preview_line() -> String:
	return _preview_line.text


func shown_tip() -> String:
	return _tip_label.text if _tip.visible else ""


func exit_button() -> Button:
	return _exit_button


func exit_reason_text() -> String:
	return _exit_reason.text if _exit_reason.visible else ""


func left_panel() -> Control:
	return _left_panel


func right_panel() -> Control:
	return _right_panel


## A named control (PartSelect_leg_long, PartBuy_leg_long, ExitButton ...), or null.
func find_control(control_name: String) -> Control:
	return _root.find_child(control_name, true, false) as Control


## Smallest font size used by any label or button, in base px.
func smallest_font_px() -> int:
	var smallest := 1000
	for node in _root.find_children("*", "Control", true, false):
		if node is Label or node is Button:
			smallest = mini(smallest, (node as Control).get_theme_font_size("font_size"))
	return smallest


## Both panels together over the screen width.
func panel_width_share() -> float:
	var screen := _root.get_viewport_rect().size.x
	return (_left_panel.size.x + _right_panel.size.x) / screen


# --- Building ---------------------------------------------------------------------------------------------------


func _build_left() -> void:
	_left_panel = _make_panel("LeftPanel", true)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_left_panel.add_child(column)
	var scrap_line := HBoxContainer.new()
	column.add_child(scrap_line)
	var scrap_label := Label.new()
	scrap_label.text = "Banked scrap"
	scrap_label.theme_type_variation = WorkshopTheme.MUTED_LABEL
	scrap_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scrap_line.add_child(scrap_label)
	_scrap_value = Label.new()
	_scrap_value.name = "ScrapValue"
	_scrap_value.text = "0"
	_scrap_value.theme_type_variation = WorkshopTheme.SCRAP_LABEL
	scrap_line.add_child(_scrap_value)
	column.add_child(HSeparator.new())
	var heading := Label.new()
	heading.text = "Parts"
	heading.theme_type_variation = WorkshopTheme.HEADING_LABEL
	column.add_child(heading)
	for part_id: StringName in PART_ORDER:
		column.add_child(_make_part_row(part_id))


func _make_part_row(part_id: StringName) -> PanelContainer:
	var data: Dictionary = PartCatalog.PARTS[part_id]
	var panel := PanelContainer.new()
	panel.name = "PartRow_%s" % part_id
	panel.theme_type_variation = WorkshopTheme.PART_ROW
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	var select := Button.new()
	select.name = "PartSelect_%s" % part_id
	select.text = data["display_name"]
	select.alignment = HORIZONTAL_ALIGNMENT_LEFT
	select.focus_mode = Control.FOCUS_NONE
	select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	select.pressed.connect(func() -> void: part_selected.emit(part_id))
	top.add_child(select)
	var owned := Label.new()
	owned.name = "PartOwned_%s" % part_id
	owned.custom_minimum_size.x = 52.0
	owned.theme_type_variation = WorkshopTheme.MUTED_LABEL
	owned.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(owned)
	var middle := HBoxContainer.new()
	column.add_child(middle)
	var spare := Label.new()
	spare.name = "PartSpare_%s" % part_id
	spare.theme_type_variation = WorkshopTheme.MUTED_LABEL
	spare.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_child(spare)
	var price := Label.new()
	price.name = "PartPrice_%s" % part_id
	price.theme_type_variation = WorkshopTheme.SCRAP_SMALL_LABEL
	middle.add_child(price)
	var buy := Button.new()
	buy.name = "PartBuy_%s" % part_id
	buy.focus_mode = Control.FOCUS_NONE
	column.add_child(buy)
	if data["for_sale"]:
		buy.pressed.connect(func() -> void: buy_pressed.emit(part_id))
	else:
		buy.disabled = true
	_part_rows[part_id] = {
		"panel": panel,
		"select": select,
		"owned": owned,
		"spare": spare,
		"price": price,
		"buy": buy,
	}
	return panel


func _build_right() -> void:
	_right_panel = _make_panel("RightPanel", false)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	_right_panel.add_child(column)
	var heading := Label.new()
	heading.text = "Walker"
	heading.theme_type_variation = WorkshopTheme.HEADING_LABEL
	column.add_child(heading)
	for entry in StatFormat.ROWS:
		column.add_child(_make_stat_row(entry))
		if entry["key"] == "load":
			_load_detail = Label.new()
			_load_detail.name = "LoadDetail"
			_load_detail.theme_type_variation = WorkshopTheme.MUTED_LABEL
			_load_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			column.add_child(_load_detail)
	column.add_child(HSeparator.new())
	_preview_line = _make_wrapped_label("PreviewLine", WorkshopTheme.MUTED_LABEL)
	column.add_child(_preview_line)
	_after_line = _make_wrapped_label("AfterLine", WorkshopTheme.MUTED_LABEL)
	_after_line.visible = false
	column.add_child(_after_line)
	column.add_child(HSeparator.new())
	_exit_button = Button.new()
	_exit_button.name = "ExitButton"
	_exit_button.text = "Exit [Tab]"
	_exit_button.theme_type_variation = WorkshopTheme.EXIT_BUTTON
	_exit_button.focus_mode = Control.FOCUS_NONE
	_exit_button.pressed.connect(func() -> void: exit_pressed.emit())
	column.add_child(_exit_button)
	_exit_reason = _make_wrapped_label("ExitReason", WorkshopTheme.ACCENT_LABEL)
	_exit_reason.visible = false
	column.add_child(_exit_reason)


func _make_stat_row(entry: Dictionary) -> PanelContainer:
	var key: String = entry["key"]
	var panel := PanelContainer.new()
	panel.name = "StatRow_%s" % key
	panel.theme_type_variation = WorkshopTheme.STAT_ROW
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 4)
	panel.add_child(line)
	var name_label := Label.new()
	name_label.text = entry["label"]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(name_label)
	var value := Label.new()
	value.name = "StatValue_%s" % key
	value.custom_minimum_size.x = VALUE_COLUMN_WIDTH
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(value)
	var cell := HBoxContainer.new()
	cell.custom_minimum_size.x = DELTA_COLUMN_WIDTH
	cell.add_theme_constant_override("separation", 3)
	line.add_child(cell)
	var mark := DeltaMark.new()
	mark.name = "StatMark_%s" % key
	cell.add_child(mark)
	var delta := Label.new()
	delta.name = "StatDelta_%s" % key
	delta.theme_type_variation = WorkshopTheme.ACCENT_LABEL
	delta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_child(delta)
	_stat_rows[key] = {"panel": panel, "value": value, "delta": delta, "mark": mark}
	if entry["unit"] != "":
		name_label.text = "%s %s" % [entry["label"], entry["unit"]]
	return panel


func _make_wrapped_label(label_name: String, variation: StringName) -> Label:
	var label := Label.new()
	label.name = label_name
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = panel_width - 20.0
	return label


func _make_panel(panel_name: String, on_left: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = panel_name
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.custom_minimum_size.x = panel_width
	if on_left:
		panel.anchor_left = 0.0
		panel.anchor_right = 0.0
		panel.offset_left = panel_margin
		panel.offset_right = panel_margin + panel_width
	else:
		panel.anchor_left = 1.0
		panel.anchor_right = 1.0
		panel.offset_left = -panel_margin - panel_width
		panel.offset_right = -panel_margin
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_top = panel_margin
	panel.offset_bottom = panel_margin
	panel.grow_vertical = Control.GROW_DIRECTION_END
	_root.add_child(panel)
	return panel


func _build_tip() -> void:
	_tip = PanelContainer.new()
	_tip.name = "HoverTip"
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.visible = false
	_tip_label = Label.new()
	_tip_label.name = "HoverTipText"
	_tip.add_child(_tip_label)
	_root.add_child(_tip)


func _set_delta(key: String, delta: float) -> void:
	var row: Dictionary = _stat_rows[key]
	(row["delta"] as Label).text = StatFormat.delta_text(delta)
	(row["mark"] as DeltaMark).direction = StatFormat.delta_direction(delta)
	(row["panel"] as PanelContainer).theme_type_variation = (
		WorkshopTheme.STAT_ROW_CHANGED if StatFormat.is_changed(delta) else WorkshopTheme.STAT_ROW
	)
