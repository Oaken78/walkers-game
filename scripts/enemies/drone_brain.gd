class_name DroneBrain
extends RefCounted
## The drone's mind (GDD 5, 8.4, 16 risk 8), pure data: no nodes, no physics, no randomness. A state is a pure function
## of the senses, the time in the state, the time since the last wind-up and the time without sight (`decide`).
## The body (Drone) reads the senses from the world, calls update() once per physics tick and moves by `speed_factor`.
##
## States: IDLE_HOVER (at home) - PATROL (drifts back home after a leash or lost sight) - ALERT (sees the walker within
## 35 m, closes in) - STRAFE (orbits at 12-18 m) - WIND_UP (0.6 s, glows, holds still) - FIRE (the tick the bolt
## leaves; it never lasts longer than that tick) - RECOVER (0.3 s, holds still) - DEAD.
## The hold: speed falls to 0 within 0.1 s of the wind-up start and stays 0 through the shot and the recovery
## (0.9 s of every 1.5 s cycle), then rises back to orbit speed over 0.3 s. A hit never cancels a shot; only a death does.

enum State { IDLE_HOVER, PATROL, ALERT, STRAFE, WIND_UP, FIRE, RECOVER, DEAD }

const SIGHT_RANGE_M: float = 35.0
## The walker further than this from the drone's spawn point sends it home.
const LEASH_RANGE_M: float = 60.0
const ORBIT_MIN_M: float = 12.0
const ORBIT_MAX_M: float = 18.0
## Orbit speed (risk 8: <= 29 deg/s at 12 m). Every other move uses the same top speed.
const ORBIT_SPEED_MPS: float = 6.0
const SHOT_PERIOD_S: float = 1.5
const WIND_UP_S: float = 0.6
const RECOVER_S: float = 0.3
const BRAKE_S: float = 0.1
const RESUME_S: float = 0.3
## Without sight for this long an engaged drone gives up and goes home.
const LOSE_SIGHT_S: float = 3.0
## PATROL ends this close to the spawn point.
const HOME_ARRIVE_M: float = 1.0
const MAX_STATE_CHAIN: int = 4
const TIMER_EPSILON: float = 0.000001

## What the brain sees this tick. The body fills it from the world; unit tests fill it by hand.
class Senses:
	extends RefCounted
	var hp: float = 45.0
	## Metres from the drone to the walker's chassis, and the horizontal part of it.
	var player_dist: float = INF
	var player_flat_dist: float = INF
	var line_of_sight: bool = false
	## Metres from the walker to the drone's spawn point (horizontal).
	var player_home_dist: float = INF
	## Metres from the drone to its spawn point.
	var home_dist: float = 0.0
	## The drone took damage and the walker is in leash range: it reacts without sight.
	var provoked: bool = false
	## The field has a free engagement slot (at most 4 drones are active at once), or this drone holds one.
	var may_engage: bool = true
	## The encounter allows a wind-up start now (starts are >= 0.4 s apart).
	var may_wind_up: bool = true

	func sees_player() -> bool:
		return line_of_sight and player_dist <= DroneBrain.SIGHT_RANGE_M

var state: State = State.IDLE_HOVER
## Seconds in the current state.
var state_t: float = 0.0
## Seconds since the last wind-up started (or since the drone became alert).
var cycle_t: float = 0.0
var lost_sight_t: float = 0.0
## 0 = holding still, 1 = full speed: brakes to 0 over BRAKE_S, rises over RESUME_S.
var speed_factor: float = 0.0
## True for the one update in which the bolt leaves.
var fired: bool = false
## True for the one update in which a wind-up started.
var wind_up_began: bool = false


## The next state. Pure: the same arguments always give the same answer.
static func decide(
	current: State, in_state_s: float, since_wind_up_s: float, without_sight_s: float, s: Senses
) -> State:
	if current == State.DEAD or s.hp <= 0.0:
		return State.DEAD
	match current:
		State.IDLE_HOVER:
			return State.ALERT if _should_engage(s) else State.IDLE_HOVER
		State.PATROL:
			if _should_engage(s):
				return State.ALERT
			return State.IDLE_HOVER if s.home_dist <= HOME_ARRIVE_M else State.PATROL
		State.ALERT:
			if _gives_up(without_sight_s, s):
				return State.PATROL
			return State.STRAFE if s.player_flat_dist <= ORBIT_MAX_M else State.ALERT
		State.STRAFE:
			if _gives_up(without_sight_s, s):
				return State.PATROL
			var due: bool = since_wind_up_s >= SHOT_PERIOD_S - TIMER_EPSILON
			if due and s.sees_player() and s.may_wind_up:
				return State.WIND_UP
			return State.STRAFE
		State.WIND_UP:
			return State.FIRE if in_state_s >= WIND_UP_S - TIMER_EPSILON else State.WIND_UP
		State.FIRE:
			return State.RECOVER
		State.RECOVER:
			return State.STRAFE if in_state_s >= RECOVER_S - TIMER_EPSILON else State.RECOVER
	return current


## Engaged states take one of the (at most 4) active slots.
static func is_engaged(of: State) -> bool:
	return of == State.ALERT or of == State.STRAFE or is_holding(of)


## WIND_UP, FIRE and RECOVER: the drone holds still.
static func is_holding(of: State) -> bool:
	return of == State.WIND_UP or of == State.FIRE or of == State.RECOVER


## The wind-up glow, 0..1: 0 to 1 over the wind-up, back to 0 over the recovery, 0 elsewhere.
static func glow_level(of: State, in_state_s: float) -> float:
	if of == State.WIND_UP:
		return clampf(in_state_s / WIND_UP_S, 0.0, 1.0)
	if of == State.FIRE:
		return 1.0
	if of == State.RECOVER:
		return clampf(1.0 - in_state_s / RECOVER_S, 0.0, 1.0)
	return 0.0


## The name of a state, for logs and scenarios.
static func state_name(of: State) -> String:
	return State.keys()[of]


## One physics tick. Moves through as many states as the senses call for (a wind-up that ends passes through FIRE to
## RECOVER in the same update; `fired` marks that tick).
func update(delta: float, s: Senses) -> void:
	fired = false
	wind_up_began = false
	if state == State.DEAD:
		return
	state_t += delta
	cycle_t += delta
	lost_sight_t = 0.0 if s.sees_player() else lost_sight_t + delta
	for i in MAX_STATE_CHAIN:
		var next: State = decide(state, state_t, cycle_t, lost_sight_t, s)
		if next == state:
			break
		_enter(next)
	_update_speed(delta)


## Dead at once (a hit took the last hit point). A shot that has not left is lost.
func kill() -> void:
	_enter(State.DEAD)
	speed_factor = 0.0


func _enter(next: State) -> void:
	state = next
	state_t = 0.0
	match next:
		State.ALERT:
			cycle_t = 0.0
			lost_sight_t = 0.0
		State.WIND_UP:
			cycle_t = 0.0
			wind_up_began = true
		State.FIRE:
			fired = true
		State.DEAD:
			speed_factor = 0.0


func _update_speed(delta: float) -> void:
	match state:
		State.IDLE_HOVER, State.WIND_UP, State.FIRE, State.RECOVER, State.DEAD:
			speed_factor = move_toward(speed_factor, 0.0, delta / BRAKE_S)
		_:
			speed_factor = move_toward(speed_factor, 1.0, delta / RESUME_S)


static func _should_engage(s: Senses) -> bool:
	var aware: bool = s.sees_player() or s.provoked
	return aware and s.player_home_dist <= LEASH_RANGE_M and s.may_engage


static func _gives_up(without_sight_s: float, s: Senses) -> bool:
	return s.player_home_dist > LEASH_RANGE_M or without_sight_s >= LOSE_SIGHT_S - TIMER_EPSILON
