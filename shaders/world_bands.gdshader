shader_type spatial;
// World flat bands (GDD 10 "Flat colour bands"): base, one lit band, one shadow band, no gradients on solids.
// Only the directional sun picks the band, so a fill light for actors never changes the rocks. No ambient, no specular.
render_mode ambient_light_disabled, specular_disabled, cull_back;

// The three bands, sRGB. Base is the role's palette hex.
uniform vec4 base_color : source_color = vec4(0.6, 0.5, 0.4, 1.0);
uniform vec4 lit_color : source_color = vec4(0.7, 0.6, 0.5, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.4, 0.3, 0.25, 1.0);
// N.L above lit_threshold is lit, at or below shadow_threshold (or in the sun's shadow) is shadow, else base.
// Flat ground sits at sin(sun elevation), so ground uses a narrow window around it and shows relief as band patches.
uniform float lit_threshold = 0.72;
uniform float shadow_threshold = -0.05;
// Vertex colour carries flags (terrain mesh only): R = wash weight, G = ledge lip. Boulders have none: leave off.
uniform bool use_vertex_flags = false;
// The wash is drawn where vertex R is above wash_threshold: a thresholded flat band, never a gradient.
// Colour of the wash in sRGB; each band is scaled by wash_color / base_color.
uniform vec4 wash_color : source_color = vec4(0.73, 0.62, 0.51, 1.0);
uniform float wash_threshold = 0.5;
// Cliff strata (vertical faces only): below foot_height metres above the floor line is the shadow band, above
// lit_height is the lit band, in between base. Away-facing walls drop one band. Off for ground and boulders.
uniform bool strata = false;
uniform float foot_height = 8.0;
uniform float lit_height = 20.0;
// Slope of the valley floor line (tan of FALL_DEG), so strata follow the floor down the valley.
uniform float fall_slope = 0.034920;

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying vec4 v_flags;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	v_flags = use_vertex_flags ? COLOR : vec4(0.0);
}

vec3 wash_ratio(float w) {
	return mix(vec3(1.0), wash_color.rgb / max(base_color.rgb, vec3(0.001)), w);
}

void fragment() {
	ALBEDO = vec3(1.0);
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
	EMISSION = shadow_color.rgb * wash_ratio(step(wash_threshold, v_flags.r));
}

void light() {
	// Only the sun picks bands; fill lights are ignored by the world.
		if (LIGHT_IS_DIRECTIONAL) {
		float nl = dot(NORMAL, LIGHT);
		bool in_sun = ATTENUATION > 0.5;
		int level = 1;
		if (strata && abs(v_world_normal.y) < 0.5) {
			float h = v_world_pos.y + v_world_pos.z * fall_slope;
			level = h < foot_height ? 0 : (h > lit_height ? 2 : 1);
			if (!in_sun || nl <= shadow_threshold) {
				level = max(level - 1, 0);
			}
		} else {
			level = nl > lit_threshold ? 2 : (nl <= shadow_threshold ? 0 : 1);
			if (!in_sun) {
				level = 0;
			}
		}
		// Ledge lip: always the lit band, so the 1.2 m step reads against the shadowed cliff behind it.
		if (v_flags.g > 0.5) {
			level = 2;
	}
	vec3 wash = wash_ratio(step(wash_threshold, v_flags.r));
	vec3 band = level == 2 ? lit_color.rgb : (level == 1 ? base_color.rgb : shadow_color.rgb);
	DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, band * wash - shadow_color.rgb * wash);
	}
}
