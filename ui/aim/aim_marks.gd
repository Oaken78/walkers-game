class_name AimMarks
extends Control
## The aim marks of the field HUD (GDD 12): a camera dot at the screen centre (where you look, it sets P) and a
## world-space weapon reticle ring where the shot will land. Merge into a pip when on target, dashed ring at an
## elevation limit, thicker stroke over an enemy hurtbox, edge chevron when the ring is off screen or behind the
## camera. Every Control here ignores the mouse, so mouse look is never swallowed (plan note).
## refresh() works out what to show (and runs headless, so scenarios can assert on it); _draw() only paints it.

## From this body size (screen pixels) the pip is drawn as a circle; under it as a pixel-aligned square.
const PIP_ROUND_FROM_PX: float = 6.0

@export var rig: WeaponRig
@export var orbit: OrbitCamera

## What the marks show after the last refresh (scenarios and tests read these).
var ring_screen: Vector2 = Vector2.ZERO
var dot_screen: Vector2 = Vector2.ZERO
var ring_visible: bool = false
var dot_visible: bool = false
var pip_visible: bool = false
var chevron_visible: bool = false
var chevron_screen: Vector2 = Vector2.ZERO
var chevron_direction: Vector2 = Vector2.RIGHT
var dashed: bool = false
var thick: bool = false
## The ring's stroke shows the hit confirmation colour.
var flashing: bool = false
var ui_scale: float = 1.0
## The viewport the marks are laid out in (canvas units; the stretch scales them to the window).
var view_size: Vector2 = Vector2(1280.0, 720.0)
## Distance in screen pixels between the ring and the dot (INF when there is no ring).
var ring_to_dot_px: float = INF


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_priority = 100
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	refresh()
	queue_redraw()


## Works out which marks show and where, from the rig's reticle and the camera of this frame.
func refresh() -> void:
	ring_visible = false
	dot_visible = false
	pip_visible = false
	chevron_visible = false
	dashed = false
	thick = false
	flashing = false
	ring_to_dot_px = INF
	view_size = get_viewport_rect().size
	ui_scale = AimLayout.ui_scale(view_size.y)
	dot_screen = view_size * 0.5
	if rig == null or orbit == null or not is_inside_tree():
		return
	rig.update_reticle()
	if not rig.reticle_valid:
		dot_visible = true
		return
	var camera: Camera3D = orbit.camera()
	var behind: bool = camera.is_position_behind(rig.reticle_point)
	if not behind:
		ring_screen = camera.unproject_position(rig.reticle_point)
	if behind or not AimLayout.on_screen(ring_screen, view_size):
		chevron_direction = ring_screen - dot_screen
		if behind:
			var local: Vector3 = camera.global_transform.affine_inverse() * rig.reticle_point
			chevron_direction = Vector2(local.x, -local.y)
		chevron_screen = AimLayout.chevron_position(chevron_direction, view_size, ui_scale)
		chevron_visible = true
		dot_visible = true
		return
	thick = rig.reticle_on_enemy
	dashed = rig.ring_dashed
	flashing = rig.ring_flashing
	ring_visible = true
	ring_to_dot_px = ring_screen.distance_to(dot_screen)
	if AimLayout.is_merged(ring_screen, dot_screen, ui_scale):
		pip_visible = true
	else:
		dot_visible = true


func _draw() -> void:
	if ring_visible:
		_draw_ring(ring_screen)
	if pip_visible:
		_draw_pip(ring_screen)
	if dot_visible:
		_draw_dot()
	if chevron_visible:
		_draw_chevron()


func _draw_dot() -> void:
	var body_radius: float = AimLayout.DOT_PX * 0.5 * ui_scale
	var outline: float = AimLayout.DOT_OUTLINE_PX * ui_scale
	draw_circle(dot_screen, body_radius + outline, AimLayout.INK)
	draw_circle(dot_screen, body_radius, AimLayout.BODY)


func _draw_pip(at: Vector2) -> void:
	var body: float = AimLayout.pip_screen_px(ui_scale)
	var outline: float = AimLayout.pip_outline_px(ui_scale)
	if body < PIP_ROUND_FROM_PX:
		# Small: whole-pixel squares, so the orange body is at least 3 solid pixels across with the ink outside it.
		var top_left: Vector2 = (at - Vector2.ONE * body * 0.5).round()
		draw_rect(Rect2(top_left - Vector2.ONE * outline, Vector2.ONE * (body + outline * 2.0)), AimLayout.INK)
		draw_rect(Rect2(top_left, Vector2.ONE * body), AimLayout.ACCENT)
	else:
		draw_circle(at, body * 0.5 + outline, AimLayout.INK)
		draw_circle(at, body * 0.5, AimLayout.ACCENT)


func _draw_ring(at: Vector2) -> void:
	var stroke_width: float = AimLayout.stroke_screen_px(thick, ui_scale)
	var radius: float = AimLayout.ring_radius(ui_scale, stroke_width)
	var outline_width: float = stroke_width + AimLayout.RING_OUTLINE_PX * 2.0 * ui_scale
	var colour: Color = AimLayout.FLASH if flashing else AimLayout.ACCENT
	if dashed:
		for arc in AimLayout.dash_arcs():
			draw_arc(at, radius, arc.x, arc.y, 8, AimLayout.INK, outline_width, true)
		for arc in AimLayout.dash_arcs():
			draw_arc(at, radius, arc.x, arc.y, 8, colour, stroke_width, true)
	else:
		draw_arc(at, radius, 0.0, TAU, 48, AimLayout.INK, outline_width, true)
		draw_arc(at, radius, 0.0, TAU, 48, colour, stroke_width, true)


func _draw_chevron() -> void:
	var points: PackedVector2Array = AimLayout.chevron_points(chevron_screen, chevron_direction, ui_scale)
	var outline: PackedVector2Array = points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, AimLayout.INK, AimLayout.RING_OUTLINE_PX * 2.0 * ui_scale, true)
	draw_colored_polygon(points, AimLayout.ACCENT)
