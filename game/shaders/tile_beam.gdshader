// Light, standing layer (billboard cards, see tile_cards.gdshaderinc).
//   2 Lightfall: motes rising off the face
//   3 Pillar: a column of light from the centre card, streaks climbing it,
//     amber-edged so it still reads against the white tiles behind it
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

#include "res://shaders/tile_fx.gdshaderinc"

uniform vec4 glow : source_color = vec4(1.0, 0.784, 0.102, 1.0);

float card_height(vec4 data) {
	if (data.w < 0.5) {
		return 3.2 * t3() + 0.9 * t2();          // the centre card: column (and motes below it)
	}
	return (0.75 + 0.35 * hash11(data.z * 3.0)) * (t2() + 0.5 * t3());
}

#include "res://shaders/tile_cards.gdshaderinc"

void vertex() {
	float h = card_height(CUSTOM0);
	// the centre card widens into the column
	float w = CUSTOM0.w < 0.5 ? mix(CUSTOM0.x, 1.35, t3()) : CUSTOM0.x;
	VERTEX += card_offset(UV, w, INV_VIEW_MATRIX, h);
	cuv = vec2(UV.x * 2.0 - 1.0, UV.y);
	cdat = vec4(w, CUSTOM0.yzw);
	ch = h;
}

void fragment() {
	if (ch <= 0.001) {
		discard;
	}
	float t = fx_time(TIME);
	float a2 = t2();
	float a3 = t3();
	float w = cdat.x;
	float x = cuv.x * w * 0.5;
	float y = cuv.y * ch;
	vec3 amber = lin(vec3(0.9, 0.5, 0.0));
	vec3 white = lin(vec3(1.0, 0.98, 0.85));
	vec4 acc = vec4(0.0);

	if (cdat.w < 0.5 && a3 > 0.0) {
		// Column: soft body, white core, climbing streaks, fades at the top.
		float ax = abs(cuv.x);
		float body = 1.0 - smoothstep(0.55, 0.95, ax);
		float core = 1.0 - smoothstep(0.0, 0.35, ax);
		float streak = smoothstep(0.55, 0.9, vnoise(vec2(cuv.x * 7.0 + seed, y * 0.9 - t * 1.6)));
		float fade = (1.0 - smoothstep(0.35, 1.0, cuv.y)) * smoothstep(0.0, 0.04, cuv.y);
		vec3 c = mix(glow.rgb, white, core * 0.85 + streak * 0.3);
		over(acc, c, (body * 0.5 + core * 0.35 + streak * body * 0.2) * fade * a3);
		float edge = (1.0 - smoothstep(0.0, 0.06, abs(ax - 0.86))) * fade;
		over(acc, amber * 0.8, edge * 0.55 * a3);
	}

	// Motes: small rising diamonds, a few per card.
	if (a2 > 0.0) {
		for (int i = 0; i < 3; i++) {
			float k = float(i) * 3.1 + cdat.z * 11.0;
			float life = fract(t * (0.28 + 0.12 * hash11(k)) + hash11(k + 2.0));
			vec2 mp = vec2((hash11(k + 5.0) - 0.5) * w * 0.8 + sin(t * 1.3 + k) * 0.05, life * ch * 0.95);
			vec2 q = abs(vec2(x, y) - mp);
			float dm = q.x + q.y * 0.7;
			float sz = 0.035 + 0.015 * a3;
			float m = 1.0 - smoothstep(sz * 0.6, sz, dm);
			float ink = (1.0 - smoothstep(sz, sz + 0.012, dm)) - m;
			float f = sin(life * 3.14159);
			over(acc, amber * 0.55, ink * f * 0.7 * a2);
			over(acc, mix(white, glow.rgb, 0.4), m * f * a2);
		}
	}

	vec3 col;
	float alpha;
	fx_out(acc, 0.0, col, alpha);
	ALBEDO = col;
	ALPHA = alpha;
}
