class_name AimTarget
extends Node3D
## Stand-in target for the aim range (GDD 5 "Drone" hitbox, "Feedback on landing a hit"): a 0.6 m sphere hurtbox on
## layer 3 with 45 HP and a 0.06 s white flash on every hit. The drone (T07) replaces it in fights.

const RADIUS_M: float = 0.6
const MAX_HP: float = 45.0
const FLASH_S: float = 0.06
const THREAT_COLOR: Color = Color("E8345A")

var health: Health
var hurtbox: Hurtbox
var flash_left_s: float = 0.0

var _material: StandardMaterial3D


func _ready() -> void:
	health = Health.new(MAX_HP)
	hurtbox = Hurtbox.new()
	hurtbox.health = health
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS_M
	shape.shape = sphere
	hurtbox.add_child(shape)
	add_child(hurtbox)
	var mesh := SphereMesh.new()
	mesh.radius = RADIUS_M
	mesh.height = RADIUS_M * 2.0
	_material = StandardMaterial3D.new()
	_material.albedo_color = THREAT_COLOR
	var piece := MeshInstance3D.new()
	piece.mesh = mesh
	piece.material_override = _material
	add_child(piece)
	hurtbox.hit_taken.connect(_on_hit_taken)
	health.depleted.connect(_on_depleted)


func _physics_process(delta: float) -> void:
	if flash_left_s > 0.0:
		flash_left_s = maxf(flash_left_s - delta, 0.0)
		_material.albedo_color = Color.WHITE if flash_left_s > 0.0 else THREAT_COLOR


func hits() -> int:
	return hurtbox.hits_taken


func _on_hit_taken(_damage: float, _source: Node, _point: Vector3) -> void:
	flash_left_s = FLASH_S
	_material.albedo_color = Color.WHITE


## A dead target stops being a target: shots and the aim ray pass through.
func _on_depleted() -> void:
	hurtbox.collision_layer = 0
	visible = false
