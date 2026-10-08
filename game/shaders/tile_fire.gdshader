// Fire, tile face (ELEMENTS §4). Tier reads through size and motion:
//   1 Smouldering: soot creeping in from the rim, embers pulsing in it
//   2 Burning: a heat bed licks across the whole face, embers drift
//   3 Blazing: white-hot core, the bed churns fast
//   4-5 Lava (D447, a Lava Walker's only): a basalt crust with molten seams
// The standing flames and smoke live on the flame cards (tile_flame).
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

#include "res://shaders/tile_fx.gdshaderinc"

uniform vec4 glow : source_color = vec4(1.0, 0.353, 0.122, 1.0);

varying vec2 lp;

void vertex() {
	lp = VERTEX.xz;
}

void fragment() {
	float a1 = t1();
	float a2 = t2();
	float a3 = t3();
	float t = fx_time(TIME);
	float d = hexd(lp);
	if (tier <= 0.001) {
		discard;
	}
	vec3 hot = lin(vec3(1.0, 0.86, 0.36));
	vec3 deep = lin(vec3(0.62, 0.08, 0.03));
	vec4 acc = vec4(0.0);

	// Soot / char: the scorch spreads inward from the rim with tier.
	float n = fbm(lp * 3.1 + seed * 3.0);
	float reach = 0.7 - 0.28 * a2 - 0.3 * a3;
	float soot = smoothstep(reach, reach + 0.25, d + 0.22 * (n - 0.5));
	over(acc, lin(vec3(0.1, 0.08, 0.07)), soot * (0.55 + 0.2 * a2) * a1);

	// Heat bed (tier 2+): flowing fbm, brighter toward the centre at 3.
	vec2 flow = lp * 2.4 + vec2(0.0, -t * (0.55 + 0.9 * a3));
	float bed = fbm(flow + fbm(lp * 1.7 - t * 0.2) * 1.6);
	float core = 1.0 - smoothstep(0.0, 0.85, d);
	float heat = clamp(bed * 1.25 - 0.18 + core * 0.35 * a3, 0.0, 1.0);
	vec3 bed_col = mix(deep, glow.rgb, smoothstep(0.25, 0.6, heat));
	bed_col = mix(bed_col, hot, smoothstep(0.62, 0.95, heat) * (0.4 + 0.6 * a3));
	over(acc, bed_col, a2 * (0.7 + 0.25 * a3) * smoothstep(0.12, 0.42, heat));

	// Embers: hot cells, in the rim band at tier 1, everywhere above.
	vec2 ep = lp * (9.0 + 3.0 * a3) + vec2(seed * 7.0, -t * 0.35);
	float cell = vnoise(ep);
	float flick = 0.55 + 0.45 * sin(t * (5.0 + 4.0 * a3) + cell * 23.0);
	float band = mix(smoothstep(0.55, 0.85, d), 1.0, a2);
	float ember = smoothstep(0.66 - 0.08 * a2, 0.8, cell) * flick * band;
	over(acc, mix(glow.rgb, hot, flick * 0.6), ember * (0.95) * a1);

	// Rim glow line along the inner border: the tile reads as "lit" at any size.
	float rim = smoothstep(0.72, 0.86, d) * (1.0 - smoothstep(0.93, 0.99, d));
	over(acc, glow.rgb, rim * (0.75 + 0.25 * a2) * (0.7 + 0.3 * sin(t * 3.0 + d * 9.0)) * a1);

	// D447 Lava (a Lava Walker's fire 4 and 5): a black basalt crust plates
	// over the bed, molten seams glow through it, wider and whiter at 5, with
	// slow bubbles rising.
	float a4 = clamp(tier - 3.0, 0.0, 1.0);
	float a5 = clamp(tier - 4.0, 0.0, 1.0);
	if (a4 > 0.001) {
		vec2 cp = lp * 3.0 + seed * 11.0;
		float plate = fbm(cp + vec2(0.0, t * 0.04));
		float seam = abs(plate - 0.5);
		float sw = 0.045 + 0.07 * a5;
		float molten = 1.0 - smoothstep(sw, sw + 0.05, seam);
		float inner = 1.0 - smoothstep(0.86, 0.97, d);
		over(acc, lin(vec3(0.045, 0.03, 0.028)), a4 * 0.9 * (1.0 - molten) * inner);
		float pulse = 0.7 + 0.3 * sin(t * 2.0 + plate * 14.0);
		vec3 mcol = mix(glow.rgb, hot, 0.35 + 0.65 * a5);
		over(acc, mcol, molten * a4 * pulse * inner);
		float bub = smoothstep(0.8, 0.88, vnoise(lp * 6.0 + vec2(seed * 3.0, -t * 0.5))) * a5 * inner;
		over(acc, lin(vec3(1.0, 0.93, 0.66)), bub);
		over(acc, glow.rgb, rim * a4 * 0.9);
	}

	vec3 col;
	float alpha;
	fx_out(acc, d, col, alpha);
	ALBEDO = col;
	ALPHA = alpha;
}
