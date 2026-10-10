shader_type spatial;
// Smoke column (GDD 10: smoke and haze are part of the look). Flat smoke colour with a soft silhouette: opacity falls
// off toward the rim so the column melts into the haze instead of cutting a hard dark shape. Fog applies (it is far).
render_mode unshaded, blend_mix, depth_draw_never, cull_back;

// Smoke colour (GDD palette).
uniform vec4 smoke_color : source_color = vec4(0.3412, 0.3176, 0.3020, 1.0);
// Opacity at the centre of the column as seen from the camera.
uniform float core_alpha = 0.9;
// How fast opacity falls toward the silhouette (higher = softer, thinner edge).
uniform float edge_power = 1.6;

void fragment() {
	float facing = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	ALBEDO = smoke_color.rgb;
	ALPHA = core_alpha * pow(facing, edge_power);
}
