class_name RecallHold
extends Node
## Hold `interact` for 3 s anywhere to recall (GDD 6). A tap shorter than 0.3 s is not a hold: a tap near the bench
## enters the workshop (T09/T12 listen to `tapped`). Progress for the HUD ring is 0..1.

## The hold ran the full time; `position` is where the target stood.
signal recall_requested(position: Vector3)
## Released before the 0.3 s hold threshold.
signal tapped
## Released after 0.3 s but before the recall fired.
signal cancelled

## Float slack for sums of 1/60 s ticks at the 0.3 s and 3.0 s boundaries.
const TIME_EPSILON: float = 0.00001

@export var hold_time: float = 3.0
@export var tap_time: float = 0.3
## Read the `interact` action every physics tick. Turn off to drive step() by hand.
@export var read_input: bool = true
## Whose position a recall reports (the walker).
@export var target: Node3D

var _held: float = 0.0
var _down: bool = false
var _fired: bool = false


## 0 until the hold threshold, then 0..1 up to the recall.
var progress: float:
	get:
		if not _down or _fired or _held < tap_time - TIME_EPSILON:
			return 0.0
		return clampf(_held / hold_time, 0.0, 1.0)

## True once past the tap threshold while held and not yet fired.
var holding: bool:
	get:
		return _down and not _fired and _held >= tap_time - TIME_EPSILON


func _physics_process(delta: float) -> void:
	if read_input:
		step(Input.is_action_pressed(&"interact"), delta)


## A pause (or resume) drops the hold without a signal: a key released while paused must not count, and a key still
## down on resume starts a fresh hold.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_UNPAUSED:
		reset()


## Forgets a hold in progress, silently.
func reset() -> void:
	_down = false
	_held = 0.0
	_fired = false


## One tick of the hold logic.
func step(pressed: bool, delta: float) -> void:
	if pressed:
		if not _down:
			_down = true
			_held = 0.0
			_fired = false
		_held += delta
		if not _fired and _held >= hold_time - TIME_EPSILON:
			_fired = true
			var where: Vector3 = target.global_position if is_instance_valid(target) else Vector3.ZERO
			recall_requested.emit(where)
	elif _down:
		var was_fired: bool = _fired
		var held: float = _held
		_down = false
		_held = 0.0
		_fired = false
		if not was_fired:
			if held < tap_time - TIME_EPSILON:
				tapped.emit()
			else:
				cancelled.emit()
