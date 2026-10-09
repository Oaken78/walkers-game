class_name Health
extends RefCounted
## Hit points of one actor (GDD 5, 8.4): the damage contract shared by the player chassis and the drones.
## `changed` fires on every change of hp or max_hp; `depleted` fires once, on the hit that takes hp to 0
## (and again only after a repair).

signal changed(hp: float, max_hp: float)
signal depleted

var max_hp: float = 100.0
var hp: float = 100.0

var _depleted_sent: bool = false


func _init(max_value: float = 100.0) -> void:
	max_hp = maxf(max_value, 0.0)
	hp = max_hp


func damage(amount: float) -> void:
	if amount <= 0.0 or hp <= 0.0:
		return
	hp = maxf(hp - amount, 0.0)
	changed.emit(hp, max_hp)
	if hp <= 0.0 and not _depleted_sent:
		_depleted_sent = true
		depleted.emit()


func repair_full() -> void:
	if hp == max_hp and not _depleted_sent:
		return
	hp = max_hp
	_depleted_sent = false
	changed.emit(hp, max_hp)


## A new maximum (an armor plate was socketed): hp keeps its share of the maximum.
func set_max_hp(value: float) -> void:
	var share: float = hp / max_hp if max_hp > 0.0 else 1.0
	max_hp = maxf(value, 0.0)
	hp = max_hp * share
	changed.emit(hp, max_hp)


func is_depleted() -> bool:
	return hp <= 0.0
