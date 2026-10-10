shader_type spatial;
// Actor toon ramp (GDD 10 "Shading"): three flat bands (lit, base, shadow) with a hard terminator.
// The base band is the palette hex. No ambient and no specular: the three bands are the whole look, so a walker reads
// the same under any sky. Every light adds its band; the brightest band wins, so a fill light cannot over-brighten.
render_mode ambient_light_disabled, specular_disabled, cull_back;

// Palette hex of the role, drawn as the middle band. sRGB in the editor, linear inside.
uniform vec4 base_color : source_color = vec4(0.9, 0.88, 0.84, 1.0);
// Lit band = base x lit_gain (linear), then lerped toward white by lit_lift. A light hue such as the body only needs
// gain; a saturated hue such as the accent clips a channel under gain, so it uses lift (same hue, lighter value).
uniform float lit_gain = 1.2;
uniform float lit_lift = 0.0;
// No lit solid may exceed this linear value. The glow threshold sits above it, so only emissives bloom.
uniform float lit_cap = 1.0;
// Shadow band = base x shadow_gain (linear).
uniform float shadow_gain = 0.55;
// N.L above this is the lit band; N.L at or below shadow_threshold (or light blocked: shadow map, light range) is the
// shadow band; anything between is the base band. 0.72 = only faces turned toward the sun; -0.05 = faces turned away.
uniform float lit_threshold = 0.72;
uniform float shadow_threshold = -0.05;
// A light weaker than this (energy, after the PI the engine folds into LIGHT_COLOR) is fill: it never sets a band, so a
// 0.35 body light cannot flatten the walker into base. The key light and the sun (energy >= 1) do.
uniform float min_light_energy = 0.5;
// Self-lit colour added on top of the bands (threat glow, crate glow). Energy 0 = none.
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;

vec3 lit_band() {
	vec3 c = base_color.rgb * lit_gain;
	c = mix(c, vec3(1.0), lit_lift);
	return min(c, vec3(lit_cap));
}

void fragment() {
	// Light is added as (band - shadow band) on top of the shadow band, which is the floor.
	ALBEDO = vec3(1.0);
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
	EMISSION = base_color.rgb * shadow_gain + emission_color.rgb * emission_energy;
}

void light() {
	float nl = dot(NORMAL, LIGHT);
	vec3 shadow_c = base_color.rgb * shadow_gain;
	vec3 band = shadow_c;
	float energy = dot(LIGHT_COLOR, vec3(0.2126, 0.7152, 0.0722)) / PI;
	if (energy >= min_light_energy && ATTENUATION > 0.5 && nl > shadow_threshold) {
		band = nl > lit_threshold ? lit_band() : base_color.rgb;
	}
	DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, band - shadow_c);
}
