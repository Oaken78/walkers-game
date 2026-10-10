class_name Projectile
extends Node3D
## One pooled pulse bolt (GDD 5, 8.3). The pool moves it; this node holds the data and draws a short bright tracer.
## It is a swept ray, not a physics body: layer 4 (CombatLayers.PLAYER_PROJECTILE) is its own layer, and the pool's
## sweep uses `hit_mask` (layers 1 and 3).

const TRACER_SIZE: Vector3 = Vector3(0.08, 0.08, 0.9)
const TRACER_COLOR: Color = Color("FFB070")

static var _tracer_mesh: BoxMesh
static var _tracer_material: StandardMaterial3D

var collision_layer: int = CombatLayers.PLAYER_PROJECTILE
var hit_mask: int = CombatLayers.WORLD | CombatLayers.ENEMY
var alive: bool = false
var velocity: Vector3 = Vector3.ZERO
var damage: float = 0.0
var source: Node = null
## The index of the player weapon that fired it (-1 for none), so a hit flashes that weapon's ring.
var weapon: int = -1
var age: float = 0.0
var travelled: float = 0.0


func _init() -> void:
	visible = false
	if _tracer_mesh == null:
		_tracer_mesh = BoxMesh.new()
		_tracer_mesh.size = TRACER_SIZE
		_tracer_material = StandardMaterial3D.new()
		_tracer_material.albedo_color = TRACER_COLOR
		_tracer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var tracer := MeshInstance3D.new()
	tracer.mesh = _tracer_mesh
	tracer.material_override = _tracer_material
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The head is at the node's origin; the body trails behind it.
	tracer.position = Vector3(0.0, 0.0, TRACER_SIZE.z * 0.5)
	add_child(tracer)
