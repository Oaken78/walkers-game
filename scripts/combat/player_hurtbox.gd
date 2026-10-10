class_name PlayerHurtbox
extends Hurtbox
## The player's hurtbox (T06 plan note): a chassis-sized box on layer 2 that follows the drawn chassis, which is the
## walker's body pose plus the chassis centre offset, so a shot that passes between the legs misses (M0 criterion 5).
## It moves in the physics tick after the walker (priority 100), so it matches the chassis the walker drew that tick.
## Layer 2 contract for enemy projectiles (T07): the WalkerBody itself is on layer 2 too (its chassis box, the hip
## spheres and the wide Guard cylinder), so a bolt must query layer 2 for AREAS ONLY (collide_with_bodies = false).
## Then only this hurtbox can be hit, and a bolt that passes between the legs misses (M0 criterion 5).

@export var walker: WalkerBody

var _shape: CollisionShape3D
var _box: BoxShape3D
var _following: bool = false


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
	if _following and is_instance_valid(walker):
		follow(_chassis_transform())


## The box size (m).
func set_box(size: Vector3) -> void:
	_box.size = size


## Places the box: `centre` is the transform of the box's centre (the walker's drawn chassis).
func follow(centre: Transform3D) -> void:
	global_transform = centre


func box_size() -> Vector3:
	return _box.size


func _on_build_applied() -> void:
	if not walker.is_node_ready():
		# This hurtbox came up before its walker (a scene may order them so); build_applied follows.
		return
	var size: Vector3 = walker.chassis_size()
	if size == Vector3.ZERO:
		push_error("PlayerHurtbox: the walker has no box chassis to follow")
		return
	_following = true
	set_box(size)
	follow(_chassis_transform())


## The drawn chassis: the body pose plus the chassis centre offset.
func _chassis_transform() -> Transform3D:
	return walker.body_pose() * Transform3D(Basis.IDENTITY, walker.chassis_center())
