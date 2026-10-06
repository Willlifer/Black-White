// Muzzle / impact flash (BWProjectileFlight): a camera-facing six-point
// star, white core, the element colour in a ring, an ink rim outside it.
// `age` 0..1 over the flash's life thins the spikes and opens a hole in
// the core as it burns out. Unlit, alpha-blended, drawn over the rig.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform vec4 ring : source_color = vec4(1.0);
uniform float age = 0.0;
uniform float seed = 0.0;
instance uniform float dim : hint_range(0.0, 1.0), instance_index(0) = 0.0;

void vertex() {
	// billboard: keep the quad facing the camera, scale from the model matrix
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x) + seed * 6.2831;
	// six long spikes, six short between
	float spikes = 0.42 + 0.58 * pow(abs(cos(a * 3.0)), 8.0) + 0.22 * pow(abs(sin(a * 3.0)), 10.0);
	spikes *= (1.0 - 0.35 * age);
	float edge = spikes * 0.92;
	if (r > edge) {
		discard;
	}
	vec3 c = vec3(1.0);
	if (r > edge - 0.11) {
		c = vec3(0.0);                       // the ink rim
	} else if (r > edge * 0.55) {
		c = ring.rgb;                        // the element ring
	}
	if (age > 0.55 && r < 0.25 * (age - 0.55) / 0.45) {
		discard;                             // burns out from the middle
	}
	ALBEDO = mix(c, c * 0.012, dim);
}
