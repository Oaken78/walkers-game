class_name WorkshopCourse
extends Node3D
## Test course for the workshop (T09): the real Workshop with a Scout, its starting inventory and some banked scrap,
## wired the way T12 will wire it, plus the helpers the workshop_edit scenario calls. Pointer input goes through real
## InputEvents (Input.parse_input_event), the same path the mouse takes, so panels and picking see what a player does.

## Scrap banked at the start (the scenario buys with it).
@export var start_scrap: int = 200
## Frames a button stays down in a click, so the viewport sees press and release as two frames.
@export var click_hold_frames: int = 2

var economy: Economy = Economy.new()
var inventory: Inventory = Inventory.new()
var build: WalkerBuild = WalkerBuild.scout()

## Exit signals seen and the leg count of the last one.
var exits_seen: int = 0
var exit_leg_count: int = -1
## Frames between the Tab press and exit_requested (0 = the same frame).
var exit_latency_frames: int:
	get:
		return workshop.last_exit_emit_frame - workshop.last_exit_key_frame
## Frames between the release of the last click and exit_requested (0 = the same frame): a click on Exit leaves at once.
var click_exit_latency_frames: int:
	get:
		return workshop.last_exit_emit_frame - _last_release_frame
## Frames in which the exit button's state differed from the build's validity (must stay 0).
var exit_mismatch_frames: int = 0
## Result of the last check_* call: true when everything matched, else what did not.
var check_ok: bool = false
var check_detail: String = ""

## The build handed out by the last exit_requested was the one passed to setup() and not a display copy.
var exit_same_build: bool = false
var exit_is_display: bool = false
## armed_changed signals seen (setup() emits one when it clears an armed part).
var armed_changes: int = 0
## Longest time (microseconds) one click took to handle: the motion and the press, or the release that fires a button.
var click_usec_max: int = 0
var click_usec_last: int = 0

var _snapshot: Dictionary = {}
var _last_release_frame: int = -1
var _old_economy: Economy
var _old_inventory: Inventory
var _setup_build: WalkerBuild
var _queue: Array[Dictionary] = []  # {frames, event}
var _start_position: Vector3 = Vector3.ZERO

@onready var workshop: Workshop = $Workshop

# --- Numbers the scenario asserts on -------------------------------------------------------------------------
var banked: int:
	get:
		return economy.banked_scrap
var conserved: bool:
	get:
		return economy.is_conserved()
var leg_count: int:
	get:
		return build.leg_count()
var build_valid: bool:
	get:
		return build.is_valid()
var armed: String:
	get:
		return String(workshop.armed_part)
var hover_id: String:
	get:
		return String(workshop.hover_socket)
var hover_mode_name: String:
	get:
		return Workshop.HoverMode.keys()[workshop.hover_mode]
var exit_disabled: bool:
	get:
		return workshop.ui().exit_button().disabled
var exit_reason: String:
	get:
		return workshop.ui().exit_reason_text()
var build_reason: String:
	get:
		return build.invalid_reason()
var shown_preview_line: String:
	get:
		return workshop.ui().shown_preview_line()
var shown_tip: String:
	get:
		return workshop.ui().shown_tip()
var owned_long: int:
	get:
		return inventory.owned(PartCatalog.LEG_LONG)
var spare_long: int:
	get:
		return inventory.spare(build, PartCatalog.LEG_LONG)
var spare_medium: int:
	get:
		return inventory.spare(build, PartCatalog.LEG_MEDIUM)
var owned_armor: int:
	get:
		return inventory.owned(PartCatalog.ARMOR_PLATE)
var spare_armor: int:
	get:
		return inventory.spare(build, PartCatalog.ARMOR_PLATE)
var parts_consistent: bool:
	get:
		return inventory.is_consistent(build)
var camera_paused: bool:
	get:
		return workshop.camera_rig().orbit_paused
var camera_yaw: float:
	get:
		return workshop.camera_rig().yaw_deg
var camera_pitch: float:
	get:
		return workshop.camera_rig().pitch_deg
var camera_distance: float:
	get:
		return workshop.camera_rig().distance
var cursor_visible: bool:
	get:
		return Input.mouse_mode == Input.MOUSE_MODE_VISIBLE
## Metres the walker has moved from where it stood at the start (field input must not move it).
var walker_drift: float:
	get:
		return workshop.walker().global_position.distance_to(_start_position)
var smallest_font_base_px: int:
	get:
		return workshop.ui().smallest_font_px()
var smallest_font_px_1080: float:
	get:
		return float(workshop.ui().smallest_font_px()) * WorkshopTheme.SCALE_TO_1080P
var panel_share: float:
	get:
		return workshop.ui().panel_width_share()
var max_panel_width: float:
	get:
		return maxf(workshop.ui().left_panel().size.x, workshop.ui().right_panel().size.x)
## "!" on the Load row, and the blocked-exit pulse.
var load_flag: bool:
	get:
		return workshop.ui().load_flag_visible()
var reason_pulse_left: float:
	get:
		return workshop.ui().reason_pulse_left()
var reason_pulses: int:
	get:
		return workshop.ui().reason_pulse_count()
var blocked_exits: int:
	get:
		return workshop.blocked_exit_count
var has_exited: bool:
	get:
		return workshop.has_exited()
var anchor_computes: int:
	get:
		return workshop.anchor_computes
var preview_computes: int:
	get:
		return workshop.preview_computes
## The better and worse marks, how far apart they are in luma (GDD 12: at least 0.25).
var mark_luma_gap: float:
	get:
		return WorkshopTheme.mark_luma_gap()
## The links the workshop holds on the current and on the replaced economy and inventory (must be 1 and 0).
var economy_links: int:
	get:
		return _links(economy.changed)
var inventory_links: int:
	get:
		return _links(inventory.changed)
var old_economy_links: int:
	get:
		return 0 if _old_economy == null else _links(_old_economy.changed)
var old_inventory_links: int:
	get:
		return 0 if _old_inventory == null else _links(_old_inventory.changed)
var shown_turn: String:
	get:
		return workshop.ui().shown_value("turn_rate")
var shown_slope: String:
	get:
		return workshop.ui().shown_value("max_slope")
var shown_spread: String:
	get:
		return workshop.ui().shown_value("spread")
var shown_scrap: String:
	get:
		return workshop.ui().shown_scrap()
var shown_short_owned: String:
	get:
		return workshop.ui().shown_owned(PartCatalog.LEG_SHORT)


func _ready() -> void:
	economy.pick_up("", start_scrap)
	economy.bank()
	workshop.exit_requested.connect(_on_exit_requested)
	workshop.armed_changed.connect(_on_armed_changed)
	_setup_build = build
	workshop.setup(build, inventory, economy)
	_start_position = workshop.walker().global_position


func _process(_delta: float) -> void:
	var due: Array[Dictionary] = []
	for entry in _queue:
		entry["frames"] -= 1
		if entry["frames"] <= 0:
			due.append(entry)
	for entry in due:
		_queue.erase(entry)
		_timed_dispatch(entry["event"])
	if workshop.ui().exit_button().disabled == build.is_valid():
		exit_mismatch_frames += 1


# --- Pointer helpers (real input events) ------------------------------------------------------------------------


## Moves the cursor to (x, y); `rel_x` and `rel_y` are the motion the event reports (what a drag reads).
func move_mouse(x: float, y: float, rel_x: float = 0.0, rel_y: float = 0.0) -> void:
	var moved := _motion(Vector2(x, y))
	moved.relative = get_viewport().get_final_transform().basis_xform(Vector2(rel_x, rel_y))
	_dispatch(moved)


## Presses or releases the middle button at the screen centre.
func middle_button(pressed: bool) -> void:
	_dispatch(_button(Vector2(640.0, 360.0), MOUSE_BUTTON_MIDDLE, pressed))


## Moves the cursor onto a socket's mark.
func hover_socket(socket_id: String) -> void:
	_dispatch(_motion(workshop.socket_screen_position(StringName(socket_id))))


## Clicks a socket ("left" places, "right" takes off).
func click_socket(socket_id: String, button: String = "left") -> void:
	_click(workshop.socket_screen_position(StringName(socket_id)), _button_index(button))


## Clicks a named UI control (PartBuy_leg_long, PartSelect_leg_medium, ExitButton ...) at its centre.
func click_control(control_name: String) -> void:
	var control := workshop.ui().find_control(control_name)
	if control == null:
		push_error("WorkshopCourse.click_control: no control %s" % control_name)
		return
	_click(control.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)


## Scrolls the wheel: positive notches zoom out, negative zoom in.
func wheel(notches: int) -> void:
	var index := MOUSE_BUTTON_WHEEL_DOWN if notches > 0 else MOUSE_BUTTON_WHEEL_UP
	for i in absi(notches):
		_dispatch(_button(Vector2(640.0, 360.0), index, true))
		_dispatch(_button(Vector2(640.0, 360.0), index, false))


## Drags with the middle button from the screen centre by (dx, dy) px.
func drag_middle(dx: float, dy: float) -> void:
	var start := Vector2(640.0, 360.0)
	_dispatch(_motion(start))
	_dispatch(_button(start, MOUSE_BUTTON_MIDDLE, true))
	var moved := _motion(start + Vector2(dx, dy))
	moved.relative = get_viewport().get_final_transform().basis_xform(Vector2(dx, dy))
	_dispatch(moved)
	_dispatch(_button(start + Vector2(dx, dy), MOUSE_BUTTON_MIDDLE, false))


# --- Camera -------------------------------------------------------------------------------------------------


func set_view(yaw: float, pitch: float, dist: float) -> void:
	workshop.camera_rig().set_view(yaw, pitch, dist)


## Stops the automatic orbit, so a shot is the same on every run.
func stop_orbit() -> void:
	workshop.camera_rig().auto_orbit_deg_per_s = 0.0


## Starts a new visit with the same build, inventory and economy (T12 opening the workshop again).
func reopen() -> void:
	_setup_build = build
	workshop.setup(build, inventory, economy)


## A new visit with a new economy (55 banked) and a new inventory (4 short legs owned): the workshop must let go of
## the old ones and show the new ones.
func swap_state() -> void:
	_old_economy = economy
	_old_inventory = inventory
	economy = Economy.new()
	economy.pick_up("", 55)
	economy.bank()
	inventory = Inventory.new(
		{
			PartCatalog.LEG_MEDIUM: 6,
			PartCatalog.PULSE_CANNON: 1,
			PartCatalog.LEG_SHORT: 4,
			PartCatalog.LEG_LONG: 2,
		}
	)
	reopen()


## Slides the camera look-at point until the socket mark sits on the left panel heading (a click there reaches the
## panel and presses nothing).
func shift_socket_under_panel(socket_id: String) -> void:
	var rig := workshop.camera_rig()
	var cam := rig.camera()
	var id := StringName(socket_id)
	# The "Parts" heading: inside the panel, nothing to press.
	var target := Vector2(120.0, 76.0)
	var screen_height := get_viewport().get_visible_rect().size.y
	for attempt in 8:
		var at := workshop.socket_screen_position(id)
		if at.distance_to(target) < 6.0:
			break
		var metres_per_px := 2.0 * rig.distance * tan(deg_to_rad(cam.fov * 0.5)) / screen_height
		var wanted := target - at
		var cam_basis := cam.global_transform.basis
		rig.look_at_point += (cam_basis.x * -wanted.x + cam_basis.y * wanted.y) * metres_per_px
		rig.set_view(rig.yaw_deg, rig.pitch_deg, rig.distance)
	var problems: PackedStringArray = PackedStringArray()
	var landed := workshop.socket_screen_position(id)
	if not workshop.ui().is_over_panel(landed):
		problems.append("%s is at %s, not under the panel" % [socket_id, landed])
	_finish_check(problems)


## Puts the look-at point back on the walker.
func reset_look() -> void:
	var rig := workshop.camera_rig()
	rig.look_at_point = Vector3(0.0, 0.9, 0.0)
	rig.set_view(rig.yaw_deg, rig.pitch_deg, rig.distance)


# --- Checks (what is on screen against what the rules say) -----------------------------------------------------


## The stats panel, the load line, the "!" flag and the scrap readout against WalkerBuild.stats(), each stat at its
## own decimals (whole degrees for turn and slope, two decimals for the others).
func check_stats_shown() -> void:
	var problems: PackedStringArray = PackedStringArray()
	var stats := BuildStats.of(build)
	var ui := workshop.ui()
	for entry in StatFormat.ROWS:
		var key: String = entry["key"]
		var shown_text := ui.shown_value(key)
		var want := StatFormat.value_text(key, float(stats[key]))
		var tolerance := 0.5 * pow(10.0, -float(entry["decimals"]))
		if absf(float(shown_text) - float(stats[key])) > tolerance + 0.0001:
			problems.append("%s shows %s, stats say %s" % [key, shown_text, want])
		if shown_text.length() != want.length():
			problems.append("%s shows %s, wanted the decimals of %s" % [key, shown_text, want])
	if ui.load_flag_visible() != StatFormat.is_overloaded(stats):
		problems.append(
			"the Load flag is %s at load %.2f" % [ui.load_flag_visible(), stats["load"]]
		)
	if ui.shown_load_detail() != StatFormat.load_detail(stats):
		problems.append(
			"load detail shows %s, wanted %s"
			% [ui.shown_load_detail(), StatFormat.load_detail(stats)]
		)
	if ui.shown_scrap() != str(economy.banked_scrap):
		problems.append("scrap shows %s, bank holds %d" % [ui.shown_scrap(), economy.banked_scrap])
	_finish_check(problems)


## The deltas on screen against after - before, worked out here with WalkerBuild alone (not through Inventory).
## kind is "place" (socket, part) or "remove" (socket).
func check_delta_shown(kind: String, socket_id: String, part_id: String = "") -> void:
	var problems: PackedStringArray = PackedStringArray()
	var before := BuildStats.of(build)
	var scratch := build.copy()
	var socket := StringName(socket_id)
	var mirror := Inventory.mirror_of(socket)
	if kind == "place":
		scratch.place(socket, StringName(part_id))
		if mirror != &"":
			scratch.place(mirror, StringName(part_id))
	else:
		scratch.remove(socket)
		if mirror != &"":
			scratch.remove(mirror)
	var after := BuildStats.of(scratch)
	var ui := workshop.ui()
	var changed_rows := 0
	for entry in StatFormat.ROWS:
		var key: String = entry["key"]
		var expected := float(after[key]) - float(before[key])
		var text := ui.shown_delta(key)
		var step := pow(10.0, -float(entry["decimals"]))
		if absf(snappedf(expected, step)) < step * 0.5:
			if text != "":
				problems.append("%s shows delta %s, none expected" % [key, text])
			continue
		changed_rows += 1
		if text == "":
			problems.append("%s shows no delta, expected %.3f" % [key, expected])
			continue
		if absf(float(text) - snappedf(expected, step)) > step * 0.5 + 0.0001:
			problems.append("%s delta shows %s, expected %.3f" % [key, text, expected])
		# The delta has the decimals of the stat's value.
		var decimals_shown := text.length() - text.find(".") - 1 if "." in text else 0
		if decimals_shown != int(entry["decimals"]):
			problems.append("%s delta %s has the wrong decimals" % [key, text])
		if ui.shown_delta_direction(key) != (1 if expected > 0.0 else -1):
			problems.append("%s mark points the wrong way" % key)
	if changed_rows == 0:
		problems.append("no stat changes at all, the preview is empty")
	_finish_check(problems)


## The better/worse marks on screen against what the polarity table says. `expected` maps a stats key to "better",
## "worse" or "none"; keys it does not list are not checked.
func check_delta_quality(expected: Dictionary) -> void:
	var problems: PackedStringArray = PackedStringArray()
	var ui := workshop.ui()
	var names := {1: "better", -1: "worse", 0: "none"}
	for key: String in expected:
		var got: String = names[ui.shown_delta_quality(key)]
		if got != expected[key]:
			problems.append("%s is marked %s, expected %s" % [key, got, expected[key]])
	_finish_check(problems)


## Remembers the work counters (anchors, previews, armed_changed) for check_counters.
func snapshot_counters() -> void:
	_snapshot = {
		"anchor_computes": workshop.anchor_computes,
		"preview_computes": workshop.preview_computes,
		"armed_changes": armed_changes,
	}


## Compares the counters with the snapshot: `expected` maps a counter to how much it must have grown since.
func check_counters(expected: Dictionary) -> void:
	var problems: PackedStringArray = PackedStringArray()
	var now := {
		"anchor_computes": workshop.anchor_computes,
		"preview_computes": workshop.preview_computes,
		"armed_changes": armed_changes,
	}
	for counter: String in expected:
		var grew: int = now[counter] - _snapshot[counter]
		if grew != int(expected[counter]):
			problems.append("%s grew by %d, expected %d" % [counter, grew, expected[counter]])
	_finish_check(problems)


## No delta shown anywhere.
func check_no_deltas() -> void:
	var problems: PackedStringArray = PackedStringArray()
	for entry in StatFormat.ROWS:
		var text := workshop.ui().shown_delta(entry["key"])
		if text != "":
			problems.append("%s still shows delta %s" % [entry["key"], text])
	_finish_check(problems)


## Prints the numbers a readability measurement needs: where the hovered ring is and how big.
func report_ring(socket_id: String) -> void:
	var at := workshop.socket_screen_position(StringName(socket_id))
	var radius := workshop.marker_radius_px(StringName(socket_id))
	print("RING %s at (%d, %d) radius %.1f px" % [socket_id, at.x, at.y, radius])


func report_clicks() -> void:
	var slowest := float(click_usec_max) / 1000.0
	print("CLICK slowest %.2f ms, last %.2f ms" % [slowest, float(click_usec_last) / 1000.0])


func report_layout() -> void:
	var ui := workshop.ui()
	print(
		"LAYOUT left=%.0f right=%.0f share=%.4f smallest_font=%d px (%.1f px at 1080p)"
		% [
			ui.left_panel().size.x,
			ui.right_panel().size.x,
			ui.panel_width_share(),
			ui.smallest_font_px(),
			float(ui.smallest_font_px()) * WorkshopTheme.SCALE_TO_1080P,
		]
	)


# --- Private ---------------------------------------------------------------------------------------------------


func _on_exit_requested(exited: WalkerBuild) -> void:
	exits_seen += 1
	exit_leg_count = exited.leg_count()
	exit_same_build = exited == _setup_build
	exit_is_display = exited.get_script() != WalkerBuild


func _on_armed_changed(_part_id: StringName) -> void:
	armed_changes += 1


## How many connections of `changed_signal` end in the workshop.
func _links(changed_signal: Signal) -> int:
	var count := 0
	for link in changed_signal.get_connections():
		if (link["callable"] as Callable).get_object() == workshop:
			count += 1
	return count


## Runs a dispatch and keeps the time it took (microseconds): the click path from the event to the redrawn UI state.
func _timed_dispatch(event: InputEvent) -> void:
	var release := event as InputEventMouseButton
	if release != null and not release.pressed:
		_last_release_frame = Engine.get_process_frames()
	var started := Time.get_ticks_usec()
	_dispatch(event)
	click_usec_last = Time.get_ticks_usec() - started
	click_usec_max = maxi(click_usec_max, click_usec_last)


func _finish_check(problems: PackedStringArray) -> void:
	check_ok = problems.is_empty()
	check_detail = "; ".join(problems)
	if not check_ok:
		print("CHECK FAILED: ", check_detail)


func _click(pos: Vector2, index: MouseButton) -> void:
	_timed_dispatch(_motion(pos))
	_timed_dispatch(_button(pos, index, true))
	_queue.append({"frames": click_hold_frames, "event": _button(pos, index, false)})


func _button_index(button: String) -> MouseButton:
	if button == "right":
		return MOUSE_BUTTON_RIGHT
	return MOUSE_BUTTON_LEFT


## Input events arrive in window pixels and the viewport maps them back through its final transform (the stretch),
## so a point given in viewport coordinates is sent as its window point. In a 1280x720 window the two are the same;
## a headless window is not, and this keeps the scenario the same in both.
func _window_point(viewport_point: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * viewport_point


func _motion(pos: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.device = InputEvent.DEVICE_ID_MOUSE
	event.position = _window_point(pos)
	event.global_position = event.position
	return event


func _button(pos: Vector2, index: MouseButton, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.device = InputEvent.DEVICE_ID_MOUSE
	event.position = _window_point(pos)
	event.global_position = event.position
	event.button_index = index
	event.pressed = pressed
	return event


func _dispatch(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func report_state() -> void:
	print(
		"STATE armed=%s hover=%s mode=%s reason=%s legs=%d spare_long=%d pos=%s mouse_over_panel=%s"
		% [
			armed,
			hover_id,
			hover_mode_name,
			workshop.hover_reason,
			leg_count,
			spare_long,
			workshop.socket_screen_position(&"leg_l3"),
			workshop.ui().is_over_panel(workshop.socket_screen_position(&"leg_l3")),
		]
	)
