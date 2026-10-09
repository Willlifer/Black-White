// Fire, standing layer (billboard flame cards, see tile_cards.gdshaderinc).
//   1 Smouldering: two or three thin smoke wisps from the rim
//   2 Burning: low licking flames across the face
//   3 Blazing: tall flames standing off the tile, sparks rising off them
// Flames carry a thin dark rim, so they hold their shape against white tiles
// as well as the black sky (the project's ink-contour rule).
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

#include "res://shaders/tile_fx.gdshaderinc"

uniform vec4 glow : source_color = vec4(1.0, 0.353, 0.122, 1.0);

float flame_h(vec4 data, float t) {
	float a2 = t2();
	float a3 = t3();
	float var = 0.75 + 0.5 * hash11(data.z * 31.0);
	float lick = 0.88 + 0.12 * sin(t * (6.0 + 3.0 * hash11(data.z)) + data.z * 9.0);
	return (0.4 * a2 + 0.62 * a3) * data.y * var * lick;
}

float smoke_h(vec4 data) {
	float a1 = t1();
	float pick = step(hash11(data.z * 5.3), 0.45) * step(1.5, data.w);   // a few rim cards
	return 0.75 * a1 * (1.0 - t2()) * pick;
}

float card_height(vec4 data, float t) {
	float hf = flame_h(data, t) * (1.0 + 0.15 * clamp(tier - 3.0, 0.0, 1.0));   // D494: lava's flames stand taller than 3's
	return max(hf * (1.0 + 0.6 * t3()), smoke_h(data));
}

#include "res://shaders/tile_cards.gdshaderinc"

void vertex() {
	float t = fx_time(TIME);
	float h = card_height(CUSTOM0, t);
	VERTEX += card_offset(UV, CUSTOM0.x, INV_VIEW_MATRIX, h);
	cuv = vec2(UV.x * 2.0 - 1.0, UV.y);
	cdat = CUSTOM0;
	ch = h;
}

void fragment() {
	if (ch <= 0.001) {
		discard;
	}
	float t = fx_time(TIME);
	float w = cdat.x;
	float x = cuv.x * w * 0.5;            // world units across
	float y = cuv.y * ch;                 // world units up
	float hf = flame_h(cdat, t);
	float a3 = t3();
	vec3 hot = lin(vec3(1.0, 0.9, 0.42));
	vec3 deep = lin(vec3(0.7, 0.1, 0.02));
	vec4 acc = vec4(0.0);

	// Smoke wisps (tier 1 only, fading out as the flames come in).
	float hs = smoke_h(cdat);
	if (hs > 0.001) {
		float v = y / hs;
		float xw = x - sin(y * 8.0 - t * 2.2 + cdat.z * 5.0) * 0.07 * v - v * v * 0.06;
		float line = 1.0 - smoothstep(0.012, 0.03 + 0.05 * v, abs(xw));
		over(acc, lin(vec3(0.32, 0.31, 0.3)), line * (1.0 - v) * smoothstep(0.0, 0.1, v) * 0.85);
	}

	// Flames.
	if (hf > 0.001) {
		float v = y / hf;
		float sway = (vnoise(vec2(v * 2.5 - t * 2.4, cdat.z * 9.0)) - 0.5) * 0.7 * w * v;
		float xf = x + sway;
		float hw = 0.5 * w * (1.25 - 0.25 * a3) * pow(clamp(1.0 - v, 0.0, 1.0), 0.6) * (0.45 + 0.55 * smoothstep(0.0, 0.3, v));
		float n = fbm(vec2(xf * 6.0 / w + cdat.z * 3.0, y * 4.0 - t * 4.2));
		// erosion grows up the flame, splitting the top into licking tongues
		float m = hw - abs(xf) - (n - 0.42) * 0.5 * w * pow(v, 0.8);
		float body = smoothstep(0.0, 0.012, m);
		float core = smoothstep(hw * 0.35, hw * 0.75, m);
		vec3 c = mix(glow.rgb, hot, core);
		c = mix(c, deep, smoothstep(0.55, 1.0, v) * 0.6);
		float rim = body * (1.0 - smoothstep(0.006, 0.02, m));
		c = mix(c, lin(vec3(0.45, 0.06, 0.0)), rim * 0.9);
		float lava = clamp(tier - 3.0, 0.0, 1.0);   // D494: lava burns whiter, full strength (it read as fire 1)
		c = mix(c, hot, 0.35 * lava * (1.0 - v));
		over(acc, c, body * (0.9 - 0.25 * smoothstep(0.6, 1.0, v)));
	}

	// Sparks (tier 3): a few hot points rising above the flame tips.
	if (a3 > 0.0 && hf > 0.001) {
		for (int i = 0; i < 3; i++) {
			float k = float(i) + cdat.z * 7.0;
			float life = fract(t * (0.55 + 0.25 * hash11(k)) + hash11(k + 1.7));
			vec2 sp = vec2((hash11(k + 4.1) - 0.5) * w * 0.7 + sin(t * 3.0 + k) * 0.04,
				hf * 0.55 + life * (ch - hf * 0.55));
			float dd = length(vec2(x, y) - sp);
			float s = 1.0 - smoothstep(0.018, 0.034, dd);
			over(acc, mix(hot, glow.rgb, life), s * (1.0 - life) * a3);
		}
	}

	vec3 col;
	float alpha;
	fx_out(acc, 0.0, col, alpha);
	ALBEDO = col;
	ALPHA = alpha;
}
