shader_type spatial;
render_mode unshaded;
// Scrap crystal: bright cyan, pulsing on a 1.2 s period (GDD 10 readability rule 3).
uniform vec4 glow_color : source_color = vec4(0.35, 1.0, 1.0, 1.0);
uniform float period = 1.2;
uniform float pulse_depth = 1.0;

void fragment() {
	float p = 0.5 + 0.5 * sin(TIME * TAU / period);
	ALBEDO = mix(glow_color.rgb, vec3(0.85, 1.0, 1.0), pulse_depth * p);
}
