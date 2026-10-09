class_name WreckCache
extends Pickup
## The wreck cache: the scrap you carried when you died or recalled, lying where you stood. Reclaimed once.

## Which cache of the ledger this is (Economy.cache_id). A stale pickup can never reclaim a newer cache.
var cache_id: int = 0

@onready var _label: Label3D = $Amount


func show_amount(amount: int) -> void:
	_label.text = str(amount)


func _deliver(economy: Economy) -> void:
	economy.reclaim(cache_id)
	visible = false
	set_deferred("monitorable", false)
	queue_free()
