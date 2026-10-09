class_name WalkerLeg
extends Node3D
## One greybox leg: hip ball, two bones, foot pad. WalkerBody owns the logic (targets, swing, planting);
## this node holds the per-leg data and poses the meshes from a TwoBoneIK solution (GDD 8.2, 10).

const BODY_COLOR: Color = Color("E6E1D6")
const ACCENT_COLOR: Color = Color("FF8A3D")
## Foot pad: at least 0.20 m tall and 0.25 m across so it reads >= 12 px at 1080p (GDD 10 rule 1).
const PAD_SIZE: Vector3 = Vector3(0.30, 0.20, 0.34)
const HIP_RADIUS: float = 0.13
const BONE_RADIUS: float = 0.06

static var _body_material: StandardMaterial3D
static var _accent_material: StandardMaterial3D

@export var upper_ratio: float = 0.45
@export var lower_ratio: float = 0.55

## -1 left, +1 right.
var side: int = 1
var reach: float = 1.0
var hip_local: Vector3 = Vector3.ZERO
var rest_local: Vector3 = Vector3.ZERO
## The rendered foot after the IK solve (world space).
var foot: Vector3 = Vector3.ZERO

var _hip_mesh: MeshInstance3D
var _upper_mesh: MeshInstance3D
var _lower_mesh: MeshInstance3D
var _foot_mesh: MeshInstance3D


static func body_material() -> StandardMaterial3D:
	if _body_material == null:
		_body_material = StandardMaterial3D.new()
		_body_material.albedo_color = BODY_COLOR
	return _body_material


static func accent_material() -> StandardMaterial3D:
	if _accent_material == null:
		_accent_material = StandardMaterial3D.new()
		_accent_material.albedo_color = ACCENT_COLOR
	return _accent_material


func _ready() -> void:
	# World-space node: the body sets every transform in global space, so nothing inherits the body's motion
	# twice (correct with physics interpolation on or off).
	top_level = true
	global_transform = Transform3D.IDENTITY
	var hip := SphereMesh.new()
	hip.radius = HIP_RADIUS
	hip.height = HIP_RADIUS * 2.0
	_hip_mesh = _make_mesh(hip, accent_material())
	var bone := CylinderMesh.new()
	bone.top_radius = BONE_RADIUS
	bone.bottom_radius = BONE_RADIUS
	bone.height = 1.0
	bone.radial_segments = 8
	bone.rings = 1
	_upper_mesh = _make_mesh(bone, body_material())
	_lower_mesh = _make_mesh(bone, body_material())
	var pad := BoxMesh.new()
	pad.size = PAD_SIZE
	_foot_mesh = _make_mesh(pad, accent_material())


func setup(
	leg_side: int, leg_reach: float, hip: Vector3, rest: Vector3
) -> void:
	side = leg_side
	reach = leg_reach
	hip_local = hip
	rest_local = rest


## Solves the leg for a hip and a foot, poses the meshes, and stores the rendered foot.
func pose(hip: Vector3, foot_target: Vector3, pole: Vector3, pad_basis: Basis) -> void:
	var solution := TwoBoneIK.solve(hip, foot_target, reach * upper_ratio, reach * lower_ratio, pole)
	foot = foot_target if solution.reached else solution.foot
	_hip_mesh.global_transform = Transform3D(Basis.IDENTITY, hip)
	_place_bone(_upper_mesh, hip, solution.knee)
	_place_bone(_lower_mesh, solution.knee, foot)
	_foot_mesh.global_transform = Transform3D(pad_basis, foot + Vector3.UP * (PAD_SIZE.y * 0.5))


func _make_mesh(mesh: Mesh, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	add_child(instance)
	return instance


func _place_bone(bone: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var span: Vector3 = to - from
	var length: float = span.length()
	if length < 0.00001:
		return
	var axis: Vector3 = span / length
	var helper: Vector3 = Vector3.UP if absf(axis.y) < 0.99 else Vector3.RIGHT
	var x_axis: Vector3 = helper.cross(axis).normalized()
	var z_axis: Vector3 = x_axis.cross(axis)
	bone.global_transform = Transform3D(Basis(x_axis, axis * length, z_axis), (from + to) * 0.5)
