// Light, tile face (ELEMENTS §4). Light yellow on white is the weakest read
// in the set, so the layer is saturated amber at its body and carries a faint
// dark ring at the rim (readability note).
//   1 First light: soft glow, slow breathing
//   2 Lightfall: bright glow, slow-turning rays
//   3 Pillar: hot white core under the column (tile_beam draws the column)
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

#include "res://shaders/tile_fx.gdshaderinc"

uniform vec4 glow : source_color = vec4(1.0, 0.784, 0.102, 1.0);

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
	vec3 amber = lin(vec3(0.93, 0.55, 0.02));
	vec3 white = lin(vec3(1.0, 0.98, 0.86));
	vec4 acc = vec4(0.0);

	float breathe = 0.85 + 0.15 * sin(t * (1.4 + 0.8 * a2));
	// Body: amber at the edge of the glow, yellow inward.
	float spread = mix(0.85, 1.05, a2);
	float body = 1.0 - smoothstep(0.0, spread, d);
	over(acc, mix(amber, glow.rgb, 0.55 + 0.45 * body), (0.8 + 0.12 * a2) * smoothstep(0.0, 0.3, body) * breathe * a1);

	// Rays (2+): twelve soft spokes turning slowly.
	float ang = atan(lp.y, lp.x);
	float rays = pow(0.5 + 0.5 * cos(ang * 6.0 + t * 0.35), 6.0) + pow(0.5 + 0.5 * cos(ang * 6.0 - t * 0.22 + 1.6), 10.0) * 0.6;
	over(acc, glow.rgb, rays * (1.0 - smoothstep(0.15, 0.95, d)) * 0.7 * a2);

	// Core (3): white-hot disc where the pillar stands.
	float core = 1.0 - smoothstep(0.18, 0.5, r);
	over(acc, white, core * 0.85 * a3 * (0.9 + 0.1 * sin(t * 6.0)));

	// The faint dark ring that makes yellow read on white.
	float ring = 1.0 - smoothstep(0.0, 0.035 + 0.01 * a2, abs(d - 0.86));
	over(acc, lin(vec3(0.5, 0.3, 0.0)), ring * (0.7 + 0.15 * a2) * a1);

	vec3 col;
	float alpha;
	fx_out(acc, d, col, alpha);
	ALBEDO = col;
	ALPHA = alpha;
}
