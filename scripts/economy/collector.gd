class_name Collector
extends Area3D
## Picks up pickups (layer 6) within 2.5 m of the chassis and pulls them in over 0.3 s. It follows
## WalkerBody.body_pose() from outside the walker: add it as a sibling of the walker, set `target` and `economy`.
## No target, no scan. T12 sets `enabled = false` during the death collapse and back to true once the walker has
## respawned: the fresh-cache grace below only lifts while the collector scans. On a death or recall (Economy.dropped) the pulls in flight are
## cancelled, and a wreck cache dropped inside the pickup range stays unclaimable until the collector has left that
## range once (so a walker that dies on the spot cannot reclaim its own cache).

signal claimed(pickup: Pickup)

## Pickup range in the horizontal plane (GDD 5).
@export var pickup_range: float = 2.5
## A pickup more than this far above or below the chassis is out of reach (pocket nodes behind a lip).
@export var vertical_range: float = 2.5
## Sphere used to find candidates; the exact range test follows. Read once in _ready.
@export var broad_radius: float = 4.2
@export var enabled: bool = true
## Keep the per-tick cost (scan plus every pickup's pull) in `tick_usec` (tests).
@export var record_timing: bool = false

var target: WalkerBody = null
var tick_usec: PackedInt32Array = PackedInt32Array()

## The ledger; pulls are cancelled when it reports a death or recall.
var economy: Economy = null:
	set(value):
		if economy != null and economy.dropped.is_connected(_on_dropped):
			economy.dropped.disconnect(_on_dropped)
		economy = value
		if economy != null:
			economy.dropped.connect(_on_dropped)

var _claims: Array[Pickup] = []
var _await_exit: bool = false


func _init() -> void:
	collision_layer = 0
	collision_mask = 32
	monitoring = true
	monitorable = false
	process_physics_priority = 10


func _ready() -> void:
	var sphere := SphereShape3D.new()
	sphere.radius = broad_radius
	var shape := CollisionShape3D.new()
	shape.shape = sphere
	add_child(shape)
	Pickup.profile = record_timing


func _physics_process(_delta: float) -> void:
	var started: int = Time.get_ticks_usec() if record_timing else 0
	if target != null and target.gait() != null:
		global_transform = target.body_pose()
	if enabled and target != null and target.gait() != null:
		_scan()
	if record_timing:
		tick_usec.append(Time.get_ticks_usec() - started + Pickup.profile_usec)
		Pickup.profile_usec = 0


## Where flying pickups head: the chassis centre.
func pull_target() -> Vector3:
	return global_position


## True when a pickup at `point` is inside the pickup range.
func in_range(point: Vector3) -> bool:
	var delta: Vector3 = point - global_position
	return Vector2(delta.x, delta.z).length() <= pickup_range and absf(delta.y) <= vertical_range


## Claims the pickup when it is collectable, in range and not blocked by the fresh-cache rule.
func try_claim(pickup: Pickup) -> bool:
	if not pickup.is_collectable() or not in_range(pickup.global_position):
		return false
	if _await_exit and pickup is WreckCache:
		return false
	if not pickup.claim(self):
		return false
	if _claims.size() > 8:
		_claims.assign(_claims.filter(func(p: Pickup) -> bool: return is_instance_valid(p) and p.is_flying()))
	_claims.append(pickup)
	claimed.emit(pickup)
	return true


## 99th percentile of the recorded tick costs in microseconds.
func tick_p99_usec() -> int:
	if tick_usec.is_empty():
		return 0
	var sorted: PackedInt32Array = tick_usec.duplicate()
	sorted.sort()
	return sorted[mini(int(sorted.size() * 0.99), sorted.size() - 1)]


func tick_max_usec() -> int:
	var worst: int = 0
	for usec: int in tick_usec:
		worst = maxi(worst, usec)
	return worst


## Lets the fresh-cache rule lift once the collector is outside the pickup range of the cache.
func update_cache_grace() -> void:
	if _await_exit and economy != null:
		var d: Vector3 = economy.cache_position - global_position
		if Vector2(d.x, d.z).length() > pickup_range:
			_await_exit = false


func _scan() -> void:
	update_cache_grace()
	for area: Area3D in get_overlapping_areas():
		var pickup := area as Pickup
		if pickup != null:
			try_claim(pickup)


func _on_dropped(position: Vector3) -> void:
	for pickup: Pickup in _claims:
		if is_instance_valid(pickup) and pickup.is_flying():
			pickup.cancel()
	_claims.clear()
	var d: Vector3 = position - global_position
	_await_exit = Vector2(d.x, d.z).length() <= pickup_range
