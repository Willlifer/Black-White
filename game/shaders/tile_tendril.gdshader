// Dark, standing layer (billboard cards on the rim, see tile_cards.gdshaderinc).
//   3 Abyss: black-violet tendrils rise from the rim and curl back toward
//     the funnel. Nothing stands up below tier 3 (tier 1 hugs the tile).
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

#include "res://shaders/tile_fx.gdshaderinc"

uniform vec4 glow : source_color = vec4(0.165, 0.09, 0.27, 1.0);

float card_height(vec4 data) {
	if (data.w < 1.5) {
		return 0.0;
	}
	return (0.42 + 0.3 * hash11(data.z * 7.0)) * t3();
}

#include "res://shaders/tile_cards.gdshaderinc"

void vertex() {
	float h = card_height(CUSTOM0);
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
	float x = cuv.x * w * 0.5;
	float v = cuv.y;
	vec3 violet = lin(vec3(0.45, 0.26, 0.78));
	vec4 acc = vec4(0.0);
	float side = hash11(cdat.z * 13.0) < 0.5 ? -1.0 : 1.0;
	for (int i = 0; i < 2; i++) {
		float k = float(i);
		float ph = t * (1.1 + 0.4 * k) + cdat.z * 6.0 + k * 2.0;
		float bend = sin(v * 7.0 - ph) * 0.06 * v + side * v * v * 0.16 * (0.8 + 0.2 * sin(ph * 0.5));
		float xt = x - bend - (k - 0.5) * 0.08;
		float hw = 0.055 * (1.0 - v) * (1.0 - 0.3 * k) + 0.006;
		float m = hw - abs(xt);
		float body = smoothstep(0.0, 0.01, m);
		float lip = body * (1.0 - smoothstep(0.004, 0.018, m));
		vec3 c = mix(lin(vec3(0.03, 0.0, 0.07)), violet, lip * 0.8);
		over(acc, c, body * (0.95 - 0.5 * v));
	}
	vec3 col;
	float alpha;
	fx_out(acc, 0.0, col, alpha);
	ALBEDO = col;
	ALPHA = alpha;
}
