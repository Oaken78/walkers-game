class_name Collector
extends Area3D
## Picks up pickups (layer 6) within 2.5 m of the chassis and pulls them in over 0.3 s. It follows
## WalkerBody.body_pose() from outside the walker: add it as a sibling of the walker, set `target` and `economy`.
## Set `enabled = false` while dead (the collapse and respawn flow), or the corpse would reclaim its own cache.

signal claimed(pickup: Pickup)

## Pickup range in the horizontal plane (GDD 5).
@export var pickup_range: float = 2.5
## A pickup more than this far above or below the chassis is out of reach (pocket nodes behind a lip).
@export var vertical_range: float = 2.5
## Sphere used to find candidates; the exact range test follows.
@export var broad_radius: float = 4.2
@export var enabled: bool = true
## Keep the per-tick cost of the scan in `tick_usec` (tests).
@export var record_timing: bool = false

var target: WalkerBody = null
var economy: Economy = null
var tick_usec: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	collision_layer = 0
	collision_mask = 32
	monitoring = true
	monitorable = false
	process_physics_priority = 10
	var sphere := SphereShape3D.new()
	sphere.radius = broad_radius
	var shape := CollisionShape3D.new()
	shape.shape = sphere
	add_child(shape)


func _physics_process(_delta: float) -> void:
	var started: int = Time.get_ticks_usec() if record_timing else 0
	if target != null and target.gait() != null:
		global_transform = target.body_pose()
	if enabled and target != null and target.gait() != null:
		_scan()
	if record_timing:
		tick_usec.append(Time.get_ticks_usec() - started)


## Where flying pickups head: the chassis centre.
func pull_target() -> Vector3:
	return global_position


## True when a pickup at `point` is inside the pickup range.
func in_range(point: Vector3) -> bool:
	var delta: Vector3 = point - global_position
	return Vector2(delta.x, delta.z).length() <= pickup_range and absf(delta.y) <= vertical_range


## 99th percentile of the recorded tick costs in microseconds.
func tick_p99_usec() -> int:
	if tick_usec.is_empty():
		return 0
	var sorted: PackedInt32Array = tick_usec.duplicate()
	sorted.sort()
	return sorted[mini(int(sorted.size() * 0.99), sorted.size() - 1)]


func _scan() -> void:
	for area: Area3D in get_overlapping_areas():
		var pickup := area as Pickup
		if pickup == null or not pickup.is_collectable():
			continue
		if not in_range(pickup.global_position):
			continue
		if pickup.claim(self):
			claimed.emit(pickup)
