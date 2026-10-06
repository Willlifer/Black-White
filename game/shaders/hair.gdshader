// Hair fill. Unlit, no sheen (D64). The look comes from a ramp texture
// over the hair's root (0) -> tip (1) coordinate (D146, BWLook.hair_gradient):
// ramp.rgb = the hair colour there; ramp.a = the contrast streaks
// (0.5 none; above: light streaks on (a - 0.5) * 2 of the locks; below:
// black streaks on (0.5 - a) * 2). See BWLook.streak_alpha.
// BWHair bakes the per-vertex attributes into vertex COLOR at load (D147):
//   COLOR.r  root -> tip (0..1)
//   COLOR.g  azimuth around the head (the lock's centroid for a lock, the
//            vertex's own for a shell), 0..1: picks the streaked locks
// `tint` (instance slot 1) multiplies the result: white normally. `value`
// darkens in perceptual (sRGB-ish) terms: 1.0 on `hair`, ~0.6 on
// `hair_shade`. Same `dim` / `dim_floor` contract as flat.gdshader.
// Opaque (no ALPHA write), so it depth-sorts against the head.
shader_type spatial;
render_mode unshaded, cull_back;

instance uniform vec4 tint : source_color, instance_index(1) = vec4(1.0);
instance uniform float dim : hint_range(0.0, 1.0), instance_index(0) = 0.0;
uniform sampler2D ramp : source_color, filter_linear, repeat_disable;
uniform vec3 streak_light : source_color = vec3(0.9);
uniform vec3 streak_dark : source_color = vec3(0.0);
uniform float value : hint_range(0.0, 1.0) = 1.0;
uniform float saturate = 0.0;
uniform float shine : hint_range(0.0, 1.0) = 0.0;
uniform float dim_floor = 0.012;
uniform float streak_cells = 22.0;                 // azimuth sectors
uniform float streak_seed = 0.0;

// 1 on a streaked lock: a lock's sector hash below `share`; faint right at
// the root so streaks read as lighter / darker locks, not a cap.
float streak(vec4 col, float share) {
	float cell = floor(col.g * streak_cells + 0.0001);
	float h = fract(sin(cell * 12.9898 + streak_seed * 78.233) * 43758.5453);
	return step(h, share) * smoothstep(0.0, 0.2, col.r);
}

void fragment() {
	vec4 g = texture(ramp, vec2(clamp(COLOR.r, 0.0, 1.0), 0.5));
	float s = g.a * 2.0 - 1.0;
	float m = streak(COLOR, abs(s) - 0.004);
	vec3 c = mix(g.rgb, s > 0.0 ? streak_light : streak_dark, m) * tint.rgb;
	// darken in perceptual space: the ramp is linear here, value is not
	c *= pow(value, 2.2);
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = max(mix(vec3(l), c, 1.0 + saturate), vec3(0.0));
	c = mix(c, vec3(1.0), shine);
	ALBEDO = mix(c, c * dim_floor, dim);
}
