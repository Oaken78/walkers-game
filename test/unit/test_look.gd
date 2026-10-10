extends GutTest
## T11 look pass: the numbers behind the GDD 10 look (fog, glow, palette hex, band order). Pure data reads: no rendering.

const VALLEY_SCENE: String = "res://scenes/world/valley.tscn"
const CRATE_SCENE: String = "res://scenes/pickups/wreck_cache.tscn"
const SCRAP_SHADER: String = "res://scenes/pickups/scrap_glow.gdshader"
const BODY_HEX: Color = Color("E6E1D6")
const ACCENT_HEX: Color = Color("FF8A3D")
const THREAT_HEX: Color = Color("E8345A")
const SALVAGE_HEX: Color = Color("3DE0E8")
## World palette (GDD 10), base band of each role.
const ROCK_BASE: Color = Color("9B7D69")
const ROCK_LIT: Color = Color("BBA189")
const ROCK_SHADOW: Color = Color("6D5548")
const FAR_ROCK: Color = Color("A58B78")
const RUINS: Color = Color("93806E")
const GROUND: Color = Color("CAB294")
const GROUND_WASH: Color = Color("B99F82")
const FOREGROUND_ROCK: Color = Color("352D28")


func _valley_environment() -> Environment:
	var root: Node = (load(VALLEY_SCENE) as PackedScene).instantiate()
	var world_environment := root.get_node("WorldEnvironment") as WorldEnvironment
	var environment: Environment = world_environment.environment
	root.free()
	return environment


## Godot's depth fog (servers/rendering/renderer_rd/shaders/forward_clustered/scene_forward_clustered.glsl, fog_process):
## fog_amount = pow(smoothstep(begin, end, distance), curve) * density. The share of the fog colour mixed in.
func _fog_at(environment: Environment, distance: float) -> float:
	var z: float = smoothstep(environment.fog_depth_begin, environment.fog_depth_end, distance)
	return pow(z, environment.fog_depth_curve) * environment.fog_density


func _hex_matches(actual: Color, expected: Color) -> bool:
	return actual.is_equal_approx(expected) or actual.to_html(false) == expected.to_html(false)


func _lin(c: Color) -> Color:
	return c.srgb_to_linear()


func test_fog_reaches_14_percent_at_100m_and_30_at_300m() -> void:
	var environment: Environment = _valley_environment()
	assert_true(environment.fog_enabled)
	assert_eq(environment.fog_mode, Environment.FOG_MODE_DEPTH)
	assert_almost_eq(_fog_at(environment, 100.0), 0.14, 0.02, "GDD 10: 14 % at 100 m")
	assert_almost_eq(_fog_at(environment, 300.0), 0.30, 0.03, "GDD 10: 30 % at 300 m")
	assert_eq(environment.fog_light_color.to_html(false), "dacfb6", "fog is the horizon colour")


func test_the_sky_horizon_is_the_fog_colour() -> void:
	var root: Node = (load(VALLEY_SCENE) as PackedScene).instantiate()
	var environment: Environment = (root.get_node("WorldEnvironment") as WorldEnvironment).environment
	var sky_material := environment.sky.sky_material as ShaderMaterial
	assert_not_null(sky_material)
	assert_eq((sky_material.get_shader_parameter("horizon_color") as Color).to_html(false), "dacfb6")
	assert_eq((sky_material.get_shader_parameter("top_color") as Color).to_html(false), "90a092")
	assert_almost_eq(float(sky_material.get_shader_parameter("mottle_amount")), 0.025, 0.0001, "GDD 10: 2.5 % mottling")
	root.free()


func test_glow_threshold_above_lit_solids() -> void:
	var environment: Environment = _valley_environment()
	assert_true(environment.glow_enabled)
	# The brightest a lit solid can be: the actor shaders cap the lit band, and the world bands are below 1 by palette.
	var brightest_solid: float = 0.0
	for path: String in ["res://assets/materials/actor_body.tres", "res://assets/materials/actor_accent.tres"]:
		var material := load(path) as ShaderMaterial
		brightest_solid = maxf(brightest_solid, float(material.get_shader_parameter("lit_cap")))
		var base: Color = _lin(material.get_shader_parameter("base_color"))
		brightest_solid = maxf(brightest_solid, maxf(base.r, maxf(base.g, base.b)))
	assert_lte(brightest_solid, 1.0, "no lit solid exceeds 1.0 linear")
	assert_gt(environment.glow_hdr_threshold, brightest_solid, "the threshold sits above every solid")
	# Emissives clear it: the wind-up ring at full glow and the bolt streak (energy 2).
	var threat: Color = _lin(THREAT_HEX)
	var ring_peak: float = maxf(threat.r, maxf(threat.g, threat.b)) * Drone.GLOW_MAX
	assert_gt(ring_peak, environment.glow_hdr_threshold, "the wind-up ring blooms")
	assert_gt(maxf(threat.r, threat.g) * 2.0, environment.glow_hdr_threshold, "bolts bloom")


func test_actor_materials_use_palette_hex() -> void:
	var body := WalkerLeg.body_material() as ShaderMaterial
	var accent := WalkerLeg.accent_material() as ShaderMaterial
	assert_not_null(body)
	assert_not_null(accent)
	assert_eq((body.get_shader_parameter("base_color") as Color).to_html(false), BODY_HEX.to_html(false))
	assert_eq((accent.get_shader_parameter("base_color") as Color).to_html(false), ACCENT_HEX.to_html(false))
	assert_eq(WalkerLeg.BODY_COLOR.to_html(false), BODY_HEX.to_html(false))
	assert_eq(WalkerLeg.ACCENT_COLOR.to_html(false), ACCENT_HEX.to_html(false))
	assert_eq(Drone.THREAT_COLOR.to_html(false), THREAT_HEX.to_html(false), "threat")
	# Salvage: the pickup's pulse trough is cyan within 5 degrees of the palette hue (rule 3).
	var shader := load(SCRAP_SHADER) as Shader
	var found: RegExMatch = RegEx.create_from_string(r"glow_color[^=]*=\s*vec4\(([0-9.]+),\s*([0-9.]+),\s*([0-9.]+)").search(shader.code)
	assert_not_null(found, "the pickup shader declares glow_color")
	var glow := Color(float(found.get_string(1)), float(found.get_string(2)), float(found.get_string(3)))
	assert_almost_eq(glow.h * 360.0, SALVAGE_HEX.h * 360.0, 5.0, "salvage hue")
	assert_eq(WorkshopTheme.SALVAGE.to_html(false), SALVAGE_HEX.to_html(false))
	# The wreck crate keeps its orange hue (it is not in the GDD 10 table yet) and goes through the actor ramp.
	var crate_scene: Node = (load(CRATE_SCENE) as PackedScene).instantiate()
	var crate := crate_scene.get_node("Crate") as MeshInstance3D
	var crate_material := crate.material_override as ShaderMaterial
	assert_not_null(crate_material)
	assert_eq(crate_material.shader, body.shader, "the crate shares the actor toon shader")
	var crate_hex: Color = crate_material.get_shader_parameter("base_color")
	assert_almost_eq(crate_hex.h * 360.0, Color(0.95, 0.5, 0.08).h * 360.0, 1.0, "crate hue unchanged")
	crate_scene.free()


func test_actor_bands_are_ordered_lit_over_base_over_shadow() -> void:
	for path: String in ["res://assets/materials/actor_body.tres", "res://assets/materials/actor_accent.tres"]:
		var material := load(path) as ShaderMaterial
		var base: Color = _lin(material.get_shader_parameter("base_color"))
		var gain: float = material.get_shader_parameter("lit_gain")
		var lift: float = material.get_shader_parameter("lit_lift")
		var cap: float = material.get_shader_parameter("lit_cap")
		var shadow_gain: float = material.get_shader_parameter("shadow_gain")
		var lit := Color(base.r * gain, base.g * gain, base.b * gain).lerp(Color.WHITE, lift)
		lit = Color(minf(lit.r, cap), minf(lit.g, cap), minf(lit.b, cap))
		var shadow := Color(base.r * shadow_gain, base.g * shadow_gain, base.b * shadow_gain)
		assert_gt(lit.get_luminance(), base.get_luminance(), "%s: lit is lighter than base" % path)
		assert_gt(base.get_luminance(), shadow.get_luminance(), "%s: base is lighter than shadow" % path)


func test_world_materials_use_palette_hex_as_the_base_band() -> void:
	var expected: Dictionary = {
		"rock_base": ROCK_BASE, "rock_far": FAR_ROCK, "ruins": RUINS, "ground": GROUND, "boulder": FOREGROUND_ROCK
	}
	for name: String in expected:
		var material := load("res://assets/world/%s.tres" % name) as ShaderMaterial
		assert_not_null(material, name)
		var base: Color = material.get_shader_parameter("base_color")
		assert_eq(base.to_html(false), (expected[name] as Color).to_html(false), "%s base band is its palette hex" % name)
		var lit: Color = material.get_shader_parameter("lit_color")
		var shadow: Color = material.get_shader_parameter("shadow_color")
		assert_gte(lit.get_luminance(), base.get_luminance(), "%s lit band" % name)
		assert_lt(shadow.get_luminance(), base.get_luminance(), "%s shadow band" % name)
	var rock := load("res://assets/world/rock_base.tres") as ShaderMaterial
	assert_eq((rock.get_shader_parameter("lit_color") as Color).to_html(false), ROCK_LIT.to_html(false))
	assert_eq((rock.get_shader_parameter("shadow_color") as Color).to_html(false), ROCK_SHADOW.to_html(false))
	var ground := load("res://assets/world/ground.tres") as ShaderMaterial
	assert_eq((ground.get_shader_parameter("wash_color") as Color).to_html(false), GROUND_WASH.to_html(false))


func test_grain_is_4_5_percent_and_the_sky_mottle_2_5_percent() -> void:
	var root: Node = (load(VALLEY_SCENE) as PackedScene).instantiate()
	var rect := root.get_node("Grain/GrainRect") as ColorRect
	var material := rect.material as ShaderMaterial
	assert_almost_eq(float(material.get_shader_parameter("opacity")), 0.045, 0.0001, "GDD 10: grain 4.5 %")
	assert_eq(rect.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the grain never eats clicks")
	assert_lt((root.get_node("Grain") as CanvasLayer).layer, 0, "under any HUD layer")
	root.free()
