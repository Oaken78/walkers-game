class_name HudCheck
extends Node3D
## Field HUD bench (T20): a flat ground, a stand-in walker position, a camera, and a Health, Economy and RecallHold the
## scenario hud_check drives through the helpers below. The HUD sits in a CanvasLayer; a grayscale layer above it
## can be switched on for the contrast shot.

const GROUND_COLOR: Color = Color("CAB294")
const SKY_COLOR: Color = Color("90A092")
const GRAY_SHADER: String = """
shader_type canvas_item;
// The whole frame behind this layer, shown as luma only (Rec. 709 weights).
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	COLOR = vec4(vec3(l), 1.0);
}
"""

## Where the workshop stands in the bench (m).
@export var home: Vector3 = Vector3(60.0, 0.0, -80.0)

var health: Health = Health.new(100.0)
var economy: Economy = Economy.new()
var recall: RecallHold = null
var hud: FieldHud = null
var hold_recall: bool = false

var _walker: Node3D = null
var _camera: Camera3D = null
var _gray: ColorRect = null


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = SKY_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = GROUND_COLOR
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ground.material_override = mat
	add_child(ground)

	_walker = Node3D.new()
	_walker.name = "Walker"
	add_child(_walker)
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.position = Vector3(0, 6, 8)
	_camera.rotation_degrees = Vector3(-20, 0, 0)
	_camera.current = true
	add_child(_camera)

	recall = RecallHold.new()
	recall.read_input = false
	recall.hold_time = 3.0
	add_child(recall)

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = (load("res://ui/hud/field_hud.tscn") as PackedScene).instantiate() as FieldHud
	layer.add_child(hud)
	var gray_layer := CanvasLayer.new()
	gray_layer.layer = 5
	add_child(gray_layer)
	_gray = ColorRect.new()
	_gray.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = GRAY_SHADER
	sm.shader = shader
	_gray.material = sm
	_gray.visible = false
	gray_layer.add_child(_gray)
	hud.bind(health, economy, _walker, _camera, home, recall)


func _physics_process(delta: float) -> void:
	recall.step(hold_recall, delta)


## Scenario helpers.
func damage(amount: float) -> void:
	health.damage(amount)


func pick_up(amount: int) -> void:
	economy.collect_loose(amount)


func bank() -> void:
	economy.bank()


func drop_cache(x: float, z: float, amount: int) -> void:
	economy.carried_scrap = amount
	economy.die(Vector3(x, 0, z))


func set_hold(held: bool) -> void:
	hold_recall = held


func set_yaw(deg: float) -> void:
	_camera.rotation_degrees = Vector3(-20, deg, 0)


func set_gray(on: bool) -> void:
	_gray.visible = on


func enter_prompt(on: bool) -> void:
	hud.set_enter_prompt(on)


func toast(text: String) -> void:
	hud.show_toast(text, 4.0)


## Frees the HUD side first, then the stand-ins, the way T12 should end a run.
func teardown() -> void:
	hud.unbind()
	_walker.queue_free()
	_walker = null
	economy = Economy.new()
