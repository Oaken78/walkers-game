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
## Pole = up + POLE_OUTWARD x outward: outward enough that a foot passing under (or 0.3 x reach inboard of) the
## hip never turns the pole parallel to the leg and flips the knee; knee rise at +/-0.5 x reach fore-aft stays 0.105.
const POLE_OUTWARD: float = 0.8

static var _body_material: StandardMaterial3D
static var _accent_material: StandardMaterial3D

## Bones 0.46 + 0.69 x reach = 1.15 x reach: the leg never straightens inside the 0.99 x reach sphere (GDD 5).
@export var upper_ratio: float = 0.46
@export var lower_ratio: float = 0.69

## -1 left, +1 right.
var side: int = 1
var reach: float = 1.0
var hip_local: Vector3 = Vector3.ZERO
var rest_local: Vector3 = Vector3.ZERO
## Bend-plane hint in body space: up plus an outward part from the rest direction (fixed per leg, never the
## current hip-to-foot vector, so a foot passing under the hip cannot flip the knee).
var pole_local: Vector3 = Vector3.UP
## The knee of the last pose (world space).
var knee: Vector3 = Vector3.ZERO
## The rendered foot after the IK solve (world space).
var foot: Vector3 = Vector3.ZERO

var _hip_mesh: MeshInstance3D
var _upper_mesh: MeshInstance3D
var _lower_mesh: MeshInstance3D
var _foot_mesh: MeshInstance3D
var _strut_mesh: MeshInstance3D


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
	var strut := CylinderMesh.new()
	strut.top_radius = BONE_RADIUS * 1.3
	strut.bottom_radius = BONE_RADIUS * 1.3
	strut.height = 1.0
	strut.radial_segments = 8
	strut.rings = 1
	_strut_mesh = _make_mesh(strut, body_material())


func setup(leg_side: int, leg_reach: float, hip: Vector3, rest: Vector3) -> void:
	side = leg_side
	reach = leg_reach
	hip_local = hip
	rest_local = rest
	var outward := Vector3(rest.x - hip.x, 0.0, rest.z - hip.z)
	outward = outward.normalized() if outward.length() > 0.0001 else Vector3(float(side), 0.0, 0.0)
	pole_local = Vector3.UP + outward * POLE_OUTWARD


## Where the drawn pad's box centre is in the world (a test compares it with the telemetry's pad box).
func pad_mesh_center() -> Vector3:
	return _foot_mesh.global_position


## Solves the leg for a hip and a foot, poses the meshes, and stores the rendered foot.
func pose(
	hip: Vector3, foot_target: Vector3, pole: Vector3, pad_basis: Basis, strut_top: Vector3
) -> void:
	var solution := TwoBoneIK.solve(hip, foot_target, reach * upper_ratio, reach * lower_ratio, pole)
	foot = foot_target if solution.reached else solution.foot
	knee = solution.knee
	_place_bone(_strut_mesh, hip, strut_top)
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
