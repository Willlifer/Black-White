// D167-D169 pooled particles (BWVfxCasts): one MultiMesh, one draw call.
// Each instance is a camera-facing quad (QuadMesh size 1) whose transform
// carries the world position and the size; COLOR is the element hue (alpha =
// fade), INSTANCE_CUSTOM = (shape, white-core amount, rotation, stretch).
//   shape 0  mote: ink rim, element body, white core
//   shape 1  shard: an inked diamond (ice, debris), half white half hue
//   shape 2  spark: a long thin diamond
//   shape 3  dust: a soft grey puff with an ink edge
// Alpha-blended, never additive.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled, skip_vertex_transform;

varying vec2 q;
varying vec4 col;
varying vec4 cus;

void vertex() {
	vec3 c = MODEL_MATRIX[3].xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	float rot = INSTANCE_CUSTOM.z;
	vec2 v = VERTEX.xy;
	v.y *= max(INSTANCE_CUSTOM.w, 1.0);
	v = vec2(cos(rot) * v.x - sin(rot) * v.y, sin(rot) * v.x + cos(rot) * v.y);
	vec3 w = c + (INV_VIEW_MATRIX[0].xyz * v.x + INV_VIEW_MATRIX[1].xyz * v.y) * s;
	VERTEX = (VIEW_MATRIX * vec4(w, 1.0)).xyz;
	q = UV * 2.0 - 1.0;
	col = COLOR;
	cus = INSTANCE_CUSTOM;
}

void fragment() {
	vec2 p = q;
	float shape = cus.x;
	float d;
	vec3 body = col.rgb;
	if (shape < 0.5) {
		d = length(p);
	} else if (shape < 1.5) {
		d = abs(p.x) + abs(p.y);
		body = p.x < 0.0 ? vec3(1.0) : col.rgb;
	} else if (shape < 2.5) {
		d = abs(p.x) * 2.2 + abs(p.y);
	} else {
		d = length(p) * (0.9 + 0.1 * sin(atan(p.y, p.x) * 5.0));
		body = col.rgb;
	}
	if (d > 1.0) {
		discard;
	}
	float fw = max(fwidth(d), 0.02);
	vec3 c = mix(body, vec3(1.0), cus.y * (1.0 - smoothstep(0.35, 0.45, d)));
	float rim = smoothstep(0.7, 0.7 + fw, d);
	c = mix(c, vec3(0.0), rim);
	float a = 1.0 - smoothstep(1.0 - fw, 1.0, d);
	if (shape > 2.5) {
		a *= 0.85;
	}
	ALBEDO = c;
	ALPHA = a * col.a;
}
