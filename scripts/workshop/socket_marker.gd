class_name SocketMarker
extends Node3D
## One socket's mark in the workshop (a camera-facing glyph drawn by socket_marker.gdshader).
## HOVER is the live ring in the player accent, BLOCKED a neutral cross, AVAILABLE a faint ring on a free socket
## that would take the armed part, DOT a small hint on a free socket while nothing is armed.

enum State { HIDDEN, DOT, AVAILABLE, HOVER, BLOCKED }

const SHADER: Shader = preload("res://scenes/workshop/socket_marker.gdshader")
## Player accent (GDD 10): the live ring. Never the threat hue.
const ACCENT: Color = Color("FF8A3D")
## Neutral off-white for everything that is not live.
const NEUTRAL: Color = Color("E6E1D6")
const INK: Color = Color("14161A")
## Ring radius of the live mark as a fraction of half the quad (matches the shader default for HOVER).
const HOVER_RADIUS: float = 0.8

## World size of the quad (m). The glyph radius is a fraction of half of this.
@export var quad_size: float = 0.9

var state: State = State.HIDDEN

var _mesh: MeshInstance3D
var _material: ShaderMaterial


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var quad := QuadMesh.new()
	quad.size = Vector2(quad_size, quad_size)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.render_priority = 20
	_mesh = MeshInstance3D.new()
	_mesh.mesh = quad
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	set_state(State.HIDDEN)


func set_state(new_state: State) -> void:
	state = new_state
	visible = new_state != State.HIDDEN
	match new_state:
		State.DOT:
			_style(2, NEUTRAL, 0.8, 0.14, 0.06, 0.85)
		State.AVAILABLE:
			_style(0, NEUTRAL, 0.55, 0.07, 0.04, 0.85)
		State.HOVER:
			_style(0, ACCENT, HOVER_RADIUS, 0.16, 0.06, 1.0)
		State.BLOCKED:
			_style(1, NEUTRAL, 0.75, 0.18, 0.06, 1.0)


func _style(
	glyph: int, color: Color, radius: float, thickness: float, ink: float, opacity: float
) -> void:
	_material.set_shader_parameter("glyph", glyph)
	_material.set_shader_parameter("fill_color", color)
	_material.set_shader_parameter("ink_color", INK)
	_material.set_shader_parameter("radius", radius)
	_material.set_shader_parameter("thickness", thickness)
	_material.set_shader_parameter("ink_width", ink)
	_material.set_shader_parameter("opacity", opacity)
