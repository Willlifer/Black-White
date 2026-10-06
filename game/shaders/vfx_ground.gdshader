// D167-D169 cast and spectacle decals (BWVfxCasts). A flat disc on a
// PlaneMesh of size 2 (local -1..1 on XZ), scaled by the node to its radius.
// One shared material per (mode, element); per-node life in `age` (0..1) and
// a strength in `tier` (slot 3; the falling shadow's growth).
//   0 casting circle   ink rings, a rotating rune band on white, a hexagram in
//                      the element colour; draws itself on, then fades
//   1 shockwave ring   an inked white ring with an element trail, broken
//   2 falling shadow   an ink disc with a white rim and four reticle ticks,
//                      growing with `tier`
//   3 storm clouds     a swirling annulus of grey cloud with ink edges, white
//                      tops and element flickers (Tempest, overhead)
//   4 hex lay          the element laid on one hex: white flash, ripple, rim
//   5 spin trail       a sweeping 300-degree crescent (Whirlwind / Fan)
//   6 aura             rings rising out from the feet (War Cry)
// Never additive (it vanishes on white tiles): white, ink and the element hue
// composited with "over", like the tile FX (D82).
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

#include "res://shaders/tile_fx.gdshaderinc"

uniform int mode = 0;
uniform vec4 glow : source_color = vec4(1.0, 0.35, 0.18, 1.0);

varying vec2 lp;

float band(float d, float w, float fw) {
	return 1.0 - smoothstep(w * 0.5, w * 0.5 + fw, abs(d));
}

void vertex() {
	lp = VERTEX.xz;
}

void fragment() {
	float a = clamp(age, 0.0, 1.0);
	float r = length(lp);
	float ang = atan(lp.y, lp.x);
	float fw = max(fwidth(r) * 1.2, 0.004);
	vec3 white = vec3(1.0);
	vec3 ink = vec3(0.0);
	vec3 acc_c = glow.rgb;
	vec4 acc = vec4(0.0);
	if (mode == 0) {
		float vis = smoothstep(0.0, 0.1, a) * (1.0 - smoothstep(0.82, 1.0, a));
		float draw = clamp(a / 0.22, 0.0, 1.0);               // draws itself on, round the clock
		float an = fract(ang / FX_TAU + 0.25);
		float drawn = step(an, draw);
		float rot = TIME * 0.7 + seed * 6.0;
		float pulse = 0.75 + 0.25 * sin(TIME * 9.0) * tier;
		// a white ground so the linework reads on the dimmed board too
		over(acc, white, (1.0 - smoothstep(0.93, 0.93 + fw, r)) * 0.32);
		// the rune band: white strip, ink runes, counter-rotating
		float in_band = step(0.64, r) * step(r, 0.84);
		over(acc, white, in_band * 0.85 * drawn);
		float ga = ang - TIME * 1.3;
		float cells = 22.0;
		float cell = floor(fract(ga / FX_TAU) * cells);
		float cu = fract(fract(ga / FX_TAU) * cells);
		float cv = (r - 0.64) / 0.2;
		float h = hash11(cell + 3.1);
		float rune = 0.0;
		rune = max(rune, band(cu - 0.5, 0.12, 0.05) * step(0.18, cv) * step(cv, 0.82) * step(0.25, h));
		rune = max(rune, band(cv - 0.5, 0.1, 0.05) * step(0.2, cu) * step(cu, 0.8) * step(0.55, h));
		rune = max(rune, band(cv - 0.22 - 0.5 * fract(h * 7.0), 0.1, 0.05) * step(0.5, cu) * step(cu, 0.85) * step(h, 0.7));
		rune = max(rune, (1.0 - smoothstep(0.07, 0.11, length(vec2(cu - 0.3, cv - 0.75)))) * step(0.8, h));
		over(acc, ink, rune * in_band * drawn);
		// rings: ink outer, element, ink band edges, element inner
		over(acc, ink, band(r - 0.955, 0.05, fw) * drawn);
		over(acc, acc_c, band(r - 0.9, 0.04, fw) * drawn * pulse);
		over(acc, ink, (band(r - 0.64, 0.018, fw) + band(r - 0.84, 0.018, fw)) * drawn);
		over(acc, acc_c, band(r - 0.3, 0.035, fw) * drawn);
		// the hexagram: two triangles inscribed at 0.6, turning
		float tri = 1e3;
		for (int k = 0; k < 6; k++) {
			float th = rot + float(k) * FX_TAU / 6.0;
			vec2 n = vec2(cos(th), sin(th));
			tri = min(tri, abs(dot(lp, n) - 0.3));
		}
		float hexa = band(tri, 0.028, fw) * step(r, 0.6);
		over(acc, ink, band(tri, 0.06, fw) * step(r, 0.6) * drawn * 0.9);
		over(acc, acc_c, hexa * drawn);
		// six nodes on the outer ring
		for (int k = 0; k < 6; k++) {
			float th = rot + float(k) * FX_TAU / 6.0;
			vec2 c = vec2(cos(th), sin(th)) * 0.9;
			float d = length(lp - c);
			over(acc, ink, (1.0 - smoothstep(0.055, 0.055 + fw, d)) * drawn);
			over(acc, white, (1.0 - smoothstep(0.03, 0.03 + fw, d)) * drawn);
		}
		acc *= vis;
	} else if (mode == 1) {
		float R = 0.12 + 0.88 * pow(a, 0.5);
		float fade = pow(1.0 - a, 1.4);
		float gaps = step(0.22, vnoise(vec2(ang * 5.0 + seed * 9.0, 1.0)));
		float w = mix(0.14, 0.05, a);
		float d = r - R;
		over(acc, acc_c, (1.0 - smoothstep(0.0, 0.32, -d)) * step(d, 0.0) * 0.45 * fade);
		over(acc, ink, band(d - w * 0.55, w * 0.5, fw) * fade * gaps);
		over(acc, white, band(d, w * 0.7, fw) * fade * gaps);
		over(acc, acc_c, band(d + w * 0.55, w * 0.35, fw) * fade);
	} else if (mode == 2) {
		float g = clamp(tier, 0.0, 1.0);
		float R = mix(0.3, 0.92, g);
		float inside = 1.0 - smoothstep(R, R + fw, r);
		over(acc, ink, inside * mix(0.55, 0.85, g));
		over(acc, white, band(r - R, 0.025, fw) * g);
		over(acc, acc_c, band(r - R * 0.55, 0.02, fw) * g * 0.8);
		float tick = 0.0;
		for (int k = 0; k < 4; k++) {
			float th = float(k) * FX_TAU / 4.0 + TIME * 1.5;
			vec2 n = vec2(cos(th), sin(th));
			float along = dot(lp, n);
			float side = abs(dot(lp, vec2(-n.y, n.x)));
			tick = max(tick, (1.0 - smoothstep(0.02, 0.02 + fw, side)) * step(R + 0.04, along) * step(along, R + 0.2));
		}
		over(acc, ink, tick * g);
		acc *= 1.0 - smoothstep(0.85, 1.0, a);
	} else if (mode == 3) {
		float vis = smoothstep(0.0, 0.3, a) * (1.0 - smoothstep(0.85, 1.0, a));
		float outer = mix(1.35, 1.0, smoothstep(0.0, 0.45, a));
		float sw = TIME * 0.9 + r * 2.2;                       // swirl: inner turns faster
		vec2 p = vec2(cos(sw) * lp.x - sin(sw) * lp.y, sin(sw) * lp.x + cos(sw) * lp.y);
		float n = fbm(p * 2.6 + seed * 5.0);
		float ring = smoothstep(0.18, 0.42, r) * (1.0 - smoothstep(outer - 0.18, outer, r));
		float cloud = smoothstep(0.42, 0.5, n * ring + ring * 0.25);
		float edge = cloud * (1.0 - smoothstep(0.5, 0.6, n * ring + ring * 0.25));
		float top = smoothstep(0.55, 0.75, fbm(p * 2.6 + seed * 5.0 + vec2(0.06, 0.04)));
		over(acc, lin(vec3(0.2, 0.2, 0.22)), cloud * 0.92);
		over(acc, lin(vec3(0.62, 0.62, 0.66)), cloud * top * 0.8);
		over(acc, ink, edge);
		float flick = step(0.78, hash11(floor(TIME * 9.0) + floor(ang * 3.0)));
		over(acc, acc_c, cloud * flick * smoothstep(0.6, 0.7, n) * 0.9);
		acc *= vis;
	} else if (mode == 4) {
		float d = hexd(lp);
		float inside = 1.0 - smoothstep(0.92, 0.92 + fw, d);
		float flash = 1.0 - smoothstep(0.0, 0.25, a);
		float fade = 1.0 - smoothstep(0.55, 1.0, a);
		over(acc, acc_c, inside * 0.55 * fade);
		over(acc, white, inside * flash * 0.85);
		float R = a * 1.4;
		over(acc, white, band(d - R, 0.08, fw) * inside * fade);
		over(acc, ink, band(d - 0.86, 0.06, fw) * fade);
		over(acc, acc_c, band(d - 0.78, 0.04, fw) * fade);
	} else if (mode == 5) {
		float vis = 1.0 - smoothstep(0.8, 1.0, a);
		float head = a * FX_TAU * 1.2;
		float dir = seed > 0.5 ? 1.0 : -1.0;
		float an = mod(dir * (head - (ang + FX_TAU)), FX_TAU);   // 0 at the head, growing behind
		float trail = 1.0 - an / (FX_TAU * 0.85);
		float w = 0.08 + 0.2 * clamp(trail, 0.0, 1.0);
		float d = r - 0.86;
		float on = step(0.0, trail) * step(abs(d), w);
		float body = (1.0 - smoothstep(w - 0.04, w, abs(d))) * step(0.0, trail);
		over(acc, ink, on * clamp(trail * 1.4, 0.0, 1.0));
		over(acc, white, body * clamp(trail * 1.6, 0.0, 1.0));
		over(acc, acc_c, band(d + w * 0.35, w * 0.3, fw) * step(0.0, trail) * clamp(trail, 0.0, 1.0));
		acc *= vis;
	} else {
		float vis = smoothstep(0.0, 0.1, a) * (1.0 - smoothstep(0.7, 1.0, a));
		for (int k = 0; k < 3; k++) {
			float ph = fract(TIME * 1.3 - float(k) / 3.0);
			float R = 0.25 + 0.75 * ph;
			float f = 1.0 - ph;
			over(acc, ink, band(r - R - 0.035, 0.025, fw) * f);
			over(acc, acc_c, band(r - R, 0.05, fw) * f);
		}
		over(acc, white, (1.0 - smoothstep(0.32, 0.36, r)) * 0.4);
		over(acc, ink, band(r - 0.36, 0.02, fw));
		acc *= vis;
	}
	ALBEDO = acc.a > 0.0001 ? acc.rgb / acc.a : vec3(0.0);
	ALPHA = clamp(acc.a, 0.0, 1.0);
}
