class_name Pickup
extends Area3D
## Base of everything the Collector picks up (physics layer 6). Idle pickups do no per-tick work: after a claim the
## pickup flies to the collector's chassis for `magnet_time` seconds and then delivers to the economy, once.

## Emitted on arrival, after the delivery.
signal arrived(pickup: Pickup)

## Seconds of magnet pull (GDD 5: 0.3).
@export var magnet_time: float = 0.3

## The Collector that claimed this pickup (null while idle).
var claimer: Node = null

var _from: Vector3 = Vector3.ZERO
var _elapsed: float = 0.0
var _flying: bool = false
var _done: bool = false


func _ready() -> void:
	collision_layer = 32
	collision_mask = 0
	monitoring = false
	set_physics_process(false)


## True when a collector may claim it now.
func is_collectable() -> bool:
	return not _flying and not _done and _can_collect()


## First caller wins. Returns false for a pickup that is already claimed, spent or inert.
func claim(by: Node) -> bool:
	if not is_collectable():
		return false
	claimer = by
	_flying = true
	_elapsed = 0.0
	_from = global_position
	set_physics_process(true)
	return true


func is_flying() -> bool:
	return _flying


func _physics_process(delta: float) -> void:
	_elapsed += delta
	var k: float = clampf(_elapsed / magnet_time, 0.0, 1.0)
	var goal: Vector3 = _from
	if is_instance_valid(claimer) and claimer.has_method("pull_target"):
		goal = claimer.call("pull_target")
	global_position = _from.lerp(goal, k * k)
	if _elapsed >= magnet_time - 0.000001:
		_flying = false
		set_physics_process(false)
		var economy: Economy = null
		if is_instance_valid(claimer):
			economy = claimer.get("economy")
		_done = true
		_deliver(economy)
		arrived.emit(self)


## Subclass hook: may this be picked up at all (not depleted).
func _can_collect() -> bool:
	return true


## Subclass hook: hand the contents to the economy. `_done` is true while this runs.
func _deliver(_economy: Economy) -> void:
	pass
