extends GutTest
## Unit tests for the drone (GDD 5, 8.4, 16 risk 8): the brain's transitions as pure functions, the shot cycle and the
## hold timings, the stagger, the engagement cap, the bolt pool, and the Drone body (hits, death, scrap, bolt aim, leash).

const TICK: float = 1.0 / 60.0
const S := DroneBrain.State

var _hits: int = 0
var _last_hit_damage: float = 0.0
var _last_hit_source: Node = null


# --- Helpers ----------------------------------------------------------------------------------------------------


## Senses of a walker `dist` m away on flat ground, in sight, at the drone's spawn point.
func _senses(dist: float = 15.0, los: bool = true) -> DroneBrain.Senses:
	var s := DroneBrain.Senses.new()
	s.player_dist = dist
	s.player_flat_dist = dist
	s.line_of_sight = los
	s.player_home_dist = dist
	s.home_dist = 0.0
	return s


## A brain that has been alert since tick 0 and orbits (STRAFE) by the next tick.
func _orbiting_brain() -> DroneBrain:
	var brain := DroneBrain.new()
	brain.update(TICK, _senses(30.0))
	brain.update(TICK, _senses(15.0))
	return brain


## Runs `ticks` updates with `s`. Returns {starts, shots, factors, states}, all by tick index.
func _run(brain: DroneBrain, s: DroneBrain.Senses, ticks: int) -> Dictionary:
	var result := {"starts": [], "shots": [], "factors": [], "states": []}
	for tick in ticks:
		brain.update(TICK, s)
		if brain.wind_up_began:
			result["starts"].append(tick)
		if brain.fired:
			result["shots"].append(tick)
		result["factors"].append(brain.speed_factor)
		result["states"].append(brain.state)
	return result


func _floor() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = CombatLayers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 2.0, 400.0)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0.0, -1.0, 0.0)
	add_child_autofree(body)
	return body


## A stand-in walker: a node with a `Chassis` child at `at`.
func _walker(at: Vector3) -> Node3D:
	var walker := Node3D.new()
	var chassis := Node3D.new()
	chassis.name = "Chassis"
	walker.add_child(chassis)
	add_child_autofree(walker)
	chassis.global_position = at
	return walker


func _drone(seed_value: int = 7) -> Drone:
	var drone: Drone = load("res://scenes/enemies/drone.tscn").instantiate()
	drone.auto_step = false
	drone.configure(seed_value)
	add_child_autofree(drone)
	return drone


func _pool(cap: int = 8) -> DroneBoltPool:
	var pool := DroneBoltPool.new()
	pool.cap = cap
	pool.auto_step = false
	add_child_autofree(pool)
	return pool


func _hurtbox_at(at: Vector3, layer: int, radius: float = 0.6) -> Hurtbox:
	var box := Hurtbox.new()
	box.collision_layer = layer
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	box.add_child(shape)
	box.position = at
	box.hit_taken.connect(
		func(damage: float, source: Node, _point: Vector3) -> void:
			_hits += 1
			_last_hit_damage = damage
			_last_hit_source = source
	)
	add_child_autofree(box)
	return box


# --- Brain: transitions are pure functions -----------------------------------------------------------------------


func test_an_idle_drone_that_sees_the_walker_within_35_m_goes_alert() -> void:
	assert_eq(DroneBrain.decide(S.IDLE_HOVER, 5.0, 5.0, 0.0, _senses(34.9)), S.ALERT)
	assert_eq(DroneBrain.decide(S.IDLE_HOVER, 5.0, 5.0, 0.0, _senses(10.0)), S.ALERT)


func test_an_idle_drone_ignores_a_walker_it_cannot_see() -> void:
	assert_eq(DroneBrain.decide(S.IDLE_HOVER, 5.0, 5.0, 0.0, _senses(35.1)), S.IDLE_HOVER, "36 m is out of sight")
	assert_eq(DroneBrain.decide(S.IDLE_HOVER, 5.0, 5.0, 0.0, _senses(10.0, false)), S.IDLE_HOVER, "no line of sight")


func test_an_idle_drone_does_not_engage_beyond_the_leash_or_without_a_slot() -> void:
	var far := _senses(20.0)
	far.player_home_dist = 60.1
	assert_eq(DroneBrain.decide(S.IDLE_HOVER, 5.0, 5.0, 0.0, far), S.IDLE_HOVER, "the walker is 60+ m from its spawn")
	var full := _senses(20.0)
	full.may_engage = false
	assert_eq(DroneBrain.decide(S.IDLE_HOVER, 5.0, 5.0, 0.0, full), S.IDLE_HOVER, "4 drones are already active")


func test_a_drone_that_took_a_hit_reacts_without_sight() -> void:
	var s := _senses(50.0, false)
	s.provoked = true
	assert_eq(DroneBrain.decide(S.IDLE_HOVER, 5.0, 5.0, 0.0, s), S.ALERT)
	s.player_home_dist = 70.0
	assert_eq(DroneBrain.decide(S.IDLE_HOVER, 5.0, 5.0, 0.0, s), S.IDLE_HOVER, "but not past the leash")


func test_alert_closes_in_until_the_walker_is_within_18_m_then_orbits() -> void:
	assert_eq(DroneBrain.decide(S.ALERT, 1.0, 1.0, 0.0, _senses(25.0)), S.ALERT)
	assert_eq(DroneBrain.decide(S.ALERT, 1.0, 1.0, 0.0, _senses(18.01)), S.ALERT)
	assert_eq(DroneBrain.decide(S.ALERT, 1.0, 1.0, 0.0, _senses(18.0)), S.STRAFE)


func test_the_leash_sends_an_engaged_drone_home_when_the_walker_is_over_60_m_from_its_spawn() -> void:
	var near := _senses(15.0)
	near.player_home_dist = 60.0
	var far := _senses(15.0)
	far.player_home_dist = 60.01
	# Inside the leash an alert drone at 15 m starts to orbit and an orbiting one keeps orbiting.
	assert_eq(DroneBrain.decide(S.ALERT, 1.0, 0.1, 0.0, near), S.STRAFE, "60.0 m is still inside the leash")
	assert_eq(DroneBrain.decide(S.STRAFE, 1.0, 0.1, 0.0, near), S.STRAFE)
	for state in [S.ALERT, S.STRAFE]:
		assert_eq(DroneBrain.decide(state, 1.0, 0.1, 0.0, far), S.PATROL, "60.01 m sends it home")


func test_three_seconds_without_sight_send_an_engaged_drone_home() -> void:
	var blind := _senses(15.0, false)
	assert_eq(DroneBrain.decide(S.STRAFE, 1.0, 0.1, 2.9, blind), S.STRAFE)
	assert_eq(DroneBrain.decide(S.STRAFE, 1.0, 0.1, 3.0, blind), S.PATROL)
	assert_eq(DroneBrain.decide(S.ALERT, 1.0, 0.1, 3.0, blind), S.PATROL)


func test_a_patrolling_drone_goes_idle_at_home_and_re_engages_a_walker_it_sees() -> void:
	var home := _senses(50.0, false)
	home.home_dist = 1.0
	assert_eq(DroneBrain.decide(S.PATROL, 1.0, 1.0, 0.0, home), S.IDLE_HOVER)
	home.home_dist = 1.01
	assert_eq(DroneBrain.decide(S.PATROL, 1.0, 1.0, 0.0, home), S.PATROL)
	var seen := _senses(20.0)
	seen.home_dist = 30.0
	assert_eq(DroneBrain.decide(S.PATROL, 1.0, 1.0, 0.0, seen), S.ALERT)


func test_strafe_winds_up_only_when_the_cycle_is_due_the_walker_is_seen_and_the_encounter_allows_it() -> void:
	var s := _senses(15.0)
	assert_eq(DroneBrain.decide(S.STRAFE, 2.0, 1.49, 0.0, s), S.STRAFE, "0.01 s early")
	assert_eq(DroneBrain.decide(S.STRAFE, 2.0, 1.5, 0.0, s), S.WIND_UP)
	var blind := _senses(15.0, false)
	assert_eq(DroneBrain.decide(S.STRAFE, 2.0, 1.6, 0.0, blind), S.STRAFE, "no shot without a line of sight")
	var held := _senses(15.0)
	held.may_wind_up = false
	assert_eq(DroneBrain.decide(S.STRAFE, 2.0, 1.6, 0.0, held), S.STRAFE, "the stagger holds it back")


func test_wind_up_lasts_0_6_s_fire_passes_and_recovery_lasts_0_3_s() -> void:
	var s := _senses(15.0)
	assert_eq(DroneBrain.decide(S.WIND_UP, 0.59, 0.59, 0.0, s), S.WIND_UP)
	assert_eq(DroneBrain.decide(S.WIND_UP, 0.6, 0.6, 0.0, s), S.FIRE)
	assert_eq(DroneBrain.decide(S.FIRE, 0.0, 0.6, 0.0, s), S.RECOVER)
	assert_eq(DroneBrain.decide(S.RECOVER, 0.29, 0.89, 0.0, s), S.RECOVER)
	assert_eq(DroneBrain.decide(S.RECOVER, 0.3, 0.9, 0.0, s), S.STRAFE)


func test_a_shot_in_progress_is_not_cancelled_by_the_leash_or_by_losing_sight() -> void:
	var far := _senses(15.0, false)
	far.player_home_dist = 90.0
	assert_eq(DroneBrain.decide(S.WIND_UP, 0.3, 0.3, 5.0, far), S.WIND_UP)
	assert_eq(DroneBrain.decide(S.RECOVER, 0.1, 0.7, 5.0, far), S.RECOVER)


func test_zero_hp_is_dead_from_every_state_and_dead_stays_dead() -> void:
	var s := _senses(15.0)
	s.hp = 0.0
	for state in S.values():
		assert_eq(DroneBrain.decide(state, 0.1, 0.1, 0.0, s), S.DEAD, "from %s" % DroneBrain.state_name(state))
	assert_eq(DroneBrain.decide(S.DEAD, 9.0, 9.0, 0.0, _senses(15.0)), S.DEAD)


func test_engaged_and_holding_states() -> void:
	for state in [S.ALERT, S.STRAFE, S.WIND_UP, S.FIRE, S.RECOVER]:
		assert_true(DroneBrain.is_engaged(state), DroneBrain.state_name(state))
	for state in [S.IDLE_HOVER, S.PATROL, S.DEAD]:
		assert_false(DroneBrain.is_engaged(state), DroneBrain.state_name(state))
	for state in [S.WIND_UP, S.FIRE, S.RECOVER]:
		assert_true(DroneBrain.is_holding(state))
	assert_false(DroneBrain.is_holding(S.STRAFE))


# --- Brain: the shot cycle and the hold -------------------------------------------------------------------------


func test_the_drone_shoots_every_1_5_s() -> void:
	var run: Dictionary = _run(_orbiting_brain(), _senses(15.0), 600)
	var starts: Array = run["starts"]
	assert_gte(starts.size(), 6)
	for i in range(1, starts.size()):
		assert_eq(starts[i] - starts[i - 1], 90, "wind-up starts are 90 ticks (1.5 s) apart")


func test_the_telegraph_is_at_least_0_6_s_before_every_shot() -> void:
	var run: Dictionary = _run(_orbiting_brain(), _senses(15.0), 600)
	assert_gte(run["shots"].size(), 5)
	for i in run["shots"].size():
		var lead_ticks: int = run["shots"][i] - run["starts"][i]
		assert_gte(float(lead_ticks) * TICK, 0.6 - 0.000001, "shot %d" % i)


func test_the_drone_brakes_to_zero_within_0_1_s_and_holds_through_the_shot_and_recovery() -> void:
	var run: Dictionary = _run(_orbiting_brain(), _senses(15.0), 400)
	var start: int = run["starts"][0]
	var factors: Array = run["factors"]
	assert_almost_eq(factors[start - 1], 1.0, 0.0001, "at full orbit speed before the wind-up")
	assert_almost_eq(factors[start + 6], 0.0, 0.0001, "stopped 6 ticks (0.1 s) after the wind-up started")
	for offset in range(6, 54):
		assert_lte(factors[start + offset] * DroneBrain.ORBIT_SPEED_MPS, 0.05, "tick +%d of the hold" % offset)


func test_the_drone_regains_orbit_speed_over_0_3_s_after_the_recovery() -> void:
	var run: Dictionary = _run(_orbiting_brain(), _senses(15.0), 400)
	var start: int = run["starts"][0]
	var factors: Array = run["factors"]
	assert_eq(run["states"][start + 53], S.RECOVER)
	assert_eq(run["states"][start + 54], S.STRAFE, "the hold is 54 ticks: 0.6 s wind-up and 0.3 s recovery")
	assert_eq(factors[start + 53], 0.0, "still stopped on the last tick of the hold")
	assert_almost_eq(factors[start + 54 + 16], 17.0 / 18.0, 0.0001, "one tick short of 0.3 s")
	assert_almost_eq(factors[start + 54 + 17], 1.0, 0.0001, "back at orbit speed 18 ticks (0.3 s) after the hold began to lift")
	for offset in range(54, 71):
		assert_gt(factors[start + offset], factors[start + offset - 1], "rising, tick +%d" % offset)


func test_the_hold_is_0_9_s_of_every_1_5_s() -> void:
	var run: Dictionary = _run(_orbiting_brain(), _senses(15.0), 600)
	var holding: int = 0
	var states: Array = run["states"]
	for i in range(run["starts"][0], run["starts"][0] + 90):
		if DroneBrain.is_holding(states[i]):
			holding += 1
	assert_eq(holding, 54, "54 of 90 ticks")


func test_a_hit_that_does_not_kill_never_cancels_the_shot() -> void:
	var brain: DroneBrain = _orbiting_brain()
	var s := _senses(15.0)
	var shots: int = 0
	var hits: int = 0
	for tick in 200:
		# Two pulses land during the first wind-up (45 -> 30 -> 15 hp).
		if brain.state == S.WIND_UP and brain.state_t > 0.2 and hits == 0:
			s.hp = 30.0
			hits = 1
		if brain.state == S.WIND_UP and brain.state_t > 0.4 and hits == 1:
			s.hp = 15.0
			hits = 2
		brain.update(TICK, s)
		if brain.fired:
			shots += 1
			break
	assert_eq(hits, 2, "the drone was hit twice during the wind-up")
	assert_eq(shots, 1, "and the shot still left")


func test_a_drone_killed_during_the_wind_up_still_fires_at_the_end_of_it() -> void:
	var brain: DroneBrain = _orbiting_brain()
	var s := _senses(15.0)
	var start: int = -1
	var shots: Array[int] = []
	for tick in 200:
		if brain.state == S.WIND_UP and brain.state_t > 0.3:
			s.hp = 0.0
		brain.update(TICK, s)
		if brain.wind_up_began:
			start = tick
		if brain.fired:
			shots.append(tick)
	assert_eq(brain.state, S.DEAD)
	assert_eq(shots.size(), 1, "one last shot, and no more after it")
	assert_eq(shots[0] - start, 36, "0.6 s after the wind-up started, as if it had lived")


func test_the_glow_of_a_drone_killed_in_its_wind_up_keeps_rising_to_the_shot() -> void:
	var brain: DroneBrain = _orbiting_brain()
	var s := _senses(15.0)
	while brain.state != S.WIND_UP:
		brain.update(TICK, s)
	for i in 20:
		brain.update(TICK, s)
	s.hp = 0.0
	brain.update(TICK, s)
	assert_eq(brain.state, S.DEAD)
	var last: float = brain.glow()
	assert_gt(last, 0.5, "it was well into its wind-up")
	for i in 100:
		brain.update(TICK, s)
		if brain.fired:
			break
		assert_gte(brain.glow(), last - 0.000001, "still rising")
		last = brain.glow()
	assert_true(brain.fired)
	assert_gt(last, 0.95, "full glow when the shot leaves")
	assert_eq(brain.glow(), 0.0, "dark once it has fired")


func test_a_drone_killed_after_its_shot_has_no_shot_left() -> void:
	var brain: DroneBrain = _orbiting_brain()
	var s := _senses(15.0)
	while brain.state != S.RECOVER:
		brain.update(TICK, s)
	s.hp = 0.0
	var fired: bool = false
	for tick in 100:
		brain.update(TICK, s)
		fired = fired or brain.fired
	assert_eq(brain.state, S.DEAD)
	assert_false(fired)


func test_the_glow_ramps_0_to_1_over_the_wind_up_and_fades_over_the_recovery() -> void:
	assert_eq(DroneBrain.glow_level(S.STRAFE, 0.5), 0.0)
	assert_eq(DroneBrain.glow_level(S.WIND_UP, 0.0), 0.0)
	assert_almost_eq(DroneBrain.glow_level(S.WIND_UP, 0.3), 0.5, 0.0001)
	assert_eq(DroneBrain.glow_level(S.WIND_UP, 0.6), 1.0)
	assert_eq(DroneBrain.glow_level(S.FIRE, 0.0), 1.0)
	assert_almost_eq(DroneBrain.glow_level(S.RECOVER, 0.15), 0.5, 0.0001)
	assert_eq(DroneBrain.glow_level(S.RECOVER, 0.3), 0.0)


func test_alert_resets_the_cycle_so_the_first_shot_is_1_5_s_after_the_drone_noticed_the_walker() -> void:
	var brain := DroneBrain.new()
	var s := _senses(15.0)
	var first: int = -1
	for tick in 200:
		brain.update(TICK, s)
		if brain.wind_up_began:
			first = tick
			break
	assert_eq(first, 90, "alert on tick 0, due 90 ticks later")


# --- Encounter stagger and engagement cap -----------------------------------------------------------------------


func test_wind_up_starts_in_one_encounter_are_at_least_0_4_s_apart() -> void:
	for count in [2, 3, 4]:
		var encounter := DroneEncounter.new()
		add_child_autofree(encounter)
		var brains: Array[DroneBrain] = []
		var senses: Array[DroneBrain.Senses] = []
		for i in count:
			brains.append(_orbiting_brain())
			senses.append(_senses(15.0))
		var starts: Array[float] = []
		var per_drone: Array = []
		for i in count:
			per_drone.append([])
		for tick in 900:
			var now: float = float(tick) * TICK
			for i in count:
				senses[i].may_wind_up = encounter.can_wind_up(now)
				brains[i].update(TICK, senses[i])
				if brains[i].wind_up_began:
					encounter.note_wind_up(now)
					starts.append(now)
					per_drone[i].append(now)
		assert_gte(starts.size(), count * 5, "%d drones all keep shooting" % count)
		for i in range(1, starts.size()):
			assert_gte(starts[i] - starts[i - 1], 0.4 - 0.000001, "%d drones, start %d" % [count, i])
		for i in count:
			for k in range(1, per_drone[i].size()):
				assert_gte(per_drone[i][k] - per_drone[i][k - 1], 1.5 - 0.000001, "drone %d keeps its 1.5 s cycle" % i)


func test_two_drones_that_are_ready_together_start_0_4_s_apart_not_together() -> void:
	var encounter := DroneEncounter.new()
	add_child_autofree(encounter)
	assert_true(encounter.can_wind_up(10.0), "the first start is free")
	encounter.note_wind_up(10.0)
	assert_false(encounter.can_wind_up(10.0))
	assert_false(encounter.can_wind_up(10.39))
	assert_true(encounter.can_wind_up(10.4))


func test_at_most_four_drones_are_active() -> void:
	var field := DroneField.new()
	add_child_autofree(field)
	var drones: Array[Node] = []
	for i in 6:
		var stub := Node.new()
		add_child_autofree(stub)
		drones.append(stub)
	for i in 4:
		assert_true(field.can_engage(drones[i]))
		field.set_engaged(drones[i], true)
	assert_false(field.can_engage(drones[4]), "a fifth drone waits")
	assert_true(field.can_engage(drones[0]), "one that already holds a slot keeps it")
	assert_eq(field.active_count(), 4)
	field.set_engaged(drones[1], false)
	assert_true(field.can_engage(drones[4]), "a slot freed")
	field.set_engaged(drones[4], true)
	assert_false(field.can_engage(drones[5]))
	assert_eq(field.active_count(), 4)


# --- Bolt pool --------------------------------------------------------------------------------------------------


func test_a_bolt_flies_at_25_m_per_s_and_lives_3_s() -> void:
	var pool: DroneBoltPool = _pool()
	assert_true(pool.fire(Vector3(0.0, 50.0, 0.0), Vector3.RIGHT))
	await wait_physics_frames(2)
	for i in 36:
		pool.step(TICK)
	assert_almost_eq(pool.live_bolts()[0].travelled, 15.0, 0.01, "0.6 s is 15 m")
	for i in range(36, 180):
		pool.step(TICK)
	assert_eq(pool.live, 0, "gone after 3 s")


func test_at_most_eight_bolts_are_live_and_refusals_are_counted() -> void:
	var pool: DroneBoltPool = _pool()
	var accepted: int = 0
	for i in 10:
		if pool.fire(Vector3(0.0, 50.0, 0.0), Vector3.UP):
			accepted += 1
	assert_eq(accepted, 8)
	assert_eq(pool.refused_count, 2)
	pool.clear()
	assert_eq(pool.live, 0)
	assert_true(pool.fire(Vector3(0.0, 50.0, 0.0), Vector3.UP), "the pool reuses a retired bolt")


func test_a_bolt_damages_a_player_hurtbox_once_for_10() -> void:
	var pool: DroneBoltPool = _pool()
	_hits = 0
	_hurtbox_at(Vector3(10.0, 1.0, 0.0), CombatLayers.PLAYER)
	await wait_physics_frames(2)
	pool.fire(Vector3(0.0, 1.0, 0.0), Vector3.RIGHT)
	for i in 40:
		pool.step(TICK)
	assert_eq(_hits, 1, "once")
	assert_eq(_last_hit_damage, 10.0)
	assert_eq(pool.live, 0, "the bolt ended on the hit")
	assert_eq(pool.impact_count, 1)


func test_a_bolt_passes_through_the_walker_body_on_layer_2_and_misses_between_the_legs() -> void:
	var pool: DroneBoltPool = _pool()
	_hits = 0
	# The WalkerBody's own colliders are bodies on layer 2: the bolt must not stop on them.
	var legs := StaticBody3D.new()
	legs.collision_layer = CombatLayers.PLAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	shape.shape = box
	legs.add_child(shape)
	legs.position = Vector3(5.0, 1.0, 0.0)
	add_child_autofree(legs)
	_hurtbox_at(Vector3(5.0, 1.0, 4.0), CombatLayers.PLAYER, 0.6)
	await wait_physics_frames(2)
	pool.fire(Vector3(0.0, 1.0, 0.0), Vector3.RIGHT)
	for i in 30:
		pool.step(TICK)
	assert_eq(_hits, 0, "no hurtbox on the line, so no hit")
	assert_eq(pool.impact_count, 0, "the body on layer 2 did not end the bolt")
	assert_gt(pool.live_bolts()[0].position.x, 8.0, "it flew on past the legs")


func test_a_wall_ends_a_bolt_and_covers_a_hurtbox_behind_it() -> void:
	var pool: DroneBoltPool = _pool()
	_hits = 0
	var wall := StaticBody3D.new()
	wall.collision_layer = CombatLayers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 6.0, 6.0)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(5.0, 1.0, 0.0)
	add_child_autofree(wall)
	_hurtbox_at(Vector3(10.0, 1.0, 0.0), CombatLayers.PLAYER)
	await wait_physics_frames(2)
	var landed: Array = []
	pool.impacted.connect(
		func(_point: Vector3, collider: Object, _bolt: DroneBoltPool.Bolt, counted: bool) -> void:
			landed.append([collider, counted])
	)
	pool.fire(Vector3(0.0, 1.0, 0.0), Vector3.RIGHT)
	for i in 40:
		pool.step(TICK)
	assert_eq(_hits, 0, "cover works")
	assert_eq(landed.size(), 1)
	assert_eq(landed[0][0], wall)
	assert_false(landed[0][1], "a wall is not a counted hit")


func test_bolt_layers_are_layer_5_with_mask_1_and_2() -> void:
	var pool: DroneBoltPool = _pool(1)
	await wait_physics_frames(1)
	pool.fire(Vector3.ZERO, Vector3.UP)
	var bolt: DroneBoltPool.Bolt = pool.live_bolts()[0]
	assert_eq(bolt.collision_layer, CombatLayers.ENEMY_PROJECTILE)
	assert_eq(bolt.collision_layer, 16)
	assert_eq(bolt.collision_mask, CombatLayers.WORLD | CombatLayers.PLAYER)
	assert_eq(bolt.collision_mask, 3)


# --- Drone body -------------------------------------------------------------------------------------------------


func test_a_drone_is_a_45_hp_target_with_a_0_6_m_hurtbox_on_layer_3() -> void:
	var drone: Drone = _drone()
	assert_eq(drone.health.max_hp, 45.0)
	assert_eq(drone.hurtbox.collision_layer, CombatLayers.ENEMY)
	assert_eq(drone.hurtbox.collision_layer, 4)
	var shape: SphereShape3D = (drone.hurtbox.get_node("Shape") as CollisionShape3D).shape as SphereShape3D
	assert_almost_eq(shape.radius, 0.6, 0.0001)


func test_three_pulses_kill_a_drone_once_and_the_wreck_takes_no_more_hits() -> void:
	_floor()
	var drone: Drone = _drone()
	drone.place(Vector3.ZERO, 4.0)
	var deaths: Array = []
	drone.died.connect(func(_d: Drone, at: Vector3) -> void: deaths.append(at))
	for i in 3:
		assert_true(drone.hurtbox.take_hit(15.0, null, Vector3.ZERO))
	assert_true(drone.is_dead())
	assert_eq(deaths.size(), 1, "one death signal")
	assert_eq(deaths[0], Vector3(0.0, 4.0, 0.0), "with the place it died")
	assert_eq(drone.hurtbox.collision_layer, 0, "shots and the aim ray pass through a wreck")
	assert_false(drone.hurtbox.take_hit(15.0, null, Vector3.ZERO))
	assert_eq(deaths.size(), 1)


func test_the_ink_rim_is_unshaded_ink_and_never_glows() -> void:
	_floor()
	var drone: Drone = _drone()
	drone.place(Vector3.ZERO, 4.0)
	var rim: MeshInstance3D = drone.get_node("Body/Rim") as MeshInstance3D
	var material: StandardMaterial3D = rim.material_override as StandardMaterial3D
	assert_eq(material.albedo_color, Color("14161A"))
	assert_eq(material.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED)
	assert_false(material.emission_enabled)
	var torus: TorusMesh = rim.mesh as TorusMesh
	assert_almost_eq(torus.inner_radius, 0.34, 0.0001)
	assert_almost_eq(torus.outer_radius, 0.66, 0.0001)
	# Full glow and a white flash: the ring changes, the rim does not.
	drone.ai_enabled = false
	drone.brain.state = DroneBrain.State.WIND_UP
	drone.brain.state_t = DroneBrain.WIND_UP_S
	drone.step(TICK)
	var ring_material: StandardMaterial3D = (drone.get_node("Body/Ring") as MeshInstance3D).material_override
	assert_almost_eq(ring_material.emission_energy_multiplier, Drone.GLOW_MAX, 0.0001)
	drone.hurtbox.take_hit(15.0, null, Vector3.ZERO)
	assert_eq(ring_material.albedo_color, Color.WHITE)
	assert_eq(material.albedo_color, Color("14161A"))
	assert_false(material.emission_enabled)


func test_a_hit_flashes_the_drone_white_for_0_06_s() -> void:
	_floor()
	var drone: Drone = _drone()
	drone.place(Vector3.ZERO, 4.0)
	drone.ai_enabled = false
	drone.hurtbox.take_hit(15.0, null, Vector3.ZERO)
	assert_eq(drone.flash_left_s, Drone.FLASH_S)
	var material: StandardMaterial3D = (drone.get_node("Body/Ring") as MeshInstance3D).material_override
	assert_eq(material.albedo_color, Color.WHITE)
	var ticks: int = 0
	while drone.flash_left_s > 0.0:
		drone.step(TICK)
		ticks += 1
	assert_eq(ticks, 4, "0.06 s is 4 ticks")
	assert_ne(material.albedo_color, Color.WHITE)


func test_a_dead_drone_falls_lands_and_drops_3_to_8_scrap_from_its_seed() -> void:
	_floor()
	await wait_physics_frames(2)
	var totals: Array[int] = []
	for run in 2:
		var drone: Drone = _drone(1234)
		drone.drop_parent = self
		drone.place(Vector3(run * 20.0, 0.0, 0.0), 5.0)
		var start_y: float = drone.global_position.y
		drone.hurtbox.take_hit(45.0, null, Vector3.ZERO)
		var ticks: int = 0
		while not drone.landed and ticks < 600:
			drone.step(TICK)
			ticks += 1
		assert_true(drone.landed, "it fell to the ground")
		assert_lt(drone.global_position.y, start_y)
		assert_gte(drone.scrap_dropped_total, 3)
		assert_lte(drone.scrap_dropped_total, 8)
		totals.append(drone.scrap_dropped_total)
	assert_eq(totals[0], totals[1], "the same seed drops the same amount")
	var pieces: int = 0
	for child in get_children():
		if child is LooseScrap:
			pieces += 1
			assert_eq((child as LooseScrap).site_name, "", "loose scrap has no node name")
			assert_eq((child as LooseScrap).amount, 1)
	assert_eq(pieces, totals[0] + totals[1], "one pickup per scrap")


func test_configure_rolls_hover_3_to_6_orbit_12_to_18_and_the_drop_varies_between_seeds() -> void:
	var drops: Dictionary = {}
	for seed_value in 40:
		var drone: Drone = _drone(seed_value)
		assert_between(drone.hover_m, 3.0, 6.0)
		assert_between(drone.orbit_radius_m, 12.0, 18.0)
		# The next number the drone's own generator gives is the amount it drops when it dies.
		var count: int = drone.rng.randi_range(Drone.SCRAP_MIN, Drone.SCRAP_MAX)
		drops[count] = true
		assert_between(count, 3, 8)
	assert_gte(drops.size(), 4, "the amount varies")


func test_the_bolt_aims_at_the_chassis_position_at_fire_time_with_no_lead() -> void:
	_floor()
	var pool: DroneBoltPool = _pool()
	var walker: Node3D = _walker(Vector3(0.0, 1.0, 15.0))
	var chassis: Node3D = walker.get_node("Chassis")
	await wait_physics_frames(2)
	var drone: Drone = _drone()
	drone.target = walker
	drone.bolts = pool
	drone.place(Vector3.ZERO, 4.0)
	drone.engage_now()
	drone.schedule_wind_up(0.0)
	var shot: Array = []
	drone.shot_fired.connect(
		func(_d: Drone, origin: Vector3, direction: Vector3) -> void:
			shot.append(origin)
			shot.append(direction)
	)
	var ticks: int = 0
	while shot.is_empty() and ticks < 100:
		# The walker strafes 3 m/s through the wind-up: the bolt must go where it is at the moment of the shot.
		chassis.global_position += Vector3(3.0 * TICK, 0.0, 0.0)
		drone.step(TICK)
		ticks += 1
	assert_false(shot.is_empty(), "the drone fired")
	var expected: Vector3 = (chassis.global_position - (shot[0] as Vector3)).normalized()
	assert_lt(rad_to_deg((shot[1] as Vector3).angle_to(expected)), 0.01, "aimed at the chassis now")
	var at_wind_up_start: Vector3 = Vector3(0.0, 1.0, 15.0) + Vector3(3.0 * TICK, 0.0, 0.0)
	var old_aim: Vector3 = (at_wind_up_start - (shot[0] as Vector3)).normalized()
	assert_gt(rad_to_deg((shot[1] as Vector3).angle_to(old_aim)), 1.0, "and not where it was at the wind-up start")


func test_neither_a_hit_nor_a_kill_during_the_wind_up_cancels_the_shot() -> void:
	_floor()
	var pool: DroneBoltPool = _pool()
	var walker: Node3D = _walker(Vector3(0.0, 1.0, 15.0))
	await wait_physics_frames(2)
	var wounded: Drone = _drone()
	var killed: Drone = _drone()
	for drone: Drone in [wounded, killed]:
		drone.target = walker
		drone.bolts = pool
		drone.place(Vector3(-8.0 if drone == wounded else 8.0, 0.0, 0.0), 4.0)
		drone.engage_now()
		drone.schedule_wind_up(0.0)
	for tick in 60:
		wounded.step(TICK)
		killed.step(TICK)
		if wounded.brain.state == DroneBrain.State.WIND_UP and wounded.brain.state_t > 0.3 and wounded.health.hp == 45.0:
			wounded.hurtbox.take_hit(15.0, null, Vector3.ZERO)
			wounded.hurtbox.take_hit(15.0, null, Vector3.ZERO)
		if killed.brain.state == DroneBrain.State.WIND_UP and killed.brain.state_t > 0.3 and not killed.is_dead():
			killed.hurtbox.take_hit(45.0, null, Vector3.ZERO)
	assert_eq(wounded.health.hp, 15.0)
	assert_eq(wounded.shots_fired, 1, "two hits in the wind-up, the shot still left")
	assert_eq(killed.shots_fired, 1, "a drone always fires: killed 0.3 s in, its bolt still left at 0.6 s")
	assert_true(killed.is_dead())
	assert_eq(pool.spawned_count, 2)


func test_the_drone_holds_still_through_the_wind_up_the_shot_and_the_recovery() -> void:
	_floor()
	var pool: DroneBoltPool = _pool()
	var walker: Node3D = _walker(Vector3(0.0, 1.0, 15.0))
	await wait_physics_frames(2)
	var drone: Drone = _drone()
	drone.target = walker
	drone.bolts = pool
	drone.orbit_radius_m = 15.0
	drone.place(Vector3.ZERO, 4.0)
	drone.engage_now()
	drone.schedule_wind_up(1.0)
	var start_tick: int = -1
	var low: Vector3 = Vector3.INF
	var high: Vector3 = -Vector3.INF
	var worst_speed: float = 0.0
	var top_speed: float = 0.0
	var ticks_in_hold: int = 0
	for tick in 240:
		drone.step(TICK)
		if drone.brain.wind_up_began:
			start_tick = tick
		if start_tick < 0:
			top_speed = maxf(top_speed, drone.velocity.length())
		elif tick - start_tick >= 54:
			break
		elif tick - start_tick >= 6:
			ticks_in_hold += 1
			worst_speed = maxf(worst_speed, drone.velocity.length())
			low = low.min(drone.get_node("Body").global_position)
			high = high.max(drone.get_node("Body").global_position)
	assert_gte(start_tick, 0)
	assert_eq(ticks_in_hold, 48)
	assert_lte(worst_speed, 0.05, "speed in the hold")
	assert_lte((high - low).length(), 0.1, "hover bob and drift together stay within 0.1 m")
	assert_lte(top_speed, 6.0 + 0.001, "orbit speed")
	assert_gt(top_speed, 5.9, "it does orbit at about 6 m/s")


func test_an_orbiting_drone_keeps_its_radius_and_never_exceeds_6_m_per_s() -> void:
	_floor()
	var walker: Node3D = _walker(Vector3(0.0, 1.0, 0.0))
	await wait_physics_frames(2)
	var drone: Drone = _drone()
	drone.target = walker
	drone.orbit_radius_m = 15.0
	drone.orbit_sign = 1
	drone.place(Vector3(0.0, 0.0, -25.0), 4.0)
	var radius_min: float = INF
	var radius_max: float = 0.0
	var speed_max: float = 0.0
	var height_min: float = INF
	var height_max: float = 0.0
	for tick in 900:
		drone.step(TICK)
		speed_max = maxf(speed_max, drone.velocity.length())
		if tick > 300:
			var to: Vector3 = drone.global_position - walker.get_node("Chassis").global_position
			var flat: float = Vector2(to.x, to.z).length()
			radius_min = minf(radius_min, flat)
			radius_max = maxf(radius_max, flat)
			height_min = minf(height_min, drone.global_position.y)
			height_max = maxf(height_max, drone.global_position.y)
	assert_eq(drone.state_name(), "STRAFE")
	assert_gte(radius_min, 12.0)
	assert_lte(radius_max, 18.0)
	assert_almost_eq(radius_min, 15.0, 0.5)
	assert_lte(speed_max, 6.0 + 0.001)
	assert_gte(height_min, 3.0, "hovers 3-6 m above the ground")
	assert_lte(height_max, 6.0)


func test_the_leash_sends_the_drone_home_and_it_goes_idle_there() -> void:
	_floor()
	var walker: Node3D = _walker(Vector3(20.0, 1.0, 0.0))
	await wait_physics_frames(2)
	var drone: Drone = _drone()
	drone.target = walker
	drone.place(Vector3.ZERO, 4.0)
	var home: Vector3 = drone.home
	var states: Array[String] = []
	drone.state_changed.connect(
		func(_d: Drone, _from: DroneBrain.State, to_state: DroneBrain.State) -> void:
			states.append(DroneBrain.state_name(to_state))
	)
	for tick in 240:
		drone.step(TICK)
	assert_true(DroneBrain.is_engaged(drone.brain.state), "it noticed the walker 20 m away")
	assert_gt(drone.global_position.distance_to(home), 1.0, "and left its site")
	walker.get_node("Chassis").global_position = Vector3(0.0, 1.0, 70.0)
	for tick in 60:
		# A shot in progress finishes first (at most 54 ticks), then the leash takes the drone home.
		drone.step(TICK)
		if drone.state_name() == "PATROL":
			break
	assert_eq(drone.state_name(), "PATROL", "the walker is 70 m from the spawn: sent home")
	for tick in 1200:
		drone.step(TICK)
		if drone.brain.state == DroneBrain.State.IDLE_HOVER and drone.global_position.distance_to(home) < 0.05:
			break
	assert_eq(drone.state_name(), "IDLE_HOVER")
	assert_lt(drone.global_position.distance_to(home), 0.05, "back at its hover point")
	assert_true("PATROL" in states)


func test_a_drone_does_not_see_a_walker_behind_a_wall() -> void:
	_floor()
	var wall := StaticBody3D.new()
	wall.collision_layer = CombatLayers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 30.0, 30.0)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(10.0, 5.0, 0.0)
	add_child_autofree(wall)
	var walker: Node3D = _walker(Vector3(20.0, 1.0, 0.0))
	await wait_physics_frames(2)
	var drone: Drone = _drone()
	drone.target = walker
	drone.place(Vector3.ZERO, 4.0)
	for tick in 120:
		drone.step(TICK)
	assert_eq(drone.state_name(), "IDLE_HOVER", "20 m away but behind the wall")


func test_a_provoked_drone_that_gave_up_goes_home_and_stays_there_while_the_walker_is_unseen() -> void:
	_floor()
	# 55 m away: inside the 60 m leash, outside the 35 m sight, and still out of sight after 3 s of closing in.
	var walker: Node3D = _walker(Vector3(0.0, 1.0, 55.0))
	await wait_physics_frames(2)
	var drone: Drone = _drone()
	drone.target = walker
	drone.place(Vector3.ZERO, 4.0)
	var entered: Array[String] = []
	drone.state_changed.connect(
		func(_d: Drone, _from: DroneBrain.State, to_state: DroneBrain.State) -> void:
			entered.append(DroneBrain.state_name(to_state))
	)
	drone.hurtbox.take_hit(15.0, null, Vector3.ZERO)
	for tick in 700:
		drone.step(TICK)
	assert_eq(entered.count("ALERT"), 1, "provoked once, and it did not turn round again")
	assert_true("PATROL" in entered, "it gave up after 3 s without sight")
	assert_eq(drone.state_name(), "IDLE_HOVER", "and went home")
	assert_lt(drone.global_position.distance_to(drone.home), 0.05)


func test_a_bolt_whose_drone_was_freed_still_lands_and_passes_no_source() -> void:
	var pool: DroneBoltPool = _pool()
	_hits = 0
	_last_hit_source = Node.new()
	add_child_autofree(_last_hit_source)
	var drone: Drone = load("res://scenes/enemies/drone.tscn").instantiate()
	drone.auto_step = false
	add_child(drone)
	_hurtbox_at(Vector3(10.0, 1.0, 0.0), CombatLayers.PLAYER)
	await wait_physics_frames(2)
	assert_true(pool.fire(Vector3(0.0, 1.0, 0.0), Vector3.RIGHT, drone))
	drone.free()
	for i in 40:
		pool.step(TICK)
	assert_eq(_hits, 1, "the bolt of a freed drone still hurts")
	assert_null(_last_hit_source, "the freed drone is passed as null")
	assert_eq(pool.live, 0)
	_last_hit_source = null


func test_a_retired_bolt_forgets_its_drone() -> void:
	var pool: DroneBoltPool = _pool()
	var drone: Drone = load("res://scenes/enemies/drone.tscn").instantiate()
	drone.auto_step = false
	add_child_autofree(drone)
	pool.fire(Vector3(0.0, 50.0, 0.0), Vector3.UP, drone)
	var bolt: DroneBoltPool.Bolt = pool.live_bolts()[0]
	assert_eq(bolt.source, drone)
	pool.clear()
	assert_null(bolt.source)


func test_respawn_all_stops_an_old_drone_that_was_due_to_fire_this_tick() -> void:
	_floor()
	var walker: Node3D = _walker(Vector3(0.0, 1.0, 15.0))
	await wait_physics_frames(2)
	var field: DroneField = _field_with_sites(walker)
	field.add_encounter(Vector3.ZERO, 1, 1)
	var old: Drone = field.encounters[0].drones[0]
	old.engage_now()
	old.brain.state = DroneBrain.State.WIND_UP
	old.brain.state_t = 0.59
	# The signal of a bank arrives in the middle of the tick; the old drone, not yet freed, still gets its turn.
	field.respawn_all()
	old.step(TICK)
	assert_eq(old.shots_fired, 0, "the old drone did not fire")
	assert_eq(field.bolts.live, 0, "and no bolt is in the air")
	assert_eq(field.alive_count(), 1, "the new drone is there")


func test_a_dead_drone_frees_its_slot_so_the_waiting_fifth_engages() -> void:
	_floor()
	var walker: Node3D = _walker(Vector3(0.0, 1.0, 0.0))
	await wait_physics_frames(2)
	var field: DroneField = _field_with_sites(walker)
	var encounter: DroneEncounter = field.add_encounter(Vector3(0.0, 0.0, -25.0), 5, 5)
	await wait_physics_frames(60)
	assert_eq(field.active_count(), 4)
	var waiting: Drone = null
	var victim: Drone = null
	for drone in encounter.drones:
		if drone.state_name() == "IDLE_HOVER":
			waiting = drone
		elif victim == null:
			victim = drone
	assert_not_null(waiting, "one drone waits at home")
	victim.hurtbox.take_hit(45.0, null, Vector3.ZERO)
	assert_eq(field.active_count(), 3, "the dead drone gave its slot back")
	await wait_physics_frames(5)
	assert_true(DroneBrain.is_engaged(waiting.brain.state), "and the waiting drone took it")
	assert_eq(field.active_count(), 4)


func test_respawn_all_mid_fight_clears_the_bolts_and_resets_the_drones() -> void:
	_floor()
	var walker: Node3D = _walker(Vector3(0.0, 1.0, 0.0))
	await wait_physics_frames(2)
	var field: DroneField = _field_with_sites(walker)
	var encounter: DroneEncounter = field.add_encounter(Vector3(0.0, 0.0, -20.0), 3, 3)
	var waited: int = 0
	while field.bolts.live == 0 and waited < 500:
		await wait_physics_frames(1)
		waited += 1
	assert_gt(field.bolts.live, 0, "the fight is on, with a bolt in the air")
	encounter.drones[0].hurtbox.take_hit(15.0, null, Vector3.ZERO)
	field.respawn_all()
	assert_eq(field.bolts.live, 0, "the bolts are gone")
	assert_eq(field.active_count(), 0, "no drone holds a slot")
	assert_eq(field.alive_count(), 3)
	for drone in encounter.drones:
		assert_eq(drone.health.hp, 45.0)
		assert_eq(drone.state_name(), "IDLE_HOVER")
	await wait_physics_frames(5)
	assert_eq(field.bolts.live, 0, "and no old drone fired after the respawn")


# --- Field ------------------------------------------------------------------------------------------------------


func _field_with_sites(walker: Node3D) -> DroneField:
	var field := DroneField.new()
	field.target = walker
	add_child_autofree(field)
	return field


func _site(at: Vector3, min_drones: int, max_drones: int) -> DroneSite:
	var site := DroneSite.new()
	site.min_drones = min_drones
	site.max_drones = max_drones
	add_child_autofree(site)
	site.global_position = at
	return site


func test_the_field_spawns_min_to_max_drones_at_every_drone_site_hovering_3_to_6_m_up() -> void:
	_floor()
	var walker: Node3D = _walker(Vector3(0.0, 1.0, 150.0))
	_site(Vector3(0.0, 0.2, -50.0), 1, 2)
	_site(Vector3(80.0, 0.2, -50.0), 2, 3)
	_site(Vector3(-80.0, 0.2, -50.0), 1, 1)
	await wait_physics_frames(2)
	var field: DroneField = _field_with_sites(walker)
	field.spawn_sites()
	assert_eq(field.encounters.size(), 3)
	var counts: Array[int] = []
	for encounter in field.encounters:
		counts.append(encounter.drones.size())
	assert_between(counts[0], 1, 2)
	assert_between(counts[1], 2, 3)
	assert_eq(counts[2], 1)
	for encounter in field.encounters:
		for drone in encounter.drones:
			assert_between(drone.global_position.y, 3.0, 6.0, "hover height above the ground")
			assert_eq(drone.home, drone.global_position)
			assert_eq(drone.target, walker)
	assert_eq(field.drone_count(), counts[0] + counts[1] + counts[2])


func test_respawn_all_brings_every_drone_back_with_full_health_and_signals_each_death_with_its_position() -> void:
	_floor()
	var walker: Node3D = _walker(Vector3(0.0, 1.0, 150.0))
	_site(Vector3(0.0, 0.2, -50.0), 2, 2)
	await wait_physics_frames(2)
	var field: DroneField = _field_with_sites(walker)
	field.spawn_sites()
	var deaths: Array[Vector3] = []
	field.drone_died.connect(func(at: Vector3) -> void: deaths.append(at))
	var victim: Drone = field.encounters[0].drones[0]
	var spot: Vector3 = victim.global_position
	victim.hurtbox.take_hit(45.0, null, Vector3.ZERO)
	assert_eq(deaths.size(), 1)
	assert_eq(deaths[0], spot)
	assert_eq(field.alive_count(), 1)
	field.respawn_all()
	await wait_physics_frames(2)
	assert_eq(field.alive_count(), 2, "both drones are back")
	for drone in field.encounters[0].drones:
		assert_eq(drone.health.hp, 45.0)
		assert_eq(drone.state_name(), "IDLE_HOVER")
	assert_eq(deaths.size(), 1, "respawning is not a death")


func test_five_drones_that_all_see_the_walker_leave_only_four_active() -> void:
	_floor()
	var walker: Node3D = _walker(Vector3(0.0, 1.0, 0.0))
	await wait_physics_frames(2)
	var field: DroneField = _field_with_sites(walker)
	field.add_encounter(Vector3(0.0, 0.0, -25.0), 5, 5)
	var most: int = 0
	for i in 120:
		await wait_physics_frames(1)
		most = maxi(most, field.active_count())
	assert_eq(most, 4, "never more than 4 active")
	var idle: int = 0
	for drone in field.encounters[0].drones:
		if drone.state_name() == "IDLE_HOVER":
			idle += 1
	assert_eq(idle, 1, "the fifth waits at home")
