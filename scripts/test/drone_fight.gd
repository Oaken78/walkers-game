class_name DroneFight
extends Node3D
## The drone fight (T07): flat ground, a reference build, the orbit camera, the weapon rig, the aim marks, a DroneField
## with the encounters a scenario asks for, and the helpers the scenario `drone_fight` calls (the same style as AimRange).
## World frame: the walker spawns at the origin facing -Z (yaw 0); a bearing is the walker's yaw convention (0 = -Z,
## positive turns left, so +90 is -X).
##
## What it measures (all in physics ticks, 60 Hz):
##   - a drone run (idle or strafing walker, 2 drones): states seen, the telegraph before every shot, the 1.5 s cycle, the
##     hold (speed, drift, brake time, resume time), orbit speed and radius, the bolt's aim, the damage the walker took;
##   - heading races (risk 8): the time to bring the heading onto a drone 90 deg off, still / orbiting away / toward;
##   - the no-lead tracker (risk 8): hit rates of shots fired in the hold window and while the drone orbits, kill times;
##   - leash, scrap drop against scrap collected, the engagement cap, the cost per tick.

signal run_finished
signal race_finished
signal trial_finished

enum Drive { NONE, IDLE, STRAFE, TRACK, RACE }

const GROUND_COLOR: Color = Color("CAB294")
const SKY_COLOR: Color = Color("90A092")
const SPAWN_Y: float = 1.0
const START_PITCH_DEG: float = 20.0
## A player that cannot die, so a run can add up all the damage the bolts would do.
const PLAYER_HP: float = 100000.0
## Risk 8: the drone orbits at 15 m, 4 m up; the heading is "on" it within its angular radius.
const ORBIT_M: float = 15.0
const HOVER_M: float = 4.0
const STOP_MARGIN_DEG: float = 0.5
const YAW_RAMP_S: float = 0.1
## A shot counts as fired during the hold when it leaves between hold start + 0.15 s and hold end - 0.25 s.
const WINDOW_FROM_S: float = 0.15
const WINDOW_TO_S: float = 0.65
const HOLD_S: float = 0.9
const RACE_S: float = 2.0
## A race ends this long after the heading first reached the drone.
const RACE_TAIL_TICKS: int = 20
const TRIAL_MAX_S: float = 6.0
const TRIAL_TAIL_TICKS: int = 30
## A shot has missed once it has flown this far past the drone's range at the moment it left.
const PASS_MARGIN_M: float = 3.0
const HOLD_SPEED_FROM_TICK: int = 6
const RESUME_SHARE: float = 0.98
const REF_WIDTH: float = 1920.0
const REF_HEIGHT: float = 1080.0
const LUMA_CHANGED: float = 0.03
## The glowing band: the ring's tube is centred 0.5 m from the drone's centre and 0.2 m thick.
const BAND_MID_M: float = 0.5
const BAND_HALF_M: float = 0.07
## The orbit radius is read after the drones have closed in.
const RADIUS_SETTLE_S: float = 5.0

## --- Run results (reset by begin_run / reset_checks) ----------------------------------------------------------
var run_done: bool = false
var seen_alert: bool = false
var seen_strafe: bool = false
var seen_wind_up: bool = false
var seen_recover: bool = false
var seen_patrol: bool = false
var seen_idle_again: bool = false
var windups: int = 0
var shots_by_drones: int = 0
var telegraph_min_s: float = INF
var cycle_min_s: float = INF
var cycle_max_s: float = 0.0
var windup_gap_min_s: float = INF
var hold_ticks_seen: int = 0
var hold_speed_max: float = 0.0
var hold_drift_max_m: float = 0.0
var brake_s_max: float = 0.0
var resume_s_min: float = INF
var resume_s_max: float = 0.0
var orbit_speed_max: float = 0.0
var orbit_radius_min: float = INF
var orbit_radius_max: float = 0.0
var bolt_aim_err_max_deg: float = 0.0
var bolts_hit_player: int = 0
var damage_taken: float = 0.0
var idle_damage: float = 0.0
var strafe_damage: float = 0.0
var deaths: int = 0
## The field's own death signal (the one T12 listens to): how many, and where the last one was.
var field_deaths: int = 0
var field_death_point: Vector3 = Vector3.ZERO
var scrap_dropped_total: int = 0
var scrap_drop_min: int = 0
var scrap_drop_max: int = 0
var last_drop_point: Vector3 = Vector3.ZERO
var engaged_max: int = 0
var field_active_max: int = 0

## --- Heading race ----------------------------------------------------------------------------------------------
var heading_time_s: float = -1.0
var heading_final_error_deg: float = 0.0
var race_done: bool = false
var race_still_s: float = -1.0
var race_away_s: float = -1.0
var race_toward_s: float = -1.0

## --- Tracker -----------------------------------------------------------------------------------------------------
var trial_done: bool = false
var tracker_trials: int = 0
var tracker_kills: int = 0
var tracker_kill_max_s: float = 0.0
var tracker_kill_min_s: float = INF
var tracker_hold_hits: int = 0
var tracker_hold_misses: int = 0
var tracker_orbit_hits: int = 0
var tracker_orbit_misses: int = 0
var tracker_other_hits: int = 0
var tracker_other_misses: int = 0

## --- Cost, freeze, luma -----------------------------------------------------------------------------------------
var frozen: bool = false
var luma_measured: bool = false
var luma_windup: float = 0.0
var luma_idle: float = 0.0
var luma_delta: float = 0.0
var luma_pixels: int = 0

var economy: Economy = Economy.new()

var _drones: Array[Drone] = []
var _tracks: Dictionary = {}
var _enc_last_start: Dictionary = {}
var _drive: Drive = Drive.NONE
var _drive_ticks: int = 0
var _drive_limit: int = 0
var _strafe_half_s: float = 1.0
var _tracked: Drone = null
var _use_aim: bool = false
var _race_cone_deg: float = 0.0
var _race_ticks: int = 0
var _trial_start_frame: int = 0
var _trial_first_hold_s: float = -1.0
var _trial_death_frame: int = -1
var _trial_tail: int = -1
var _voided: bool = false
var _shots: Array[Dictionary] = []
var _freeze_state: bool = false
var _freeze_at_s: float = 0.0
var _cost_on: bool = false
var _cost_ms: PackedFloat32Array = PackedFloat32Array()
var _frames: Array[Image] = []
var _run_origin_s: float = 0.0
var _gray_layer: CanvasLayer

@onready var _walker: WalkerBody = %Walker
@onready var _orbit: OrbitCamera = %OrbitCamera
@onready var _rig: WeaponRig = %WeaponRig
@onready var _marks: AimMarks = %AimMarks
@onready var _player_box: PlayerHurtbox = %PlayerHurtbox
@onready var _collector: Collector = %Collector
@onready var _field: DroneField = %DroneField

var cost_p99_ms: float:
	get:
		return _p99(_cost_ms)
var cost_mean_ms: float:
	get:
		if _cost_ms.is_empty():
			return 0.0
		var sum: float = 0.0
		for value in _cost_ms:
			sum += value
		return sum / float(_cost_ms.size())
var cost_samples: int:
	get:
		return _cost_ms.size()
var strafe_ratio: float:
	get:
		return strafe_damage / idle_damage if idle_damage > 0.0 else INF
var tracker_hold_rate: float:
	get:
		return _rate(tracker_hold_hits, tracker_hold_misses)
var tracker_orbit_rate: float:
	get:
		return _rate(tracker_orbit_hits, tracker_orbit_misses)
## Bolts that left a drone, are no longer in the air and did not hurt the walker: the dodges.
var bolts_missed: int:
	get:
		return shots_by_drones - bolts_hit_player - _field.bolts.live
var pieces_match_drop: bool:
	get:
		return loose_pieces == scrap_dropped_total
var scrap_matched: bool:
	get:
		return economy.carried_scrap == scrap_dropped_total and loose_pieces == 0
var all_idle: bool:
	get:
		for drone in _drones:
			if is_instance_valid(drone) and not drone.is_dead() and drone.brain.state != DroneBrain.State.IDLE_HOVER:
				return false
		return true
var max_home_dist: float:
	get:
		var worst: float = 0.0
		for drone in _drones:
			if is_instance_valid(drone) and not drone.is_dead():
				worst = maxf(worst, drone.global_position.distance_to(drone.home))
		return worst
var luma_ok: bool:
	get:
		# Pixels cannot be read headless: the check is skipped there. Windowed it must have measured, and passed.
		if DisplayServer.get_name() == "headless":
			return true
		return luma_measured and luma_delta >= 0.3
var drone_count: int:
	get:
		return _drones.size()
var alive_drones: int:
	get:
		return _field.alive_count()
var engaged_now: int:
	get:
		var count: int = 0
		for drone in _drones:
			if is_instance_valid(drone) and DroneBrain.is_engaged(drone.brain.state):
				count += 1
		return count
var carried_scrap: int:
	get:
		return economy.carried_scrap
var scrap_conserved: bool:
	get:
		return economy.is_conserved()
var loose_pieces: int:
	get:
		var count: int = 0
		for encounter in _field.encounters:
			if not is_instance_valid(encounter):
				continue
			for child in encounter.get_children():
				if child is LooseScrap and not child.is_queued_for_deletion():
					count += 1
		return count
var bolts_live: int:
	get:
		return _field.bolts.live
var bolts_refused: int:
	get:
		return _field.bolts.refused_count
var first_state: String:
	get:
		return _drones[0].state_name() if not _drones.is_empty() else ""
var first_home_dist: float:
	get:
		return _drones[0].global_position.distance_to(_drones[0].home) if not _drones.is_empty() else -1.0
var first_hits: int:
	get:
		return _drones[0].hurtbox.hits_taken if not _drones.is_empty() else -1
var first_dead: bool:
	get:
		return not _drones.is_empty() and _drones[0].is_dead()
var first_glow: float:
	get:
		return _drones[0].glow() if not _drones.is_empty() else -1.0
var player_hits: int:
	get:
		return _player_box.hits_taken
var camera_pitch_deg: float:
	get:
		return _orbit.pitch_deg
var aim_on_enemy: bool:
	get:
		return _rig.aim_on_enemy


func _ready() -> void:
	# After the walker (0), the drones (50), the rig (100) and the pools (200): reads this tick's results.
	process_physics_priority = 300
	_build_world()
	_build_gray_layer()
	_orbit.capture_mouse = false
	_collector.target = _walker
	_collector.economy = economy
	_player_box.health = Health.new(PLAYER_HP)
	_player_box.hit_taken.connect(_on_player_hit)
	_field.target = _walker
	_field.drone_died.connect(_on_field_death)
	_rig.fired.connect(_on_player_shot)
	_rig.pool.impacted.connect(_on_player_impact)
	_race_cone_deg = rad_to_deg(asin(Drone.HURT_RADIUS_M / ORBIT_M))


func _physics_process(delta: float) -> void:
	_sample_drones()
	match _drive:
		Drive.STRAFE:
			_drive_strafe()
		Drive.TRACK:
			_drive_track(delta)
		Drive.RACE:
			_drive_race(delta)
	if _drive != Drive.NONE:
		_drive_ticks += 1
		if _drive_limit > 0 and _drive_ticks >= _drive_limit:
			_end_drive()
	if _cost_on:
		var usec: int = _field.bolts.step_usec
		for drone in _drones:
			if is_instance_valid(drone):
				usec += drone.tick_usec
		_cost_ms.append(float(usec) / 1000.0)
	if _freeze_state and not frozen:
		_check_freeze()
	engaged_max = maxi(engaged_max, engaged_now)
	field_active_max = maxi(field_active_max, _field.active_count())


# --- Scenario helpers: setup ------------------------------------------------------------------------------------


## "scout", "strider" or "crawler".
func use_build(build_name: String) -> void:
	var build: WalkerBuild
	match build_name:
		"scout":
			build = WalkerBuild.scout()
		"strider":
			build = WalkerBuild.strider()
		"crawler":
			build = WalkerBuild.crawler()
		_:
			push_error("DroneFight.use_build: unknown build %s" % build_name)
			return
	_walker.apply_build(build)


## The walker at the origin facing `yaw_deg`, the camera behind it, no drones, a new ledger, fresh checks.
func spawn(yaw_deg: float = 0.0, pitch_deg: float = START_PITCH_DEG) -> void:
	_end_drive()
	_release_inputs()
	unfreeze()
	_field.clear_all()
	_drones.clear()
	_tracks.clear()
	_enc_last_start.clear()
	_shots.clear()
	_tracked = null
	economy = Economy.new()
	_collector.economy = economy
	_player_box.health = Health.new(PLAYER_HP)
	_player_box.hits_taken = 0
	_rig.pool.clear()
	_walker.teleport(Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), Vector3(0.0, SPAWN_Y, 0.0)))
	_walker.reset_physics_interpolation()
	_orbit.snap()
	_orbit.set_angles(yaw_deg, pitch_deg)
	reset_checks()


func reset_checks() -> void:
	run_done = false
	seen_alert = false
	seen_strafe = false
	seen_wind_up = false
	seen_recover = false
	seen_patrol = false
	seen_idle_again = false
	windups = 0
	shots_by_drones = 0
	telegraph_min_s = INF
	cycle_min_s = INF
	cycle_max_s = 0.0
	windup_gap_min_s = INF
	hold_ticks_seen = 0
	hold_speed_max = 0.0
	hold_drift_max_m = 0.0
	brake_s_max = 0.0
	resume_s_min = INF
	resume_s_max = 0.0
	orbit_speed_max = 0.0
	orbit_radius_min = INF
	orbit_radius_max = 0.0
	bolt_aim_err_max_deg = 0.0
	bolts_hit_player = 0
	damage_taken = 0.0
	deaths = 0
	field_deaths = 0
	scrap_dropped_total = 0
	scrap_drop_min = 0
	scrap_drop_max = 0
	engaged_max = 0
	field_active_max = 0
	heading_time_s = -1.0
	heading_final_error_deg = 0.0
	race_done = false
	trial_done = false
	_enc_last_start.clear()


func set_spread(degrees: float) -> void:
	_rig.spread_override_deg = degrees


## One drone `distance_m` from the walker at `bearing_deg`, `hover_m` up. Mode "ai" (idle until it sees the walker),
## "engaged" (already orbiting) or "dormant" (no brain: hits, flash and death only).
func add_drone(bearing_deg: float, distance_m: float, hover_m: float = HOVER_M, mode: String = "ai") -> void:
	var spot: Vector3 = _spot(bearing_deg, distance_m)
	var encounter: DroneEncounter = _field.add_encounter(spot, 1, 1)
	var drone: Drone = encounter.drones[0]
	drone.place(spot, hover_m)
	_adopt(drone, mode)


## `count` drones of one encounter around a site `distance_m` from the walker at `bearing_deg`.
func add_group(count: int, bearing_deg: float, distance_m: float, mode: String = "ai") -> void:
	var spot: Vector3 = _spot(bearing_deg, distance_m)
	var encounter: DroneEncounter = _field.add_encounter(spot, count, count)
	for drone in encounter.drones:
		_adopt(drone, mode)


## The risk 8 drone: orbit radius 15 m, a direction, and the wind-up `seconds` from now.
func set_orbit(index: int, radius_m: float, direction: int, wind_up_in_s: float) -> void:
	var drone: Drone = _drones[index]
	drone.orbit_radius_m = radius_m
	drone.orbit_sign = direction
	drone.schedule_wind_up(wind_up_in_s)


func hold_action(action: String, pressed: bool) -> void:
	if pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)


func set_camera(yaw_deg: float, pitch_deg: float) -> void:
	_orbit.set_angles(yaw_deg, pitch_deg)


## Points the camera's centre ray at the first drone.
func look_at_drone() -> void:
	if _drones.is_empty():
		return
	_look_at(_drones[0])


## The walker teleported to (x, z), facing its heading.
func move_walker_to(x: float, z: float) -> void:
	_walker.teleport(Transform3D(Basis(Vector3.UP, _walker.yaw_radians()), Vector3(x, SPAWN_Y, z)))
	_walker.reset_physics_interpolation()
	_orbit.snap()


## The walker on the spot where the last drone's scrap landed.
func walk_to_drop() -> void:
	move_walker_to(last_drop_point.x, last_drop_point.z)


# --- Scenario helpers: runs ---------------------------------------------------------------------------------------


## Two drones of one encounter 30 m ahead of a fresh walker, then a timed run (see begin_run). One call, so no tick
## passes between the setup and the run.
func duel(mode: String, seconds: float, half_cycle_s: float = 1.0) -> void:
	spawn(0.0)
	add_group(2, 0.0, 30.0)
	begin_run(mode, seconds, half_cycle_s)


## A timed run: mode "idle" (the walker stands still) or "strafe" (Q/E alternating every `half_cycle_s`, the heading held
## on the nearest drone with A/D).
func begin_run(mode: String, seconds: float, half_cycle_s: float = 1.0) -> void:
	reset_checks()
	_run_origin_s = _now_s()
	_drive_ticks = 0
	_drive_limit = int(round(seconds * float(Engine.physics_ticks_per_second)))
	_strafe_half_s = half_cycle_s
	_drive = Drive.STRAFE if mode == "strafe" else Drive.IDLE


func mark_idle() -> void:
	idle_damage = damage_taken


func mark_strafe() -> void:
	strafe_damage = damage_taken


## Risk 8 heading race. A drone 90 deg to the left at 15 m, 4 m up; the walker turns left onto it. `mode`: "still" (the
## drone starts its wind-up now and holds), "away" (it orbits away from the turn) or "toward".
func begin_race(mode: String) -> void:
	var build_spread: float = _rig.spread_override_deg
	spawn(0.0)
	_rig.spread_override_deg = build_spread
	add_drone(90.0, ORBIT_M, HOVER_M, "engaged")
	match mode:
		"still":
			set_orbit(0, ORBIT_M, 1, 0.0)
		"away":
			set_orbit(0, ORBIT_M, 1, 5.0)
		"toward":
			set_orbit(0, ORBIT_M, -1, 5.0)
	_race_ticks = 0
	heading_time_s = -1.0
	heading_final_error_deg = INF
	race_done = false
	_drive_ticks = 0
	_drive_limit = int(round(RACE_S * float(Engine.physics_ticks_per_second)))
	_drive = Drive.RACE


func end_race(mode: String) -> void:
	match mode:
		"still":
			race_still_s = heading_time_s
		"away":
			race_away_s = heading_time_s
		"toward":
			race_toward_s = heading_time_s


## Starts a set of tracker trials (totals reset).
func begin_tracker_set(use_aim: bool = false) -> void:
	_use_aim = use_aim
	tracker_trials = 0
	tracker_kills = 0
	tracker_kill_max_s = 0.0
	tracker_kill_min_s = INF
	tracker_hold_hits = 0
	tracker_hold_misses = 0
	tracker_orbit_hits = 0
	tracker_orbit_misses = 0
	tracker_other_hits = 0
	tracker_other_misses = 0


## One tracker trial: a fresh drone 15 m out, `start_deg` off the heading, orbiting in `direction` (+1 away from a left turn,
## -1 toward), its first wind-up 1.0 s away. The tracker holds A/D toward the drone's current position, aims the camera at it
## and fires continuously, until the drone is dead (or 6 s).
func tracker_trial(direction: int, start_deg: float = 40.0) -> void:
	var build_spread: float = _rig.spread_override_deg
	spawn(0.0)
	_rig.spread_override_deg = build_spread
	add_drone(start_deg, ORBIT_M, HOVER_M, "engaged")
	set_orbit(0, ORBIT_M, direction, 1.0)
	_tracked = _drones[0]
	_trial_first_hold_s = -1.0
	_trial_death_frame = -1
	_trial_tail = -1
	_voided = false
	trial_done = false
	_trial_start_frame = Engine.get_physics_frames()
	_drive_ticks = 0
	_drive_limit = 0
	_look_at(_tracked)
	_drive = Drive.TRACK


## Cost runs: record the drones' and the bolt pool's tick time (microseconds in the nodes, milliseconds here).
func begin_cost() -> void:
	_cost_ms = PackedFloat32Array()
	_cost_on = true


func end_cost(label: String) -> void:
	_cost_on = false
	print(
		(
			"DRONECOST %s p99_ms=%.3f mean_ms=%.3f samples=%d drones=%d active_max=%d bolts_live=%d"
			% [label, cost_p99_ms, cost_mean_ms, cost_samples, _drones.size(), field_active_max, bolts_live]
		)
	)


func respawn_all() -> void:
	_field.respawn_all()
	_drones.clear()
	for encounter in _field.encounters:
		for drone in encounter.drones:
			_register(drone)


## Deals the damage a pulse does to the first drone (a hit during its wind-up, say).
func hit_first(damage: float) -> void:
	if not _drones.is_empty():
		_drones[0].hurtbox.take_hit(damage, null, _drones[0].global_position)


# --- Scenario helpers: shots --------------------------------------------------------------------------------------


## Stops the world (the harness keeps running) on the tick the first drone's wind-up reaches `seconds`.
func freeze_at_wind_up(seconds: float) -> void:
	frozen = false
	_freeze_state = true
	_freeze_at_s = seconds


func unfreeze() -> void:
	_freeze_state = false
	if frozen:
		get_tree().paused = false
	frozen = false


## The same screen, in grayscale (GDD 10 rule 2, M0 criterion 8).
func set_grayscale(on: bool) -> void:
	_gray_layer.visible = on


## Paints the first drone's ring at `glow` (0..1) by hand, while the world is frozen.
func paint_glow(glow: float) -> void:
	var ring: MeshInstance3D = _drones[0].get_node("Body/Ring") as MeshInstance3D
	var material: StandardMaterial3D = ring.material_override as StandardMaterial3D
	material.emission_energy_multiplier = Drone.GLOW_MAX * glow


func hide_first_drone(hidden: bool) -> void:
	_drones[0].visible = not hidden


## Windowed only: keeps the current frame for the luma check. Order: "windup", "idle" (glow 0), "clear" (no drone).
func keep_frame() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var image: Image = get_viewport().get_texture().get_image()
	if image != null and not image.is_empty():
		_frames.append(image)


## The luma of the glowing band in the wound-up frame and in the idle frame, 0..1: the pixels of the ring's tube (0.07 m
## either side of its mid radius, the ink rim excluded) where the drone differs from the clear frame. Needs the three
## kept frames; headless there are none and luma_measured stays false.
func measure_luma() -> void:
	luma_measured = false
	if _frames.size() < 3:
		return
	var wound: Image = _frames[0]
	var idle: Image = _frames[1]
	var clear: Image = _frames[2]
	_frames.clear()
	var camera: Camera3D = _orbit.camera()
	var at: Vector3 = _drones[0].global_position
	var scale: float = float(wound.get_width()) / get_viewport().get_visible_rect().size.x
	var centre: Vector2 = camera.unproject_position(at) * scale
	var depth: float = -(camera.global_transform.affine_inverse() * at).z
	var focal: float = 0.5 * float(wound.get_height()) / tan(deg_to_rad(camera.fov) * 0.5)
	var reach: int = int(ceil(focal * Drone.HURT_RADIUS_M / maxf(depth, 0.001) * 1.5))
	var mid_px: float = focal * BAND_MID_M / maxf(depth, 0.001)
	var half_px: float = focal * BAND_HALF_M / maxf(depth, 0.001)
	var sum_wound: float = 0.0
	var sum_idle: float = 0.0
	var count: int = 0
	for y in range(int(centre.y) - reach, int(centre.y) + reach + 1):
		for x in range(int(centre.x) - reach, int(centre.x) + reach + 1):
			if x < 0 or y < 0 or x >= wound.get_width() or y >= wound.get_height():
				continue
			if absf(Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(centre) - mid_px) > half_px:
				continue
			var l_clear: float = clear.get_pixel(x, y).get_luminance()
			var l_idle: float = idle.get_pixel(x, y).get_luminance()
			if absf(l_idle - l_clear) <= LUMA_CHANGED:
				continue
			sum_idle += l_idle
			sum_wound += wound.get_pixel(x, y).get_luminance()
			count += 1
	luma_pixels = count
	if count == 0:
		return
	luma_idle = sum_idle / float(count)
	luma_windup = sum_wound / float(count)
	luma_delta = luma_windup - luma_idle
	luma_measured = true
	print(
		"DRONELUMA idle=%.3f windup=%.3f delta=%.3f ring_pixels=%d centre=(%.0f,%.0f)"
		% [luma_idle, luma_windup, luma_delta, count, centre.x, centre.y]
	)


## One log line of what the marks show, for the shot checks.
func log_marks(label: String) -> void:
	_marks.refresh()
	print(
		(
			"AIMMARKS %s dot=(%.1f,%.1f) ring=(%.1f,%.1f) ring_shown=%s pip=%s dot_shown=%s thick=%s d=%.1f h=%.1f pitch=%.1f on_enemy=%s"
			% [
				label, _marks.dot_screen.x, _marks.dot_screen.y, _marks.ring_screen.x, _marks.ring_screen.y,
				_marks.ring_visible, _marks.pip_visible, _marks.dot_visible, _marks.thick, _rig.aim_range_m,
				_rig.aim_height_m, _orbit.pitch_deg, _rig.aim_on_enemy,
			]
		)
	)


# --- Scenario helpers: logs ---------------------------------------------------------------------------------------


func log_run(label: String) -> void:
	var text: String = (
		"DRONERUN %s damage=%.0f bolts_hit=%d windups=%d shots=%d telegraph_min_s=%.4f cycle_s=%.4f..%.4f"
		+ " windup_gap_min_s=%.4f hold_ticks=%d hold_speed_max=%.4f hold_drift_max_m=%.4f brake_s_max=%.4f"
		+ " resume_s=%.4f..%.4f orbit_speed_max=%.4f orbit_radius=%.2f..%.2f bolt_aim_err_max_deg=%.5f"
		+ " engaged_max=%d refused=%d"
	)
	print(
		(
			text
			% [
				label, damage_taken, bolts_hit_player, windups, shots_by_drones, telegraph_min_s, cycle_min_s,
				cycle_max_s, windup_gap_min_s, hold_ticks_seen, hold_speed_max, hold_drift_max_m, brake_s_max,
				resume_s_min, resume_s_max, orbit_speed_max, orbit_radius_min, orbit_radius_max,
				bolt_aim_err_max_deg, engaged_max, bolts_refused,
			]
		)
	)


func log_race(label: String) -> void:
	print(
		(
			"DRONERACE %s turn_rate=%.1f heading_time_s=%.3f final_err_deg=%.2f cone_deg=%.2f"
			% [
				label, float(_walker.stats().get("turn_rate", 0.0)), heading_time_s, heading_final_error_deg,
				_race_cone_deg,
			]
		)
	)


func log_scrap(label: String) -> void:
	print(
		(
			"DRONESCRAP %s dropped=%d drop_range=%d..%d pieces_lying=%d carried=%d banked=%d conserved=%s"
			% [
				label, scrap_dropped_total, scrap_drop_min, scrap_drop_max, loose_pieces, economy.carried_scrap,
				economy.banked_scrap, economy.is_conserved(),
			]
		)
	)


func log_tracker(label: String) -> void:
	var text: String = (
		"DRONETRACK %s trials=%d kills=%d kill_s=%.3f..%.3f hold_hit_rate=%.3f (%d of %d)"
		+ " orbit_hit_rate=%.3f (%d of %d) other=%d of %d aim=%s spread=%.2f"
	)
	print(
		(
			text
			% [
				label, tracker_trials, tracker_kills, tracker_kill_min_s, tracker_kill_max_s, tracker_hold_rate,
				tracker_hold_hits, tracker_hold_hits + tracker_hold_misses, tracker_orbit_rate, tracker_orbit_hits,
				tracker_orbit_hits + tracker_orbit_misses, tracker_other_hits,
				tracker_other_hits + tracker_other_misses, _use_aim, _rig.spread_deg(),
			]
		)
	)


# --- Drives -------------------------------------------------------------------------------------------------------


func _drive_strafe() -> void:
	var nearest: Drone = _nearest_alive()
	if nearest != null:
		_turn_onto(nearest.global_position)
	var phase: int = int(float(_drive_ticks) / (_strafe_half_s * float(Engine.physics_ticks_per_second))) % 2
	hold_action("strafe_left", phase == 0)
	hold_action("strafe_right", phase == 1)


func _drive_track(_delta: float) -> void:
	if _tracked == null:
		return
	var frame: int = Engine.get_physics_frames()
	_resolve_passed_shots()
	if _trial_death_frame < 0 and _tracked.is_dead():
		_trial_death_frame = frame
		_trial_tail = TRIAL_TAIL_TICKS
	if _trial_death_frame >= 0:
		if not _voided:
			# Shots still short of the drone when it died hit a wreck: they say nothing about the aim. The shot
			# that killed it has already been counted as a hit by the pool's impact signal.
			_voided = true
			for shot in _shots:
				if shot["status"] == "pending":
					shot["status"] = "void"
		hold_action("turn_left", false)
		hold_action("turn_right", false)
		hold_action("fire", false)
		_trial_tail -= 1
		if _trial_tail <= 0:
			_finish_trial()
		return
	if float(frame - _trial_start_frame) / float(Engine.physics_ticks_per_second) >= TRIAL_MAX_S:
		_finish_trial()
		return
	_turn_onto(_tracked.global_position)
	_look_at(_tracked)
	hold_action("aim", _use_aim)
	hold_action("fire", true)


func _drive_race(_delta: float) -> void:
	var drone: Drone = _drones[0]
	_race_ticks += 1
	var error: float = _turn_onto(drone.global_position)
	if heading_time_s < 0.0 and absf(error) <= _race_cone_deg:
		heading_time_s = float(_race_ticks) / float(Engine.physics_ticks_per_second)
		_drive_limit = mini(_drive_limit, _drive_ticks + RACE_TAIL_TICKS + 1)
	heading_final_error_deg = absf(error)


## A/D toward `spot`'s bearing, released inside the stopping distance (yaw rate x ramp / 2) + 0.5 deg, the tracker's rule.
## Returns the signed heading error in degrees.
func _turn_onto(spot: Vector3) -> float:
	var bearing: float = rad_to_deg(AimMath.bearing_to(_walker.global_position, spot))
	var error: float = wrapf(bearing - rad_to_deg(_walker.yaw_radians()), -180.0, 180.0)
	var stop: float = absf(_walker.yaw_rate_dps) * YAW_RAMP_S * 0.5 + STOP_MARGIN_DEG
	hold_action("turn_left", error > stop)
	hold_action("turn_right", error < -stop)
	return error


func _look_at(drone: Drone) -> void:
	var to: Vector3 = drone.global_position - (_walker.global_position + _orbit.target_offset)
	var flat: float = Vector2(to.x, to.z).length()
	_orbit.set_angles(rad_to_deg(atan2(-to.x, -to.z)), -rad_to_deg(atan2(to.y, flat)))


func _end_drive() -> void:
	if _drive == Drive.NONE:
		return
	var was: Drive = _drive
	_drive = Drive.NONE
	_release_inputs()
	if was == Drive.RACE:
		race_done = true
		race_finished.emit()
	elif was == Drive.IDLE or was == Drive.STRAFE:
		run_done = true
		run_finished.emit()


func _release_inputs() -> void:
	for action in ["turn_left", "turn_right", "strafe_left", "strafe_right", "move_forward", "move_back", "fire", "aim"]:
		Input.action_release(action)


func _nearest_alive() -> Drone:
	var best: Drone = null
	var best_d: float = INF
	for drone in _drones:
		if not is_instance_valid(drone) or drone.is_dead():
			continue
		var d: float = drone.global_position.distance_to(_walker.global_position)
		if d < best_d:
			best_d = d
			best = drone
	return best


# --- Tracker bookkeeping ------------------------------------------------------------------------------------------


## Tags the pooled bolt the rig just fired and says which window the shot left in.
func _on_player_shot(_weapon: int, origin: Vector3, _direction: Vector3) -> void:
	if _tracked == null or _trial_death_frame >= 0:
		return
	var frame: int = Engine.get_physics_frames()
	var bolt: Projectile = null
	for child in _rig.pool.get_children():
		var candidate := child as Projectile
		if candidate != null and candidate.alive and candidate.age == 0.0 and candidate.get_meta("tag_frame", -1) != frame:
			bolt = candidate
			break
	if bolt == null:
		return
	bolt.set_meta("tag_frame", frame)
	var track: DroneTrack = _track_of(_tracked)
	var class_name_: String = "orbit"
	if DroneBrain.is_holding(_tracked.brain.state):
		var since: float = float(frame - track.start_frame) / float(Engine.physics_ticks_per_second)
		class_name_ = "hold" if since >= WINDOW_FROM_S - 0.000001 and since <= WINDOW_TO_S + 0.000001 else "other"
	var info := {
		"class": class_name_,
		"status": "pending",
		"bolt": bolt,
		"frame": frame,
		"range": origin.distance_to(_tracked.global_position),
	}
	bolt.set_meta("shot", info)
	_shots.append(info)


## Shots that have flown past the drone, or expired, without hitting it are misses.
func _resolve_passed_shots() -> void:
	for shot in _shots:
		if shot["status"] != "pending":
			continue
		var bolt: Projectile = shot["bolt"]
		var gone: bool = not bolt.alive or bolt.get_meta("tag_frame", -1) != shot["frame"]
		if gone or bolt.travelled > float(shot["range"]) + PASS_MARGIN_M:
			shot["status"] = "miss"


func _on_player_impact(_point: Vector3, collider: Object, projectile: Projectile, counted: bool) -> void:
	if _tracked == null or not projectile.has_meta("shot"):
		return
	var shot: Dictionary = projectile.get_meta("shot")
	if shot["status"] != "pending":
		return
	shot["status"] = "hit" if counted and collider == _tracked.hurtbox else "miss"
	projectile.remove_meta("shot")


func _finish_trial() -> void:
	if trial_done:
		return
	var killed: bool = _trial_death_frame >= 0
	for shot in _shots:
		if shot["status"] == "pending":
			# A shot still short of the drone when it died or the trial timed out says nothing.
			shot["status"] = "void"
		match shot["class"]:
			"hold":
				if shot["status"] == "hit":
					tracker_hold_hits += 1
				elif shot["status"] == "miss":
					tracker_hold_misses += 1
			"orbit":
				if shot["status"] == "hit":
					tracker_orbit_hits += 1
				elif shot["status"] == "miss":
					tracker_orbit_misses += 1
			_:
				if shot["status"] == "hit":
					tracker_other_hits += 1
				elif shot["status"] == "miss":
					tracker_other_misses += 1
	var trial_line: PackedStringArray = PackedStringArray()
	for shot in _shots:
		trial_line.append("%s:%s" % [shot["class"], shot["status"]])
	var kill_text: String = "none"
	if killed and _trial_first_hold_s >= 0.0:
		kill_text = "%.3f" % (float(_trial_death_frame) / float(Engine.physics_ticks_per_second) - _trial_first_hold_s)
	print("DRONETRIAL killed_after_first_hold_s=%s shots=%s" % [kill_text, " ".join(trial_line)])
	_shots.clear()
	tracker_trials += 1
	if killed and _trial_first_hold_s >= 0.0:
		var kill_s: float = float(_trial_death_frame) / float(Engine.physics_ticks_per_second) - _trial_first_hold_s
		tracker_kills += 1
		tracker_kill_max_s = maxf(tracker_kill_max_s, kill_s)
		tracker_kill_min_s = minf(tracker_kill_min_s, kill_s)
	_drive = Drive.NONE
	_release_inputs()
	trial_done = true
	trial_finished.emit()


func _rate(hits: int, misses: int) -> float:
	var total: int = hits + misses
	return float(hits) / float(total) if total > 0 else 0.0


# --- Drone bookkeeping --------------------------------------------------------------------------------------------


class DroneTrack:
	extends RefCounted
	var wind_up_s: float = -INF
	var start_frame: int = -1
	var anchor: Vector3 = Vector3.ZERO
	var braked: bool = false
	var pre_speed: float = 0.0
	var resume_s: float = -1.0
	var resume_ref: float = 0.0


func _track_of(drone: Drone) -> DroneTrack:
	var id: int = drone.get_instance_id()
	if not _tracks.has(id):
		_tracks[id] = DroneTrack.new()
	return _tracks[id]


func _spot(bearing_deg: float, distance_m: float) -> Vector3:
	var at: Vector3 = _walker.global_position + AimMath.heading(deg_to_rad(bearing_deg)) * distance_m
	return Vector3(at.x, 0.0, at.z)


func _adopt(drone: Drone, mode: String) -> void:
	match mode:
		"engaged":
			drone.engage_now()
		"dormant":
			drone.ai_enabled = false
	_register(drone)


func _register(drone: Drone) -> void:
	drone.wind_up_started.connect(_on_wind_up_started)
	drone.shot_fired.connect(_on_shot_fired)
	drone.state_changed.connect(_on_state_changed)
	drone.died.connect(_on_drone_died)
	drone.scrap_dropped.connect(_on_scrap_dropped)
	_drones.append(drone)


func _now_s() -> float:
	return float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second)


func _sample_drones() -> void:
	var frame: int = Engine.get_physics_frames()
	var now: float = _now_s()
	var aim: Vector3 = _walker.body_pose() * _walker.chassis_center()
	for drone in _drones:
		if not is_instance_valid(drone) or drone.is_dead() or not drone.ai_enabled:
			continue
		var track: DroneTrack = _track_of(drone)
		var speed: float = drone.velocity.length()
		var state: DroneBrain.State = drone.brain.state
		if DroneBrain.is_engaged(state):
			orbit_speed_max = maxf(orbit_speed_max, speed)
			var to: Vector3 = drone.global_position - aim
			var flat: float = Vector2(to.x, to.z).length()
			if now - _run_origin_s > RADIUS_SETTLE_S:
				orbit_radius_min = minf(orbit_radius_min, flat)
				orbit_radius_max = maxf(orbit_radius_max, flat)
		if DroneBrain.is_holding(state):
			var since: int = frame - track.start_frame
			if not track.braked and speed <= 0.05:
				track.braked = true
				brake_s_max = maxf(brake_s_max, float(since) / float(Engine.physics_ticks_per_second))
			if since >= HOLD_SPEED_FROM_TICK:
				var body: Vector3 = drone.get_node("Body").global_position
				if since == HOLD_SPEED_FROM_TICK:
					track.anchor = body
				hold_ticks_seen += 1
				hold_speed_max = maxf(hold_speed_max, speed)
				hold_drift_max_m = maxf(hold_drift_max_m, body.distance_to(track.anchor))
		else:
			if drone.brain.speed_factor >= 0.999:
				track.pre_speed = speed
			if track.resume_s >= 0.0 and speed >= RESUME_SHARE * track.resume_ref:
				var took: float = now - track.resume_s
				resume_s_min = minf(resume_s_min, took)
				resume_s_max = maxf(resume_s_max, took)
				track.resume_s = -1.0


func _on_wind_up_started(drone: Drone) -> void:
	var now: float = _now_s()
	var track: DroneTrack = _track_of(drone)
	if track.wind_up_s > -INF:
		var cycle: float = now - track.wind_up_s
		cycle_min_s = minf(cycle_min_s, cycle)
		cycle_max_s = maxf(cycle_max_s, cycle)
	track.wind_up_s = now
	track.start_frame = Engine.get_physics_frames()
	track.braked = false
	windups += 1
	var enc_id: int = drone.encounter.get_instance_id() if drone.encounter != null else 0
	if _enc_last_start.has(enc_id):
		windup_gap_min_s = minf(windup_gap_min_s, now - float(_enc_last_start[enc_id]))
	_enc_last_start[enc_id] = now
	if drone == _tracked and _trial_first_hold_s < 0.0:
		_trial_first_hold_s = now


func _on_shot_fired(drone: Drone, origin: Vector3, direction: Vector3) -> void:
	shots_by_drones += 1
	var track: DroneTrack = _track_of(drone)
	telegraph_min_s = minf(telegraph_min_s, _now_s() - track.wind_up_s)
	var chassis: Vector3 = _walker.body_pose() * _walker.chassis_center()
	bolt_aim_err_max_deg = maxf(bolt_aim_err_max_deg, rad_to_deg(direction.angle_to(chassis - origin)))


func _on_state_changed(drone: Drone, from_state: DroneBrain.State, to_state: DroneBrain.State) -> void:
	match to_state:
		DroneBrain.State.ALERT:
			seen_alert = true
		DroneBrain.State.STRAFE:
			seen_strafe = true
			if from_state == DroneBrain.State.RECOVER:
				var track: DroneTrack = _track_of(drone)
				track.resume_s = _now_s()
				track.resume_ref = track.pre_speed
		DroneBrain.State.WIND_UP:
			seen_wind_up = true
		DroneBrain.State.RECOVER:
			seen_recover = true
		DroneBrain.State.PATROL:
			seen_patrol = true
		DroneBrain.State.IDLE_HOVER:
			if seen_patrol:
				seen_idle_again = true


func _on_drone_died(drone: Drone, _position: Vector3) -> void:
	deaths += 1
	if drone == _tracked and _trial_death_frame < 0:
		_trial_death_frame = Engine.get_physics_frames()
		_trial_tail = TRIAL_TAIL_TICKS


func _on_scrap_dropped(_drone: Drone, amount: int, position: Vector3) -> void:
	scrap_dropped_total += amount
	scrap_drop_min = amount if scrap_drop_min == 0 else mini(scrap_drop_min, amount)
	scrap_drop_max = maxi(scrap_drop_max, amount)
	last_drop_point = position


func _on_field_death(position: Vector3) -> void:
	field_deaths += 1
	field_death_point = position


func _on_player_hit(damage: float, _source: Node, _point: Vector3) -> void:
	damage_taken += damage
	bolts_hit_player += 1


# --- Freeze -----------------------------------------------------------------------------------------------------


func _check_freeze() -> void:
	if _drones.is_empty():
		return
	var drone: Drone = _drones[0]
	if drone.brain.state == DroneBrain.State.WIND_UP and drone.brain.state_t >= _freeze_at_s - 0.000001:
		frozen = true
		get_tree().paused = true


# --- World ------------------------------------------------------------------------------------------------------


func _p99(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted: PackedFloat32Array = values.duplicate()
	sorted.sort()
	return sorted[clampi(int(ceil(0.99 * float(sorted.size()))) - 1, 0, sorted.size() - 1)]


func _build_gray_layer() -> void:
	_gray_layer = CanvasLayer.new()
	_gray_layer.layer = 100
	_gray_layer.visible = false
	var shader := Shader.new()
	shader.code = (
		"shader_type canvas_item;\n"
		+ "uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;\n"
		+ "void fragment() {\n"
		+ "	vec3 c = texture(screen_texture, SCREEN_UV).rgb;\n"
		+ "	float l = dot(c, vec3(0.299, 0.587, 0.114));\n"
		+ "	COLOR = vec4(vec3(l), 1.0);\n"
		+ "}\n"
	)
	var material := ShaderMaterial.new()
	material.shader = shader
	var rect := ColorRect.new()
	rect.material = material
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_gray_layer.add_child(rect)
	add_child(_gray_layer)


func _build_world() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = GROUND_COLOR
	var ground := StaticBody3D.new()
	ground.collision_layer = CombatLayers.WORLD
	ground.collision_mask = 0
	ground.position = Vector3(0.0, -1.0, 0.0)
	var shape := BoxShape3D.new()
	shape.size = Vector3(600.0, 2.0, 600.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	ground.add_child(collider)
	var mesh := BoxMesh.new()
	mesh.size = shape.size
	var piece := MeshInstance3D.new()
	piece.mesh = mesh
	piece.material_override = material
	ground.add_child(piece)
	add_child(ground)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = SKY_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.78, 0.82)
	environment.ambient_light_energy = 0.6
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60.0, 25.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)
