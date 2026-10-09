class_name PlayerHurtbox
extends Hurtbox
## The player's hurtbox (T06 plan note): a chassis-sized box on layer 2 that follows the drawn body pose, so a shot
## that passes between the legs misses (M0 criterion 5). Enemy projectiles (T07) put layer 2 in their mask.
## It moves in the physics tick after the walker (priority 100), so it matches the pose the walker drew that tick.

@export var walker: WalkerBody

var _shape: CollisionShape3D
var _box: BoxShape3D
var _half_height: float = 0.0


func _init() -> void:
	super()
	collision_layer = CombatLayers.PLAYER
	process_physics_priority = 100


func _ready() -> void:
	top_level = true
	_box = BoxShape3D.new()
	_shape = CollisionShape3D.new()
	_shape.shape = _box
	add_child(_shape)
	if walker != null:
		walker.build_applied.connect(_on_build_applied)
		_on_build_applied()


func _physics_process(_delta: float) -> void:
	if walker != null and is_instance_valid(walker):
		follow(walker.body_pose())


## Box size (m) and the pose of the body's underside; the box is centred half its height above it.
func set_box(size: Vector3) -> void:
	_box.size = size
	_half_height = size.y * 0.5


## Places the box on a body pose (the walker's body_pose(): origin at the chassis underside).
func follow(pose: Transform3D) -> void:
	global_transform = pose * Transform3D(Basis.IDENTITY, Vector3(0.0, _half_height, 0.0))


func box_size() -> Vector3:
	return _box.size


func _on_build_applied() -> void:
	var chassis: MeshInstance3D = walker.get_node_or_null("Chassis") as MeshInstance3D
	if chassis == null or not (chassis.mesh is BoxMesh):
		return
	set_box((chassis.mesh as BoxMesh).size)
	follow(walker.body_pose())
