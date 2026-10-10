shader_type canvas_item;
// Film grain over the 3D view (GDD 10: 4.5 % opacity). Deterministic: the noise is a hash of the pixel and the frame
// index, and TIME advances exactly 1/60 s per frame under the tools' --fixed-fps, so the same frame number gives the
// same grain. Mid-grey noise at low opacity: it never shifts a flat band by more than about 0.02 luma.

// Opacity of the grain layer (GDD: 0.045).
uniform float opacity = 0.045;
// Contrast of the noise around mid-grey (1 = full black to white, 0.35 keeps every pixel within +/-0.8 % of its band).
uniform float contrast = 0.35;
// Grain refresh rate in Hz (film runs at 24; the hash changes only on a new step).
uniform float refresh_hz = 24.0;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void fragment() {
	float step_index = floor(TIME * refresh_hz + 0.001);
	float n = hash13(vec3(floor(FRAGCOORD.xy), mod(step_index, 997.0)));
	float g = 0.5 + (n - 0.5) * contrast;
	COLOR = vec4(vec3(g), opacity);
}
