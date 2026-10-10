shader_type sky;
// Valley sky (GDD 10): sky top -> horizon gradient in the fog colour, plus faint mottling (2.5 %) so a big flat
// sky does not look like a CSS gradient. Static: no TIME, so screenshots stay comparable.

// Zenith colour (GDD sky top).
uniform vec4 top_color : source_color = vec4(0.5647, 0.6275, 0.5725, 1.0);
// Horizon colour; must equal the fog colour so the far cliffs melt into it.
uniform vec4 horizon_color : source_color = vec4(0.8549, 0.8118, 0.7137, 1.0);
// Colour straight down (only seen in a top-down view).
uniform vec4 ground_color : source_color = vec4(0.72, 0.66, 0.56, 1.0);
// Gradient exponent: lower = the top colour reaches lower in the sky.
uniform float curve = 0.5;
// Mottling strength as a share of the sky colour (GDD: 0.025) and its size (bigger = smaller blotches).
uniform float mottle_amount = 0.025;
uniform float mottle_scale = 6.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
			mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void sky() {
	float y = EYEDIR.y;
	vec3 c = mix(horizon_color.rgb, top_color.rgb, pow(clamp(y, 0.0, 1.0), curve));
	c = mix(c, ground_color.rgb, pow(clamp(-y, 0.0, 1.0), 0.5));
	// Direction projected onto a plane above the viewer, so blotches are wide near the horizon like cloud banks.
	vec2 p = EYEDIR.xz / (abs(y) + 0.35) * mottle_scale * 0.25;
	float n = 0.6 * value_noise(p) + 0.4 * value_noise(p * 2.7 + 11.0);
	COLOR = c * (1.0 + mottle_amount * (n - 0.5) * 2.0);
}
