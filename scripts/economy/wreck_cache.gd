class_name WreckCache
extends Pickup
## The wreck cache: the scrap you carried when you died or recalled, lying where you stood. Reclaimed once.

@onready var _label: Label3D = $Amount


func show_amount(amount: int) -> void:
	_label.text = str(amount)


func _deliver(economy: Economy) -> void:
	if economy != null:
		economy.reclaim()
	visible = false
	monitorable = false
	queue_free()
