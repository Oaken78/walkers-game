class_name DroneBoltPool
extends Node3D
## The drones' bolts (GDD 5, 8.4, 13): a fixed pool of `cap` slow bolts, stepped in one place. A bolt flies straight at
## 25 m/s, lives 3 s and is swept as a ray from last tick's position to this tick's. It is on layer 5
## (CombatLayers.ENEMY_PROJECTILE) with mask 1 and 2: the world (bodies) and the player's hurtbox (areas only).
## Layer 2 holds the WalkerBody's own colliders too, so the player query uses collide_with_bodies = false: a bolt that
## passes between the legs misses (M0 criterion 5). The nearest of the two hits ends the bolt, and the hurtbox is hit
## once. Fire is refused at the cap and the refusals are counted.

## `collider` is the hurtbox or the world body that ended the bolt; `counted` is true when a hurtbox took the hit.
signal impacted(point: Vector3, collider: Object, bolt: Bolt, counted: bool)

const SPEED_MPS: float = 25.0
const DAMAGE: float = 10.0
const LIFETIME_S: float = 3.0
const THREAT_COLOR: Color = Color("E8345A")
const BOLT_SIZE: Vector3 = Vector3(0.22, 0.22, 0.9)

static var _mesh: BoxMesh
static var _material: StandardMaterial3D

@export var cap: int = 8
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

var _bolts: Array[Bolt] = []
var _live: int = 0
var _world_query: PhysicsRayQueryParameters3D
var _player_query: PhysicsRayQueryParameters3D


## One pooled bolt: the data, and a bright threat-hued streak as the picture.
class Bolt:
	extends Node3D
	var collision_layer: int = CombatLayers.ENEMY_PROJECTILE
	var collision_mask: int = CombatLayers.WORLD | CombatLayers.PLAYER
	var alive: bool = false
	var velocity: Vector3 = Vector3.ZERO
	var damage: float = 0.0
	var source: Node = null
	var age: float = 0.0
	var travelled: float = 0.0


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	process_physics_priority = 200
	_world_query = PhysicsRayQueryParameters3D.new()
	_world_query.collision_mask = CombatLayers.WORLD
	_world_query.collide_with_areas = false
	_world_query.collide_with_bodies = true
	_player_query = PhysicsRayQueryParameters3D.new()
	_player_query.collision_mask = CombatLayers.PLAYER
	_player_query.collide_with_areas = true
	_player_query.collide_with_bodies = false
	_player_query.hit_from_inside = true
	if _mesh == null:
		_mesh = BoxMesh.new()
		_mesh.size = BOLT_SIZE
		_material = StandardMaterial3D.new()
		_material.albedo_color = THREAT_COLOR
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.emission_enabled = true
		_material.emission = THREAT_COLOR
		_material.emission_energy_multiplier = 2.0
	for i in cap:
		var bolt := Bolt.new()
		bolt.name = "Bolt%d" % i
		bolt.visible = false
		var streak := MeshInstance3D.new()
		streak.mesh = _mesh
		streak.material_override = _material
		streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The head is at the node's origin; the streak trails behind it.
		streak.position = Vector3(0.0, 0.0, BOLT_SIZE.z * 0.5)
		bolt.add_child(streak)
		add_child(bolt)
		_bolts.append(bolt)


func _physics_process(delta: float) -> void:
	if auto_step:
		step(delta)


## Starts a bolt at `origin` along `direction`. False (and a counted refusal) when `cap` are already live.
func fire(
	origin: Vector3,
	direction: Vector3,
	source: Node = null,
	speed: float = SPEED_MPS,
	damage: float = DAMAGE
) -> bool:
	var bolt: Bolt = null
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
	bolt.age = 0.0
	bolt.travelled = 0.0
	bolt.alive = true
	bolt.visible = true
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
		var wall: Dictionary = {}
		var limit: Vector3 = to
		if (bolt.collision_mask & CombatLayers.WORLD) != 0:
			_world_query.from = from
			_world_query.to = to
			wall = space.intersect_ray(_world_query)
			if not wall.is_empty():
				limit = wall["position"]
		if (bolt.collision_mask & CombatLayers.PLAYER) != 0:
			_player_query.from = from
			_player_query.to = limit
			var hurt: Dictionary = space.intersect_ray(_player_query)
			if not hurt.is_empty():
				_land(bolt, hurt)
				continue
		if not wall.is_empty():
			_land(bolt, wall)
			continue
		bolt.position = to
		bolt.age += delta
		bolt.travelled += from.distance_to(to)
		if bolt.age >= LIFETIME_S - 0.000001:
			_retire(bolt)
	step_usec = Time.get_ticks_usec() - started


## Removes every live bolt (a respawn, a test).
func clear() -> void:
	for bolt in _bolts:
		if bolt.alive:
			_retire(bolt)


## The live bolts, for scenarios and tests.
func live_bolts() -> Array[Bolt]:
	var result: Array[Bolt] = []
	for bolt in _bolts:
		if bolt.alive:
			result.append(bolt)
	return result


func _land(bolt: Bolt, hit: Dictionary) -> void:
	var point: Vector3 = hit["position"]
	var collider: Object = hit["collider"]
	impact_count += 1
	var damage: float = bolt.damage
	var source: Node = bolt.source
	_retire(bolt)
	var counted: bool = false
	if collider != null and collider.has_method("take_hit"):
		var result: Variant = collider.call("take_hit", damage, source, point)
		counted = result == null or bool(result)
	impacted.emit(point, collider, bolt, counted)


func _retire(bolt: Bolt) -> void:
	bolt.alive = false
	bolt.visible = false
	_live -= 1
