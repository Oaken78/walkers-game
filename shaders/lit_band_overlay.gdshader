shader_type spatial;
// Third toon band for surfaces that must keep a StandardMaterial3D base pass (the drone ring: its emissive ramp and flash
// are driven through StandardMaterial3D properties). The base pass is a toon-diffuse material that gives the shadow and
// base bands; this additive pass adds the lit band where a face turns straight toward the sun.
render_mode blend_add, depth_draw_never, ambient_light_disabled, specular_disabled, fog_disabled, cull_back;

// Linear colour added inside the lit band (small: the ring is near-black ink).
uniform vec4 lit_add : source_color = vec4(0.19, 0.19, 0.22, 1.0);
// N.L above this is the lit band; keep equal to the actor shader's lit_threshold.
uniform float lit_threshold = 0.5;

void fragment() {
	ALBEDO = vec3(1.0);
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
}

void light() {
	if (ATTENUATION > 0.5 && dot(NORMAL, LIGHT) > lit_threshold) {
		DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, lit_add.rgb);
	}
}
