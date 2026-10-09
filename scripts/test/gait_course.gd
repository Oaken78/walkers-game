class_name GaitCourse
extends Node3D
## The gait test course (T03): flat, bumps, ledges, wall and pocket lanes on one big ground plane, built in code
## from a fixed seed, plus the helpers the scenarios call (use_build, spawn_at, hold_action, record_result,
## show_pair, autopilot, camera modes, yaw source). The scripted shot cameras (follow, pair, side, crest) stay for the
## baselines; T04's OrbitCamera is the play camera (T14 gate rig): it follows the walker node itself, which sits at the
## un-bobbed base height, so the 2.8 Hz body bob never reaches the view. Run without a scenario (F6) for free play.

const WALKER_SCENE: PackedScene = preload("res://scenes/walker/walker.tscn")
const GROUND_COLOR: Color = Color("CAB294")
const LANE_FLAT: String = "flat"
const LANE_BUMPS: String = "bumps"
const LANE_LEDGES: String = "ledges"
const LANE_WALL: String = "wall"
const LANE_POCKET: String = "pocket"
const LANE_PATCH_A: String = "patch_a"
const LANE_TALUS: String = "talus"
const LANE_X: Dictionary = {
	"flat": 0.0, "bumps": 60.0, "ledges": 120.0, "wall": 180.0, "pocket": 240.0, "talus": 300.0
}
## Half-width of the area each lane is meant to be driven in (edge margins are measured against it).
const LANE_HALF_WIDTH: Dictionary = {
	"flat": 20.0, "bumps": 15.0, "ledges": 5.0, "wall": 10.0, "pocket": 10.0, "talus": 6.0
}
const FLAT_LENGTH: float = 150.0
const FLAT_STRIPE: float = 2.0
const BUMP_LENGTH: float = 100.0
const BUMP_WIDTH: float = 30.0
const BUMP_CELL: float = 0.5
## Rolling hills: peak-to-peak height and wavelength (the short-legged builds cap the usable amplitude).
const HILL_P2P: float = 1.0
const HILL_FREQUENCY: float = 0.1
const HILL_NOISE_RANGE: float = 0.8
const PATCH_A_DEG: float = 29.0
## The talus lane copies ValleyLayout.talus_y: flat apron, sharp corner, 40 degrees for 4.9 m, sharp edge, flat shelf.
const TALUS_CORNER_ALONG: float = 14.0
const TALUS_LENGTH: float = 32.0
const TALUS_HALF_WIDTH: float = (ValleyLayout.TALUS_Z1 - ValleyLayout.TALUS_Z0) * 0.5
const PATCH_FLANK: float = 2.4
## Radius of the rounded crest of the steep patches (m).
const PATCH_CREST_ROUNDING: float = 0.6
## Measured trim so the 2 m disc average at the flank centre lands on the patch slope (28-30 / 40).
const PATCH_STEEPNESS_TRIM: float = 1.0585
const PATCH_HALF_WIDTH: float = 3.5
const PATCH_X: float = 10.5
const PATCH_ALONG: float = 45.0
## Two swells across the whole lane (steady slope the plane fit tilts to; every build can cross them).
const SWELLS_ALONG: Array[float] = [28.0, 62.0]
## Smooth cosine swells: crest height and half-length (steepest flank = crest x PI / (2 x half-length) = ~21 deg).
const SWELL_CREST: float = 0.88
const SWELL_FLANK: float = 3.6
## Boulders (0.3-0.9 m high) fill a strip right of the centre line: a Strider run along it goes through the field.
const BOULDER_COUNT: int = 30
const BOULDER_X_MIN: float = 5.5
const BOULDER_X_MAX: float = 8.5
## A 1.05 m block face on the crest of the second swell (hills 62 m down the lane), driven into along the crest.
const CREST_ALONG: float = 62.0
const CREST_FACE_X: float = 6.0
const CREST_BLOCK_TOP: float = 2.5
const LEDGE_WIDTH: float = 10.0
const LEDGE_FLAT_RUN: float = 6.0
const LEDGE_DECK_DEPTH: float = 6.0
const LEDGE_FIRST_HEIGHT: float = 0.30
const LEDGE_HEIGHT_STEP: float = 0.05
const LEDGE_COUNT: int = 16
const POCKET_HEIGHT: float = 0.8
const WALL_Z: float = -14.0
const WALL_HEIGHT: float = 1.5
const WALL_WIDTH: float = 20.0
const SPAWN_Z: float = -2.0
const SPAWN_Y: float = 1.5
## Side-on camera height above the body (about 12 degrees of pitch at 8 m: lifted pads clear of their neighbours).
## The crest camera looks this far above its own eye height (the body and hips sit above the eye).
const CREST_LOOK_RISE: float = 0.25
const SIDE_CAMERA_HEIGHT: float = 2.0
const SUN_ELEVATION_DEG: float = 60.0
const SUN_AZIMUTH_DEG: float = 25.0
const CAMERA_PITCH_DEG: float = 25.0
const CAMERA_AZIMUTH_DEG: float = 20.0
const TERRAIN_SEED: int = 99
const AUTOPILOT_PERIOD_S: float = 8.0
const AUTOPILOT_CENTERING: float = 0.12
const AUTOPILOT_DEAD_DEG: float = 3.0

@export var camera_distance: float = 8.0
## Key list shown in the free-play label (kept next to the key handling below).
@export_multiline var help_text: String = (
	"W/S drive   A/D turn   Q/E strafe   mouse look   wheel zoom   RMB aim\n"
	+ "T  steer mode TANK <-> CAMERA_YAW\n"
	+ "1 Scout  2 Strider  3 Crawler  4 Quad  5 Short-pair Scout\n"
	+ "F1 flat  F2 bumps  F3 talus (40 deg)  F4 ledges  F5 29 deg slope  F6 wall  F7 pocket  R respawn\n"
	+ "Esc frees the mouse, click captures it again"
)
## Foot box limit (GDD 10 rule 1): every foot at least this tall at 1080p (checked by the pitch scenarios).
@export var min_foot_px_1080: float = 12.0

## The lowest visible-sight-line count (0..5) over all pads at the last log_foot_vis call (chassis and terrain only).
var min_foot_vis: int = 5

## Mean slope of the two steep patches over a 2 m disc, in degrees (28-30 and 35-40).
var patch_a_slope_deg: float = 0.0
## Slope of the talus lane between its corner and its edge (measured from the built heights).
var talus_slope_deg: float = 0.0
var a_speed: float = 0.0
var a_step_up: float = 0.0
var b_speed: float = 0.0
var b_step_up: float = 0.0
var contrast_speed: float = 0.0
var contrast_step_up: float = 0.0
var autopilot_amplitude_deg: float = 35.0
var yaw_overshoot_deg: float = 0.0
## Straight-line distance the walker has travelled since mark().
var moved_since_mark: float:
	get:
		return _walker.global_position.distance_to(_mark) if _walker != null else 0.0
## Distance in front of the wall face (wall lane).
var wall_gap: float:
	get:
		return _walker.global_position.z - (WALL_Z + 0.5) if _walker != null else 0.0
## Yaw error to the yaw source in degrees (CAMERA_YAW checks).
var yaw_error_deg: float:
	get:
		if _walker == null or _steer_source() == null:
			return 0.0
		return rad_to_deg(wrapf(_yaw_target() - _walker.yaw_radians(), -PI, PI))
## Distance from the walker to the nearest edge of the current lane's driving area.
var edge_margin_m: float:
	get:
		return _edge_margin()
## True when the walker has not passed the face of the first ledge block it cannot climb.
var stopped_before_face: bool:
	get:
		return _stopped_before_face()
## Every foot is past the back face of the pocket block.
var past_pocket: bool:
	get:
		return _all_feet_beyond(_pocket_back_z - 0.5)
## The walker (body and every foot) has not reached the block face on the crest.
var stopped_before_crest_block: bool:
	get:
		if _walker == null or _lane != "crest":
			return false
		var face: float = LANE_X[LANE_BUMPS] + CREST_FACE_X
		if _walker.global_position.x >= face:
			return false
		for i in _walker.leg_count():
			if _walker.foot_position(i).x >= face:
				return false
		return true
## Every foot is past the far side of the 29 degree patch (A) or the 38 degree patch (B).
var past_patch: bool:
	get:
		if _lane == LANE_TALUS:
			return _all_feet_beyond(-(TALUS_CORNER_ALONG + ValleyLayout.TALUS_SLOPE_LEN) - 0.2)
		return _all_feet_beyond(-(PATCH_ALONG + PATCH_FLANK) - 0.5)
## Every foot is in front of the wall face (a foot behind a thin wall means a ray started above it).
var feet_before_wall: bool:
	get:
		if _walker == null or _walker.gait() == null:
			return false
		for i in _walker.leg_count():
			if _walker.foot_position(i).z <= WALL_Z + 0.5:
				return false
		return true
## Distance from the walker to the foot of the patch flank (positive while still in front of it).
var patch_gap: float:
	get:
		if _walker == null:
			return 0.0
		if _lane == LANE_TALUS:
			return _walker.global_position.z + TALUS_CORNER_ALONG
		return _walker.global_position.z + (PATCH_ALONG - PATCH_FLANK)
## True while the orbit camera recentres behind the walker (a spawn restores it after an abeam view).
var orbit_recentering: bool:
	get:
		return _orbit.recenter_enabled
## True when the walker steers by the orbit camera (CAMERA_YAW with the rig as its yaw source).
var steers_by_orbit: bool:
	get:
		return _walker.yaw_source == _orbit and _walker.steer_mode == WalkerBody.SteerMode.CAMERA_YAW
## True while the orbit camera is the play camera.
var orbit_active: bool:
	get:
		return _camera_mode == "orbit"
## "TANK" or "CAMERA_YAW".
var steer_mode_name: String:
	get:
		return "CAMERA_YAW" if _walker.steer_mode == WalkerBody.SteerMode.CAMERA_YAW else "TANK"
## Peak-to-peak height of the play camera since track_camera_bob(true) (m).
var camera_bob_p2p_m: float:
	get:
		return _cam_y_max - _cam_y_min if _cam_y_max >= _cam_y_min else 0.0
## Height of the play camera above the ground straight below it (m).
var camera_height_m: float:
	get:
		return _camera_height()
## Tilt of the walker body from level (degrees).
var tilt_deg: float:
	get:
		return _walker.tilt_degrees()
## Every foot box is inside the viewport (and in front of the camera).
var feet_in_frame: bool:
	get:
		return _feet_in_frame()
## Smallest foot box height over all feet, scaled to a 1080 p tall viewport (px).
var foot_min_height_px: float:
	get:
		return _foot_min_height()
## Steps per leg per second of the reference run (record_steps_ref) and the current run's ratio to it.
var steps_ref: float = 0.0
var steps_ratio: float:
	get:
		return _telemetry.steps_per_s / steps_ref if steps_ref > 0.0 else 0.0

## Frame times (ms between consecutive _process calls) since track_frames(true): in the fixed-step test runs
## that is the work per frame. Used for the boulder lag gate (no frame over 16.7 ms while walking).
var frame_max_ms: float:
	get:
		return _frame_ms_max
var frame_p95_ms: float:
	get:
		return _frame_percentile(0.95)

var _walker: WalkerBody
var _telemetry: WalkerTelemetry
var _camera: Camera3D
var _pair_walker: WalkerBody
var _lane: String = LANE_FLAT
var _mark: Vector3 = Vector3.ZERO
var _blocks: Dictionary = {}
var _last_plant: PackedVector3Array = PackedVector3Array()
var _ground_material: StandardMaterial3D
var _block_material: StandardMaterial3D
var _wall_material: StandardMaterial3D
var _stripe_material: StandardMaterial3D
var _boulder_material: StandardMaterial3D
var _noise: FastNoiseLite
var _first_tick: bool = true
var _sun: DirectionalLight3D
var _freeze_at: float = -1.0
var _freeze_tilt: float = -1.0
var _freeze_tick: int = -1
var _tick: int = 0
var _track_clearance: bool = false
## Tick (since spawn_at) and value of the lowest hip clearance seen while tracking.
var clearance_tick: int = -1
var clearance_min: float = INF
var _clearance_first: int = -1
var _camera_mode: String = "follow"
var _orbit: OrbitCamera
var _free_play: bool = false
var _hud_label: Label
var _track_camera: bool = false
var _cam_y_min: float = INF
var _cam_y_max: float = -INF
var _cam_samples: int = 0
var _autopilot: bool = false
var _autopilot_time: float = 0.0
var _autopilot_center: float = 0.0
var _yaw_source: Node3D
var _spawn_offset: float = 0.0
var _yaw_start_sign: float = 0.0
var _pocket_back_z: float = 0.0
var _track_frames: bool = false
var _frame_last_usec: int = 0
var _frame_ms: PackedFloat32Array = PackedFloat32Array()
var _frame_ms_max: float = 0.0


func _ready() -> void:
	process_physics_priority = 50
	_walker = get_node("%Walker")
	_telemetry = get_node("%Telemetry")
	_camera = get_node("Camera")
	# The camera moves in _process from interpolated poses: it must not be interpolated itself.
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_orbit = get_node("OrbitCamera")
	_free_play = not _scenario_run()
	_make_materials()
	_build_environment()
	_build_ground()
	_build_flat()
	_build_bumps()
	_build_ledges()
	_build_wall()
	_build_pocket()
	_build_talus()
	_telemetry.observe(_walker)
	_walker.foot_planted.connect(_on_foot_planted)
	if _free_play:
		_orbit.capture_mouse = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_build_hud()
		_camera_mode = "orbit"
		_set_orbit_active(true)
	else:
		_set_orbit_active(false)
	spawn_at(LANE_FLAT)


func _input(event: InputEvent) -> void:
	if not _free_play or not event is InputEventKey:
		return
	var key: InputEventKey = event
	if not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_T:
			toggle_steer_mode()
		KEY_1:
			use_build("scout")
		KEY_2:
			use_build("strider")
		KEY_3:
			use_build("crawler")
		KEY_4:
			use_build("quad")
		KEY_5:
			use_build("scout_short_pair")
		KEY_F1:
			spawn_at(LANE_FLAT)
		KEY_F2:
			spawn_at(LANE_BUMPS)
		KEY_F3:
			spawn_at(LANE_TALUS, -8.0)
		KEY_F4:
			spawn_at(LANE_LEDGES)
		KEY_F5:
			spawn_at(LANE_PATCH_A)
		KEY_F6:
			spawn_at(LANE_WALL)
		KEY_F7:
			spawn_at(LANE_POCKET)
		KEY_R:
			spawn_at(_lane, _spawn_offset)
		_:
			return
	get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if _first_tick:
		# The static bodies are registered with the physics server by now: plant on the real ground.
		_first_tick = false
		spawn_at(_lane, _spawn_offset)
	if _autopilot:
		_run_autopilot(delta)
	_track_step_up()
	_track_yaw_overshoot()
	_track_hover_inside()
	_tick += 1
	if _tick == 5:
		_nominal_root_y = _walker.global_position.y
	# Walking into the end of a lane (no ground ahead) is not a stall of the controller.
	_telemetry.stall_exempt = _walker.global_position.z < -(TALUS_LENGTH - 2.0) and _lane == LANE_TALUS
	if _walker.gait() != null:
		foot_rise_max = maxf(foot_rise_max, foot_rise_above_apron)
		if _tick > 5:
			root_rise_max = maxf(root_rise_max, root_rise_over_nominal)
	if _track_clearance and _walker.gait() != null and _on_patch():
		# The clearance sits on its floor (the push-up holds it there) for a stretch of the crest: take the middle.
		var clearance: float = _walker.min_hip_clearance()
		if clearance < clearance_min - 0.0001:
			clearance_min = clearance
			_clearance_first = _tick
			clearance_tick = _tick
		elif clearance <= clearance_min + 0.0001:
			clearance_tick = (_clearance_first + _tick) / 2
	if _freeze_tick >= 0 and _tick >= _freeze_tick:
		get_tree().paused = true
		_freeze_tick = -1
	if _freeze_tilt >= 0.0 and _walker.tilt_degrees() >= _freeze_tilt:
		get_tree().paused = true
		_freeze_tilt = -1.0
	if _freeze_at >= 0.0:
		for i in _walker.leg_count():
			if _walker.gait().swing_progress(i) >= _freeze_at:
				get_tree().paused = true
				_freeze_at = -1.0
				break


func _process(_delta: float) -> void:
	if _walker == null:
		return
	if _track_frames:
		var now_usec: int = Time.get_ticks_usec()
		if _frame_last_usec > 0:
			var frame_ms: float = float(now_usec - _frame_last_usec) / 1000.0
			_frame_ms.append(frame_ms)
			_frame_ms_max = maxf(_frame_ms_max, frame_ms)
		_frame_last_usec = now_usec
	if _hud_label != null:
		_hud_label.text = "STEER: %s   (T toggles)\n%s" % [steer_mode_name, help_text]
	if _camera_mode == "orbit":
		if _track_camera:
			var y: float = _orbit.camera().global_position.y
			_cam_y_min = minf(_cam_y_min, y)
			_cam_y_max = maxf(_cam_y_max, y)
			_cam_samples += 1
		return
	var walker_pose: Transform3D = _walker.get_global_transform_interpolated()
	var focus: Vector3 = walker_pose.origin
	var forward: Vector3 = -walker_pose.basis.z
	var yaw: float = atan2(-forward.x, -forward.z)
	if _pair_walker != null:
		var other: Vector3 = _pair_walker.get_global_transform_interpolated().origin
		focus = (focus + other) * 0.5
	if _camera_mode == "pair":
		# Perpendicular to the pair: both walkers at the same distance, seen from behind.
		_camera.global_position = focus + Vector3(0.0, 2.2, camera_distance)
		_camera.look_at(focus + Vector3(0.0, 0.9, 0.0), Vector3.UP)
		return
	if _camera_mode == "crest":
		# True side-on (perpendicular to travel), about 4 m out, eye 0.4 m above the ground under the body.
		var across: Vector3 = Basis(Vector3.UP, yaw) * Vector3.RIGHT
		var sun_side: float = 1.0 if across.dot(_sun.global_transform.basis.z) >= 0.0 else -1.0
		var ground_y: float = focus.y - _walker.height_above_plane()
		_camera.global_position = Vector3(focus.x, ground_y + 0.4, focus.z) + across * (camera_distance * sun_side)
		_camera.look_at(Vector3(focus.x, ground_y + 0.4 + CREST_LOOK_RISE, focus.z), Vector3.UP)
		return
	if _camera_mode == "side":
		# Side-on, level with the legs: a lifted foot shows as a gap under the pad.
		var right: Vector3 = Basis(Vector3.UP, yaw) * Vector3.RIGHT
		var toward_sun: Vector3 = _sun.global_transform.basis.z
		var lit_side: float = 1.0 if right.dot(toward_sun) >= 0.0 else -1.0
		_camera.global_position = focus + right * (camera_distance * lit_side) + Vector3(0.0, SIDE_CAMERA_HEIGHT, 0.0)
		_camera.look_at(focus + Vector3(0.0, 0.3, 0.0), Vector3.UP)
		return
	var pitch: float = deg_to_rad(CAMERA_PITCH_DEG)
	var azimuth: float = deg_to_rad(CAMERA_AZIMUTH_DEG)
	var horizontal: float = camera_distance * cos(pitch)
	var offset := Vector3(
		horizontal * sin(azimuth), camera_distance * sin(pitch), horizontal * cos(azimuth)
	)
	_camera.global_position = focus + Basis(Vector3.UP, yaw) * offset
	_camera.look_at(focus + Vector3(0.0, 0.5, 0.0), Vector3.UP)


# --- Scenario helpers ------------------------------------------------------------------------------------------


## "scout", "strider", "crawler", "quad" (4 medium legs and 1 cannon: the wave gait) or "scout_short_pair"
## (the Scout with its rear pair swapped for short legs).
func use_build(build_name: String) -> void:
	var build: WalkerBuild
	match build_name:
		"scout":
			build = WalkerBuild.scout()
		"strider":
			build = WalkerBuild.strider()
		"crawler":
			build = WalkerBuild.crawler()
		"quad":
			build = WalkerBuild.new()
			for socket: StringName in [&"leg_l0", &"leg_l1", &"leg_r0", &"leg_r1"]:
				build.place(socket, PartCatalog.LEG_MEDIUM)
			build.place(&"top_0", PartCatalog.PULSE_CANNON)
		"scout_short_pair":
			build = WalkerBuild.new()
			for socket: StringName in [&"leg_l0", &"leg_l1", &"leg_r0", &"leg_r1"]:
				build.place(socket, PartCatalog.LEG_MEDIUM)
			for socket: StringName in [&"leg_l2", &"leg_r2"]:
				build.place(socket, PartCatalog.LEG_SHORT)
			build.place(&"top_0", PartCatalog.PULSE_CANNON)
		_:
			push_error("GaitCourse.use_build: unknown build %s" % build_name)
			return
	_remove_pair()
	_walker.apply_build(build)


## Teleports the walker to the start of a lane, facing -Z. Telemetry keeps its numbers (call reset() on it).
func spawn_at(lane: String, offset_z: float = 0.0) -> void:
	var origin: Vector3 = _spawn_point(lane) + Vector3(0.0, 0.0, offset_z)
	if origin.y < -100.0:
		push_error("GaitCourse.spawn_at: unknown lane %s" % lane)
		return
	_lane = lane
	_spawn_offset = offset_z
	_tick = 0
	hover_inside_ticks = 0
	foot_rise_max = -INF
	root_rise_max = -INF
	_walker.teleport(Transform3D(Basis(Vector3.UP, _spawn_yaw(lane)), origin))
	if _camera_mode == "orbit":
		# The interpolated pose would still show the old spot: drop it, and put the camera behind the walker.
		_walker.reset_physics_interpolation()
		_orbit.recenter_enabled = true
		_orbit.set_angles(OrbitMath.behind_yaw(-_walker.global_basis.z), _orbit.pitch_deg)
		_orbit.snap()
	_last_plant.resize(_walker.leg_count())
	for i in _walker.leg_count():
		_last_plant[i] = _walker.foot_position(i)
	mark()


func mark() -> void:
	_mark = _walker.global_position


func hold_action(action: String, pressed: bool, strength: float = 1.0) -> void:
	if pressed:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func release_all() -> void:
	for action in [
		"move_forward", "move_back", "turn_left", "turn_right", "strafe_left", "strafe_right", "aim"
	]:
		Input.action_release(action)


## Holds the heading on a slow weave around the lane centre (turns mixed in, lateral drift corrected).
func autopilot(enabled: bool, lane_offset: float = 0.0, amplitude_deg: float = 35.0) -> void:
	_autopilot = enabled
	_autopilot_time = 0.0
	autopilot_amplitude_deg = amplitude_deg
	_autopilot_center = float(LANE_X[LANE_BUMPS]) + lane_offset if enabled and _lane_key() == LANE_BUMPS else _walker.global_position.x
	if not enabled:
		Input.action_release("turn_left")
		Input.action_release("turn_right")


## Pauses the game the first tick any leg's swing reaches `progress` (a mid-stride still); resume() continues.
func arm_swing_freeze(progress: float) -> void:
	_freeze_at = progress


## Pauses the game the first tick the body's tilt reaches `degrees` (a still at the steepest part of a climb).
func arm_tilt_freeze(degrees: float) -> void:
	_freeze_tilt = degrees


## Starts (or resets) the search for the tick of the lowest hip clearance; read clearance_tick afterwards.
func track_clearance(enabled: bool) -> void:
	_track_clearance = enabled
	if enabled:
		clearance_min = INF
		clearance_tick = -1


## Pauses the game at tick `offset` ticks from the recorded minimum-clearance tick (a deterministic replay).
func arm_freeze_at_clearance(offset: int) -> void:
	_freeze_tick = clearance_tick + offset


func resume() -> void:
	get_tree().paused = false


## Remembers the current run's steps per leg per second as the reference for steps_ratio.
func record_steps_ref() -> void:
	steps_ref = _telemetry.steps_per_s


## Shadows on or off (the midstride still is shot without them so the sand under a lifted pad reads).
func set_shadows(enabled: bool) -> void:
	_sun.shadow_enabled = enabled


func set_camera_mode(mode: String, distance: float = 8.0) -> void:
	_set_orbit_active(mode == "orbit")
	_camera_mode = mode
	camera_distance = distance


## Switches the play camera to the orbit rig at a pitch (degrees) and distance (m), behind the walker.
## yaw_offset_deg turns the camera that far around the walker (90 = abeam); a non-zero offset also switches the
## rig's recentring off so the view holds while the walker moves.
func use_orbit_camera(pitch_deg: float = 20.0, distance: float = 8.0, yaw_offset_deg: float = 0.0) -> void:
	_set_orbit_active(true)
	_camera_mode = "orbit"
	_orbit.distance = distance
	_orbit.recenter_enabled = is_zero_approx(yaw_offset_deg)
	_orbit.set_angles(OrbitMath.behind_yaw(-_walker.global_basis.z) + yaw_offset_deg, pitch_deg)
	_walker.reset_physics_interpolation()
	_orbit.snap()


## Flips the walker between tank steering and heading-follows-camera (the gate question).
func toggle_steer_mode() -> void:
	if _walker.steer_mode == WalkerBody.SteerMode.TANK:
		_walker.yaw_source = _orbit
		_walker.steer_mode = WalkerBody.SteerMode.CAMERA_YAW
	else:
		_walker.steer_mode = WalkerBody.SteerMode.TANK
		_walker.yaw_source = null


## Starts (clears) or stops the frame-time record; read frame_max_ms and frame_p95_ms afterwards.
func track_frames(enabled: bool) -> void:
	_track_frames = enabled
	_frame_last_usec = 0
	if enabled:
		_frame_ms.resize(0)
		_frame_ms_max = 0.0


func log_frames(label: String) -> void:
	print("FRAMES %s p95_ms=%.2f max_ms=%.2f n=%d" % [label, frame_p95_ms, frame_max_ms, _frame_ms.size()])


func track_camera_bob(enabled: bool) -> void:
	_track_camera = enabled
	_cam_y_min = INF
	_cam_y_max = -INF
	_cam_samples = 0


## Prints the camera height above the ground and the bob left on it (report numbers).
func log_camera(label: String) -> void:
	print(
		"CAMERA %s pitch=%.1f arm=%.2f height_m=%.3f bob_p2p_m=%.4f samples=%d"
		% [label, _orbit.pitch_deg, _orbit.arm_length, _camera_height(), camera_bob_p2p_m, _cam_samples]
	)


## For every pad: how many of 5 sight lines (top centre + 4 top corners) from the active camera reach it, against
## the world (layer 1) and the walker's chassis box ONLY. Other legs, hip balls, the tops and pad side faces are not
## tested, so 5/5 does not mean "readable": it means no terrain or chassis is in the way. Logged as
## `FOOTVIS(chassis+terrain) <tag> leg=i visible=k/5`; the lowest count is kept in `min_foot_vis`.
func log_foot_vis(tag: String) -> void:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var eye: Vector3 = _active_camera().global_position
	var basis := Basis(Vector3.UP, _walker.yaw_radians())
	var half := WalkerLeg.PAD_SIZE * 0.5
	var top: float = WalkerLeg.PAD_SIZE.y
	var offsets: Array[Vector3] = [
		Vector3(0.0, top, 0.0),
		Vector3(-half.x, top, -half.z),
		Vector3(half.x, top, -half.z),
		Vector3(-half.x, top, half.z),
		Vector3(half.x, top, half.z)
	]
	var chassis: MeshInstance3D = _walker.get_node("Chassis")
	var box: BoxMesh = chassis.mesh as BoxMesh
	var to_local: Transform3D = chassis.global_transform.affine_inverse()
	var local_box := AABB(-box.size * 0.5, box.size) if box != null else AABB()
	var rows: Array[String] = []
	min_foot_vis = 5
	for i in _walker.leg_count():
		var foot: Vector3 = _walker.foot_position(i)
		var seen: int = 0
		for offset in offsets:
			var point: Vector3 = foot + basis * offset
			var toward: Vector3 = (point - eye).normalized()
			# Stop 2 cm short of the pad: the pad itself has no collider, but the ground under it is close.
			var end: Vector3 = point - toward * 0.02
			var query := PhysicsRayQueryParameters3D.create(eye, end, 1)
			var blocked: bool = not space.intersect_ray(query).is_empty()
			if not blocked and box != null:
				blocked = local_box.intersects_segment(to_local * eye, to_local * end) != null
			if not blocked:
				seen += 1
		min_foot_vis = mini(min_foot_vis, seen)
		rows.append("FOOTVIS(chassis+terrain) %s leg=%d visible=%d/5" % [tag, i, seen])
	for row in rows:
		print(row)


## Prints every foot's screen box (viewport px) and its height scaled to 1080 p.
func log_foot_boxes(label: String) -> void:
	var scale_1080: float = 1080.0 / get_viewport().get_visible_rect().size.y
	var boxes: Array[Rect2] = _foot_boxes()
	for i in boxes.size():
		var box: Rect2 = boxes[i]
		print(
			"FOOTBOX %s leg=%d x=%.0f..%.0f y=%.0f..%.0f h_1080=%.1f"
			% [label, i, box.position.x, box.end.x, box.position.y, box.end.y, box.size.y * scale_1080]
		)
	print(
		"FOOTBOX %s viewport=%s min_h_1080=%.1f tilt=%.1f along_z=%.2f arm=%.2f"
		% [
			label,
			str(get_viewport().get_visible_rect().size),
			_foot_min_height(),
			_walker.tilt_degrees(),
			_walker.global_position.z,
			_orbit.arm_length
		]
	)


## Steer by a node rotated `degrees` about Y (CAMERA_YAW mode, the gate fallback).
func use_yaw_source(degrees: float) -> void:
	if _yaw_source == null:
		_yaw_source = Node3D.new()
		_yaw_source.name = "YawSource"
		add_child(_yaw_source)
	_yaw_source.rotation_degrees = Vector3(0.0, degrees, 0.0)
	_walker.yaw_source = _yaw_source
	_walker.steer_mode = WalkerBody.SteerMode.CAMERA_YAW
	yaw_overshoot_deg = 0.0
	_yaw_start_sign = signf(wrapf(_yaw_target() - _walker.yaw_radians(), -PI, PI))


## Moves the yaw source by `degrees` (a mouse nudge) without starting a new overshoot measurement.
func nudge_yaw_source(degrees: float) -> void:
	if _yaw_source != null:
		_yaw_source.rotation_degrees.y += degrees


func clear_yaw_source() -> void:
	_walker.steer_mode = WalkerBody.SteerMode.TANK
	_walker.yaw_source = null
	_yaw_start_sign = 0.0


## Copies the telemetry's top speed and step-up into slot "a" or "b" and updates the contrast numbers.
func record_result(slot: String) -> void:
	if slot == "a":
		a_speed = _telemetry.top_speed_mps
		a_step_up = _telemetry.max_step_up_m
	elif slot == "b":
		b_speed = _telemetry.top_speed_mps
		b_step_up = _telemetry.max_step_up_m
	else:
		push_error("GaitCourse.record_result: slot must be a or b")
		return
	if a_speed > 0.0:
		contrast_speed = (a_speed - b_speed) / a_speed
	if a_step_up > 0.0:
		contrast_step_up = (a_step_up - b_step_up) / a_step_up


## The Strider and the Crawler side by side on the flat lane, camera square-on from behind. They start a
## metre apart in z so that after 30 frames of walking they are level.
func show_pair() -> void:
	_walker.apply_build(WalkerBuild.strider())
	_lane = LANE_FLAT
	var left := Vector3(LANE_X[LANE_FLAT] - 2.5, SPAWN_Y, SPAWN_Z + 1.0)
	var right := Vector3(LANE_X[LANE_FLAT] + 2.5, SPAWN_Y, SPAWN_Z)
	_walker.teleport(Transform3D(Basis.IDENTITY, left))
	_remove_pair()
	_pair_walker = WALKER_SCENE.instantiate()
	add_child(_pair_walker)
	_pair_walker.apply_build(WalkerBuild.crawler())
	_pair_walker.teleport(Transform3D(Basis.IDENTITY, right))
	set_camera_mode("pair", 10.0)
	mark()


## Prints where every pad of the walker is on screen and how far each is off the ground (screenshot evidence).
func log_pads() -> void:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = 1
	for i in _walker.leg_count():
		var foot: Vector3 = _walker.foot_position(i)
		query.from = foot + Vector3.UP * 1.0
		query.to = foot + Vector3.DOWN * 3.0
		var hit: Dictionary = space.intersect_ray(query)
		var ground: Vector3 = hit["position"] if not hit.is_empty() else foot
		var foot_px: Vector2 = _camera.unproject_position(foot)
		var ground_px: Vector2 = _camera.unproject_position(ground)
		print(
			"PADS leg=%d state=%d px=(%.0f,%.0f) gap_m=%.3f gap_px=%.1f"
			% [
				i,
				_walker.gait().state_of(i),
				foot_px.x,
				foot_px.y,
				foot.y - ground.y,
				ground_px.y - foot_px.y
			]
		)


## Prints where each pad's shadow lands on screen (the lift cue) next to log_pads.
func log_shadows() -> void:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = 1
	var light: Vector3 = -_sun.global_transform.basis.z
	var horizontal := Vector3(light.x, 0.0, light.z)
	for i in _walker.leg_count():
		var foot: Vector3 = _walker.foot_position(i)
		query.from = foot + Vector3.UP * 1.0
		query.to = foot + Vector3.DOWN * 3.0
		var hit: Dictionary = space.intersect_ray(query)
		var ground: Vector3 = hit["position"] if not hit.is_empty() else foot
		var lift: float = foot.y - ground.y
		var spot: Vector3 = ground + horizontal / maxf(-light.y, 0.01) * lift
		var spot_px: Vector2 = _camera.unproject_position(spot)
		print("SHADOW leg=%d px=(%.0f,%.0f) lift_m=%.3f" % [i, spot_px.x, spot_px.y, lift])


## Prints the projected centre of every hip ball (for pixel checks that the hips are above the ground).
func log_hips() -> void:
	var across: Vector3 = Basis(Vector3.UP, _walker.yaw_radians()) * Vector3.RIGHT
	var camera_side: int = 1 if across.dot(_camera.global_position - _walker.global_position) >= 0.0 else -1
	for i in _walker.leg_count():
		var hip: Vector3 = _walker.hip_position(i)
		var px: Vector2 = _camera.unproject_position(hip)
		print(
			"HIPS leg=%d near=%s px=(%.0f,%.0f)"
			% [i, str(_walker.leg_side(i) == camera_side), px.x, px.y]
		)


## Prints the on-screen height of both walkers (feet to top) for the Strider-vs-Crawler shot.
func log_pair_extents() -> void:
	if _pair_walker == null:
		return
	for entry in [["strider", _walker], ["crawler", _pair_walker]]:
		var body: WalkerBody = entry[1]
		var low: float = -INF
		var x_sum: float = 0.0
		for i in body.leg_count():
			var px: Vector2 = _camera.unproject_position(body.foot_position(i))
			low = maxf(low, px.y)
			x_sum += px.x
		var top_px: Vector2 = _camera.unproject_position(body.top_point())
		print(
			"PAIR %s x=%.0f top_px=%.0f feet_px=%.0f height_px=%.0f"
			% [entry[0], x_sum / float(body.leg_count()), top_px.y, low, low - top_px.y]
		)


# --- Measurements ------------------------------------------------------------------------------------------------


## True for any run started with --scenario= (free play only when there is none).
func _scenario_run() -> bool:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="):
			return true
	return false


## Makes the orbit rig (processing, input, current camera) or the scripted camera the play camera.
func _set_orbit_active(active: bool) -> void:
	_orbit.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if active:
		_orbit.camera().make_current()
	else:
		_camera.make_current()


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	_hud_label = Label.new()
	_hud_label.position = Vector2(12.0, 8.0)
	_hud_label.add_theme_font_size_override("font_size", 16)
	_hud_label.add_theme_color_override("font_color", Color.WHITE)
	_hud_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_hud_label)
	add_child(layer)


func _active_camera() -> Camera3D:
	return _orbit.camera() if _camera_mode == "orbit" else _camera


## Screen box (viewport px) of every foot pad: the 8 corners of the pad box, yaw-aligned like the drawn pad.
func _foot_boxes() -> Array[Rect2]:
	var boxes: Array[Rect2] = []
	var camera: Camera3D = _active_camera()
	var basis := Basis(Vector3.UP, _walker.yaw_radians())
	var half := WalkerLeg.PAD_SIZE * 0.5
	for i in _walker.leg_count():
		var foot: Vector3 = _walker.foot_position(i)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		var behind: bool = false
		for sx: float in [-1.0, 1.0]:
			for sy: float in [0.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var corner: Vector3 = foot + basis * Vector3(sx * half.x, sy * WalkerLeg.PAD_SIZE.y, sz * half.z)
					if camera.is_position_behind(corner):
						behind = true
						continue
					var px: Vector2 = camera.unproject_position(corner)
					lo = Vector2(minf(lo.x, px.x), minf(lo.y, px.y))
					hi = Vector2(maxf(hi.x, px.x), maxf(hi.y, px.y))
		if behind:
			boxes.append(Rect2(Vector2(-1.0e6, -1.0e6), Vector2(2.0e6, 2.0e6)))
		else:
			boxes.append(Rect2(lo, hi - lo))
	return boxes


func _feet_in_frame() -> bool:
	var view: Rect2 = get_viewport().get_visible_rect()
	for box in _foot_boxes():
		if not view.encloses(box):
			return false
	return true


func _foot_min_height() -> float:
	var scale_1080: float = 1080.0 / get_viewport().get_visible_rect().size.y
	var low: float = INF
	for box in _foot_boxes():
		low = minf(low, box.size.y * scale_1080)
	return low


func _frame_percentile(fraction: float) -> float:
	if _frame_ms.is_empty():
		return 0.0
	var sorted: PackedFloat32Array = _frame_ms.duplicate()
	sorted.sort()
	return sorted[clampi(int(ceil(fraction * float(sorted.size()))) - 1, 0, sorted.size() - 1)]


func _camera_height() -> float:
	var from: Vector3 = _active_camera().global_position
	var query := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 5.0, from + Vector3.DOWN * 50.0, 1)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	return from.y - (hit["position"].y if not hit.is_empty() else 0.0)


func _spawn_point(lane: String) -> Vector3:
	match lane:
		"talus_top":
			# On the shelf above the face, 3 m back from the edge, facing +Z down the face.
			var along: float = TALUS_CORNER_ALONG + ValleyLayout.TALUS_SLOPE_LEN + 3.0
			return Vector3(LANE_X[LANE_TALUS], _talus_height(along) + SPAWN_Y, -along)
		LANE_PATCH_A:
			return Vector3(LANE_X[LANE_BUMPS] - PATCH_X, SPAWN_Y, -(PATCH_ALONG - 7.0))
		"crest":
			return Vector3(LANE_X[LANE_BUMPS] - 8.0, SPAWN_Y, -CREST_ALONG)
		"boulders":
			return Vector3(LANE_X[LANE_BUMPS] + (BOULDER_X_MIN + BOULDER_X_MAX) * 0.5, SPAWN_Y, -6.0)
	if not LANE_X.has(lane):
		return Vector3(0.0, -1000.0, 0.0)
	return Vector3(LANE_X[lane], SPAWN_Y, SPAWN_Z)


func _spawn_yaw(lane: String) -> float:
	# The crest lane starts on the crest line, facing +X (along the ridge, toward the block face).
	if lane == "talus_top":
		return PI
	return -PI * 0.5 if lane == "crest" else 0.0


## True while the walker is over the steep patch (its flank and crest) along the lane.
## Hovering feet found inside solid geometry (summed over ticks since the last spawn).
var hover_inside_ticks: int = 0
var _nominal_root_y: float = 0.0


func _track_hover_inside() -> void:
	if _walker == null or _walker.gait() == null:
		return
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsPointQueryParameters3D.new()
	query.collision_mask = 1
	for i in _walker.leg_count():
		if _walker.gait().state_of(i) != GaitSolver.LegState.HOVERING:
			continue
		query.position = _walker.foot_position(i)
		if not space.intersect_point(query, 1).is_empty():
			hover_inside_ticks += 1


## Planted-foot rise above the lane's apron, and the body root's rise over (apron + nominal body height): the
## blocked-at-the-talus numbers (a blocked walker stays level on the apron).
var foot_rise_above_apron: float:
	get:
		if _walker == null or _walker.gait() == null:
			return 0.0
		var rise: float = -INF
		for i in _walker.leg_count():
			if _walker.gait().state_of(i) == GaitSolver.LegState.PLANTED:
				rise = maxf(rise, _walker.foot_position(i).y)
		return rise
## Running maxima of the two since the last spawn_at (a blocked push is judged over the whole push, not one frame).
var foot_rise_max: float = -INF
var root_rise_max: float = -INF
var root_rise_over_nominal: float:
	get:
		if _walker == null:
			return 0.0
		return _walker.global_position.y - _nominal_root_y


func _on_patch() -> bool:
	var z: float = _walker.global_position.z
	if _lane == LANE_TALUS:
		return z < -(TALUS_CORNER_ALONG - 1.0)
	return z < -(PATCH_ALONG - PATCH_FLANK) and z > -(PATCH_ALONG + PATCH_FLANK)


func _lane_key() -> String:
	if _lane == "talus_top":
		return LANE_TALUS
	if _lane == LANE_PATCH_A or _lane == "boulders" or _lane == "crest":
		return LANE_BUMPS
	return _lane


func _edge_margin() -> float:
	if _walker == null:
		return 0.0
	var key: String = _lane_key()
	var half: float = LANE_HALF_WIDTH[key]
	var at: Vector3 = _walker.global_position
	var dx: float = half - absf(at.x - float(LANE_X[key]))
	var far: float = BUMP_LENGTH if key == LANE_BUMPS else FLAT_LENGTH
	var dz_far: float = at.z + far
	return minf(dx, dz_far)


func _first_blocked_block() -> Dictionary:
	var step_up: float = _walker.stats()["step_up"]
	for block in _blocks.get(LANE_LEDGES, []):
		if float(block["h"]) > step_up + 0.001:
			return block
	return {}


func _stopped_before_face() -> bool:
	if _walker == null or _lane != LANE_LEDGES:
		return false
	var block: Dictionary = _first_blocked_block()
	if block.is_empty():
		return false
	var face: float = block["z_front"]
	if _walker.global_position.z < face:
		return false
	for i in _walker.leg_count():
		if _walker.foot_position(i).z < face:
			return false
	return true


func _on_foot_planted(leg: int, position: Vector3, _normal: Vector3) -> void:
	if leg < _last_plant.size():
		_last_plant[leg] = position


## "Every foot planted on the block's top": each leg's most recent plant point lies on the deck. (A walking
## tripod gait never has all feet on the ground in the same tick.)
func _track_step_up() -> void:
	if _walker == null or _walker.gait() == null or not _blocks.has(_lane):
		return
	if _last_plant.size() != _walker.leg_count():
		return
	var z: float = _walker.global_position.z
	for block in _blocks[_lane]:
		if z > block["z_front"] + 3.0 or z < block["z_back"] - 3.0:
			continue
		var height: float = block["h"]
		var all_on_top: bool = true
		for foot in _last_plant:
			if foot.z > block["z_front"] or foot.z < block["z_back"] or absf(foot.y - height) > 0.05:
				all_on_top = false
				break
		if all_on_top:
			_telemetry.max_step_up_m = maxf(_telemetry.max_step_up_m, height)


## The node the walker steers to in CAMERA_YAW (the orbit rig after toggle_steer_mode, else the scripted YawSource).
func _steer_source() -> Node3D:
	return _walker.yaw_source if is_instance_valid(_walker.yaw_source) else null


func _yaw_target() -> float:
	var source: Node3D = _steer_source()
	if source == null:
		return 0.0
	var heading: Vector3 = -source.global_transform.basis.z
	return atan2(-heading.x, -heading.z)


func _track_yaw_overshoot() -> void:
	if _yaw_source == null or _yaw_start_sign == 0.0 or _walker.steer_mode != WalkerBody.SteerMode.CAMERA_YAW:
		return
	var remaining: float = wrapf(_yaw_target() - _walker.yaw_radians(), -PI, PI) * _yaw_start_sign
	if remaining < 0.0:
		yaw_overshoot_deg = maxf(yaw_overshoot_deg, rad_to_deg(-remaining))


func _run_autopilot(delta: float) -> void:
	_autopilot_time += delta
	var weave: float = deg_to_rad(autopilot_amplitude_deg) * sin(TAU * _autopilot_time / AUTOPILOT_PERIOD_S)
	var centering: float = clampf(
		(_walker.global_position.x - _autopilot_center) * AUTOPILOT_CENTERING, -0.6, 0.6
	)
	var error: float = rad_to_deg(wrapf(weave + centering - _walker.yaw_radians(), -PI, PI))
	if error > AUTOPILOT_DEAD_DEG:
		Input.action_press("turn_left")
		Input.action_release("turn_right")
	elif error < -AUTOPILOT_DEAD_DEG:
		Input.action_press("turn_right")
		Input.action_release("turn_left")
	else:
		Input.action_release("turn_left")
		Input.action_release("turn_right")


func _all_feet_beyond(z: float) -> bool:
	if _walker == null or _walker.gait() == null:
		return false
	for i in _walker.leg_count():
		if _walker.foot_position(i).z >= z:
			return false
	return true


func _remove_pair() -> void:
	if _pair_walker != null:
		_pair_walker.queue_free()
		_pair_walker = null
	if _camera_mode != "orbit":
		set_camera_mode("follow", 8.0)


# --- Course construction ---------------------------------------------------------------------------------------


func _make_materials() -> void:
	_ground_material = StandardMaterial3D.new()
	_ground_material.albedo_color = GROUND_COLOR
	_ground_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_stripe_material = StandardMaterial3D.new()
	_stripe_material.albedo_color = Color("9C8461")
	_block_material = StandardMaterial3D.new()
	_block_material.albedo_color = Color("6F7F8F")
	_wall_material = StandardMaterial3D.new()
	_wall_material.albedo_color = Color("4A5563")
	_boulder_material = StandardMaterial3D.new()
	_boulder_material.albedo_color = Color("7A6A58")


func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.62, 0.72, 0.82)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.78, 0.82)
	environment.ambient_light_energy = 0.6
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	_sun = sun
	# One high sun (60 degrees) behind and a little right of the cameras (25 degrees off): it lights the
	# camera-facing side in every shot, and shadows stay on (a pad leaving its shadow is the lift cue).
	sun.rotation_degrees = Vector3(-SUN_ELEVATION_DEG, SUN_AZIMUTH_DEG, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)


func _add_box(
	center: Vector3, size: Vector3, material: Material, solid: bool = true
) -> StaticBody3D:
	var holder: Node3D = null
	var body: StaticBody3D = null
	if solid:
		body = StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = center
		var shape := BoxShape3D.new()
		shape.size = size
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
		holder = body
	else:
		holder = Node3D.new()
		holder.position = center
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	holder.add_child(instance)
	add_child(holder)
	return body


## One big slab (top at y = 0) under and around every lane: no void edges anywhere.
func _build_ground() -> void:
	_add_box(Vector3(120.0, -0.5, -160.0), Vector3(460.0, 1.0, 560.0), _ground_material)


func _build_flat() -> void:
	# 2 m stripes across the lane so speed reads on screen.
	var x: float = LANE_X[LANE_FLAT]
	var count: int = int(FLAT_LENGTH / (FLAT_STRIPE * 2.0))
	for i in count:
		var z: float = 10.0 - FLAT_STRIPE * (2.0 * float(i) + 0.5)
		_add_box(
			Vector3(x, 0.006, z),
			Vector3(LANE_HALF_WIDTH[LANE_FLAT] * 2.0, 0.012, FLAT_STRIPE),
			_stripe_material,
			false
		)


# Terrain of the bumps lane in lane coordinates: lx across (-15..15), along down the lane (0..100).
func _terrain_height(lx: float, along: float) -> float:
	var n: float = clampf(_noise.get_noise_2d(lx, along) / HILL_NOISE_RANGE, -1.0, 1.0)
	var hills: float = HILL_P2P * 0.5 * (1.0 + n)
	hills *= smoothstep(0.0, 4.0, minf(lx + BUMP_WIDTH * 0.5, BUMP_WIDTH * 0.5 - lx))
	hills *= smoothstep(3.0, 9.0, along)
	var mask: float = _patch_mask(lx, along, -PATCH_X)
	var swell: float = 0.0
	for centre in SWELLS_ALONG:
		var gap: float = absf(along - centre)
		if gap < SWELL_FLANK:
			swell += SWELL_CREST * 0.5 * (1.0 + cos(PI * gap / SWELL_FLANK))
	swell *= smoothstep(0.0, 4.0, minf(lx + BUMP_WIDTH * 0.5, BUMP_WIDTH * 0.5 - lx))
	return (
		swell
		+ hills * (1.0 - mask)
		+ _patch_height(lx, along, -PATCH_X, tan(deg_to_rad(PATCH_A_DEG)))
	)


func _patch_mask(lx: float, along: float, cx: float) -> float:
	var across: float = 1.0 - smoothstep(PATCH_HALF_WIDTH, PATCH_HALF_WIDTH + 4.0, absf(lx - cx))
	# Hills fade out over 6 m before the patch (a short fade would leave a ditch at the foot of the flank).
	var lengthwise: float = 1.0 - smoothstep(PATCH_FLANK, PATCH_FLANK + 6.0, absf(along - PATCH_ALONG))
	return across * lengthwise


## A ridge across the patch: flanks at exactly the patch slope, crest PATCH_FLANK x tan(slope) high.
func _patch_height(lx: float, along: float, cx: float, tan_slope: float) -> float:
	var taper: float = 1.0 - smoothstep(PATCH_HALF_WIDTH - 1.0, PATCH_HALF_WIDTH, absf(lx - cx))
	var d: float = absf(along - PATCH_ALONG)
	if d >= PATCH_FLANK:
		return 0.0
	# Rounded crest (a talus crest is not a knife edge): g(d) = sqrt(d^2 + r^2) - r runs like |d| away from the top.
	# The slope is raised so the flank centre still has the patch's slope.
	var centre: float = PATCH_FLANK * 0.5
	var steepness: float = tan_slope / (centre / sqrt(centre * centre + PATCH_CREST_ROUNDING * PATCH_CREST_ROUNDING))
	return PATCH_STEEPNESS_TRIM * steepness * (_crest_g(PATCH_FLANK) - _crest_g(d)) * taper


func _crest_g(d: float) -> float:
	return sqrt(d * d + PATCH_CREST_ROUNDING * PATCH_CREST_ROUNDING) - PATCH_CREST_ROUNDING


## Mean slope (degrees) over a 2 m disc centred on the approach flank of a patch.
func _disc_slope_deg(cx: float) -> float:
	var centre_along: float = PATCH_ALONG - PATCH_FLANK * 0.5
	var total: float = 0.0
	var samples: int = 0
	for ix in range(-4, 5):
		for iz in range(-4, 5):
			var offset := Vector2(float(ix), float(iz)) * 0.25
			if offset.length() > 1.0:
				continue
			var x: float = cx + offset.x
			var a: float = centre_along + offset.y
			var gx: float = (_terrain_height(x + 0.05, a) - _terrain_height(x - 0.05, a)) / 0.1
			var gz: float = (_terrain_height(x, a + 0.05) - _terrain_height(x, a - 0.05)) / 0.1
			total += Vector2(gx, gz).length()
			samples += 1
	return rad_to_deg(atan(total / float(maxi(samples, 1))))


func _build_bumps() -> void:
	_noise = FastNoiseLite.new()
	_noise.seed = TERRAIN_SEED
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = HILL_FREQUENCY
	patch_a_slope_deg = _disc_slope_deg(-PATCH_X)
	var nx: int = int(BUMP_WIDTH / BUMP_CELL) + 1
	var nz: int = int(BUMP_LENGTH / BUMP_CELL) + 1
	var heights := PackedFloat32Array()
	heights.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			var lx: float = float(ix) * BUMP_CELL - BUMP_WIDTH * 0.5
			heights[iz * nx + ix] = _terrain_height(lx, float(iz) * BUMP_CELL)
	var origin_x: float = LANE_X[LANE_BUMPS] - BUMP_WIDTH * 0.5
	var faces := PackedVector3Array()
	for iz in nz - 1:
		for ix in nx - 1:
			var v00: Vector3 = _bump_vertex(heights, nx, ix, iz, origin_x)
			var v10: Vector3 = _bump_vertex(heights, nx, ix + 1, iz, origin_x)
			var v01: Vector3 = _bump_vertex(heights, nx, ix, iz + 1, origin_x)
			var v11: Vector3 = _bump_vertex(heights, nx, ix + 1, iz + 1, origin_x)
			_add_face(faces, v00, v10, v01)
			_add_face(faces, v10, v11, v01)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex in faces:
		tool.add_vertex(vertex)
	tool.generate_normals()
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	var instance := MeshInstance3D.new()
	instance.mesh = tool.commit()
	instance.material_override = _ground_material
	body.add_child(instance)
	add_child(body)
	_build_boulders()
	_build_crest_block()


func _build_crest_block() -> void:
	var x: float = LANE_X[LANE_BUMPS] + CREST_FACE_X + 2.0
	_add_box(
		Vector3(x, CREST_BLOCK_TOP * 0.5, -CREST_ALONG),
		Vector3(4.0, CREST_BLOCK_TOP, 4.0),
		_block_material
	)


func _build_boulders() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = TERRAIN_SEED
	var placed: int = 0
	while placed < BOULDER_COUNT:
		var lx: float = rng.randf_range(BOULDER_X_MIN, BOULDER_X_MAX)
		var along: float = rng.randf_range(10.0, BUMP_LENGTH - 4.0)
		var radius: float = rng.randf_range(0.2, 0.6)
		if absf(along - PATCH_ALONG) < PATCH_FLANK + 2.0 or absf(along - CREST_ALONG) < 4.0:
			continue
		placed += 1
		var base: float = _terrain_height(lx, along)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = Vector3(LANE_X[LANE_BUMPS] + lx, base + radius * 0.5, -along)
		var shape := SphereShape3D.new()
		shape.radius = radius
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
		var mesh := SphereMesh.new()
		mesh.radius = radius
		mesh.height = radius * 2.0
		mesh.radial_segments = 12
		mesh.rings = 6
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = _boulder_material
		body.add_child(instance)
		add_child(body)


func _bump_vertex(
	heights: PackedFloat32Array, nx: int, ix: int, iz: int, origin_x: float
) -> Vector3:
	return Vector3(origin_x + float(ix) * BUMP_CELL, heights[iz * nx + ix], -float(iz) * BUMP_CELL)


## Winding for Godot's front face (clockwise seen from the front): an up-facing triangle has a right-hand
## normal pointing down.
func _add_face(faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal: Vector3 = (b - a).cross(c - a)
	faces.append(a)
	if normal.y > 0.0:
		faces.append(c)
		faces.append(b)
	else:
		faces.append(b)
		faces.append(c)


## Flat 6 m, then a 6 m deep block with vertical faces on both sides, repeated, 0.30 to 1.05 m in 0.05 steps.
func _build_ledges() -> void:
	var x: float = LANE_X[LANE_LEDGES]
	var cursor: float = SPAWN_Z - 4.0
	var list: Array[Dictionary] = []
	for i in LEDGE_COUNT:
		var height: float = LEDGE_FIRST_HEIGHT + LEDGE_HEIGHT_STEP * float(i)
		var z_front: float = cursor - LEDGE_FLAT_RUN
		var z_back: float = z_front - LEDGE_DECK_DEPTH
		_add_box(
			Vector3(x, height * 0.5, (z_front + z_back) * 0.5),
			Vector3(LEDGE_WIDTH, height, LEDGE_DECK_DEPTH),
			_block_material
		)
		list.append({"h": height, "z_front": z_front, "z_back": z_back})
		cursor = z_back
	_blocks[LANE_LEDGES] = list


## One 0.8 m block with vertical faces, like the T05 pocket: climb on, then leave over the far face.
func _build_pocket() -> void:
	var x: float = LANE_X[LANE_POCKET]
	var z_front: float = SPAWN_Z - 6.0
	var z_back: float = z_front - 6.0
	_pocket_back_z = z_back
	_add_box(
		Vector3(x, POCKET_HEIGHT * 0.5, (z_front + z_back) * 0.5),
		Vector3(LEDGE_WIDTH, POCKET_HEIGHT, 6.0),
		_block_material
	)
	_blocks[LANE_POCKET] = [{"h": POCKET_HEIGHT, "z_front": z_front, "z_back": z_back}]


## Height of the talus lane above its apron at `along` metres down the lane: ValleyLayout.talus_y itself.
func _talus_height(along: float) -> float:
	return (
		ValleyLayout.talus_y(ValleyLayout.WALL_RIGHT_X + (along - TALUS_CORNER_ALONG))
		- ValleyLayout.talus_apron_y()
	)


## The valley's talus (GDD 9.1) copied exactly: flat apron, sharp concave corner, 40 degrees for 4.9 m, sharp edge,
## flat shelf, 12 m wide.
func _build_talus() -> void:
	var x: float = LANE_X[LANE_TALUS]
	var stops: Array[float] = [
		0.0,
		TALUS_CORNER_ALONG,
		TALUS_CORNER_ALONG + ValleyLayout.TALUS_SLOPE_LEN,
		TALUS_LENGTH
	]
	var faces := PackedVector3Array()
	for k in stops.size() - 1:
		var a0: float = stops[k]
		var a1: float = stops[k + 1]
		var p00 := Vector3(x - TALUS_HALF_WIDTH, _talus_height(a0), -a0)
		var p10 := Vector3(x + TALUS_HALF_WIDTH, _talus_height(a0), -a0)
		var p01 := Vector3(x - TALUS_HALF_WIDTH, _talus_height(a1), -a1)
		var p11 := Vector3(x + TALUS_HALF_WIDTH, _talus_height(a1), -a1)
		_add_face(faces, p00, p10, p01)
		_add_face(faces, p10, p11, p01)
	var rise: float = _talus_height(TALUS_CORNER_ALONG + ValleyLayout.TALUS_SLOPE_LEN) - _talus_height(TALUS_CORNER_ALONG)
	talus_slope_deg = rad_to_deg(atan(rise / ValleyLayout.TALUS_SLOPE_LEN))
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex in faces:
		tool.add_vertex(vertex)
	tool.generate_normals()
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	var instance := MeshInstance3D.new()
	instance.mesh = tool.commit()
	instance.material_override = _ground_material
	body.add_child(instance)
	add_child(body)


func _build_wall() -> void:
	var x: float = LANE_X[LANE_WALL]
	_add_box(
		Vector3(x, WALL_HEIGHT * 0.5, WALL_Z),
		Vector3(WALL_WIDTH, WALL_HEIGHT, 1.0),
		_wall_material
	)
