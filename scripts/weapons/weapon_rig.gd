class_name WeaponRig
extends Node3D
## Mounts the walker's pulse cannons and aims and fires them (GDD 6, 8.3). Given a WalkerBody and an OrbitCamera, it
## draws one barrel per cannon on the walker's drawn pose and hides the static barrels the walker draws.
## Aim: P is the camera's centre-ray hit. Every cannon keeps a yaw and pitch in the chassis frame and swings toward
## the pose that puts its line (pivot to P) on P, at its own traverse rate (AimMath), inside its mount's arc. A cannon
## whose pose is outside the arc is gray: it swings to the nearest reachable pose and does not fire.
## LMB (`fire`) fires every live cannon on its own phase (FireClock), along its current barrel line, even mid-swing.
## Logic runs in _physics_process, after the walker (priority 100). Barrels are set on that tick's pose and drawn
## through physics interpolation; the aim marks follow the interpolated barrels (no 60 Hz steps).
## Shots leave the muzzle as drawn on the tick and never inherit the walker's velocity.

signal fired(weapon: int, origin: Vector3, direction: Vector3)
signal mounted(count: int)

## Barrel geometry in the barrel's own frame: the pivot (trunnion) sits 0.25 m ahead of the breech, the muzzle 0.75 m
## ahead of the pivot. The walker draws the same 1 m barrel centred 0.25 m ahead of this pivot.
const MUZZLE_LOCAL: Vector3 = Vector3(0.0, 0.0, -0.75)
const PIVOT_BEHIND_CENTRE: float = 0.25
const BARREL_LENGTH: float = 1.0
const REACH_M: float = 120.0
const SEED_BASE: int = 7001
## The ring's stroke flashes for this long after a player projectile hits a hurtbox (GDD 12).
const HIT_FLASH_S: float = 0.06
const TIMER_EPSILON: float = 0.000001
const SOCKETS: Array[StringName] = [&"top_0", &"top_1", &"top_2"]

@export var walker: WalkerBody
@export var orbit: OrbitCamera
@export var pool: ProjectilePool
@export var input_enabled: bool = true
## Degrees. Negative uses the build's `spread` stat; scenarios set 0 for the exact-aim checks.
@export var spread_override_deg: float = -1.0
@export var hide_walker_barrels: bool = true
## Test hook (aim_range): while true, P is `aim_override_point` instead of the camera's centre-ray hit. The game never sets it.
@export var aim_override_active: bool = false
@export var aim_override_point: Vector3 = Vector3.ZERO

## Read-only aim state of the last physics tick: P, and whether it lies on an enemy hurtbox.
var aim_point: Vector3 = Vector3.ZERO
var aim_on_enemy: bool = false
var shots_fired: int = 0
## Cost of the last physics tick in microseconds (rig plus aim maths, pool excluded).
var tick_usec: int = 0
## Mounted weapons whose P is out of reach this tick.
var gray_count: int = 0

var _cannons: Array[Cannon] = []
var _walker_hidden: bool = false
var _clock: FireClock
var _now: float = 0.0
var _teleports: int = -1
var _reticle_frame: int = -1
var _ray: PhysicsRayQueryParameters3D
## The cannon part's numbers and the build's spread, read when the build is mounted.
var _shot_speed: float = 0.0
var _shot_damage: float = 0.0
var _build_spread_deg: float = 0.0
var _rate_dps: float = AimMath.TRAVERSE_MAX_DEG_S


class Cannon:
	extends RefCounted
	var index: int = 0
	var socket: StringName = &"top_0"
	var pivot_local: Vector3 = Vector3.ZERO
	var barrel: Node3D
	var arc: Dictionary = {}
	## Chassis-frame yaw and pitch (deg) as of the last tick.
	var pose: Vector2 = Vector2.ZERO
	## The pose that puts the line on P, and the one swung toward.
	var wanted: Vector2 = Vector2.ZERO
	var live: bool = false
	var held: bool = false
	## The first hit along the barrel line as of the last tick.
	var line_point: Vector3 = Vector3.ZERO
	var line_on_enemy: bool = false
	var flash_left_s: float = 0.0
	## The same from the interpolated barrel, for the marks (update_reticle).
	var reticle_point: Vector3 = Vector3.ZERO
	var reticle_on_enemy: bool = false
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
	var pose: Transform3D = walker.body_pose()
	_read_camera()
	gray_count = 0
	for cannon in _cannons:
		cannon.flash_left_s = maxf(cannon.flash_left_s - delta, 0.0)
		_aim(cannon, pose, delta)
		if not cannon.live:
			gray_count += 1
	if walker.teleport_count != _teleports:
		# After the barrels took their new transform, so they do not streak from where they were.
		_teleports = walker.teleport_count
		for cannon in _cannons:
			cannon.barrel.reset_physics_interpolation()
	if input_enabled:
		_fire(Input.is_action_pressed("fire"))
	else:
		_clock.disarm()
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


## Cannon `index`'s state as of the last physics tick: live (P reachable), the first hit along its current barrel
## line (aim_point, up to 120 m), on_enemy, flash_left (s), and its chassis-frame yaw and pitch in degrees.
func weapon_state(index: int) -> Dictionary:
	var cannon: Cannon = _cannons[index]
	return {
		"live": cannon.live,
		"aim_point": cannon.line_point,
		"on_enemy": cannon.line_on_enemy,
		"flash_left": cannon.flash_left_s,
		"yaw_deg": cannon.pose.x,
		"pitch_deg": cannon.pose.y,
	}


func is_live(index: int) -> bool:
	return _cannons[index].live


## Chassis-frame (yaw deg, pitch deg) of cannon `index` as of the last tick.
func pose_deg(index: int) -> Vector2:
	return _cannons[index].pose


## The chassis-frame pose that puts cannon `index`'s line on P (before the arc clamp).
func wanted_pose_deg(index: int) -> Vector2:
	return _cannons[index].wanted


## Every cannon back to pose (0, 0) on the walker's current pose (a respawn; scenarios between runs).
func reset_aim() -> void:
	for cannon in _cannons:
		cannon.pose = Vector2.ZERO
		cannon.wanted = Vector2.ZERO
		_place_at_rest(cannon)


func traverse_rate_dps() -> float:
	return _rate_dps


## Fires cannon `index` now, from its muzzle as it stands, along its barrel with spread. The clock decides when; this
## is also the entry point for tests. A shot the pool refuses (the 40-bolt cap) is not counted and not signalled.
func shoot(index: int) -> bool:
	var cannon: Cannon = _cannons[index]
	var origin: Vector3 = cannon.barrel.global_transform * MUZZLE_LOCAL
	var direction: Vector3 = -cannon.barrel.global_transform.basis.z
	direction = AimMath.spread_direction(direction, spread_deg(), cannon.rng.randf(), cannon.rng.randf())
	if pool != null and not pool.fire(origin, direction, _shot_speed, _shot_damage, walker, index):
		return false
	shots_fired += 1
	fired.emit(index, origin, direction)
	return true


func muzzle_position(index: int) -> Vector3:
	return _cannons[index].barrel.global_transform * MUZZLE_LOCAL


func muzzle_direction(index: int) -> Vector3:
	return -_cannons[index].barrel.global_transform.basis.z


func pivot_position(index: int) -> Vector3:
	return _cannons[index].barrel.global_transform.origin


## Where cannon `index`'s pivot is on the walker's current pose (the barrel's own origin is last tick's).
func pivot_now(index: int) -> Vector3:
	return walker.body_pose() * _cannons[index].pivot_local


func spread_deg() -> float:
	if spread_override_deg >= 0.0:
		return spread_override_deg
	return _build_spread_deg


## Where a shot from each drawn (interpolated) barrel lands now: the first hit on layers 1 and 3 along its line, up to
## 120 m, else the point at 120 m. Cached per rendered frame; read with reticle_point() and reticle_on_enemy().
func update_reticle() -> void:
	var frame: int = Engine.get_process_frames()
	if frame == _reticle_frame:
		return
	_reticle_frame = frame
	if _cannons.is_empty() or not is_inside_tree():
		return
	for cannon in _cannons:
		var t: Transform3D = cannon.barrel.get_global_transform_interpolated()
		var hit: Array = _line_hit(t * MUZZLE_LOCAL, -t.basis.z)
		cannon.reticle_point = hit[0]
		cannon.reticle_on_enemy = hit[1]


func reticle_point(index: int) -> Vector3:
	return _cannons[index].reticle_point


func reticle_on_enemy(index: int) -> bool:
	return _cannons[index].reticle_on_enemy


func weapon_flashing(index: int) -> bool:
	return _cannons[index].flash_left_s > TIMER_EPSILON


# --- Mount ----------------------------------------------------------------------------------------------------


func _mount() -> void:
	_unmount()
	if walker == null:
		return
	var parts: Dictionary = walker.get_build().parts()
	var mounts: Dictionary = walker.top_mounts()
	var present: Array[StringName] = []
	for socket in SOCKETS:
		if parts.has(socket):
			present.append(socket)
	var part: Dictionary = PartCatalog.get_part(PartCatalog.PULSE_CANNON)
	_rate_dps = AimMath.traverse_rate(float(part["mass"]))
	for index in present.size():
		if parts[present[index]] != PartCatalog.PULSE_CANNON or not mounts.has(present[index]):
			continue
		var drawn: MeshInstance3D = mounts[present[index]] as MeshInstance3D
		if drawn == null or not (drawn.mesh is CylinderMesh):
			continue
		var cannon := Cannon.new()
		cannon.index = _cannons.size()
		cannon.socket = present[index]
		# Arcs belong to the socket face, not to the weapon: every top socket has the roof arc.
		cannon.arc = AimMath.mount_arc(AimMath.FACE_TOP)
		# The walker's barrel is centred ahead of the pivot; the pivot is where the barrel tips.
		cannon.pivot_local = walker.socket_transform(present[index]).origin + Vector3(0.0, 0.0, PIVOT_BEHIND_CENTRE)
		cannon.rng.seed = SEED_BASE + index
		cannon.barrel = _make_barrel()
		add_child(cannon.barrel)
		_cannons.append(cannon)
		_place_at_rest(cannon)
	if hide_walker_barrels:
		walker.draw_cannons = false
		_walker_hidden = true
	var expected: int = 0
	for socket in present:
		if parts[socket] == PartCatalog.PULSE_CANNON:
			expected += 1
	if _cannons.size() != expected:
		push_error(
			"WeaponRig: the build has %d pulse cannons but %d barrels were found on the walker's tops"
			% [expected, _cannons.size()]
		)
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
	if _clock != null:
		_clock.disarm()
	_show_walker_barrels()
	for cannon in _cannons:
		cannon.barrel.queue_free()
	_cannons.clear()


## The barrel on the walker's current pose at pose (0, 0), so it is drawn in place before the first tick.
func _place_at_rest(cannon: Cannon) -> void:
	var pose: Transform3D = walker.body_pose()
	cannon.barrel.global_transform = Transform3D(AimMath.barrel_basis(pose.basis, Vector2.ZERO), pose * cannon.pivot_local)
	cannon.barrel.reset_physics_interpolation()
	cannon.line_point = cannon.barrel.global_transform * MUZZLE_LOCAL
	cannon.reticle_point = cannon.line_point


func _show_walker_barrels() -> void:
	if _walker_hidden and walker != null and is_instance_valid(walker):
		walker.draw_cannons = true
	_walker_hidden = false


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


## P from the camera's centre ray (layers 1 and 3, never the player).
func _read_camera() -> void:
	if aim_override_active:
		aim_point = aim_override_point
		aim_on_enemy = false
		return
	var from: Vector3 = orbit.global_position
	var to: Vector3 = from - orbit.camera().global_basis.z * REACH_M
	var hit: Dictionary = _cast(from, to)
	if hit.is_empty():
		aim_point = to
		aim_on_enemy = false
	else:
		aim_point = hit["position"]
		aim_on_enemy = _is_enemy(hit["collider"])


func _aim(cannon: Cannon, pose: Transform3D, delta: float) -> void:
	var pivot: Vector3 = pose * cannon.pivot_local
	var solved: Dictionary = AimMath.solve(pivot, pose.basis, aim_point, cannon.arc, cannon.pose)
	cannon.wanted = solved["wanted"]
	cannon.live = bool(solved["live"])
	cannon.held = bool(solved["hold"])
	if not cannon.held:
		cannon.pose = AimMath.step(cannon.pose, solved["target"], _rate_dps, delta, cannon.arc)
	cannon.barrel.global_transform = Transform3D(AimMath.barrel_basis(pose.basis, cannon.pose), pivot)
	var hit: Array = _line_hit(cannon.barrel.global_transform * MUZZLE_LOCAL, -cannon.barrel.global_transform.basis.z)
	cannon.line_point = hit[0]
	cannon.line_on_enemy = hit[1]


func _fire(held: bool) -> void:
	for k in _clock.update(_now, held):
		# A gray weapon skips its slot; the others keep their phases.
		if _cannons[k].live:
			shoot(k)


func _on_impacted(_point: Vector3, _collider: Object, projectile: Projectile, counted: bool) -> void:
	if counted and projectile != null and projectile.weapon >= 0 and projectile.weapon < _cannons.size():
		_cannons[projectile.weapon].flash_left_s = HIT_FLASH_S


## [point, on_enemy] of the first hit along a line, up to 120 m, else the point at 120 m.
func _line_hit(origin: Vector3, direction: Vector3) -> Array:
	var hit: Dictionary = _cast(origin, origin + direction * REACH_M)
	if hit.is_empty():
		return [origin + direction * REACH_M, false]
	return [hit["position"], _is_enemy(hit["collider"])]


func _cast(from: Vector3, to: Vector3) -> Dictionary:
	_ray.from = from
	_ray.to = to
	return get_world_3d().direct_space_state.intersect_ray(_ray)


func _is_enemy(collider: Object) -> bool:
	var layered: CollisionObject3D = collider as CollisionObject3D
	return layered != null and (layered.collision_layer & CombatLayers.ENEMY) != 0
