shader_type spatial;
// Dust sprite: a camera-facing quad that is lit like the ground (world-up normal), so it darkens in shadow with it.
render_mode blend_mix, cull_disabled, depth_draw_never, specular_disabled;

// Soft radial sprite, white; its alpha is the falloff.
uniform sampler2D sprite_tex : source_color, filter_linear;

void vertex() {
	// Billboard: face the camera, keep the instance scale.
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	mat4 face = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * face * mat4(vec4(scale.x, 0.0, 0.0, 0.0), vec4(0.0, scale.y, 0.0, 0.0), vec4(0.0, 0.0, scale.z, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	// Instance colour: rgb = dust tone, a = opacity over the puff's life.
	vec4 t = texture(sprite_tex, UV);
	ALBEDO = COLOR.rgb;
	ALPHA = t.a * COLOR.a;
	// World up in view space: lit as the floor is, not as a screen-facing card.
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	ROUGHNESS = 1.0;
}
