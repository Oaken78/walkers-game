shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
// Vertical beam over a pickup: strongest at the base, fading out at the top. The mesh is a unit cylinder
// (height 1, centred), scaled in Y by the node, so the fade reads the local height.
instance uniform vec4 beam_color : source_color = vec4(0.15, 0.95, 1.0, 1.0);
uniform float period = 1.2;
uniform float base_alpha = 0.55;

varying float height01;

void vertex() {
	height01 = clamp(VERTEX.y + 0.5, 0.0, 1.0);
}

void fragment() {
	float p = 0.75 + 0.25 * sin(TIME * TAU / period);
	ALBEDO = beam_color.rgb;
	ALPHA = base_alpha * (1.0 - height01) * p;
}
