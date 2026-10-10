class_name Workshop
extends Node3D
## The workshop (GDD 8.6, 12): the walker on a stand, a camera circling it, the part list and stat panel. Pick a part,
## hover a socket and every stat shows its change before you place it; LMB places, RMB takes a part off, Tab (or the
## button) leaves while the build is valid. It does not assume it is the main scene.
##
## For T12:
##   workshop.setup(build, inventory, economy)   # edits `build` and `inventory` in place; `economy` pays for parts
##   workshop.exit_requested.connect(func(build: WalkerBuild) -> void: ...)   # the very `build` passed to setup()
## - exit_requested fires once per visit. From then on the workshop ignores input (keys, clicks, the buttons, the
##   camera) until the next setup(), so a second Tab or a click while T12 fades out changes nothing.
## - It sets the mouse visible in setup() and never touches the mouse mode again; T12 captures it when the field starts.
## - It brings its own Camera3D (made current), two DirectionalLight3Ds and a WorldEnvironment. Once the visit is over
##   T12 must free the workshop, or set `process_mode = PROCESS_MODE_DISABLED`, hide it and make its own camera
##   current: an unused workshop would still own the current camera and the environment.
## - The workshop owns its walker (%Walker, set to ignore field input for good in _ready): never put the field walker in
##   it, and never reuse the workshop walker in the field.
## - The workshop never changes scenes, banks scrap or repairs.

## The player pressed Tab or the exit button on a valid build.
signal exit_requested(build: WalkerBuild)
## A part was placed or taken off (the build changed).
signal build_changed
## The armed part changed (empty means nothing armed), including when setup() clears it.
signal armed_changed(part_id: StringName)

enum HoverMode { NONE, IDLE, PLACE, REMOVE, BLOCKED }

## How close (px at the 1280 base) the cursor must be to a socket to pick it.
@export var pick_radius_px: float = 36.0

## The armed part (empty: none). Read-only from outside; use arm().
var armed_part: StringName = &""
## The socket under the cursor (empty: none) and what a click there would do.
var hover_socket: StringName = &""
var hover_mode: HoverMode = HoverMode.NONE
var hover_reason: String = ""
## Inventory.preview() of the hovered place or remove.
var hover_preview: Dictionary = {}
## Frames (Engine.get_process_frames) of the last exit key press and of the last exit_requested, for the 1-frame check.
var last_exit_key_frame: int = -1
var last_exit_emit_frame: int = -1
## Work counters the scenario reads: anchors and previews are computed only when something changed.
var anchor_computes: int = 0
var preview_computes: int = 0
## Exit attempts while the build was invalid (each one pulses the reason).
var blocked_exit_count: int = 0

var _build: WalkerBuild
var _inventory: Inventory
var _economy: Economy
var _anchors: Dictionary = {}
var _anchor_armed: StringName = &""
var _anchor_version: int = -1
var _anchor_pose: Transform3D = Transform3D()
var _markers: Dictionary = {}  # socket id -> SocketMarker
var _mouse_pos: Vector2 = Vector2.ZERO
var _ready_done: bool = false
var _exited: bool = false
var _replant_pending: bool = true
var _build_version: int = 0
var _hover_signature: String = ""

@onready var _walker: WalkerBody = %Walker
@onready var _camera: WorkshopCamera = %OrbitRig
@onready var _ui: WorkshopUI = %UI
@onready var _markers_root: Node3D = %Markers


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_walker.input_enabled = false
	# The chassis and the tops get render layer 2, the layer the camera body light lights (legs stay on layer 1 only).
	_walker.body_layer_mask = WorkshopCamera.BODY_LAYER_MASK
	for socket in PartCatalog.chassis_sockets(PartCatalog.CHASSIS_MEDIUM):
		var marker := SocketMarker.new()
		marker.name = "Marker_%s" % socket["id"]
		_markers_root.add_child(marker)
		_markers[socket["id"]] = marker
	_ui.part_selected.connect(_on_part_selected)
	_ui.buy_pressed.connect(_on_buy_pressed)
	_ui.exit_pressed.connect(request_exit)
	_ui.exit_blocked_pressed.connect(_on_exit_blocked)
	_mouse_pos = get_viewport().get_mouse_position()
	_ready_done = true
	if _build != null:
		_start()


func _physics_process(_delta: float) -> void:
	# A static body added in the same frame cannot be raycast yet: seat the feet once more on the first tick.
	if _replant_pending and _build != null:
		_replant_pending = false
		_apply_build_to_walker()


func _process(_delta: float) -> void:
	if _build == null or _exited:
		return
	_refresh_anchors()
	_update_hover()
	_update_markers()
	_camera.orbit_paused = hover_socket != &"" or _ui.is_over_panel(_mouse_pos)


func _input(event: InputEvent) -> void:
	if _exited:
		return
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_mouse_pos = (event as InputEventMouse).position
	if event.is_action_pressed("build_exit"):
		last_exit_key_frame = Engine.get_process_frames()
		request_exit()
		get_viewport().set_input_as_handled()


## LMB places the armed part on the socket under the cursor, RMB takes the part off it. Clicks on a panel are
## consumed by the panel and never get here.
func _unhandled_input(event: InputEvent) -> void:
	if _build == null or _exited:
		return
	if event.is_action_pressed("build_place"):
		place_on(_pick_socket(_mouse_pos))
	elif event.is_action_pressed("build_remove"):
		remove_from(_pick_socket(_mouse_pos))


# --- Public API (T12 and the scenarios) -----------------------------------------------------------------------


## Starts a workshop visit (and ends the latch of the one before). `build` and `inventory` are edited in place;
## `economy` pays for purchases. Calling it again moves every connection to the new economy and inventory.
func setup(build: WalkerBuild, inventory: Inventory, economy: Economy) -> void:
	_disconnect_sources()
	_build = build
	_inventory = inventory
	_economy = economy
	_economy.changed.connect(_on_economy_changed)
	_inventory.changed.connect(_refresh_all)
	_exited = false
	_build_version += 1
	_replant_pending = true
	if armed_part != &"":
		armed_part = &""
		armed_changed.emit(armed_part)
	if _ready_done:
		_start()


func current_build() -> WalkerBuild:
	return _build


## True once exit_requested has fired, until the next setup().
func has_exited() -> bool:
	return _exited


func is_exit_enabled() -> bool:
	return _build != null and not _exited and _build.is_valid()


## Emits exit_requested(build) when the build is valid, once per visit. While the build is not valid nothing is
## emitted and the reason pulses instead.
func request_exit() -> void:
	if _build == null or _exited:
		return
	if not _build.is_valid():
		_on_exit_blocked()
		return
	_latch()
	last_exit_emit_frame = Engine.get_process_frames()
	exit_requested.emit(_build)


## Arms a part for placing (empty disarms). Arming the armed part again disarms it.
func arm(part_id: StringName) -> void:
	if _exited:
		return
	if part_id == armed_part:
		part_id = &""
	armed_part = part_id
	armed_changed.emit(armed_part)
	_refresh_all()


## Buys the part (a leg pair, or one top part) out of the bank and arms it.
func buy(part_id: StringName) -> bool:
	if _exited or not _inventory.buy(part_id, _economy):
		return false
	armed_part = part_id
	armed_changed.emit(armed_part)
	_refresh_all()
	return true


## Mounts the armed part on a socket (a leg also on its mirror).
func place_on(socket_id: StringName) -> bool:
	if _exited or socket_id == &"" or armed_part == &"":
		return false
	if not _inventory.mount(_build, socket_id, armed_part):
		return false
	_after_edit()
	return true


## Takes the part off a socket (a leg takes its mirror off too). The part goes back to the spare stock.
func remove_from(socket_id: StringName) -> bool:
	if _exited or socket_id == &"" or not _inventory.unmount(_build, socket_id):
		return false
	_after_edit()
	return true


func camera_rig() -> WorkshopCamera:
	return _camera


func walker() -> WalkerBody:
	return _walker


func ui() -> WorkshopUI:
	return _ui


## Screen position (px) of a socket's mark, or (-1, -1) when the camera cannot see it.
func socket_screen_position(socket_id: StringName) -> Vector2:
	if not _anchors.has(socket_id):
		return Vector2(-1.0, -1.0)
	var cam := _camera.camera()
	var at: Vector3 = _anchors[socket_id]["pos"]
	if cam.is_position_behind(at):
		return Vector2(-1.0, -1.0)
	return cam.unproject_position(at)


## Radius (px) of the ring drawn at a socket, from the marker size and the camera.
func marker_radius_px(socket_id: StringName) -> float:
	if not _anchors.has(socket_id):
		return 0.0
	var cam := _camera.camera()
	var at: Vector3 = _anchors[socket_id]["pos"]
	var marker: SocketMarker = _markers[socket_id]
	var world_radius := marker.quad_size * 0.5 * SocketMarker.HOVER_RADIUS
	var edge: Vector3 = at + cam.global_transform.basis.x * world_radius
	return cam.unproject_position(edge).distance_to(cam.unproject_position(at))


func marker_state(socket_id: StringName) -> SocketMarker.State:
	return (_markers[socket_id] as SocketMarker).state


func is_socket_pickable(socket_id: StringName) -> bool:
	return _anchors.has(socket_id) and _faces_camera(_anchors[socket_id])


# --- Private -------------------------------------------------------------------------------------------------


func _start() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_camera.input_enabled = true
	# The cursor may have moved while the workshop was latched and ignoring input: no stale hover from the last visit.
	_mouse_pos = get_viewport().get_mouse_position()
	_ui.setup(_inventory, _economy)
	_apply_build_to_walker()
	_refresh_all()


## After exit_requested: no more input, no more work, nothing shown, until the next setup().
func _latch() -> void:
	_exited = true
	_camera.input_enabled = false
	_camera.orbit_paused = true
	_ui.show_tip("", _mouse_pos)
	hover_socket = &""
	hover_mode = HoverMode.NONE
	hover_reason = ""
	hover_preview = {}
	_hover_signature = ""
	_ui.clear_deltas("")
	for id: StringName in _markers:
		(_markers[id] as SocketMarker).set_state(SocketMarker.State.HIDDEN)


func _disconnect_sources() -> void:
	if _economy != null and _economy.changed.is_connected(_on_economy_changed):
		_economy.changed.disconnect(_on_economy_changed)
	if _inventory != null and _inventory.changed.is_connected(_refresh_all):
		_inventory.changed.disconnect(_refresh_all)


func _on_economy_changed() -> void:
	_refresh_all()


func _on_part_selected(part_id: StringName) -> void:
	arm(part_id)


func _on_buy_pressed(part_id: StringName) -> void:
	buy(part_id)


## Tab or a click on the disabled exit while the build is invalid: the reason pulses.
func _on_exit_blocked() -> void:
	if _exited or _build == null or _build.is_valid():
		return
	blocked_exit_count += 1
	_ui.pulse_reason()


func _after_edit() -> void:
	_build_version += 1
	_apply_build_to_walker()
	build_changed.emit()
	_refresh_all()


func _apply_build_to_walker() -> void:
	# The workshop draws what the player built, valid or not.
	_walker.apply_build(_build, true)
	_refresh_anchors(true)


## Socket anchors and the marks' places are worked out again only when the build, the armed part or the walker's pose
## changed, not every frame.
func _refresh_anchors(force: bool = false) -> void:
	var pose := _walker.body_pose()
	if (
		not force
		and _anchor_version == _build_version
		and _anchor_armed == armed_part
		and _anchor_pose == pose
	):
		return
	_anchor_version = _build_version
	_anchor_armed = armed_part
	_anchor_pose = pose
	_anchors = _compute_anchors()
	anchor_computes += 1
	for id: StringName in _markers:
		(_markers[id] as SocketMarker).global_position = _anchors[id]["pos"]


## World-space place, outward normal, kind and mounted flag of every socket, from the walker's own socket_transform.
func _compute_anchors() -> Dictionary:
	var anchors: Dictionary = {}
	for socket in PartCatalog.chassis_sockets(_build.chassis_id):
		var id: StringName = socket["id"]
		var local: Transform3D = _walker.socket_transform(id, armed_part)
		var pose := _walker.body_pose()
		anchors[id] = {
			"pos": pose * local.origin,
			"normal": (pose.basis * local.basis.y).normalized(),
			"kind": socket["kind"],
			"mounted": _build.part_at(id) != &"",
		}
	return anchors


func _refresh_all() -> void:
	if _build == null or not _ready_done:
		return
	_ui.show_stats(BuildStats.of(_build))
	_ui.refresh_scrap()
	_ui.refresh_parts(_build, armed_part)
	_ui.set_exit(_build.is_valid(), _build.invalid_reason())
	_hover_signature = ""
	if not _exited:
		_update_hover()


func _pick_socket(pos: Vector2) -> StringName:
	if _ui.is_over_panel(pos):
		return &""
	var cam := _camera.camera()
	var best: StringName = &""
	var best_distance := pick_radius_px
	for id: StringName in _anchors:
		var anchor: Dictionary = _anchors[id]
		if cam.is_position_behind(anchor["pos"]) or not _faces_camera(anchor):
			continue
		var distance := cam.unproject_position(anchor["pos"]).distance_to(pos)
		if distance < best_distance:
			best_distance = distance
			best = id
	return best


## Sockets on the far side of the walker are not picked (the near ones are in front).
func _faces_camera(anchor: Dictionary) -> bool:
	var to_camera: Vector3 = _camera.camera().global_position - anchor["pos"]
	return (anchor["normal"] as Vector3).dot(to_camera) > 0.0


## The socket under the cursor is picked every frame (the camera moves); what a click there would do, and its stat
## preview, are worked out only when the pick, the armed part or the build changed.
func _update_hover() -> void:
	var hit := _pick_socket(_mouse_pos)
	var signature := "%s|%s|%d" % [hit, armed_part, _build_version]
	if signature != _hover_signature:
		_hover_signature = signature
		_compute_hover(hit)
		_show_hover_in_ui()
	_ui.show_tip(_tip_text(), _mouse_pos)


func _compute_hover(hit: StringName) -> void:
	hover_socket = hit
	hover_reason = ""
	hover_preview = {}
	if hover_socket == &"":
		hover_mode = HoverMode.NONE
	elif _build.part_at(hover_socket) != &"":
		hover_mode = HoverMode.REMOVE
		hover_preview = _inventory.preview(_build, hover_socket)
		preview_computes += 1
	elif armed_part == &"":
		hover_mode = HoverMode.IDLE
	else:
		hover_reason = _inventory.mount_reason(_build, hover_socket, armed_part)
		if hover_reason == "":
			hover_mode = HoverMode.PLACE
			hover_preview = _inventory.preview(_build, hover_socket, armed_part)
			preview_computes += 1
		else:
			hover_mode = HoverMode.BLOCKED


func _show_hover_in_ui() -> void:
	match hover_mode:
		HoverMode.PLACE:
			_ui.show_deltas(
				hover_preview["delta"],
				"Place %s on %s" % [_part_label(armed_part), _socket_label(hover_socket)],
				hover_preview["invalid_reason_after"]
			)
		HoverMode.REMOVE:
			_ui.show_deltas(
				hover_preview["delta"],
				(
					"Take off %s from %s"
					% [_part_label(_build.part_at(hover_socket)), _socket_label(hover_socket)]
				),
				hover_preview["invalid_reason_after"]
			)
		HoverMode.BLOCKED:
			_ui.clear_deltas(hover_reason)
		HoverMode.IDLE:
			_ui.clear_deltas("Pick a part to place on %s" % _socket_label(hover_socket))
		_:
			_ui.clear_deltas(_idle_hint())


func _tip_text() -> String:
	match hover_mode:
		HoverMode.PLACE:
			return "LMB: place"
		HoverMode.REMOVE:
			return "RMB: take off"
		HoverMode.BLOCKED:
			return hover_reason
		HoverMode.IDLE:
			return "Pick a part first"
	return ""


func _idle_hint() -> String:
	if armed_part == &"":
		return "Pick a part, then hover a socket"
	var short := _inventory.spare_reason(_build, armed_part)
	if short != "":
		return short
	return "Hover a socket to place %s" % _part_label(armed_part)


func _update_markers() -> void:
	var live: Array[StringName] = []
	if hover_mode in [HoverMode.PLACE, HoverMode.REMOVE, HoverMode.BLOCKED]:
		live.append(hover_socket)
		var mirror := Inventory.mirror_of(hover_socket)
		var mirror_shown := hover_mode != HoverMode.BLOCKED or hover_reason.begins_with("Mirror")
		if mirror != &"" and mirror_shown:
			live.append(mirror)
	var armed_kind := PartCatalog.socket_kind(armed_part)
	for id: StringName in _markers:
		var marker: SocketMarker = _markers[id]
		var anchor: Dictionary = _anchors[id]
		var state := SocketMarker.State.HIDDEN
		if id in live:
			state = SocketMarker.State.HOVER
			if hover_mode == HoverMode.BLOCKED:
				state = SocketMarker.State.BLOCKED
		elif id == hover_socket:
			state = SocketMarker.State.AVAILABLE
		elif not anchor["mounted"] and _faces_camera(anchor):
			if armed_part == &"":
				state = SocketMarker.State.DOT
			elif anchor["kind"] == armed_kind:
				state = SocketMarker.State.AVAILABLE
		if marker.state != state:
			marker.set_state(state)


func _part_label(part_id: StringName) -> String:
	var data: Dictionary = PartCatalog.PARTS[part_id]
	var label: String = data["display_name"]
	if data["socket"] == PartCatalog.KIND_LEG:
		label += " pair"
	return label


## "Left leg 3", "Right leg 1", "Top 2".
func _socket_label(socket_id: StringName) -> String:
	var text := String(socket_id)
	var row := int(text.right(1)) + 1
	if text.begins_with("leg_l"):
		return "left leg %d" % row
	if text.begins_with("leg_r"):
		return "right leg %d" % row
	return "top %d" % row
