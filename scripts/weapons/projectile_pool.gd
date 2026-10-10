class_name ProjectilePool
extends Node3D
## The player's pulse bolts (GDD 5, 8.3, 13): a fixed pool of `cap` (40) projectiles, stepped in one place.
## A bolt flies straight at its own speed (it never inherits the walker's velocity), lives 2 s (120 m at 60 m/s)
## and is swept as a ray from last tick's position to this tick's against layers 1 and 3. The first thing it meets
## ends it, so damage is applied once per projectile even where hurtboxes overlap. Fire is refused at the cap and
## the refusals are counted.

## `counted` is true when the collider took the hit: a hurtbox that was not a wreck. A wall or a wreck gives false.
signal impacted(point: Vector3, collider: Object, projectile: Projectile, counted: bool)

@export var cap: int = 40
@export var lifetime_s: float = 2.0
## When false the pool does not step itself (unit tests call step()).
@export var auto_step: bool = true

var refused_count: int = 0
var spawned_count: int = 0
var impact_count: int = 0
var max_live: int = 0
## Cost of the last step() in microseconds.
var step_usec: int = 0

## Bolts in flight.
var live: int:
	get:
		return _live

var _bolts: Array[Projectile] = []
var _live: int = 0
var _query: PhysicsRayQueryParameters3D


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	process_physics_priority = 200
	_query = PhysicsRayQueryParameters3D.new()
	_query.collide_with_areas = true
	_query.collide_with_bodies = true
	_query.hit_from_inside = true
	for i in cap:
		var bolt := Projectile.new()
		bolt.name = "Bolt%d" % i
		add_child(bolt)
		_bolts.append(bolt)


func _physics_process(delta: float) -> void:
	if auto_step:
		step(delta)


## Starts a bolt at `origin` along `direction`. Returns false (and counts a refusal) when `cap` are already live.
func fire(origin: Vector3, direction: Vector3, speed: float, damage: float, source: Node = null, weapon: int = -1) -> bool:
	if _live >= cap:
		refused_count += 1
		return false
	var bolt: Projectile = null
	for candidate in _bolts:
		if not candidate.alive:
			bolt = candidate
			break
	if bolt == null:
		refused_count += 1
		return false
	var dir: Vector3 = direction.normalized()
	var up: Vector3 = Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	bolt.global_transform = Transform3D(Basis.looking_at(dir, up), origin)
	bolt.velocity = dir * speed
	bolt.damage = damage
	bolt.source = source
	bolt.weapon = weapon
	bolt.age = 0.0
	bolt.travelled = 0.0
	bolt.alive = true
	bolt.visible = true
	# No streak from wherever this pooled bolt was drawn last.
	bolt.reset_physics_interpolation()
	_live += 1
	spawned_count += 1
	max_live = maxi(max_live, _live)
	return true


## Moves every live bolt one tick and resolves what it meets.
func step(delta: float) -> void:
	var started: int = Time.get_ticks_usec()
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	for bolt in _bolts:
		if not bolt.alive:
			continue
		var from: Vector3 = bolt.position
		var to: Vector3 = from + bolt.velocity * delta
		_query.from = from
		_query.to = to
		_query.collision_mask = bolt.hit_mask
		var hit: Dictionary = space.intersect_ray(_query)
		if not hit.is_empty():
			_land(bolt, hit)
			continue
		bolt.position = to
		bolt.age += delta
		bolt.travelled += from.distance_to(to)
		if bolt.age >= lifetime_s - 0.000001:
			_retire(bolt)
	step_usec = Time.get_ticks_usec() - started


## Removes every live bolt (a respawn, a test).
func clear() -> void:
	for bolt in _bolts:
		if bolt.alive:
			_retire(bolt)


func _land(bolt: Projectile, hit: Dictionary) -> void:
	var point: Vector3 = hit["position"]
	var collider: Object = hit["collider"]
	impact_count += 1
	var damage: float = bolt.damage
	var source: Node = bolt.source
	var projectile: Projectile = bolt
	_retire(bolt)
	var counted: bool = false
	if collider != null and collider.has_method("take_hit"):
		var result: Variant = collider.call("take_hit", damage, source, point)
		counted = result == null or bool(result)
	impacted.emit(point, collider, projectile, counted)


func _retire(bolt: Projectile) -> void:
	bolt.alive = false
	bolt.visible = false
	_live -= 1
