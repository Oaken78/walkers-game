class_name CameraTest
extends Node3D
## Test bed for the orbit camera: the valley plus a box stand-in at the size of the largest M0 build (the Strider).
## Scenario camera_orbit calls the helpers and reads the read-only properties below.

const BODY_SIZE := Vector3(2.2, 0.6, 1.4)
const FOOT_SIZE := Vector3(0.25, 0.20, 0.25)
const FOOT_X: float = 2.4
const FOOT_ZS: Array[float] = [-2.0, 0.0, 2.0]
const ORIGIN_HEIGHT: float = 0.96
const BODY_COLOR := Color("E6E1D6")
const FOOT_COLOR := Color("FF8A3D")
const LINE_COLOR := Color(0.25, 0.25, 0.25)

## Stand-in spots (x, z). "cliff" is 4 m from the west wall.
@export var workshop_spot: Vector2 = Vector2(-10.0, 25.0)
@export var cliff_z: float = 100.0
@export var cliff_wall_gap: float = 4.0
@export var cliff_close_gap: float = 1.0

var _feet: Array[MeshInstance3D] = []
var _lines := ImmediateMesh.new()
var _line_material: StandardMaterial3D
var _walk_speed: float = 0.0
var _walk_ticks: int = 0

## Pivot (rig position) to target origin + offset, m.
var lag_m: float:
	get:
		var goal: Vector3 = _standin.get_global_transform_interpolated().origin + _orbit.target_offset
		return _orbit.global_position.distance_to(goal)

## True when a world ray from the pivot to the camera hits nothing.
var camera_clear: bool:
	get:
		var cam: Camera3D = get_viewport().get_camera_3d()
		var query := PhysicsRayQueryParameters3D.create(
			_orbit.global_position, cam.global_position, OrbitCamera.WORLD_MASK
		)
		return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

## Camera yaw minus behind-the-stand-in yaw, wrapped to +/-180.
var yaw_error_deg: float:
	get:
		var behind: float = OrbitMath.behind_yaw(-_standin.global_basis.z)
		return wrapf(_orbit.yaw_deg - behind, -180.0, 180.0)

@onready var _valley: Valley = $Valley
@onready var _standin: Node3D = $Standin
@onready var _orbit: OrbitCamera = $OrbitCamera


func _ready() -> void:
	if _valley.terrain == null:
		await _valley.built
	_build_standin()
	_orbit.target = _standin
	place_standin("workshop")


func _physics_process(delta: float) -> void:
	if _walk_ticks <= 0:
		return
	_walk_ticks -= 1
	var pos: Vector3 = _standin.global_position
	pos += -_standin.global_basis.z * _walk_speed * delta
	pos.y = _valley.floor_height(pos.x, pos.z) + ORIGIN_HEIGHT
	_standin.global_position = pos
	_fit_feet()


## spot: "workshop" or "cliff". The stand-in faces -Z (up-valley); the camera is snapped to it.
func place_standin(spot: String) -> void:
	var xz := workshop_spot
	if spot == "cliff":
		xz = Vector2(ValleyLayout.WALL_LEFT_X + cliff_wall_gap, cliff_z)
	elif spot == "cliff_close":
		xz = Vector2(ValleyLayout.WALL_LEFT_X + cliff_close_gap, cliff_z)
	_standin.global_transform = Transform3D(
		Basis.IDENTITY, Vector3(xz.x, _valley.floor_height(xz.x, xz.y) + ORIGIN_HEIGHT, xz.y)
	)
	_walk_ticks = 0
	_fit_feet()
	_standin.reset_physics_interpolation()
	_orbit.snap()


## Straight walk along the stand-in's forward at constant speed, advanced in physics ticks.
func walk_standin(speed: float, seconds: float) -> void:
	_walk_speed = speed
	_walk_ticks = roundi(seconds * float(Engine.physics_ticks_per_second))


func hold_action(action: String, pressed: bool) -> void:
	if pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _build_standin() -> void:
	if _standin.get_child_count() > 0:
		return
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = BODY_SIZE
	body.mesh = body_mesh
	body.material_override = _material(BODY_COLOR)
	_standin.add_child(body)
	_line_material = _material(LINE_COLOR, true)
	for sx: float in [-FOOT_X, FOOT_X]:
		for fz: float in FOOT_ZS:
			var foot := MeshInstance3D.new()
			var foot_mesh := BoxMesh.new()
			foot_mesh.size = FOOT_SIZE
			foot.mesh = foot_mesh
			foot.material_override = _material(FOOT_COLOR)
			foot.position = Vector3(sx, -ORIGIN_HEIGHT + 0.5 * FOOT_SIZE.y, fz)
			_standin.add_child(foot)
			_feet.append(foot)
	var line_node := MeshInstance3D.new()
	line_node.mesh = _lines
	_standin.add_child(line_node)
	_fit_feet()


## Puts each foot on the ground under its own x, z (the terrain rises up-valley) and redraws the body lines.
func _fit_feet() -> void:
	if _feet.is_empty():
		return
	_lines.clear_surfaces()
	_lines.surface_begin(Mesh.PRIMITIVE_LINES, _line_material)
	for foot: MeshInstance3D in _feet:
		var world: Vector3 = _standin.global_transform * Vector3(foot.position.x, 0.0, foot.position.z)
		var ground: float = _valley.floor_height(world.x, world.z)
		foot.global_position = Vector3(world.x, ground + 0.5 * FOOT_SIZE.y, world.z)
		_lines.surface_add_vertex(Vector3.ZERO)
		_lines.surface_add_vertex(foot.position)
	_lines.surface_end()


func _material(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat
