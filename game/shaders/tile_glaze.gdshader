// Ice glaze (ELEMENTS §2.4, §4): a frost sheet laid over a charged tile's
// glow layers (which BWBoardView dims to ~60 % and slows via `frost`).
//   `age` 0..1: the sheet forming, frost spreading out from the centre with
//               a crystalline front (the one-shot "glaze forming" event)
//   `crack` 0..1: the glaze's last cycle, dark cracks branch across it
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

#include "res://shaders/tile_fx.gdshaderinc"

uniform vec4 glow : source_color = vec4(0.749, 0.957, 1.0, 1.0);
uniform vec4 ink : source_color = vec4(0.06, 0.4, 0.5, 1.0);

varying vec2 lp;

void vertex() {
	lp = VERTEX.xz;
}

// Voronoi: x = distance to the nearest cell edge, y = cell id.
vec2 voro(vec2 p) {
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	float id = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = vec2(hash21(ip + g), hash21(ip + g + 19.1));
			float dd = length(g + o - fp);
			if (dd < d1) {
				d2 = d1;
				d1 = dd;
				id = hash21(ip + g + 7.7);
			} else if (dd < d2) {
				d2 = dd;
			}
		}
	}
	return vec2(d2 - d1, id);
}

void fragment() {
	if (tier <= 0.001) {
		discard;
	}
	float t = TIME + seed * 13.7;
	float d = hexd(lp);
	float r = length(lp);
	vec4 acc = vec4(0.0);
	// forming front: a ragged frost edge growing from the centre
	float form = clamp(age, 0.0, 1.0);
	float front = form * 1.25 - r - 0.12 * (vnoise(lp * 9.0) - 0.5);
	float cov = smoothstep(0.0, 0.05, front);
	float front_line = (1.0 - smoothstep(0.0, 0.05, abs(front))) * step(form, 0.999);

	vec2 v = voro(lp * 4.2 + seed);
	float facet = 0.35 + 0.25 * v.y;
	over(acc, mix(glow.rgb, vec3(1.0), facet), (0.22 + 0.1 * v.y) * cov);
	// pale facet edges and heavier rime at the rim
	float edge = 1.0 - smoothstep(0.0, 0.05, v.x);
	over(acc, vec3(1.0), edge * 0.75 * cov);
	float rime = smoothstep(0.72, 0.95, d + 0.1 * (fbm(lp * 7.0) - 0.5));
	over(acc, lin(vec3(0.95, 0.99, 1.0)), rime * 0.55 * cov);
	over(acc, ink.rgb, (1.0 - smoothstep(0.0, 0.025, abs(d - 0.92))) * 0.55 * cov);
	over(acc, vec3(1.0), front_line * 0.9);

	// Last cycle: cracks along a coarser voronoi, flickering slightly.
	if (crack > 0.0) {
		vec2 cv = voro(lp * 2.3 + seed * 3.0);
		float c = 1.0 - smoothstep(0.0, 0.035, cv.x);
		float spokes = 1.0 - smoothstep(0.0, 0.02, abs(sin(atan(lp.y, lp.x) * 3.0 + seed * 4.0)) * r);
		float lines = clamp(c * smoothstep(0.15, 0.5, r) + spokes * step(r, 0.55), 0.0, 1.0);
		over(acc, ink.rgb * 0.5, lines * crack * cov * (0.8 + 0.2 * sin(t * 5.0)));
	}

	// glint
	float gl = 1.0 - smoothstep(0.0, 0.07, abs(lp.x * 0.8 + lp.y - (fract(t * 0.12) * 3.4 - 1.7)));
	over(acc, vec3(1.0), gl * 0.6 * cov);

	acc *= t1();
	vec3 col;
	float alpha;
	vec4 a2 = acc;
	// glaze itself is never dimmed by `frost`
	float a = a2.a * (1.0 - smoothstep(0.985, 1.0, d));
	col = (a2.a > 0.0001 ? a2.rgb / a2.a : vec3(0.0)) * (1.0 - 0.9 * dim);
	alpha = clamp(a * (1.0 - 0.85 * dim), 0.0, 1.0);
	ALBEDO = col;
	ALPHA = alpha;
}
