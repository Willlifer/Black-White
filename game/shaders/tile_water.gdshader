// Water, tile face (ELEMENTS §4).
//   1 Damp: a wet sheen, one slow ripple, a glint sweeping across
//   2 Flooded: standing water, concentric ripples, a foam line at the rim
//   3 Deep: the face sinks (parallax floor + inner walls), strong ripples
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

#include "res://shaders/tile_fx.gdshaderinc"

uniform vec4 glow : source_color = vec4(0.18, 0.55, 1.0, 1.0);

varying vec2 lp;

void vertex() {
	lp = VERTEX.xz;
}

void fragment() {
	if (tier <= 0.001) {
		discard;
	}
	float a1 = t1();
	float a2 = t2();
	float a3 = t3();
	float t = fx_time(TIME);
	float d = hexd(lp);
	float r = length(lp);
	vec3 wv = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 deep = lin(vec3(0.03, 0.13, 0.42));
	vec3 pale = lin(vec3(0.78, 0.9, 1.0));
	vec4 acc = vec4(0.0);

	// Sheen (1) -> standing water (2) -> surface over the sunk well (3).
	float cover = mix(0.75 + 0.2 * (1.0 - a2), 1.0, a2);
	float inside = 1.0 - smoothstep(cover - 0.08, cover, d + 0.08 * (vnoise(lp * 4.0 + seed) - 0.5) * (1.0 - a2));
	over(acc, mix(glow.rgb, glow.rgb * 0.75, a2), inside * (0.4 + 0.25 * a2) * a1);

	// Deep: a floor 0.55 below the face seen through it; where the ray hits
	// the inner wall (outside the hex on the floor) draw the wall instead.
	if (a3 > 0.0) {
		float depth = 0.55 * a3;
		vec2 fp = sink(lp, wv, depth);
		float fd = hexd(fp / 0.93);
		float wall = smoothstep(0.96, 1.0, fd);
		float caust = fbm(fp * 3.0 + vec2(t * 0.15, -t * 0.1));
		vec3 floor_col = mix(deep, glow.rgb * 0.6, smoothstep(0.45, 0.75, caust) * 0.6);
		floor_col = mix(floor_col, deep * 0.6, smoothstep(0.4, 1.0, fd) * 0.7);
		vec3 wall_col = mix(glow.rgb * 0.55, deep, 0.4);
		over(acc, mix(floor_col, wall_col, wall), a3 * 0.85 * (1.0 - smoothstep(0.9, 0.97, d)));
	}

	// Ripples: 1 slow ring from a seeded point at tier 1; concentric rings
	// from the centre at 2; faster, harder rings at 3.
	vec2 c1 = vec2(hash11(seed) - 0.5, hash11(seed + 3.0) - 0.5) * 0.5;
	float ph1 = fract(t * 0.22);
	float ring1 = 1.0 - smoothstep(0.0, 0.045, abs(length(lp - c1) - ph1 * 0.85));
	over(acc, pale, ring1 * (1.0 - ph1) * 0.95 * a1 * (1.0 - a2) * inside);
	float rings = sin(r * (16.0 + 6.0 * a3) - t * (2.2 + 1.6 * a3));
	float rr = smoothstep(0.55 - 0.2 * a3, 0.98, rings) * (1.0 - smoothstep(0.55, 0.92, d));
	over(acc, pale, rr * (0.32 + 0.35 * a3) * a2);

	// Glint: a bright streak sweeping across.
	float sweep = fract(t * 0.13 + seed);
	float g = 1.0 - smoothstep(0.0, 0.06 + 0.04 * a2, abs(dot(lp, normalize(vec2(1.0, 0.6))) - (sweep * 2.6 - 1.3)));
	over(acc, vec3(1.0), g * 0.55 * inside * a1);

	// Foam line just inside the black border (2+), wobbling.
	float foam = 1.0 - smoothstep(0.0, 0.035, abs(d - 0.88 - 0.02 * sin(atan(lp.y, lp.x) * 7.0 + t * 1.5)));
	over(acc, vec3(1.0), foam * 0.8 * a2);
	// Dark lip under the foam, so the water edge reads on white.
	float lip = 1.0 - smoothstep(0.0, 0.03, abs(d - 0.92));
	over(acc, deep, lip * 0.55 * a1);

	vec3 col;
	float alpha;
	fx_out(acc, d, col, alpha);
	ALBEDO = col;
	ALPHA = alpha;
}
