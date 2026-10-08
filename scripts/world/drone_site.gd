class_name DroneSite
extends Marker3D
## A drone group location (GDD 8.4). T07 spawns and leashes the drones; this packet only places the marker.

## Fewest drones the site holds.
@export var min_drones: int = 1
## Most drones the site holds.
@export var max_drones: int = 2
## Distance ring of the site (0: 0-60 m, 1: 60-150 m, 2: 150-250 m from the workshop).
@export var ring: int = 1


func _ready() -> void:
	add_to_group("drone_sites")
