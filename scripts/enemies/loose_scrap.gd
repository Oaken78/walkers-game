class_name LooseScrap
extends ScrapPickup
## One piece of scrap dropped by a dead drone (GDD 8.4, 8.5): a ScrapPickup with an empty node name, so the ledger
## adds it with `Economy.collect_loose` and never marks a node depleted. It is not tied to a ScrapSite: it stays where
## it lay if a pull is cancelled, and frees itself once delivered.

const SCALE: float = 0.6
const BEAM_HEIGHT_M: float = 1.6


## Lays `scrap` units of scrap at `at`. Call after adding it to the tree.
func place(at: Vector3, scrap: int) -> void:
	top_level = true
	site_name = ""
	amount = scrap
	scale = Vector3.ONE * SCALE
	global_position = at
	_beam.scale = Vector3(1.0, BEAM_HEIGHT_M, 1.0)
	_beam.position = Vector3(0.0, BEAM_HEIGHT_M * 0.5, 0.0)


func _deliver(economy: Economy) -> void:
	economy.collect_loose(amount)
	visible = false
	set_deferred("monitorable", false)
	queue_free()


func _on_cancelled() -> void:
	# Pickup.cancel() already put it back where it lay; there is no site to go home to.
	pass
