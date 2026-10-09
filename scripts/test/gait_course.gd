class_name GaitCourse
extends Node3D
## The gait test course (T03): flat, bumps, ledges and a wall lane, built in code from a fixed seed, plus the
## helpers the scenarios call (use_build, spawn_at, hold_action, record_result, show_pair).
## One plain camera follows the walker at 8 m and 25 deg pitch from behind-right; T04's rig replaces it later.

const WALKER_SCENE: PackedScene = preload("res://scenes/walker/walker.tscn")
const LANE_FLAT: String = "flat"
const LANE_BUMPS: String = "bumps"
const LANE_LEDGES: String = "ledges"
const LANE_WALL: String = "wall"
const LANE_X: Dictionary = {"flat": 0.0, "bumps": 60.0, "ledges": 120.0, "wall": 180.0}
const FLAT_LENGTH: float = 150.0
const FLAT_WIDTH: float = 12.0
const BUMP_LENGTH: float = 100.0
const BUMP_WIDTH: float = 30.0
const BUMP_CELL: float = 0.5
const BUMP_TARGET_SLOPE_DEG: float = 29.0
const BUMP_NOISE_FREQUENCY: float = 0.12
const BUMP_BASE_AMPLITUDE: float = 0.25
const BUMP_FEATURES: int = 140
const LEDGE_WIDTH: float = 10.0
const LEDGE_FLAT_RUN: float = 6.0
const LEDGE_DECK_DEPTH: float = 6.0
const LEDGE_FIRST_HEIGHT: float = 0.30
const LEDGE_HEIGHT_STEP: float = 0.05
const LEDGE_COUNT: int = 16
## The back of each block is a ramp the walker can walk down (a leg cannot step down more than ~0.3 x reach).
const LEDGE_RAMP_DEG: float = 22.0
const WALL_Z: float = -14.0
const WALL_HEIGHT: float = 1.5
const WALL_WIDTH: float = 20.0
const SPAWN_Z: float = -2.0
const SPAWN_Y: float = 1.5
const CAMERA_PITCH_DEG: float = 25.0
const CAMERA_AZIMUTH_DEG: float = 20.0
const TERRAIN_SEED: int = 1234

@export var camera_distance: float = 8.0

## Steepest bump triangle in degrees (28-30).
var max_slope_deg: float = 0.0
var a_speed: float = 0.0
var a_step_up: float = 0.0
var b_speed: float = 0.0
var b_step_up: float = 0.0
var contrast_speed: float = 0.0
var contrast_step_up: float = 0.0
## Straight-line distance the walker has travelled since mark().
var moved_since_mark: float:
	get:
		return _walker.global_position.distance_to(_mark) if _walker != null else 0.0

var _walker: WalkerBody
var _telemetry: WalkerTelemetry
var _camera: Camera3D
var _pair_walker: WalkerBody
var _lane: String = LANE_FLAT
var _mark: Vector3 = Vector3.ZERO
var _ledges: Array[Dictionary] = []
var _last_plant: PackedVector3Array = PackedVector3Array()
var _ground_material: StandardMaterial3D
var _block_material: StandardMaterial3D
var _wall_material: StandardMaterial3D
var _first_tick: bool = true


func _ready() -> void:
	process_physics_priority = 50
	_walker = get_node("%Walker")
	_telemetry = get_node("%Telemetry")
	_camera = get_node("Camera")
	_make_materials()
	_build_environment()
	_build_flat()
	_build_bumps()
	_build_ledges()
	_build_wall()
	_telemetry.observe(_walker)
	_walker.foot_planted.connect(_on_foot_planted)
	spawn_at(LANE_FLAT)


func _physics_process(_delta: float) -> void:
	if _first_tick:
		# The static bodies are registered with the physics server by now: plant on the real ground.
		_first_tick = false
		spawn_at(_lane)
	_track_step_up()


func _process(_delta: float) -> void:
	if _walker == null:
		return
	var focus: Vector3 = _walker.get_global_transform_interpolated().origin
	var yaw: float = _walker.yaw_radians()
	var distance: float = camera_distance
	if _pair_walker != null:
		var other: Vector3 = _pair_walker.get_global_transform_interpolated().origin
		focus = (focus + other) * 0.5
	var pitch: float = deg_to_rad(CAMERA_PITCH_DEG)
	var azimuth: float = deg_to_rad(CAMERA_AZIMUTH_DEG)
	var horizontal: float = distance * cos(pitch)
	var offset := Vector3(horizontal * sin(azimuth), distance * sin(pitch), horizontal * cos(azimuth))
	_camera.global_position = focus + Basis(Vector3.UP, yaw) * offset
	_camera.look_at(focus + Vector3(0.0, 0.5, 0.0), Vector3.UP)


# --- Scenario helpers ------------------------------------------------------------------------------------------


## "scout", "strider", "crawler" or "quad" (4 medium legs and 1 cannon: the wave gait).
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
		_:
			push_error("GaitCourse.use_build: unknown build %s" % build_name)
			return
	_remove_pair()
	_walker.apply_build(build)


## Teleports the walker to the start of a lane, facing -Z. Telemetry keeps its numbers (call reset() on it).
func spawn_at(lane: String) -> void:
	if not LANE_X.has(lane):
		push_error("GaitCourse.spawn_at: unknown lane %s" % lane)
		return
	_lane = lane
	var origin := Vector3(LANE_X[lane], SPAWN_Y, SPAWN_Z)
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
	Input.action_release("move_forward")
	Input.action_release("move_back")
	Input.action_release("turn_left")
	Input.action_release("turn_right")
	Input.action_release("strafe_left")
	Input.action_release("strafe_right")
	Input.action_release("aim")


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


## The Strider and the Crawler side by side on the flat lane (hold move_forward to walk them).
func show_pair() -> void:
	_walker.apply_build(WalkerBuild.strider())
	_lane = LANE_FLAT
	var left := Vector3(LANE_X[LANE_FLAT] - 3.5, SPAWN_Y, SPAWN_Z)
	var right := Vector3(LANE_X[LANE_FLAT] + 3.5, SPAWN_Y, SPAWN_Z)
	_walker.teleport(Transform3D(Basis.IDENTITY, left))
	_remove_pair()
	_pair_walker = WALKER_SCENE.instantiate()
	add_child(_pair_walker)
	_pair_walker.apply_build(WalkerBuild.crawler())
	_pair_walker.teleport(Transform3D(Basis.IDENTITY, right))
	camera_distance = 15.0
	mark()


# --- Ledge step-up measurement ---------------------------------------------------------------------------------


func _track_step_up() -> void:
	if _lane != LANE_LEDGES or _walker == null or _walker.gait() == null:
		return
	# "Every foot planted on the block's top": each leg's most recent plant point lies on the deck. (A walking
	# tripod gait never has all feet on the ground in the same tick.)
	if _last_plant.size() != _walker.leg_count():
		return
	var z: float = _walker.global_position.z
	for block in _ledges:
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


func _on_foot_planted(leg: int, position: Vector3, _normal: Vector3) -> void:
	if leg < _last_plant.size():
		_last_plant[leg] = position


func _remove_pair() -> void:
	if _pair_walker != null:
		_pair_walker.queue_free()
		_pair_walker = null
		camera_distance = 8.0


# --- Course construction ---------------------------------------------------------------------------------------


func _make_materials() -> void:
	_ground_material = StandardMaterial3D.new()
	_ground_material.albedo_color = Color(0.36, 0.40, 0.34)
	_ground_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_block_material = StandardMaterial3D.new()
	_block_material.albedo_color = Color(0.52, 0.47, 0.40)
	_wall_material = StandardMaterial3D.new()
	_wall_material.albedo_color = Color(0.30, 0.32, 0.38)


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
	sun.rotation_degrees = Vector3(-52.0, -35.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)


func _add_box(center: Vector3, size: Vector3, material: Material, basis: Basis = Basis.IDENTITY) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.transform = Transform3D(basis, center)
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	body.add_child(instance)
	add_child(body)


func _build_flat() -> void:
	# Thick slab so its top face sits at y = 0; starts 10 m behind the spawn point.
	var length: float = FLAT_LENGTH + 10.0
	_add_box(
		Vector3(LANE_X[LANE_FLAT], -0.5, 10.0 - length * 0.5),
		Vector3(FLAT_WIDTH, 1.0, length),
		_ground_material
	)


func _build_bumps() -> void:
	var nx: int = int(BUMP_WIDTH / BUMP_CELL) + 1
	var nz: int = int(BUMP_LENGTH / BUMP_CELL) + 1
	var noise := FastNoiseLite.new()
	noise.seed = TERRAIN_SEED
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = BUMP_NOISE_FREQUENCY
	var heights := PackedFloat32Array()
	heights.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			var across: float = float(ix) * BUMP_CELL
			var along: float = float(iz) * BUMP_CELL
			# Fade the bumps in over the first 8 m and out at the sides so the lane has no cliffs.
			var fade: float = smoothstep(0.0, 3.0, minf(across, BUMP_WIDTH - across))
			fade *= smoothstep(2.0, 8.0, along)
			heights[iz * nx + ix] = noise.get_noise_2d(across, along) * fade * BUMP_BASE_AMPLITUDE
	# Sparse steep bumps on top of the gentle rolling base: they set the 28-30 deg maximum.
	var rng := RandomNumberGenerator.new()
	rng.seed = TERRAIN_SEED
	for n in BUMP_FEATURES:
		var cx: float = rng.randf_range(2.0, BUMP_WIDTH - 2.0)
		var cz: float = rng.randf_range(8.0, BUMP_LENGTH - 2.0)
		var radius: float = rng.randf_range(0.9, 1.5)
		var peak: float = rng.randf_range(0.20, 0.40)
		for iz in nz:
			for ix in nx:
				var dist: float = Vector2(float(ix) * BUMP_CELL - cx, float(iz) * BUMP_CELL - cz).length()
				if dist < radius:
					var c: float = cos(dist / radius * PI * 0.5)
					heights[iz * nx + ix] += peak * c * c
	# Heights scale linearly with the gradient, so one factor makes the steepest triangle exactly the target.
	var steepest: float = 0.0
	for iz in nz - 1:
		for ix in nx - 1:
			steepest = maxf(steepest, _cell_steepest(heights, nx, ix, iz))
	var scale: float = tan(deg_to_rad(BUMP_TARGET_SLOPE_DEG)) / maxf(steepest, 0.0001)
	for i in heights.size():
		heights[i] *= scale
	max_slope_deg = rad_to_deg(atan(steepest * scale))

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
	# A slab under the whole lane catches anything that slips past the mesh and covers the spawn area.
	_add_box(
		Vector3(LANE_X[LANE_BUMPS], -1.5, 10.0 - (BUMP_LENGTH + 10.0) * 0.5),
		Vector3(BUMP_WIDTH, 1.0, BUMP_LENGTH + 10.0),
		_ground_material
	)


func _bump_vertex(heights: PackedFloat32Array, nx: int, ix: int, iz: int, origin_x: float) -> Vector3:
	return Vector3(
		origin_x + float(ix) * BUMP_CELL, heights[iz * nx + ix], -float(iz) * BUMP_CELL
	)


## Steepest of the two triangles of one cell, as tan(slope).
func _cell_steepest(heights: PackedFloat32Array, nx: int, ix: int, iz: int) -> float:
	var v00: Vector3 = _bump_vertex(heights, nx, ix, iz, 0.0)
	var v10: Vector3 = _bump_vertex(heights, nx, ix + 1, iz, 0.0)
	var v01: Vector3 = _bump_vertex(heights, nx, ix, iz + 1, 0.0)
	var v11: Vector3 = _bump_vertex(heights, nx, ix + 1, iz + 1, 0.0)
	return maxf(_triangle_tan(v00, v10, v01), _triangle_tan(v10, v11, v01))


func _triangle_tan(a: Vector3, b: Vector3, c: Vector3) -> float:
	var normal: Vector3 = (b - a).cross(c - a)
	return Vector2(normal.x, normal.z).length() / maxf(absf(normal.y), 0.000001)


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


func _build_ledges() -> void:
	var x: float = LANE_X[LANE_LEDGES]
	var cursor: float = SPAWN_Z - 4.0
	var ramp_slope: float = tan(deg_to_rad(LEDGE_RAMP_DEG))
	for i in LEDGE_COUNT:
		var height: float = LEDGE_FIRST_HEIGHT + LEDGE_HEIGHT_STEP * float(i)
		var z_front: float = cursor - LEDGE_FLAT_RUN
		var z_back: float = z_front - LEDGE_DECK_DEPTH
		_add_box(
			Vector3(x, height * 0.5, (z_front + z_back) * 0.5),
			Vector3(LEDGE_WIDTH, height, LEDGE_DECK_DEPTH),
			_block_material
		)
		# Ramp down the back: a slab whose top face runs from the deck edge to the ground.
		var run: float = height / ramp_slope
		var span: float = sqrt(height * height + run * run)
		var up := Vector3(0.0, run, -height) / span
		var along := Vector3(0.0, height, run) / span
		var slab_basis := Basis(Vector3.RIGHT, up, along)
		var top_center := Vector3(x, height * 0.5, z_back - run * 0.5)
		var thickness: float = 0.4
		_add_box(
			top_center - up * (thickness * 0.5),
			Vector3(LEDGE_WIDTH, thickness, span),
			_block_material,
			slab_basis
		)
		_ledges.append({"h": height, "z_front": z_front, "z_back": z_back})
		cursor = z_back - run
	var end_z: float = cursor - 12.0
	_add_box(
		Vector3(x, -0.5, (10.0 + end_z) * 0.5),
		Vector3(LEDGE_WIDTH, 1.0, 10.0 - end_z),
		_ground_material
	)


func _build_wall() -> void:
	var x: float = LANE_X[LANE_WALL]
	var length: float = 10.0 + 40.0
	_add_box(Vector3(x, -0.5, 10.0 - length * 0.5), Vector3(WALL_WIDTH, 1.0, length), _ground_material)
	_add_box(
		Vector3(x, WALL_HEIGHT * 0.5, WALL_Z),
		Vector3(WALL_WIDTH, WALL_HEIGHT, 1.0),
		_wall_material
	)
