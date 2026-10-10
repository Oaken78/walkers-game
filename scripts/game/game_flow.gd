class_name GameFlow
extends RefCounted
## The game loop as a state machine (GDD 3, 7, 12): Workshop -> Field -> (Collapsing) -> Fading out -> Workshop.
## Pure logic, no nodes: Main owns the scene work and listens to the signals; this class owns who may do what when,
## the timers (collapse, fade) and the ledger calls of a return home (Economy.die / recall / bank).
##
## Every return home is a workshop visit and ends in `Economy.bank()`, also for 0 carried scrap: the `banked` signal
## repairs the walker, respawns the drones and refills ring 1-2 nodes (Klas, 2026-10-10).
##   enter (F within 4 m):  bank
##   death (HP 0):          collapse 1.0 s, fade 0.5 s, die(position) then bank (the carried scrap is now the cache)
##   recall (hold F 3 s):   fade 0.5 s, recall(position) then bank, no collapse

## Why the player goes home.
enum Kind { ENTER, DEATH, RECALL }
enum State { WORKSHOP, FIELD, COLLAPSING, FADING_OUT }

const ENTER_RANGE_M: float = 4.0
const COLLAPSE_S: float = 1.0
const FADE_OUT_S: float = 0.5
const FADE_IN_S: float = 0.5
## Float slack for sums of 1/60 s ticks.
const TIME_EPSILON: float = 0.00001

## The collapse starts (Main calls WalkerBody.collapse and turns input, collector and hurtbox off).
signal collapse_started
## The screen starts to go dark (the collapse is over, or a recall or enter began).
signal fade_out_started(kind: Kind)
## The screen is black and the ledger has been settled: Main swaps to the workshop now. `kind` is why, `cache_amount`
## the wreck cache that now lies in the field (0 when none).
signal arrived_home(kind: Kind, cache_amount: int, cache_position: Vector3)
## The player left the workshop for the field: Main swaps to the field now.
signal field_started

var state: State = State.WORKSHOP
var economy: Economy
## Why the current trip home started (valid in COLLAPSING and FADING_OUT).
var kind: Kind = Kind.ENTER

var _timer: float = 0.0
var _fade_in_left: float = 0.0
var _drop_position: Vector3 = Vector3.ZERO


func _init(ledger: Economy = null) -> void:
	economy = ledger if ledger != null else Economy.new()


## 0 clear .. 1 black: up during FADING_OUT, down for FADE_IN_S after the screen went black.
func fade_alpha() -> float:
	if state == State.FADING_OUT:
		return clampf(_timer / FADE_OUT_S, 0.0, 1.0)
	return clampf(_fade_in_left / FADE_IN_S, 0.0, 1.0)


## True while a trip home is under way: no other transition is accepted.
func is_busy() -> bool:
	return state == State.COLLAPSING or state == State.FADING_OUT


## Tab on a valid build in the workshop. False while the build is invalid or when not in the workshop.
func request_exit(build_valid: bool) -> bool:
	if state != State.WORKSHOP or not build_valid:
		return false
	state = State.FIELD
	_fade_in_left = FADE_IN_S
	field_started.emit()
	return true


## F tapped in the field: the bench is `distance_m` away. Banks and visits the workshop when within ENTER_RANGE_M.
func request_enter(distance_m: float) -> bool:
	if state != State.FIELD or distance_m > ENTER_RANGE_M:
		return false
	_start_fade(Kind.ENTER, Vector3.ZERO)
	return true


## F held 3 s in the field: recall to the workshop, carried scrap drops where the walker stood.
func request_recall(position: Vector3) -> bool:
	if state != State.FIELD:
		return false
	_start_fade(Kind.RECALL, position)
	return true


## HP reached 0 in the field. Ignored unless the walker is alive in the field (a dying walker dies once).
func request_death(position: Vector3) -> bool:
	if state != State.FIELD:
		return false
	kind = Kind.DEATH
	_drop_position = position
	state = State.COLLAPSING
	_timer = 0.0
	collapse_started.emit()
	return true


## Advances the collapse and fade timers by one tick.
func tick(delta: float) -> void:
	match state:
		State.COLLAPSING:
			_timer += delta
			if _timer >= COLLAPSE_S - TIME_EPSILON:
				_start_fade(Kind.DEATH, _drop_position)
		State.FADING_OUT:
			_timer += delta
			if _timer >= FADE_OUT_S - TIME_EPSILON:
				_arrive()
		_:
			_fade_in_left = maxf(_fade_in_left - delta, 0.0)


func _start_fade(why: Kind, position: Vector3) -> void:
	kind = why
	_drop_position = position
	state = State.FADING_OUT
	_timer = 0.0
	fade_out_started.emit(why)


func _arrive() -> void:
	match kind:
		Kind.DEATH:
			economy.die(_drop_position)
		Kind.RECALL:
			economy.recall(_drop_position)
	# Also for 0 carried scrap: the bank is what repairs and refills.
	economy.bank()
	state = State.WORKSHOP
	_timer = 0.0
	_fade_in_left = FADE_IN_S
	arrived_home.emit(kind, economy.cache_amount, economy.cache_position)
