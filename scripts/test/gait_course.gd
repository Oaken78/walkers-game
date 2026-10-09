class_name GaitCourse
extends Node3D
## The gait test course (T03): flat, bumps, ledges, wall and pocket lanes on one big ground plane, built in code
## from a fixed seed, plus the helpers the scenarios call (use_build, spawn_at, hold_action, record_result,
## show_pair, autopilot, camera modes, yaw source). One plain camera follows the walker; T04's rig replaces it later.

const WALKER_SCENE: PackedScene = preload("res://scenes/walker/walker.tscn")
const GROUND_COLOR: Color = Color("CAB294")
const LANE_FLAT: String = "flat"
const LANE_BUMPS: String = "bumps"
const LANE_LEDGES: String = "ledges"
const LANE_WALL: String = "wall"
const LANE_POCKET: String = "pocket"
const LANE_PATCH_A: String = "patch_a"
const LANE_PATCH_B: String = "patch_b"
const LANE_X: Dictionary = {
	"flat": 0.0, "bumps": 60.0, "ledges": 120.0, "wall": 180.0, "pocket": 240.0
}
## Half-width of the area each lane is meant to be driven in (edge margins are measured against it).
const LANE_HALF_WIDTH: Dictionary = {
	"flat": 20.0, "bumps": 15.0, "ledges": 5.0, "wall": 10.0, "pocket": 10.0
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
const PATCH_B_DEG: float = 38.0
const PATCH_FLANK: float = 2.4
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
const CAMERA_PITCH_DEG: float = 25.0
const CAMERA_AZIMUTH_DEG: float = 20.0
const TERRAIN_SEED: int = 99
const AUTOPILOT_PERIOD_S: float = 8.0
const AUTOPILOT_CENTERING: float = 0.12
const AUTOPILOT_DEAD_DEG: float = 3.0

@export var camera_distance: float = 8.0

## Mean slope of the two steep patches over a 2 m disc, in degrees (28-30 and 35-40).
var patch_a_slope_deg: float = 0.0
var patch_b_slope_deg: float = 0.0
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
		if _walker == null or _yaw_source == null:
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
## Every foot is past the far side of the 29 degree patch (A) or the 38 degree patch (B).
var past_patch: bool:
	get:
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
		return _walker.global_position.z + (PATCH_ALONG - PATCH_FLANK) if _walker != null else 0.0
## Steps per leg per second of the reference run (record_steps_ref) and the current run's ratio to it.
var steps_ref: float = 0.0
var steps_ratio: float:
	get:
		return _telemetry.steps_per_s / steps_ref if steps_ref > 0.0 else 0.0

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
var _camera_mode: String = "follow"
var _autopilot: bool = false
var _autopilot_time: float = 0.0
var _autopilot_center: float = 0.0
var _yaw_source: Node3D
var _yaw_start_sign: float = 0.0
var _pocket_back_z: float = 0.0


func _ready() -> void:
	process_physics_priority = 50
	_walker = get_node("%Walker")
	_telemetry = get_node("%Telemetry")
	_camera = get_node("Camera")
	_make_materials()
	_build_environment()
	_build_ground()
	_build_flat()
	_build_bumps()
	_build_ledges()
	_build_wall()
	_build_pocket()
	_telemetry.observe(_walker)
	_walker.foot_planted.connect(_on_foot_planted)
	spawn_at(LANE_FLAT)


func _physics_process(delta: float) -> void:
	if _first_tick:
		# The static bodies are registered with the physics server by now: plant on the real ground.
		_first_tick = false
		spawn_at(_lane)
	if _autopilot:
		_run_autopilot(delta)
	_track_step_up()
	_track_yaw_overshoot()
	if _freeze_at >= 0.0:
		for i in _walker.leg_count():
			if _walker.gait().swing_progress(i) >= _freeze_at:
				get_tree().paused = true
				_freeze_at = -1.0
				break


func _process(_delta: float) -> void:
	if _walker == null:
		return
	var focus: Vector3 = _walker.get_global_transform_interpolated().origin
	var yaw: float = _walker.yaw_radians()
	if _pair_walker != null:
		var other: Vector3 = _pair_walker.get_global_transform_interpolated().origin
		focus = (focus + other) * 0.5
	if _camera_mode == "pair":
		# Perpendicular to the pair: both walkers at the same distance, seen from behind.
		_camera.global_position = focus + Vector3(0.0, 2.2, camera_distance)
		_camera.look_at(focus + Vector3(0.0, 0.9, 0.0), Vector3.UP)
		return
	if _camera_mode == "side":
		# Side-on, level with the legs: a lifted foot shows as a gap under the pad.
		var right: Vector3 = Basis(Vector3.UP, yaw) * Vector3.RIGHT
		var toward_sun: Vector3 = _sun.global_transform.basis.z
		var lit_side: float = 1.0 if right.dot(toward_sun) >= 0.0 else -1.0
		_camera.global_position = focus + right * (camera_distance * lit_side) + Vector3(0.0, 0.9, 0.0)
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
func spawn_at(lane: String) -> void:
	var origin: Vector3 = _spawn_point(lane)
	if origin.y < -100.0:
		push_error("GaitCourse.spawn_at: unknown lane %s" % lane)
		return
	_lane = lane
	_walker.teleport(Transform3D(Basis.IDENTITY, origin))
	_last_plant.resize(_walker.leg_count())
	for i in _walker.leg_count():
		_last_plant[i] = _walker.foot_position(i)
	mark()


func mark() -> void:
	_mark = _walker.global_position


func hold_action(action: String, pressed: bool) -> void:
	if pressed:
		Input.action_press(action)
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


func resume() -> void:
	get_tree().paused = false


## Remembers the current run's steps per leg per second as the reference for steps_ratio.
func record_steps_ref() -> void:
	steps_ref = _telemetry.steps_per_s


func set_camera_mode(mode: String, distance: float = 8.0) -> void:
	_camera_mode = mode
	camera_distance = distance


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


func _spawn_point(lane: String) -> Vector3:
	match lane:
		LANE_PATCH_A:
			return Vector3(LANE_X[LANE_BUMPS] - PATCH_X, SPAWN_Y, -(PATCH_ALONG - 7.0))
		LANE_PATCH_B:
			return Vector3(LANE_X[LANE_BUMPS] + PATCH_X, SPAWN_Y, -(PATCH_ALONG - 7.0))
		"boulders":
			return Vector3(LANE_X[LANE_BUMPS] + (BOULDER_X_MIN + BOULDER_X_MAX) * 0.5, SPAWN_Y, -6.0)
	if not LANE_X.has(lane):
		return Vector3(0.0, -1000.0, 0.0)
	return Vector3(LANE_X[lane], SPAWN_Y, SPAWN_Z)


func _lane_key() -> String:
	if _lane == LANE_PATCH_A or _lane == LANE_PATCH_B or _lane == "boulders":
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


func _yaw_target() -> float:
	if _yaw_source == null:
		return 0.0
	var heading: Vector3 = -_yaw_source.global_transform.basis.z
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
	sun.rotation_degrees = Vector3(-52.0, -35.0, 0.0)
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
	var mask: float = maxf(_patch_mask(lx, along, -PATCH_X), _patch_mask(lx, along, PATCH_X))
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
		+ _patch_height(lx, along, PATCH_X, tan(deg_to_rad(PATCH_B_DEG)))
	)


func _patch_mask(lx: float, along: float, cx: float) -> float:
	var across: float = 1.0 - smoothstep(PATCH_HALF_WIDTH, PATCH_HALF_WIDTH + 4.0, absf(lx - cx))
	# Hills fade out over 6 m before the patch (a short fade would leave a ditch at the foot of the flank).
	var lengthwise: float = 1.0 - smoothstep(PATCH_FLANK, PATCH_FLANK + 6.0, absf(along - PATCH_ALONG))
	return across * lengthwise


## A ridge across the patch: flanks at exactly the patch slope, crest PATCH_FLANK x tan(slope) high.
func _patch_height(lx: float, along: float, cx: float, tan_slope: float) -> float:
	var taper: float = 1.0 - smoothstep(PATCH_HALF_WIDTH - 1.0, PATCH_HALF_WIDTH, absf(lx - cx))
	return maxf(0.0, tan_slope * (PATCH_FLANK - absf(along - PATCH_ALONG))) * taper


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
	patch_b_slope_deg = _disc_slope_deg(PATCH_X)
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


func _build_boulders() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = TERRAIN_SEED
	var placed: int = 0
	while placed < BOULDER_COUNT:
		var lx: float = rng.randf_range(BOULDER_X_MIN, BOULDER_X_MAX)
		var along: float = rng.randf_range(10.0, BUMP_LENGTH - 4.0)
		var radius: float = rng.randf_range(0.2, 0.6)
		if absf(along - PATCH_ALONG) < PATCH_FLANK + 2.0:
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


func _build_wall() -> void:
	var x: float = LANE_X[LANE_WALL]
	_add_box(
		Vector3(x, WALL_HEIGHT * 0.5, WALL_Z),
		Vector3(WALL_WIDTH, WALL_HEIGHT, 1.0),
		_wall_material
	)
