// D167-D169 element releases and flashes (BWVfxCasts). A QuadMesh of size 1
// billboarded in the vertex stage: around Y (columns: the pivot is the quad's
// bottom edge, on the ground) or fully (spheres, flashes: the pivot is the
// centre). The node's scale is the quad's size. Life in `age` (0..1).
//   0 fire      a column of flame: noisy tongues, ink rim, white core
//   1 water     a geyser: a striped jet with a bulging crown that falls back
//   2 ice       a spike burst: seven faceted spikes (white / ice) shooting up
//   3 thunder   a strike from above: a jagged bolt, white core, ground flash
//   4 wind      a cyclone: a funnel of sheared bands
//   5 light     a pillar: a hard-edged column, white core, rising rings
//   6 dark      a collapsing sphere: swells, implodes to a point, rings out
//   7 gleam     a four-point glint
//   8 flash     a spiky impact star with an ink rim
//   9 shout     concentric shout rings (War Cry)
//  10 pour      a thin falling stream (Saturate)
// Alpha-blended white / ink / element only, never additive (white tiles).
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled, skip_vertex_transform;

#include "res://shaders/tile_fx.gdshaderinc"

uniform int mode = 0;
uniform bool sphere = false;
uniform vec4 glow : source_color = vec4(1.0, 0.35, 0.18, 1.0);

varying vec2 q;

void vertex() {
	vec3 c = MODEL_MATRIX[3].xyz;
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 w;
	if (sphere) {
		w = c + INV_VIEW_MATRIX[0].xyz * VERTEX.x * sx + INV_VIEW_MATRIX[1].xyz * VERTEX.y * sy;
	} else {
		vec3 to_cam = CAMERA_POSITION_WORLD - c;
		to_cam.y = 0.0;
		vec3 right = length(to_cam) > 0.001 ? normalize(cross(vec3(0.0, 1.0, 0.0), to_cam)) : vec3(1.0, 0.0, 0.0);
		w = c + right * VERTEX.x * sx + vec3(0.0, 1.0, 0.0) * (VERTEX.y + 0.5) * sy;
	}
	q = VERTEX.xy + 0.5;
	VERTEX = (VIEW_MATRIX * vec4(w, 1.0)).xyz;
}

float band(float d, float w, float fw) {
	return 1.0 - smoothstep(w * 0.5, w * 0.5 + fw, abs(d));
}

void fragment() {
	float a = clamp(age, 0.0, 1.0);
	float x = q.x * 2.0 - 1.0;          // -1..1 across
	float y = q.y;                      // 0 bottom .. 1 top
	float fw = max(fwidth(x) * 1.5, 0.004);
	vec3 white = vec3(1.0);
	vec3 ink = vec3(0.0);
	vec3 ac = glow.rgb;
	vec4 acc = vec4(0.0);
	float t = TIME + seed * 17.0;
	if (mode == 0) {
		float rise = smoothstep(0.0, 0.22, a);
		float thin = 1.0 - smoothstep(0.62, 1.0, a);
		float n = fbm(vec2(x * 2.2, y * 3.2 - t * 3.6));
		float n2 = vnoise(vec2(x * 5.0 + 3.0, y * 6.0 - t * 5.0));
		float top = rise * (0.72 + 0.3 * n2) * mix(1.0, 0.7, 1.0 - thin);
		float w = mix(0.62, 0.1, y) * (0.7 + 0.6 * n) * (0.35 + 0.65 * thin) * (1.0 + 0.4 * (1.0 - smoothstep(0.0, 0.12, y)));
		float tongue = 1.0 - smoothstep(top - 0.1, top, y + 0.12 * abs(x) / max(w, 0.01));
		float body = (1.0 - smoothstep(w - fw, w, abs(x))) * tongue;
		float core = (1.0 - smoothstep(w * 0.42 - fw, w * 0.42, abs(x))) * (1.0 - smoothstep(top * 0.5, top * 0.68, y));
		float rim = body * (1.0 - (1.0 - smoothstep(w - 0.11, w - 0.1, abs(x))) * (1.0 - smoothstep(top - 0.16, top - 0.1, y + 0.12 * abs(x) / max(w, 0.01))));
		over(acc, ac, body);
		over(acc, lin(vec3(1.0, 0.86, 0.4)), core * 0.85);
		over(acc, white, core * smoothstep(0.35, 0.0, y) * 0.9);
		over(acc, ink, rim);
	} else if (mode == 1) {
		float up = smoothstep(0.0, 0.2, a);
		float down = smoothstep(0.55, 1.0, a);
		float top = 0.92 * up * (1.0 - 0.75 * down);
		float w = 0.26 + 0.04 * sin(y * 24.0 - t * 14.0) + 0.3 * (1.0 - smoothstep(0.0, 0.14, y));
		float col = (1.0 - smoothstep(w - fw, w, abs(x))) * step(y, top);
		float crown_r = 0.28 + 0.06 * vnoise(vec2(atan(y - top, x) * 3.0, t * 4.0));
		float crown = (1.0 - smoothstep(crown_r - fw, crown_r, length(vec2(x * 1.0, (y - top) * 2.2)))) * up * (1.0 - down);
		float body = max(col, crown);
		float stripes = step(0.62, fract(y * 5.0 - t * 5.0 + x * 0.6)) * col;
		float edge = body * (1.0 - (1.0 - smoothstep(w - 0.1, w - 0.09, abs(x))) * step(y, top) * (1.0 - crown) - (1.0 - smoothstep(crown_r - 0.1, crown_r - 0.09, length(vec2(x, (y - top) * 2.2)))) * crown);
		over(acc, ac, body);
		over(acc, white, stripes * 0.9);
		over(acc, white, crown * (1.0 - smoothstep(0.0, 0.18, length(vec2(x + 0.08, (y - top) * 2.2 - 0.07)))));
		over(acc, ink, clamp(edge, 0.0, 1.0));
		acc *= 1.0 - smoothstep(0.85, 1.0, a);
	} else if (mode == 2) {
		float shatter = smoothstep(0.7, 0.95, a);
		for (int i = 0; i < 7; i++) {
			float fi = float(i);
			float hb = hash11(fi * 3.7 + seed * 11.0);
			float bx = (fi - 3.0) * 0.1;
			float tx = (fi - 3.0) * 0.27 + (hb - 0.5) * 0.12;
			float h = mix(0.45, 0.95, hash11(fi * 1.3 + 2.0)) * (i == 3 ? 1.05 : 1.0);
			float grow = smoothstep(fi * 0.012, fi * 0.012 + 0.12, a);
			h *= grow;
			float wb = 0.13;
			float tt = y / max(h, 0.001);
			float cx = mix(bx, tx, tt);
			float half_w = wb * (1.0 - tt);
			float dx = x - cx;
			float inside = step(abs(dx), half_w) * step(y, h) * step(0.001, h);
			float broken = step(shatter, vnoise(vec2(x * 14.0, y * 14.0) + fi));
			inside *= broken;
			float rimw = 0.028;
			float rim = inside * (1.0 - step(abs(dx), half_w - rimw * (1.0 - tt * 0.6)));
			over(acc, dx < 0.0 ? white : ac, inside);
			over(acc, ink, max(rim, inside * band(dx, 0.012, fw) * 0.7));
		}
		acc *= 1.0 - smoothstep(0.8, 1.0, a);
	} else if (mode == 3) {
		float reveal = smoothstep(1.0 - clamp(a / 0.12, 0.0, 1.0) - 0.02, 1.0 - clamp(a / 0.12, 0.0, 1.0), y);
		float fl = step(0.25, hash11(floor(t * 22.0)));
		float fade = (1.0 - smoothstep(0.35, 0.75, a)) * mix(0.55, 1.0, fl);
		float seg = y * 9.0;
		float s0 = floor(seg);
		float roll = floor(t * 12.0);
		float j0 = (hash11(s0 + roll * 7.0) - 0.5) * 0.55;
		float j1 = (hash11(s0 + 1.0 + roll * 7.0) - 0.5) * 0.55;
		float cx = mix(j0, j1, fract(seg)) * smoothstep(0.0, 0.15, y);
		float d = abs(x - cx);
		// a branch off the main bolt, upper half
		float bc = cx + (y - 0.55) * 0.9;
		float db = abs(x - bc) + step(y, 0.55) * 10.0 + step(0.8, y) * 10.0;
		over(acc, ink, (1.0 - smoothstep(0.1, 0.1 + fw, min(d, db + 0.03))) * reveal * fade);
		over(acc, ac, (1.0 - smoothstep(0.075, 0.075 + fw, min(d, db + 0.03))) * reveal * fade);
		over(acc, white, (1.0 - smoothstep(0.03, 0.03 + fw, d)) * reveal * fade);
		float g = length(vec2(x, y * 9.0));
		float gf = (1.0 - smoothstep(0.0, 0.5, a)) * step(0.1, a);
		over(acc, ac, (1.0 - smoothstep(0.55, 0.6, g)) * gf * 0.8);
		over(acc, white, (1.0 - smoothstep(0.3, 0.34, g)) * gf);
	} else if (mode == 4) {
		float rise = smoothstep(0.0, 0.25, a);
		float vis = 1.0 - smoothstep(0.75, 1.0, a);
		float top = rise;
		float w = (0.14 + 0.8 * pow(y, 1.25)) * (0.85 + 0.15 * sin(t * 6.0 + y * 8.0));
		float sway = sin(y * 4.0 + t * 3.0) * 0.08 * y;
		float xs = x - sway;
		float inside = (1.0 - smoothstep(w - fw, w, abs(xs))) * step(y, top);
		float s = clamp(xs / max(w, 0.01), -1.0, 1.0);
		float ph = asin(s) * 1.4 + y * 9.0 - t * 10.0;
		float bands = smoothstep(0.1, 0.25, sin(ph)) * (1.0 - smoothstep(0.6, 0.8, sin(ph)));
		float lines = band(sin(ph) - 0.12, 0.1, 0.06);
		over(acc, white, inside * 0.55);
		over(acc, ac, inside * bands);
		over(acc, ink, inside * lines);
		over(acc, ink, inside * smoothstep(w - 0.07, w - 0.06, abs(xs)));
		acc *= vis;
	} else if (mode == 5) {
		float open = smoothstep(0.0, 0.14, a) * (1.0 - smoothstep(0.7, 1.0, a));
		float w = 0.5 * open * (1.0 + 0.3 * (1.0 - smoothstep(0.0, 0.1, y)));
		float top_fade = 1.0 - smoothstep(0.55, 1.0, y);
		float inside = 1.0 - smoothstep(w - fw, w, abs(x));
		float core = 1.0 - smoothstep(w * 0.45 - fw, w * 0.45, abs(x));
		float rings = band(fract(y * 4.0 - t * 1.4) - 0.5, 0.08, 0.04) * inside;
		over(acc, ac, inside * 0.9 * top_fade);
		over(acc, white, core * top_fade);
		over(acc, white, rings * top_fade * 0.7);
		over(acc, ink, inside * smoothstep(w - 0.07, w - 0.06, abs(x)) * top_fade);
		float base = length(vec2(x, y * 7.0));
		over(acc, white, (1.0 - smoothstep(0.5, 0.56, base)) * (1.0 - smoothstep(0.0, 0.4, a)));
	} else if (mode == 6) {
		vec2 p = q * 2.0 - 1.0;
		float r = length(p);
		float R = a < 0.35 ? 0.62 * smoothstep(0.0, 0.35, a) : (a < 0.55 ? 0.62 + 0.03 * sin(t * 30.0) : 0.62 * (1.0 - smoothstep(0.55, 0.72, a)));
		float inside = 1.0 - smoothstep(R - fw, R, r);
		float ang = atan(p.y, p.x);
		float sw = fbm(vec2(ang * 1.5 + r * 4.0 - t * 3.0, r * 3.0 + t));
		over(acc, ink, inside);
		over(acc, ac, inside * smoothstep(0.45, 0.65, sw));
		over(acc, white, band(r - R, 0.05, fw) * step(0.02, R));
		over(acc, ac, band(r - R - 0.05, 0.03, fw) * step(0.02, R));
		float burst = smoothstep(0.7, 0.74, a);
		float Rb = (a - 0.72) * 3.2;
		float fb = 1.0 - smoothstep(0.75, 1.0, a);
		over(acc, white, (1.0 - smoothstep(0.0, 0.12, r)) * burst * (1.0 - smoothstep(0.72, 0.82, a)));
		over(acc, ink, band(r - Rb - 0.04, 0.03, fw) * burst * fb);
		over(acc, ac, band(r - Rb, 0.06, fw) * burst * fb);
	} else if (mode == 7) {
		vec2 p = q * 2.0 - 1.0;
		float s = sin(a * 3.14159);
		float rot = a * 1.2;
		p = vec2(cos(rot) * p.x - sin(rot) * p.y, sin(rot) * p.x + cos(rot) * p.y) / max(s, 0.05);
		float star = min(abs(p.x) * 7.0 + abs(p.y), abs(p.y) * 7.0 + abs(p.x));
		float star2 = min(abs(p.x + p.y) * 9.0 + abs(p.x - p.y), abs(p.x - p.y) * 9.0 + abs(p.x + p.y)) * 1.6;
		over(acc, ink, 1.0 - smoothstep(0.95, 1.05, min(star, star2)));
		over(acc, ac, 1.0 - smoothstep(0.75, 0.85, min(star, star2 * 1.1)));
		over(acc, white, 1.0 - smoothstep(0.5, 0.58, star));
	} else if (mode == 8) {
		vec2 p = q * 2.0 - 1.0;
		float r = length(p);
		float ang = atan(p.y, p.x);
		float spikes = 0.42 + 0.58 * pow(abs(cos(ang * 4.0 + seed * 7.0)), 8.0) + 0.22 * pow(abs(sin(ang * 3.0 + seed * 3.0)), 10.0);
		float edge = spikes * (0.9 - 0.25 * a) * smoothstep(0.0, 0.12, a + 0.04);
		float inside = 1.0 - smoothstep(edge - fw, edge, r);
		float hole = (1.0 - smoothstep(max((a - 0.45) * 1.8, 0.0) - fw, max((a - 0.45) * 1.8, 0.0), r)) * step(0.45, a);
		float body = inside * (1.0 - hole);
		over(acc, ink, body);
		over(acc, ac, body * (1.0 - smoothstep(edge * 0.82 - fw, edge * 0.82, r)));
		over(acc, white, body * (1.0 - smoothstep(edge * 0.55 - fw, edge * 0.55, r)));
		acc *= 1.0 - smoothstep(0.75, 1.0, a);
	} else if (mode == 9) {
		vec2 p = q * 2.0 - 1.0;
		float r = length(p);
		for (int k = 0; k < 3; k++) {
			float R = a * 1.1 - float(k) * 0.2;
			float f = step(0.0, R) * (1.0 - smoothstep(0.5, 1.0, a));
			over(acc, ink, band(r - R - 0.045, 0.035, fw) * f);
			over(acc, white, band(r - R, 0.06, fw) * f);
			over(acc, ac, band(r - R + 0.045, 0.025, fw) * f);
		}
	} else {
		float head = clamp(a / 0.18, 0.0, 1.0);
		float tail = smoothstep(0.7, 1.0, a);
		float on = step(1.0 - head, y) * step(tail, y);
		float w = 0.22 + 0.06 * sin(y * 30.0 - t * 18.0);
		float inside = (1.0 - smoothstep(w - fw, w, abs(x))) * on;
		over(acc, ac, inside);
		over(acc, white, inside * band(x + w * 0.35, w * 0.3, 0.05) * 0.9);
		over(acc, ink, inside * smoothstep(w - 0.13, w - 0.12, abs(x)));
	}
	ALBEDO = acc.a > 0.0001 ? acc.rgb / acc.a : vec3(0.0);
	ALPHA = clamp(acc.a, 0.0, 1.0);
}
