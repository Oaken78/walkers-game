shader_type spatial;
render_mode unshaded;
// Scrap crystal: bright cyan, pulsing on a 1.2 s period (GDD 10 readability rule 3).
// Trough colour of the pulse: saturated cyan, still well above the sand floor in luma.
uniform vec4 glow_color : source_color = vec4(0.35, 1.0, 1.0, 1.0);
uniform float period = 1.2;
// How far the peak moves toward light cyan (0.4 -> peak about #8CFFFF, saturation 0.45). Never toward white:
// scrap must stay cyan at its brightest (GDD 10).
uniform float pulse_depth = 0.4;

void fragment() {
	float p = 0.5 + 0.5 * sin(TIME * TAU / period);
	ALBEDO = mix(glow_color.rgb, vec3(0.85, 1.0, 1.0), pulse_depth * p);
}
