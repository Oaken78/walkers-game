shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, blend_mix;
// A socket mark in the workshop: a flat glyph that always faces the camera, drawn over the walker (no depth test)
// so a socket behind the chassis still shows. An ink outline keeps it readable on any body shade.

// 0 = ring (socket you can use), 1 = cross (socket that cannot take the armed part), 2 = dot (idle hint).
uniform int glyph : hint_range(0, 2) = 0;
// Fill colour of the stroke (the player accent for a live socket, a neutral off-white otherwise). Never the threat hue.
uniform vec4 fill_color : source_color = vec4(1.0, 0.541, 0.239, 1.0);
// Outline colour around the stroke (the ink of the palette).
uniform vec4 ink_color : source_color = vec4(0.078, 0.086, 0.102, 1.0);
// Outer radius of the glyph, as a fraction of the half-size of the quad (0..1).
uniform float radius : hint_range(0.1, 1.0) = 0.62;
// Stroke width as a fraction of the half-size of the quad.
uniform float thickness : hint_range(0.02, 0.5) = 0.14;
// Ink outline width on each side of the stroke, same unit as thickness.
uniform float ink_width : hint_range(0.0, 0.2) = 0.06;
// Overall opacity (0..1), for the faint "free socket" hints.
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	// Billboard: face the camera, keep the node's scale.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	// Signed distance to the stroke: negative inside it.
	float d;
	if (glyph == 0) {
		d = abs(length(p) - (radius - thickness * 0.5)) - thickness * 0.5;
	} else if (glyph == 1) {
		float bar = min(abs(p.x - p.y), abs(p.x + p.y)) * 0.70710678 - thickness * 0.5;
		float limit = max(abs(p.x), abs(p.y)) - radius * 0.72;
		d = max(bar, limit);
	} else {
		d = length(p) - radius * 0.4;
	}
	float aa = max(fwidth(d), 0.0001);
	float fill = 1.0 - smoothstep(-aa, aa, d);
	float outline = 1.0 - smoothstep(-aa, aa, d - ink_width);
	ALBEDO = mix(ink_color.rgb, fill_color.rgb, fill);
	ALPHA = outline * opacity;
}
