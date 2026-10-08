class_name Valley
extends Node3D
## The M0 greybox valley (GDD 9.1). Builds terrain, wash path, pocket triggers, boulders, sites and the
## smoke column from ValleyLayout at _ready. Other packets instance valley.tscn and read the markers.

signal built

const MAT_GROUND: Material = preload("res://assets/world/ground.tres")
const MAT_STREAK: Material = preload("res://assets/world/ground_streak.tres")
const MAT_ROCK: Material = preload("res://assets/world/rock_base.tres")
const MAT_FAR: Material = preload("res://assets/world/rock_far.tres")
const MAT_RUINS: Material = preload("res://assets/world/ruins.tres")
const MAT_BOULDER: Material = preload("res://assets/world/boulder.tres")
const MAT_SMOKE: Material = preload("res://assets/world/smoke.tres")

## Smoke column: z of its centre, height, radii (330-370 m out, at least 80 m tall, no collision).
@export var smoke_z: float = 350.0
@export var smoke_height: float = 100.0
@export var smoke_bottom_radius: float = 7.0
@export var smoke_top_radius: float = 13.0
## How far a boulder box is buried below the ground so slopes never show a gap (m).
@export var boulder_buried_depth: float = 0.6
## Markers sit this far above the collision surface (m, must stay under 0.2).
@export var marker_lift: float = 0.05
## Height of the pocket trigger boxes above the pocket floor (m).
@export var pocket_trigger_height: float = 3.0

var terrain: TerrainBuilder = null

@onready var _terrain_mesh: MeshInstance3D = $Terrain/TerrainMesh
@onready var _terrain_shape: CollisionShape3D = $Terrain/TerrainShape
@onready var _boulder_body: StaticBody3D = $Boulders
@onready var _boulder_mesh: MultiMeshInstance3D = $BoulderMesh
@onready var _sites: Node3D = $Sites
@onready var _smoke: MeshInstance3D = $Smoke
@onready var _wash_path: Path3D = %WashPath
@onready var _ledge: Area3D = %LedgePocket
@onready var _talus: Area3D = %TalusPocket
@onready var _workshop: Marker3D = %WorkshopSite


func _ready() -> void:
	terrain = TerrainBuilder.new()
	terrain.build()
	_terrain_mesh.mesh = terrain.make_mesh([MAT_GROUND, MAT_STREAK, MAT_ROCK, MAT_FAR, MAT_RUINS])
	_terrain_shape.shape = terrain.make_shape()
	_workshop.position = Vector3(0.0, terrain.height_at(0.0, 0.0), 0.0)
	_build_wash_path()
	_build_pockets()
	_build_boulders()
	_build_sites()
	_build_smoke()
	built.emit()


## Floor surface height at (x, z) (the same triangles the collision uses).
func floor_height(x: float, z: float) -> float:
	return terrain.height_at(x, z)


func _build_wash_path() -> void:
	var curve := Curve3D.new()
	for p: Vector2 in ValleyLayout.wash_points():
		curve.add_point(Vector3(p.x, terrain.height_at(p.x, p.y), p.y))
	_wash_path.curve = curve


func _build_pockets() -> void:
	var lz: float = 0.5 * (ValleyLayout.LEDGE_Z0 + ValleyLayout.LEDGE_Z1)
	var lw: float = ValleyLayout.LEDGE_Z1 - ValleyLayout.LEDGE_Z0
	var ledge_box := BoxShape3D.new()
	ledge_box.size = Vector3(ValleyLayout.LEDGE_DEPTH, pocket_trigger_height, lw)
	var ledge_shape: CollisionShape3D = _ledge.get_node("Shape")
	ledge_shape.shape = ledge_box
	ledge_shape.position = Vector3(
		ValleyLayout.WALL_LEFT_X - 0.5 * ValleyLayout.LEDGE_DEPTH,
		ValleyLayout.ledge_floor_y() + 0.5 * pocket_trigger_height,
		lz
	)
	var tz: float = 0.5 * (ValleyLayout.TALUS_Z0 + ValleyLayout.TALUS_Z1)
	var tw: float = ValleyLayout.TALUS_Z1 - ValleyLayout.TALUS_Z0
	var low: float = ValleyLayout.talus_apron_y()
	var top: float = ValleyLayout.talus_y(1000.0) + pocket_trigger_height
	var talus_box := BoxShape3D.new()
	talus_box.size = Vector3(ValleyLayout.TALUS_DEPTH, top - low, tw)
	var talus_shape: CollisionShape3D = _talus.get_node("Shape")
	talus_shape.shape = talus_box
	talus_shape.position = Vector3(
		ValleyLayout.WALL_RIGHT_X + 0.5 * ValleyLayout.TALUS_DEPTH, 0.5 * (top + low), tz
	)


func _build_boulders() -> void:
	var specs: Array = ValleyLayout.boulders()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	mm.mesh = box
	mm.instance_count = specs.size()
	for i in range(specs.size()):
		var spec: Dictionary = specs[i]
		var pos: Vector2 = spec["pos"]
		var size: Vector3 = spec["size"]
		var ground: float = terrain.height_at(pos.x, pos.y)
		var total_h: float = size.y + boulder_buried_depth
		var centre := Vector3(pos.x, ground + 0.5 * size.y - 0.5 * boulder_buried_depth, pos.y)
		var rot := Basis(Vector3.UP, float(spec["yaw"]))
		mm.set_instance_transform(
			i, Transform3D(rot * Basis.from_scale(Vector3(size.x, total_h, size.z)), centre)
		)
		var shape := BoxShape3D.new()
		shape.size = Vector3(size.x, total_h, size.z)
		var col := CollisionShape3D.new()
		col.name = "Boulder_%d" % i
		col.shape = shape
		col.transform = Transform3D(rot, centre)
		_boulder_body.add_child(col)
	_boulder_mesh.multimesh = mm
	_boulder_mesh.material_override = MAT_BOULDER


func _build_sites() -> void:
	for spec: Dictionary in ValleyLayout.SCRAP_SITES:
		var site := ScrapSite.new()
		site.name = spec["name"]
		site.amount = spec["amount"]
		site.ring = spec["ring"]
		site.respawns = spec["respawns"]
		site.in_pocket = spec.get("in_pocket", false)
		_place(site, ValleyLayout.site_xz(spec))
	for spec: Dictionary in ValleyLayout.DRONE_SITES:
		var site := DroneSite.new()
		site.name = spec["name"]
		site.min_drones = spec["min"]
		site.max_drones = spec["max"]
		site.ring = spec["ring"]
		_place(site, ValleyLayout.site_xz(spec))


func _place(marker: Marker3D, xz: Vector2) -> void:
	marker.position = Vector3(xz.x, terrain.height_at(xz.x, xz.y) + marker_lift, xz.y)
	_sites.add_child(marker)


func _build_smoke() -> void:
	var cyl := CylinderMesh.new()
	cyl.height = smoke_height
	cyl.bottom_radius = smoke_bottom_radius
	cyl.top_radius = smoke_top_radius
	cyl.radial_segments = 12
	cyl.rings = 1
	_smoke.mesh = cyl
	_smoke.material_override = MAT_SMOKE
	_smoke.position = Vector3(0.0, ValleyLayout.plateau_y(smoke_z) + 0.5 * smoke_height - 2.0, smoke_z)
