class_name ScrapSite
extends Marker3D
## A scrap node location (GDD 8.5). T08 spawns the pickup here; this packet only places the marker.
## Node names are unique across the valley: T08 stores depleted nodes by name.

## Scrap a full node holds.
@export var amount: int = 10
## Distance ring of the site (0: 0-60 m, 1: 60-150 m, 2: 150-250 m from the workshop).
@export var ring: int = 0
## Whether the node refills after the player leaves the area.
@export var respawns: bool = true
## True for the 60-scrap node inside a pocket.
@export var in_pocket: bool = false


func _ready() -> void:
	add_to_group("scrap_sites")
