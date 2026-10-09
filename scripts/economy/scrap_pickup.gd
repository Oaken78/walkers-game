class_name ScrapPickup
extends Pickup
## One scrap node at a ScrapSite. Depleted means hidden and inert; bank restores it when the site respawns.

@export var beam_height: float = 3.5
@export var pocket_beam_height: float = 10.0

var site_name: String = ""
var amount: int = 0
var in_pocket: bool = false
var ring: int = 0
var depleted: bool = false

var _home: Vector3 = Vector3.ZERO

@onready var _beam: MeshInstance3D = $Beam


## Call after adding to the tree; places the node at the site.
func setup(site: ScrapSite) -> void:
	site_name = String(site.name)
	amount = site.amount
	in_pocket = site.in_pocket
	ring = site.ring
	_home = site.global_position
	global_position = _home
	var h: float = pocket_beam_height if in_pocket else beam_height
	_beam.scale = Vector3(1.0, h, 1.0)
	_beam.position = Vector3(0.0, h * 0.5, 0.0)


## The pickup returns to its site, visible and collectable again.
func restore() -> void:
	depleted = false
	_done = false
	global_position = _home
	visible = true
	monitorable = true


func _deplete() -> void:
	depleted = true
	visible = false
	monitorable = false
	global_position = _home


func _can_collect() -> bool:
	return not depleted


func _deliver(economy: Economy) -> void:
	# Whether or not the ledger took it, the node is spent: never count one node twice.
	if economy != null:
		economy.pick_up(site_name, amount)
	_deplete()
