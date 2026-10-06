// Dark, tile face (ELEMENTS §4): sinking and swirling.
//   1 Gloaming: a faint swirl at the centre
//   2 Deep shadow: a slow vortex over the face, the edges darkening inward
//   3 Abyss: the face sinks into a black-violet funnel (parallax layers);
//      tendrils at the rim are drawn by the tendril cards (tile_tendril)
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

#include "res://shaders/tile_fx.gdshaderinc"

uniform vec4 glow : source_color = vec4(0.165, 0.09, 0.27, 1.0);

varying vec2 lp;

void vertex() {
	lp = VERTEX.xz;
}

float swirl(vec2 p, float t, float arms, float twist) {
	float r = length(p) + 1e-4;
	float a = atan(p.y, p.x);
	float s = sin(a * arms + log(r) * twist + t);
	float n = fbm(p * 3.0 + vec2(t * 0.1, 0.0));
	return smoothstep(-0.1, 0.9, s + (n - 0.5) * 0.8);
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
	vec3 violet = lin(vec3(0.42, 0.25, 0.72));
	vec3 black = lin(vec3(0.02, 0.0, 0.05));
	vec4 acc = vec4(0.0);

	float spin = t * (0.45 + 0.35 * a3);
	// Gloaming swirl, centred, growing outward with tier.
	// Blending is linear, so a shadow needs real opacity to read dark on a
	// white tile: the pool is near-opaque and the swirl is drawn as lighter
	// violet arms on it, not as holes in it.
	float reach = mix(0.5, 1.15, a2);
	float sw = swirl(lp, spin * 2.0, 3.0, 4.0);
	float disc = 1.0 - smoothstep(reach * 0.45, reach, mix(r, d, a2));
	over(acc, glow.rgb, disc * mix(0.62, 0.93, a2) * a1);
	over(acc, violet, disc * smoothstep(0.55, 1.0, sw) * (0.55 - 0.15 * a3) * a1);
	over(acc, black, disc * smoothstep(0.45, 0.0, sw) * 0.5 * a2);

	// Edges darkening inward (2+): an ink band creeping from the rim.
	float creep = 0.62 - 0.12 * a3 + 0.05 * sin(atan(lp.y, lp.x) * 5.0 + t * 0.6);
	float edge = smoothstep(creep, 0.95, d + 0.1 * (fbm(lp * 4.0 - t * 0.15) - 0.5));
	over(acc, black, edge * 0.9 * a2);

	// Abyss (3): three swirl layers seen at increasing depth, each darker
	// and smaller, so the centre reads as a funnel falling away.
	if (a3 > 0.0) {
		for (int i = 1; i <= 3; i++) {
			float k = float(i);
			vec2 sp = sink(lp, wv, 0.22 * k * a3);
			float rr = length(sp);
			float s = swirl(sp * (1.0 + 0.4 * k), spin * (2.0 + k), 3.0, 5.0 + k);
			float hole = 1.0 - smoothstep(0.15, 0.75 - 0.15 * k, rr);
			vec3 c = mix(violet * (0.9 - 0.25 * k), black, 0.25 + 0.25 * k);
			over(acc, mix(c, black, s * 0.6), hole * 0.9 * a3);
		}
		over(acc, black, (1.0 - smoothstep(0.0, 0.28, length(sink(lp, wv, 0.75)))) * a3);
	}

	// Violet lip at the rim, so a dark tile separates from the black border.
	float lip = 1.0 - smoothstep(0.0, 0.03, abs(d - 0.88));
	over(acc, violet, lip * (0.5 + 0.4 * a2) * a1);

	vec3 col;
	float alpha;
	fx_out(acc, d, col, alpha);
	ALBEDO = col;
	ALPHA = alpha;
}
