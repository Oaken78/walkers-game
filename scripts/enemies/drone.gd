class_name Drone
extends Node3D
## One drone (GDD 5, 8.4, 10): a dark ring that hovers 3-6 m up at its site, closes on the walker within 35 m, orbits it
## at 12-18 m and, every 1.5 s, stops, glows threat-red for 0.6 s and fires a slow bolt at where the walker is. The mind
## is DroneBrain (pure); this node reads the world into its senses, moves by the brain's speed factor and owns the
## picture, the hurtbox (layer 3, radius 0.6 m, 45 HP) and the death.
##
## The root is the hover point: it is the position that holds still (<= 0.05 m/s from 0.1 s after the wind-up start to
## the end of the recovery). `Body` bobs +-4 cm around it, so the hold drifts at most 0.1 m including the bob.
## Place it with place() after adding it to the tree. Physics priority 50: after the walker (0), before the bolt pool (200).

signal state_changed(drone: Drone, from_state: DroneBrain.State, to_state: DroneBrain.State)
signal wind_up_started(drone: Drone)
signal shot_fired(drone: Drone, origin: Vector3, direction: Vector3)
## The drone took its last hit point: `position` is where it was.
signal died(drone: Drone, position: Vector3)
signal scrap_dropped(drone: Drone, amount: int, position: Vector3)

const LOOSE_SCRAP: PackedScene = preload("res://scenes/enemies/loose_scrap.tscn")

const MAX_HP: float = 45.0
const HURT_RADIUS_M: float = 0.6
## White flash on a hit, no hit-stop (GDD 5).
const FLASH_S: float = 0.06
const THREAT_COLOR: Color = Color("E8345A")
const RING_COLOR: Color = Color("181A1F")
## The ink rim behind the ring (GDD 10 rule 2): unshaded, never glows, so the ring keeps a dark edge in grayscale.
const RIM_COLOR: Color = Color("14161A")
## Additive lit-band pass chained after the ring material (third toon band).
const LIT_BAND_PASS: Material = preload("res://assets/materials/drone_lit_band.tres")
## The rim torus is squashed to this share of its thickness along the ring's axis and sits this far behind the ring, so
## the whole ring stays in front of it and only a dark edge shows round the ring.
const RIM_FLATTEN: float = 0.25
const RIM_BEHIND_M: float = 0.05
## Emissive energy at the end of the wind-up (GDD 10: 0 to 3 over 0.6 s).
const GLOW_MAX: float = 3.0
const FLASH_ENERGY: float = 1.5
const HOVER_MIN_M: float = 3.0
const HOVER_MAX_M: float = 6.0
const SCRAP_MIN: int = 3
const SCRAP_MAX: int = 8
const BOB_AMPLITUDE_M: float = 0.04
const BOB_HZ: float = 0.5
## Climb and sink toward the hover height, per metre of error, and the cap in m/s.
const ALTITUDE_GAIN: float = 2.0
const ALTITUDE_MAX_MPS: float = 2.0
## How hard the orbit pulls back to its radius, per metre of error.
const RADIAL_GAIN: float = 0.6
const RADIAL_MAX: float = 1.5
## Drifting the last metre home.
const IDLE_DRIFT_MPS: float = 1.5
const GRAVITY_MPS2: float = 9.8
const FALL_DRAG: float = 2.0
const MAX_FALL_S: float = 4.0
const HUSK_S: float = 2.0
const GROUND_PROBE_UP_M: float = 30.0
const GROUND_PROBE_DOWN_M: float = 200.0
const SCRAP_SCATTER_MIN_M: float = 0.3
const SCRAP_SCATTER_MAX_M: float = 1.4
const SCRAP_LIFT_M: float = 0.15
const HUSK_REST_LIFT_M: float = 0.6
const SIGHT_MIN_FACING_M: float = 0.01

## False: the brain sleeps (scenario setups and shots). Hits, flash and death still work.
@export var ai_enabled: bool = true
## When false the drone does not step itself (unit tests call step()).
@export var auto_step: bool = true

## The walker (its `Chassis` child is the aim point). Without one the drone sees nothing.
var target: Node3D:
	set(value):
		target = value
		_chassis = null
var bolts: DroneBoltPool = null
## Asks for the stagger and the engagement cap; both optional.
var encounter: DroneEncounter = null
var field: DroneField = null
## Where scrap goes when this drone dies (it outlives the drone). Falls back to this drone's parent.
var drop_parent: Node = null

var brain: DroneBrain = DroneBrain.new()
var health: Health = Health.new(MAX_HP)
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
## The spawn point (the hover point it returns to).
var home: Vector3 = Vector3.ZERO
var hover_m: float = 4.0
var orbit_radius_m: float = 15.0
## +1: the bearing from the walker grows (counter-clockwise from above); -1: the other way.
var orbit_sign: int = 1
## Displacement of the hover point over the last tick, per second (the bob excluded).
var velocity: Vector3 = Vector3.ZERO
var shots_fired: int = 0
var shots_refused: int = 0
var scrap_dropped_total: int = 0
var flash_left_s: float = 0.0
## Cost of the last step() in microseconds.
var tick_usec: int = 0
var landed: bool = false

var _senses: DroneBrain.Senses = DroneBrain.Senses.new()
var _chassis: Node3D = null
var _ring_material: StandardMaterial3D
var _move_dir: Vector3 = Vector3.ZERO
var _prev_state: DroneBrain.State = DroneBrain.State.IDLE_HOVER
var _provoked: bool = false
var _bob_t: float = 0.0
var _fall_v: float = 0.0
var _fall_h: Vector3 = Vector3.ZERO
var _fall_t: float = 0.0
var _husk_t: float = 0.0
var _ground_query: PhysicsRayQueryParameters3D
var _sight_query: PhysicsRayQueryParameters3D

@onready var hurtbox: Hurtbox = $Body/Hurtbox
@onready var _body: Node3D = $Body
@onready var _ring: MeshInstance3D = $Body/Ring
@onready var _rim: MeshInstance3D = $Body/Rim


func _init() -> void:
	process_physics_priority = 50


func _ready() -> void:
	top_level = true
	_ring_material = StandardMaterial3D.new()
	_ring_material.albedo_color = RING_COLOR
	# Toon diffuse with a hard edge gives the shadow and base bands; the next pass adds the lit band (GDD 10 toon ramp).
	# The ring stays a StandardMaterial3D because its glow and flash are driven through these properties.
	_ring_material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	_ring_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_ring_material.roughness = 0.0
	_ring_material.next_pass = LIT_BAND_PASS
	_ring_material.emission_enabled = true
	_ring_material.emission = THREAT_COLOR
	_ring_material.emission_energy_multiplier = 0.0
	_ring.material_override = _ring_material
	var rim_material := StandardMaterial3D.new()
	rim_material.albedo_color = RIM_COLOR
	rim_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rim.material_override = rim_material
	# Mesh space: the torus' axis is Y. Squash it, then lay the axis along the body's Z (the way the ring faces).
	var lay_flat := Basis.from_euler(Vector3(PI * 0.5, 0.0, 0.0))
	_rim.transform = Transform3D(lay_flat * Basis.from_scale(Vector3(1.0, RIM_FLATTEN, 1.0)), Vector3(0.0, 0.0, RIM_BEHIND_M))
	_ground_query = PhysicsRayQueryParameters3D.new()
	_ground_query.collision_mask = CombatLayers.WORLD
	_ground_query.collide_with_areas = false
	_ground_query.collide_with_bodies = true
	_sight_query = PhysicsRayQueryParameters3D.new()
	_sight_query.collision_mask = CombatLayers.WORLD
	_sight_query.collide_with_areas = false
	_sight_query.collide_with_bodies = true
	hurtbox.health = health
	hurtbox.hit_taken.connect(_on_hit_taken)
	health.depleted.connect(_on_depleted)


func _physics_process(delta: float) -> void:
	if auto_step:
		step(delta)


# --- Public -----------------------------------------------------------------------------------------------------


## Rolls this drone's own numbers from `seed_value` in a fixed order: hover height 3-6 m, orbit radius 12-18 m, orbit
## direction. The same seed gives the same drone (and the same scrap drop at its death).
func configure(seed_value: int) -> void:
	rng.seed = seed_value
	hover_m = rng.randf_range(HOVER_MIN_M, HOVER_MAX_M)
	orbit_radius_m = rng.randf_range(DroneBrain.ORBIT_MIN_M, DroneBrain.ORBIT_MAX_M)
	orbit_sign = 1 if rng.randf() < 0.5 else -1


## Puts the drone `hover_m` above `ground_point` and makes that its home.
func place(ground_point: Vector3, hover: float = -1.0) -> void:
	if hover >= 0.0:
		hover_m = hover
	global_position = ground_point + Vector3.UP * hover_m
	home = global_position
	velocity = Vector3.ZERO
	_move_dir = Vector3.ZERO
	reset_physics_interpolation()


## Starts the cycle so that the next wind-up begins `seconds` from now (scenario setups).
func schedule_wind_up(seconds: float) -> void:
	brain.cycle_t = DroneBrain.SHOT_PERIOD_S - maxf(seconds, 0.0)


## The drone orbiting at once, as if it had just closed in (scenario setups).
func engage_now() -> void:
	brain.state = DroneBrain.State.STRAFE
	brain.state_t = 0.0
	brain.speed_factor = 1.0
	_prev_state = DroneBrain.State.STRAFE
	_set_engaged(true)


func is_dead() -> bool:
	return brain.state == DroneBrain.State.DEAD


func state_name() -> String:
	return DroneBrain.state_name(brain.state)


## The walker's chassis position (the bolt's aim, the sight line's end). INF when there is no walker.
func chassis_point() -> Vector3:
	if _chassis == null or not is_instance_valid(_chassis):
		_chassis = null
		if target != null and is_instance_valid(target):
			_chassis = target.get_node_or_null("Chassis") as Node3D
			if _chassis == null:
				return target.global_position + Vector3.UP
		else:
			return Vector3.INF
	return _chassis.global_position


## The wind-up glow as drawn, 0..1.
func glow() -> float:
	return brain.glow()


## The body's bob offset from the hover point (m).
func bob_offset() -> Vector3:
	return _body.position


## One physics tick.
func step(delta: float) -> void:
	var started: int = Time.get_ticks_usec()
	flash_left_s = maxf(flash_left_s - delta, 0.0)
	if brain.state == DroneBrain.State.DEAD:
		if ai_enabled:
			# A drone always fires: one killed during its wind-up still sends its bolt at the end of the 0.6 s.
			brain.update(delta, _senses)
			if brain.fired:
				_fire_bolt()
		_fall(delta)
	else:
		if ai_enabled:
			_think(delta)
		_bob(delta)
		_face_target()
	_paint()
	tick_usec = Time.get_ticks_usec() - started


# --- Mind -------------------------------------------------------------------------------------------------------


func _think(delta: float) -> void:
	var now: float = DroneEncounter.now_s()
	_sense(now)
	brain.update(delta, _senses)
	if brain.state == DroneBrain.State.DEAD:
		return
	if brain.state != _prev_state:
		var from_state: DroneBrain.State = _prev_state
		_prev_state = brain.state
		_set_engaged(DroneBrain.is_engaged(brain.state))
		if brain.state == DroneBrain.State.PATROL or brain.state == DroneBrain.State.IDLE_HOVER:
			# Going home ends the grudge: a drone that gave up does not turn round for a walker it cannot see.
			_provoked = false
		state_changed.emit(self, from_state, brain.state)
	if brain.wind_up_began:
		if encounter != null:
			encounter.note_wind_up(now)
		wind_up_started.emit(self)
	if brain.fired:
		_fire_bolt()
	_move(delta)


func _sense(now: float) -> void:
	var s: DroneBrain.Senses = _senses
	var here: Vector3 = global_position
	s.hp = health.hp
	s.home_dist = here.distance_to(home)
	var aim: Vector3 = chassis_point()
	if aim.is_finite():
		var to: Vector3 = aim - here
		s.player_dist = to.length()
		s.player_flat_dist = Vector2(to.x, to.z).length()
		s.player_home_dist = Vector2(aim.x - home.x, aim.z - home.z).length()
		s.line_of_sight = s.player_dist <= DroneBrain.SIGHT_RANGE_M and _clear_line(here, aim)
	else:
		s.player_dist = INF
		s.player_flat_dist = INF
		s.player_home_dist = INF
		s.line_of_sight = false
	s.provoked = _provoked
	s.may_engage = field == null or field.can_engage(self)
	s.may_wind_up = encounter == null or encounter.can_wind_up(now)


func _clear_line(from: Vector3, to: Vector3) -> bool:
	_sight_query.from = from
	_sight_query.to = to
	return get_world_3d().direct_space_state.intersect_ray(_sight_query).is_empty()


func _fire_bolt() -> void:
	var aim: Vector3 = chassis_point()
	if bolts == null or not aim.is_finite():
		return
	var origin: Vector3 = _body.global_position
	var direction: Vector3 = (aim - origin).normalized()
	if bolts.fire(origin, direction, self):
		shots_fired += 1
		shot_fired.emit(self, origin, direction)
	else:
		shots_refused += 1


func _set_engaged(engaged: bool) -> void:
	if field != null:
		field.set_engaged(self, engaged)


# --- Body -------------------------------------------------------------------------------------------------------


## Steers while the brain says move; during a hold the last direction decays with the speed factor to 0.
func _move(delta: float) -> void:
	match brain.state:
		DroneBrain.State.ALERT:
			_move_dir = _steer_to_walker()
		DroneBrain.State.STRAFE:
			_move_dir = _steer_orbit()
		DroneBrain.State.PATROL:
			_move_dir = (home - global_position).limit_length(1.0)
			if _move_dir.length() > 0.001:
				_move_dir = _move_dir.normalized()
	var before: Vector3 = global_position
	if brain.state == DroneBrain.State.IDLE_HOVER:
		global_position = before.move_toward(home, IDLE_DRIFT_MPS * delta)
	else:
		global_position = before + _move_dir * DroneBrain.ORBIT_SPEED_MPS * brain.speed_factor * delta
	velocity = (global_position - before) / delta


func _steer_to_walker() -> Vector3:
	var aim: Vector3 = chassis_point()
	if not aim.is_finite():
		return Vector3.ZERO
	var flat: Vector2 = Vector2(aim.x - global_position.x, aim.z - global_position.z)
	if flat.length() < 0.001:
		return Vector3.ZERO
	return _with_altitude(flat.normalized())


func _steer_orbit() -> Vector3:
	var aim: Vector3 = chassis_point()
	if not aim.is_finite():
		return Vector3.ZERO
	var out: Vector2 = Vector2(global_position.x - aim.x, global_position.z - aim.z)
	var distance: float = out.length()
	if distance < 0.001:
		return Vector3.ZERO
	var radial: Vector2 = out / distance
	# Bearing b grows counter-clockwise: p = R(-sin b, -cos b), so d/db is (-cos b, sin b) = (radial.y, -radial.x).
	var tangent: Vector2 = Vector2(radial.y, -radial.x) * float(orbit_sign)
	var pull: float = clampf((orbit_radius_m - distance) * RADIAL_GAIN, -RADIAL_MAX, RADIAL_MAX)
	return _with_altitude((tangent + radial * pull).normalized())


## The horizontal heading plus the climb or sink toward ground + hover height, as a vector of length <= 1.
func _with_altitude(heading: Vector2) -> Vector3:
	var goal_y: float = _ground_y(global_position) + hover_m
	var climb: float = clampf((goal_y - global_position.y) * ALTITUDE_GAIN, -ALTITUDE_MAX_MPS, ALTITUDE_MAX_MPS)
	return Vector3(heading.x, climb / DroneBrain.ORBIT_SPEED_MPS, heading.y).limit_length(1.0)


func _ground_y(at: Vector3) -> float:
	_ground_query.from = at + Vector3.UP * GROUND_PROBE_UP_M
	_ground_query.to = at + Vector3.DOWN * GROUND_PROBE_DOWN_M
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(_ground_query)
	if hit.is_empty():
		return at.y - hover_m
	return (hit["position"] as Vector3).y


func _bob(delta: float) -> void:
	_bob_t += delta
	_body.position = Vector3(0.0, BOB_AMPLITUDE_M * sin(TAU * BOB_HZ * _bob_t), 0.0)


## The ring's face toward the walker, so it always reads as a ring.
func _face_target() -> void:
	var aim: Vector3 = chassis_point()
	if not aim.is_finite():
		return
	var to: Vector3 = aim - _body.global_position
	if to.length() < SIGHT_MIN_FACING_M:
		return
	var up: Vector3 = Vector3.UP if absf(to.normalized().y) < 0.99 else Vector3.RIGHT
	_body.global_basis = Basis.looking_at(to.normalized(), up)


func _paint() -> void:
	var level: float = glow()
	if flash_left_s > 0.0:
		_ring_material.albedo_color = Color.WHITE
		_ring_material.emission = Color.WHITE
		_ring_material.emission_energy_multiplier = FLASH_ENERGY
	else:
		_ring_material.albedo_color = RING_COLOR
		_ring_material.emission = THREAT_COLOR
		_ring_material.emission_energy_multiplier = GLOW_MAX * level


# --- Hits and death ---------------------------------------------------------------------------------------------


func _on_hit_taken(_damage: float, _source: Node, _point: Vector3) -> void:
	flash_left_s = FLASH_S
	_provoked = true
	_paint()


## A killing hit: the drone is dead at once but a drone always fires, so a wind-up in progress still ends in its shot
## (DroneBrain.shot_pending_s). It falls, drops 3-8 scrap where it lands and is gone 2 s later.
func _on_depleted() -> void:
	brain.kill()
	_set_engaged(false)
	hurtbox.collision_layer = 0
	_fall_v = 0.0
	_fall_h = velocity
	velocity = Vector3.ZERO
	died.emit(self, global_position)


func _fall(delta: float) -> void:
	if landed:
		_husk_t += delta
		if _husk_t >= HUSK_S - 0.000001:
			queue_free()
		return
	_fall_t += delta
	_fall_v += GRAVITY_MPS2 * delta
	_fall_h *= maxf(1.0 - FALL_DRAG * delta, 0.0)
	var from: Vector3 = global_position
	var to: Vector3 = from + _fall_h * delta + Vector3.DOWN * _fall_v * delta
	_ground_query.from = from
	_ground_query.to = to + Vector3.DOWN * HUSK_REST_LIFT_M
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(_ground_query)
	_body.rotate_z(delta * 3.0)
	if not hit.is_empty():
		var ground: Vector3 = hit["position"]
		global_position = ground + Vector3.UP * HUSK_REST_LIFT_M
		landed = true
		_drop_scrap(ground)
	else:
		global_position = to
		if _fall_t >= MAX_FALL_S:
			landed = true
			_drop_scrap(to)


func _drop_scrap(at: Vector3) -> void:
	var count: int = rng.randi_range(SCRAP_MIN, SCRAP_MAX)
	var parent: Node = drop_parent if drop_parent != null and is_instance_valid(drop_parent) else get_parent()
	if parent == null:
		return
	for i in count:
		var angle: float = rng.randf() * TAU
		var radius: float = rng.randf_range(SCRAP_SCATTER_MIN_M, SCRAP_SCATTER_MAX_M)
		var piece: LooseScrap = LOOSE_SCRAP.instantiate()
		parent.add_child(piece)
		piece.place(at + Vector3(cos(angle) * radius, SCRAP_LIFT_M, sin(angle) * radius), 1)
	scrap_dropped_total += count
	scrap_dropped.emit(self, count, at)
