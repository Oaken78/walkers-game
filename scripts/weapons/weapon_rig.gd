class_name WeaponRig
extends Node3D
## Mounts the walker's pulse cannons and aims and fires them (GDD 5, 6, 8.3). Given a WalkerBody and an OrbitCamera,
## it draws one elevating barrel per cannon on the walker's drawn pose and hides the static barrels the walker draws.
## Aim: Q lies on the body's heading line, and every cannon converges on Q from its own muzzle (AimMath): its yaw is
## the muzzle-to-Q bearing on every tick, with no lag, and its elevation tips to put the muzzle on Q.
## LMB (`fire`) fires every cannon in even phases (FireClock).
## Logic runs in _physics_process, after the walker (priority 100). Barrels are set on that tick's pose and drawn
## through physics interpolation; the reticle for the aim marks follows the interpolated barrels (no 60 Hz steps).
## Shots leave the muzzle as drawn on the tick and never inherit the walker's velocity.

signal fired(weapon: int, origin: Vector3, direction: Vector3)
signal mounted(count: int)

## Barrel geometry in the barrel's own frame: the pivot (trunnion) sits 0.25 m ahead of the breech, the muzzle 0.75 m
## ahead of the pivot. The walker draws the same 1 m barrel centred 0.25 m ahead of this pivot.
const MUZZLE_LOCAL: Vector3 = Vector3(0.0, 0.0, -0.75)
const PIVOT_BEHIND_CENTRE: float = 0.25
const BARREL_LENGTH: float = 1.0
const REACH_M: float = AimMath.RANGE_MAX_M
const SEED_BASE: int = 7001
## d before the camera has been read inside 90 deg of the heading.
const DEFAULT_RANGE_M: float = 30.0
## The at-limit ring is dashed only when it matters: the dot is on an enemy, or `fire` is held or was released less
## than this long ago (GDD 12).
const DASH_HOLD_S: float = 0.5
## The ring's stroke flashes for this long after a player projectile hits a hurtbox (GDD 12).
const HIT_FLASH_S: float = 0.06
const TIMER_EPSILON: float = 0.000001

@export var walker: WalkerBody
@export var orbit: OrbitCamera
@export var pool: ProjectilePool
@export var input_enabled: bool = true
## Degrees. Negative uses the build's `spread` stat; scenarios set 0 for the exact-aim checks.
@export var spread_override_deg: float = -1.0
@export var hide_walker_barrels: bool = true

## Read-only aim state of the last physics tick.
var aim_point: Vector3 = Vector3.ZERO
var aim_on_enemy: bool = false
var aim_range_m: float = DEFAULT_RANGE_M
var aim_height_m: float = 0.0
var convergence: Vector3 = Vector3.ZERO
var held_off_heading: bool = false
## Degrees between the bearing of Q from the body origin and the body's heading, this tick (zero by construction;
## scenarios assert it).
var q_bearing_error_deg: float = 0.0
## True when any cannon's wanted elevation is outside -10..+45 deg.
var limited: bool = false
## True while `fire` is held and for DASH_HOLD_S after it was released.
var firing_recent: bool = false
## The ring is drawn dashed: at a limit and (the dot is on an enemy hurtbox or firing_recent).
var ring_dashed: bool = false
## True for HIT_FLASH_S after one of this rig's projectiles hit a hurtbox.
var ring_flashing: bool:
	get:
		return _flash_left_s > TIMER_EPSILON
var shots_fired: int = 0
## Cost of the last physics tick in microseconds (rig plus aim maths, pool excluded).
var tick_usec: int = 0

## Where the drawn barrels would land a shot (aim marks): refreshed by update_reticle().
var reticle_point: Vector3 = Vector3.ZERO
var reticle_on_enemy: bool = false
var reticle_valid: bool = false

var _cannons: Array[Cannon] = []
var _hidden: Array[Node3D] = []
var _clock: FireClock
var _now: float = 0.0
var _teleports: int = -1
var _reticle_frame: int = -1
var _has_height: bool = false
var _fire_idle_s: float = DASH_HOLD_S
var _flash_left_s: float = 0.0
var _ray: PhysicsRayQueryParameters3D
## The cannon part's numbers and the build's spread, read when the build is mounted.
var _shot_speed: float = 0.0
var _shot_damage: float = 0.0
var _build_spread_deg: float = 0.0


class Cannon:
	extends RefCounted
	var index: int = 0
	var pivot_local: Vector3 = Vector3.ZERO
	var barrel: Node3D
	var elevation_deg: float = 0.0
	var wanted_deg: float = 0.0
	var limited: bool = false
	var yaw_error_deg: float = 0.0
	var convergence_deg: float = 0.0
	var rng := RandomNumberGenerator.new()


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	process_physics_priority = 100
	_ray = PhysicsRayQueryParameters3D.new()
	_ray.collision_mask = CombatLayers.WORLD | CombatLayers.ENEMY
	_ray.collide_with_areas = true
	_ray.collide_with_bodies = true
	_ray.hit_from_inside = false
	if pool != null:
		pool.impacted.connect(_on_impacted)
	if walker != null:
		walker.build_applied.connect(_mount)
		if not walker.stats().is_empty():
			_mount()


func _exit_tree() -> void:
	_show_walker_barrels()


func _physics_process(delta: float) -> void:
	if walker == null or orbit == null or _cannons.is_empty():
		return
	var started: int = Time.get_ticks_usec()
	_now += delta
	_flash_left_s = maxf(_flash_left_s - delta, 0.0)
	var pose: Transform3D = walker.body_pose()
	var yaw: float = walker.yaw_radians()
	_read_camera(pose, yaw)
	limited = false
	for cannon in _cannons:
		_aim(cannon, pose, yaw, delta)
		limited = limited or cannon.limited
	if walker.teleport_count != _teleports:
		# After the barrels took their new transform, so they do not streak from where they were.
		_teleports = walker.teleport_count
		for cannon in _cannons:
			cannon.barrel.reset_physics_interpolation()
	var held: bool = input_enabled and Input.is_action_pressed("fire")
	_fire_idle_s = 0.0 if held else _fire_idle_s + delta
	firing_recent = _fire_idle_s < DASH_HOLD_S - TIMER_EPSILON
	ring_dashed = limited and (aim_on_enemy or firing_recent)
	if input_enabled:
		_fire(held)
	tick_usec = Time.get_ticks_usec() - started


# --- Public ------------------------------------------------------------------------------------------------------


func cannon_count() -> int:
	return _cannons.size()


## The world transform of cannon `index`'s barrel as set this tick (not interpolated).
func barrel_transform(index: int) -> Transform3D:
	return _cannons[index].barrel.global_transform


## The barrel as drawn this frame (interpolated), for the marks and for checks.
func barrel_drawn_transform(index: int) -> Transform3D:
	return _cannons[index].barrel.get_global_transform_interpolated()


## Fires cannon `index` now, from its muzzle as it stands, along its barrel with spread. The clock decides when; this
## is also the entry point for tests. A shot the pool refuses (the 40-bolt cap) is not counted and not signalled.
func shoot(index: int) -> bool:
	var cannon: Cannon = _cannons[index]
	var origin: Vector3 = cannon.barrel.global_transform * MUZZLE_LOCAL
	var direction: Vector3 = -cannon.barrel.global_transform.basis.z
	direction = AimMath.spread_direction(direction, spread_deg(), cannon.rng.randf(), cannon.rng.randf())
	if pool != null and not pool.fire(origin, direction, _shot_speed, _shot_damage, walker):
		return false
	shots_fired += 1
	fired.emit(index, origin, direction)
	return true


func muzzle_position(index: int) -> Vector3:
	return _cannons[index].barrel.global_transform * MUZZLE_LOCAL


func muzzle_direction(index: int) -> Vector3:
	return -_cannons[index].barrel.global_transform.basis.z


## Degrees between the barrel's yaw and the bearing from its muzzle to Q, as drawn on the last tick (the yaw check).
func yaw_error_deg(index: int) -> float:
	return _cannons[index].yaw_error_deg


## Degrees the barrel's yaw is off the body's heading on the last tick: the lateral convergence from its socket offset.
func convergence_deg(index: int) -> float:
	return _cannons[index].convergence_deg


func elevation_deg(index: int) -> float:
	return _cannons[index].elevation_deg


func wanted_elevation_deg(index: int) -> float:
	return _cannons[index].wanted_deg


func spread_deg() -> float:
	if spread_override_deg >= 0.0:
		return spread_override_deg
	return _build_spread_deg


## Where a shot from the drawn (interpolated) barrels lands now: the first hit on layers 1 and 3 along the average
## barrel line, up to 120 m, else the point at 120 m. Cached per rendered frame.
func update_reticle() -> void:
	var frame: int = Engine.get_process_frames()
	if frame == _reticle_frame:
		return
	_reticle_frame = frame
	reticle_valid = false
	if _cannons.is_empty() or not is_inside_tree():
		return
	var origin := Vector3.ZERO
	var direction := Vector3.ZERO
	for cannon in _cannons:
		var t: Transform3D = cannon.barrel.get_global_transform_interpolated()
		origin += t * MUZZLE_LOCAL
		direction += -t.basis.z
	origin /= float(_cannons.size())
	direction = direction.normalized()
	var hit: Dictionary = _cast(origin, origin + direction * REACH_M)
	reticle_valid = true
	if hit.is_empty():
		reticle_point = origin + direction * REACH_M
		reticle_on_enemy = false
	else:
		reticle_point = hit["position"]
		reticle_on_enemy = _is_enemy(hit["collider"])


# --- Mount ----------------------------------------------------------------------------------------------------


func _mount() -> void:
	_unmount()
	if walker == null:
		return
	var parts: Dictionary = walker.get_build().parts()
	var tops: Node = walker.get_node_or_null("Tops")
	var present: Array[StringName] = []
	for socket: StringName in [&"top_0", &"top_1", &"top_2"]:
		if parts.has(socket):
			present.append(socket)
	var drawn_barrels: Array[Node3D] = []
	for index in present.size():
		if parts[present[index]] != PartCatalog.PULSE_CANNON or tops == null or index >= tops.get_child_count():
			continue
		var drawn: MeshInstance3D = tops.get_child(index) as MeshInstance3D
		if drawn == null or not (drawn.mesh is CylinderMesh):
			continue
		drawn_barrels.append(drawn)
		var cannon := Cannon.new()
		cannon.index = _cannons.size()
		# The walker's barrel is centred ahead of the pivot; the pivot is where the barrel tips.
		cannon.pivot_local = drawn.position + Vector3(0.0, 0.0, PIVOT_BEHIND_CENTRE)
		cannon.rng.seed = SEED_BASE + index
		cannon.barrel = _make_barrel()
		add_child(cannon.barrel)
		_cannons.append(cannon)
		_place_at_rest(cannon)
	if hide_walker_barrels:
		for drawn in drawn_barrels:
			drawn.visible = false
			_hidden.append(drawn)
	var expected: int = 0
	for socket in present:
		if parts[socket] == PartCatalog.PULSE_CANNON:
			expected += 1
	if _cannons.size() != expected:
		push_error(
			"WeaponRig: the build has %d pulse cannons but %d barrels were found on the walker's Tops"
			% [expected, _cannons.size()]
		)
	var part: Dictionary = PartCatalog.get_part(PartCatalog.PULSE_CANNON)
	var previous: FireClock = _clock
	_clock = FireClock.new(_cannons.size(), float(part["fire_rate"]))
	if previous != null:
		_clock.carry_over(previous)
	_shot_speed = float(part["projectile_speed"])
	_shot_damage = float(part["damage"])
	_build_spread_deg = float(walker.stats().get("spread", 0.0))
	_teleports = -1
	mounted.emit(_cannons.size())


func _unmount() -> void:
	_show_walker_barrels()
	for cannon in _cannons:
		cannon.barrel.queue_free()
	_cannons.clear()


## The barrel on the walker's current pose at elevation 0, so it is drawn in place before the first tick.
func _place_at_rest(cannon: Cannon) -> void:
	var pivot: Vector3 = walker.body_pose() * cannon.pivot_local
	cannon.barrel.global_transform = Transform3D(AimMath.barrel_basis(walker.yaw_radians(), 0.0), pivot)
	cannon.barrel.reset_physics_interpolation()


func _show_walker_barrels() -> void:
	for drawn in _hidden:
		if is_instance_valid(drawn):
			drawn.visible = true
	_hidden.clear()


func _make_barrel() -> Node3D:
	var pivot := Node3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.08
	mesh.bottom_radius = 0.1
	mesh.height = BARREL_LENGTH
	mesh.radial_segments = 10
	var piece := MeshInstance3D.new()
	piece.mesh = mesh
	piece.material_override = WalkerLeg.body_material()
	# Lying along -Z, centred 0.25 m ahead of the pivot, like the walker's own barrel.
	piece.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
	piece.position = Vector3(0.0, 0.0, -PIVOT_BEHIND_CENTRE)
	pivot.add_child(piece)
	return pivot


# --- Tick ------------------------------------------------------------------------------------------------------


## P from the camera's centre ray (layers 1 and 3, never the player), then d, h and Q.
func _read_camera(pose: Transform3D, yaw: float) -> void:
	var from: Vector3 = orbit.global_position
	var to: Vector3 = from - orbit.camera().global_basis.z * REACH_M
	var hit: Dictionary = _cast(from, to)
	if hit.is_empty():
		aim_point = to
		aim_on_enemy = false
	else:
		aim_point = hit["position"]
		aim_on_enemy = _is_enemy(hit["collider"])
	held_off_heading = AimMath.holds(orbit.yaw_deg, yaw)
	if not _has_height:
		_has_height = true
		aim_height_m = pose.origin.y
	var rh: Vector2 = AimMath.range_and_height(
		Vector2(aim_range_m, aim_height_m), aim_point, pose.origin, orbit.yaw_deg, yaw
	)
	aim_range_m = rh.x
	aim_height_m = rh.y
	convergence = AimMath.convergence_point(pose.origin, yaw, aim_range_m, aim_height_m)
	q_bearing_error_deg = absf(
		rad_to_deg(wrapf(AimMath.bearing_to(pose.origin, convergence) - yaw, -PI, PI))
	)


func _aim(cannon: Cannon, pose: Transform3D, yaw: float, delta: float) -> void:
	var pivot: Vector3 = pose * cannon.pivot_local
	var wanted: Vector2 = AimMath.solve_aim(pivot, MUZZLE_LOCAL, convergence)
	cannon.wanted_deg = wanted.y
	cannon.limited = AimMath.is_limited(wanted.y)
	cannon.elevation_deg = AimMath.slew(
		cannon.elevation_deg, AimMath.clamp_elevation(wanted.y), delta
	)
	# Yaw has no lag: it is solved for the muzzle where the barrel really is after this tick's elevation step.
	var barrel_yaw: float = AimMath.solve_yaw(pivot, MUZZLE_LOCAL, cannon.elevation_deg, convergence, wanted.x)
	cannon.barrel.global_transform = Transform3D(AimMath.barrel_basis(barrel_yaw, cannon.elevation_deg), pivot)
	cannon.yaw_error_deg = AimMath.yaw_error_deg(cannon.barrel.global_transform, MUZZLE_LOCAL, convergence)
	cannon.convergence_deg = absf(rad_to_deg(wrapf(barrel_yaw - yaw, -PI, PI)))


func _fire(held: bool) -> void:
	for k in _clock.update(_now, held):
		shoot(k)


func _on_impacted(_point: Vector3, collider: Object, _projectile: Projectile) -> void:
	if collider != null and collider.has_method("take_hit"):
		_flash_left_s = HIT_FLASH_S


func _cast(from: Vector3, to: Vector3) -> Dictionary:
	_ray.from = from
	_ray.to = to
	return get_world_3d().direct_space_state.intersect_ray(_ray)


func _is_enemy(collider: Object) -> bool:
	var layered: CollisionObject3D = collider as CollisionObject3D
	return layered != null and (layered.collision_layer & CombatLayers.ENEMY) != 0
