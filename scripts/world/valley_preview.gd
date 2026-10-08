extends Node3D
## Preview rig for the valley: one camera with named views for screenshots (scenario valley_overview).
## Only the top_down view draws debug markers (cyan pillar per scrap site, magenta ring per drone site,
## orange disc at the workshop, a ribbon along the wash).

## from_workshop: camera offset from the workshop site (8 m behind, 3 m above) and field of view.
@export var workshop_camera_offset: Vector3 = Vector3(0.0, 3.0, -8.0)
@export var workshop_camera_fov: float = 70.0
## top_down: orthographic height in metres (covers z -60..380) and camera height.
@export var top_down_size: float = 440.0
@export var top_down_height: float = 300.0
@export var top_down_center_z: float = 160.0
## Pocket views: distance from the entrance and camera height above the apron.
@export var pocket_camera_distance: float = 8.0
@export var pocket_camera_height: float = 3.0
## Debug marker sizes (metres).
@export var pillar_radius: float = 2.5
@export var pillar_height: float = 14.0
@export var ring_inner: float = 5.0
@export var ring_outer: float = 7.0
@export var ribbon_half_width: float = 1.2

var _debug: Node3D = null

@onready var _valley: Valley = $Valley
@onready var _camera: Camera3D = $Camera3D
@onready var _world_env: WorldEnvironment = $Valley/WorldEnvironment
@onready var _sun: DirectionalLight3D = $Valley/Sun


func _ready() -> void:
	show_view("from_workshop")


## Switches the camera to one of: from_workshop, top_down, ledge_pocket, talus_pocket.
func show_view(view: String) -> void:
	_clear_debug()
	_world_env.environment.fog_enabled = view != "top_down"
	_sun.shadow_enabled = view != "top_down"
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = workshop_camera_fov
	_camera.far = 1200.0
	match view:
		"from_workshop":
			_camera.position = workshop_camera_offset
			_camera.look_at(Vector3(0.0, workshop_camera_offset.y, 100.0))
		"top_down":
			_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			_camera.size = top_down_size
			_camera.position = Vector3(0.0, top_down_height, top_down_center_z)
			_camera.look_at(Vector3(0.0, 0.0, top_down_center_z), Vector3(0.0, 0.0, -1.0))
			_build_debug()
		"ledge_pocket":
			var c: Vector2 = ValleyLayout.entrance_center("ledge")
			var y: float = ValleyLayout.ledge_apron_y()
			_camera.position = Vector3(c.x + pocket_camera_distance, y + pocket_camera_height, c.y)
			_camera.look_at(Vector3(c.x - 6.0, y + 1.0, c.y))
		"talus_pocket":
			var c: Vector2 = ValleyLayout.entrance_center("talus")
			var y: float = ValleyLayout.talus_apron_y()
			_camera.position = Vector3(c.x - pocket_camera_distance, y + pocket_camera_height, c.y)
			_camera.look_at(Vector3(c.x + 6.0, y + 3.0, c.y))
		_:
			push_error("valley_preview: unknown view %s" % view)


func _clear_debug() -> void:
	if _debug != null:
		remove_child(_debug)
		_debug.free()
		_debug = null


func _unshaded(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	return m


func _build_debug() -> void:
	_debug = Node3D.new()
	_debug.name = "DebugMarkers"
	add_child(_debug)
	var cyan: StandardMaterial3D = _unshaded(Color(0.0, 0.9, 1.0))
	var magenta: StandardMaterial3D = _unshaded(Color(1.0, 0.1, 0.45))
	var orange: StandardMaterial3D = _unshaded(Color(1.0, 0.55, 0.1))
	var ribbon_mat: StandardMaterial3D = _unshaded(Color(0.12, 0.18, 0.55))
	ribbon_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for node: Node in get_tree().get_nodes_in_group("scrap_sites"):
		var site := node as ScrapSite
		var pillar := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = pillar_radius
		cyl.bottom_radius = pillar_radius
		cyl.height = pillar_height
		pillar.mesh = cyl
		pillar.material_override = cyan
		_debug.add_child(pillar)
		pillar.global_position = site.global_position + Vector3(0.0, 0.5 * pillar_height, 0.0)
	for node: Node in get_tree().get_nodes_in_group("drone_sites"):
		var dsite := node as DroneSite
		var ring := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = ring_inner
		tor.outer_radius = ring_outer
		ring.mesh = tor
		ring.material_override = magenta
		_debug.add_child(ring)
		ring.global_position = dsite.global_position + Vector3(0.0, 2.0, 0.0)
	var disc := MeshInstance3D.new()
	var dcyl := CylinderMesh.new()
	dcyl.top_radius = 8.0
	dcyl.bottom_radius = 8.0
	dcyl.height = 0.5
	disc.mesh = dcyl
	disc.material_override = orange
	_debug.add_child(disc)
	disc.global_position = Vector3(0.0, 1.0, 0.0)
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var pts: PackedVector2Array = ValleyLayout.wash_points()
	for i in range(pts.size()):
		var a: Vector2 = pts[maxi(i - 1, 0)]
		var b: Vector2 = pts[mini(i + 1, pts.size() - 1)]
		var d: Vector2 = (b - a).normalized()
		var side := Vector2(-d.y, d.x) * ribbon_half_width
		var y: float = _valley.floor_height(pts[i].x, pts[i].y) + 1.5
		im.surface_add_vertex(Vector3(pts[i].x + side.x, y, pts[i].y + side.y))
		im.surface_add_vertex(Vector3(pts[i].x - side.x, y, pts[i].y - side.y))
	im.surface_end()
	var line := MeshInstance3D.new()
	line.mesh = im
	line.material_override = ribbon_mat
	_debug.add_child(line)
