// The downtime hall's floor (D83): pale polished marble slabs with ink
// seams and veining, lit only by the spotlight pools and the window light,
// with a planar reflection (a mirrored camera's view, BWHall) laid over it.
// Unshaded and graphic like flat.gdshader: the light is painted, not lit.
shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D reflection : source_color, filter_linear, repeat_disable;
uniform float reflect_amount = 0.24;
uniform float ambient = 0.11;          // linear: the hall outside the pools
uniform vec4 spots[12];                // x, z, radius, intensity
uniform int spot_count = 0;
uniform vec4 patches[6];               // window light on the floor: xy = where the window's foot lands, z = weight
uniform vec4 patch_dir;                // xy = the floor offset from the window's foot to its head, z = width, w = strength
uniform int patch_count = 0;
uniform float slab = 2.2;

varying vec3 wpos;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1, 0)), u.x), mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	vec2 cell = floor(p / slab);
	vec2 inner = fract(p / slab) * slab;
	// slab tone: a hair of variation, like cut stone
	float tone = 0.80 + 0.08 * hash2(cell);
	// veining: thin warped bands, two scales, rotated per slab
	float ang = hash2(cell + 3.1) * 3.14159;
	vec2 q = mat2(vec2(cos(ang), sin(ang)), vec2(-sin(ang), cos(ang))) * p;
	float w1 = fbm(q * 0.55 + cell * 4.0);
	float v1 = 1.0 - smoothstep(0.0, 0.018, abs(fract(w1 * 3.2 + q.x * 0.12) - 0.5) - 0.47);
	float w2 = fbm(q * 1.6 + 11.0);
	float v2 = 1.0 - smoothstep(0.0, 0.01, abs(fract(w2 * 5.0) - 0.5) - 0.485);
	float cloud = fbm(p * 0.35) * 0.10;
	float base = tone - cloud - v1 * 0.34 - v2 * 0.16;
	// ink seams between slabs, thin and crisp; fade a little with distance
	vec2 e = min(inner, slab - inner);
	float px = fwidth(p.x) + fwidth(p.y);
	float seam = 1.0 - smoothstep(0.012, 0.012 + px * 1.2, min(e.x, e.y));
	base = mix(base, 0.0, seam * 0.9);

	// light: ambient + spotlight pools (crisp edge, soft falloff) + window patches
	float light = ambient;
	for (int i = 0; i < spot_count; i++) {
		vec4 s = spots[i];
		float d = length(p - s.xy);
		float pool = 1.0 - smoothstep(s.z * 0.80, s.z, d);
		float halo = 1.0 - smoothstep(s.z, s.z * 1.9, d);
		light += s.w * (pool * 0.80 + halo * 0.07 + pool * 0.10 * (1.0 - d / s.z));
	}
	for (int i = 0; i < patch_count; i++) {
		vec4 w = patches[i];
		// a parallelogram: x across the window, y from its foot to its head
		vec2 axis = patch_dir.xy;
		vec2 rel = p - w.xy;
		float along = rel.y / max(axis.y, 0.001);     // 0 at the window's foot, 1 at its head
		float across = rel.x - along * axis.x;         // the window's edges stay along x
		float fx = 1.0 - smoothstep(patch_dir.z * 0.42, patch_dir.z * 0.5 + 0.08, abs(across));
		float fy = smoothstep(-0.04, 0.03, along) * (1.0 - smoothstep(0.92, 1.02, along));
		// the arch: the far end rounds off
		float arch = 1.0 - smoothstep(0.80, 1.0, length(vec2(across / (patch_dir.z * 0.5), max(0.0, along - 0.8) / 0.2)));
		light += patch_dir.w * w.z * fx * fy * mix(1.0, arch, step(0.8, along));
	}
	vec3 col = vec3(base) * light;
	// reflection: a darkened mirror, stronger where the floor is lit
	vec2 ruv = vec2(SCREEN_UV.x, 1.0 - SCREEN_UV.y);
	vec2 o = vec2(0.0015, 0.0);
	vec3 r = (texture(reflection, ruv).rgb * 2.0 + texture(reflection, ruv + o).rgb + texture(reflection, ruv - o).rgb) * 0.25;
	float k = reflect_amount * (0.55 + 0.45 * clamp(light, 0.0, 1.0));
	col = mix(col, r * (0.35 + 0.65 * clamp(light, 0.0, 1.0)), k);
	ALBEDO = col;
}
