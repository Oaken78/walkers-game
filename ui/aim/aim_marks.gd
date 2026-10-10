class_name AimMarks
extends Control
## The aim marks of the field HUD (GDD 12): a camera dot at the screen centre (where the mouse aims, it sets P) and
## one world-space ring per mounted weapon where that weapon's shot goes now. A gray weapon (P out of its arc) has a
## gray dashed ring at its arc limit; a ring over an enemy hurtbox has a thicker stroke; a ring that is off screen or
## behind the camera has an edge chevron in its colour. Every Control here ignores the mouse, so mouse look is never
## swallowed. refresh() works out what to show (and runs headless, so scenarios can assert on it); _draw() paints it.

@export var rig: WeaponRig
@export var orbit: OrbitCamera

## One entry per mounted weapon, as of the last refresh().
var rings: Array[Ring] = []
var dot_screen: Vector2 = Vector2.ZERO
var ui_scale: float = 1.0
## The viewport the marks are laid out in (canvas units; the stretch scales them to the window).
var view_size: Vector2 = Vector2(1280.0, 720.0)


class Ring:
	extends RefCounted
	var screen: Vector2 = Vector2.ZERO
	## Drawn as a ring (on screen); otherwise as a chevron.
	var visible: bool = false
	var chevron_visible: bool = false
	var chevron_screen: Vector2 = Vector2.ZERO
	var chevron_direction: Vector2 = Vector2.RIGHT
	var live: bool = true
	var dashed: bool = false
	var thick: bool = false
	var flashing: bool = false
	## Distance in screen pixels between the ring and the dot (INF when it is not on screen).
	var to_dot_px: float = INF

	func colour() -> Color:
		if flashing:
			return AimLayout.FLASH
		return AimLayout.ACCENT if live else AimLayout.GRAY


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_priority = 100
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	refresh()
	queue_redraw()


## Works out which marks show and where, from the rig's weapons and the camera of this frame.
func refresh() -> void:
	view_size = get_viewport_rect().size
	ui_scale = AimLayout.ui_scale(view_size.y)
	dot_screen = view_size * 0.5
	if rig == null or orbit == null or not is_inside_tree():
		rings.clear()
		return
	rig.update_reticle()
	var count: int = rig.cannon_count()
	while rings.size() > count:
		rings.pop_back()
	while rings.size() < count:
		rings.append(Ring.new())
	var camera: Camera3D = orbit.camera()
	for i in count:
		_refresh_ring(rings[i], i, camera)


func _refresh_ring(ring: Ring, index: int, camera: Camera3D) -> void:
	var point: Vector3 = rig.reticle_point(index)
	ring.visible = false
	ring.chevron_visible = false
	ring.to_dot_px = INF
	ring.live = rig.is_live(index)
	ring.dashed = not ring.live
	ring.thick = rig.reticle_on_enemy(index)
	ring.flashing = rig.weapon_flashing(index)
	var behind: bool = camera.is_position_behind(point)
	if not behind:
		ring.screen = camera.unproject_position(point)
	if behind or not AimLayout.on_screen(ring.screen, view_size):
		ring.chevron_direction = ring.screen - dot_screen
		if behind:
			var local: Vector3 = camera.global_transform.affine_inverse() * point
			ring.chevron_direction = Vector2(local.x, -local.y)
		ring.chevron_screen = AimLayout.chevron_position(ring.chevron_direction, view_size, ui_scale)
		ring.chevron_visible = true
		return
	ring.visible = true
	ring.to_dot_px = ring.screen.distance_to(dot_screen)


## The number of rings drawn on screen.
func visible_ring_count() -> int:
	var n: int = 0
	for ring in rings:
		n += 1 if ring.visible else 0
	return n


func chevron_count() -> int:
	var n: int = 0
	for ring in rings:
		n += 1 if ring.chevron_visible else 0
	return n


func _draw() -> void:
	for ring in rings:
		if ring.visible:
			_draw_ring(ring)
		if ring.chevron_visible:
			_draw_chevron(ring)
	_draw_dot()


func _draw_dot() -> void:
	var body_radius: float = AimLayout.DOT_PX * 0.5 * ui_scale
	var outline: float = AimLayout.DOT_OUTLINE_PX * ui_scale
	draw_circle(dot_screen, body_radius + outline, AimLayout.INK)
	draw_circle(dot_screen, body_radius, AimLayout.BODY)


func _draw_ring(ring: Ring) -> void:
	var stroke_width: float = AimLayout.stroke_screen_px(ring.thick, ui_scale)
	var radius: float = AimLayout.ring_radius(ui_scale, stroke_width)
	var outline_width: float = stroke_width + AimLayout.RING_OUTLINE_PX * 2.0 * ui_scale
	var colour: Color = ring.colour()
	if ring.dashed:
		for arc in AimLayout.dash_arcs():
			draw_arc(ring.screen, radius, arc.x, arc.y, 8, AimLayout.INK, outline_width, true)
		for arc in AimLayout.dash_arcs():
			draw_arc(ring.screen, radius, arc.x, arc.y, 8, colour, stroke_width, true)
	else:
		draw_arc(ring.screen, radius, 0.0, TAU, 48, AimLayout.INK, outline_width, true)
		draw_arc(ring.screen, radius, 0.0, TAU, 48, colour, stroke_width, true)


func _draw_chevron(ring: Ring) -> void:
	var points: PackedVector2Array = AimLayout.chevron_points(ring.chevron_screen, ring.chevron_direction, ui_scale)
	var outline: PackedVector2Array = points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, AimLayout.INK, AimLayout.RING_OUTLINE_PX * 2.0 * ui_scale, true)
	draw_colored_polygon(points, ring.colour())
