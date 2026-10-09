class_name PlayerHurtbox
extends Hurtbox
## The player's hurtbox (T06 plan note): a chassis-sized box on layer 2 that follows the drawn chassis, which is the
## walker's body pose plus the chassis centre offset, so a shot that passes between the legs misses (M0 criterion 5).
## Enemy projectiles (T07) put layer 2 in their mask. It moves in the physics tick after the walker (priority 100),
## so it matches the chassis the walker drew that tick.

@export var walker: WalkerBody

var _shape: CollisionShape3D
var _box: BoxShape3D
var _chassis: MeshInstance3D


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
	if _chassis != null and is_instance_valid(_chassis):
		follow(_chassis.global_transform)


## The box size (m).
func set_box(size: Vector3) -> void:
	_box.size = size


## Places the box: `centre` is the transform of the box's centre (the walker's drawn chassis).
func follow(centre: Transform3D) -> void:
	global_transform = centre


func box_size() -> Vector3:
	return _box.size


func _on_build_applied() -> void:
	_chassis = walker.get_node_or_null("Chassis") as MeshInstance3D
	if _chassis == null or not (_chassis.mesh is BoxMesh):
		push_error("PlayerHurtbox: the walker has no box chassis to follow")
		return
	set_box((_chassis.mesh as BoxMesh).size)
	follow(_chassis.global_transform)
