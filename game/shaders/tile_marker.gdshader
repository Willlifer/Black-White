// Operator markers on empty ground (ELEMENTS §2.3, §4). One shader, one
// shared material per marker (`mode`):
//   0 fuse   (thunder): purple arcs crackling along the hex edges
//   1 gale   (wind):    green eddies swirling over the face
//   2 stasis (ice):     a pale cyan rime pattern, glinting
// `tier` is 0..1 here (the marker fading in/out); markers have no levels,
// except gale 2 (D102): the "gale2" material sets `gale_size` 1.0 -> a
// bigger, faster swirl that fills the hex, a fourth stroke and a gust ring.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

#include "res://shaders/tile_fx.gdshaderinc"

uniform int mode = 0;
uniform vec4 glow : source_color = vec4(0.608, 0.302, 1.0, 1.0);
uniform vec4 ink : source_color = vec4(0.2, 0.05, 0.35, 1.0);
uniform float gale_size = 0.0;     // D102: 0 = gale 1, 1 = gale 2

varying vec2 lp;

void vertex() {
	lp = VERTEX.xz;
}

// Signed distance-ish value to a jagged bolt running around the hex at
// hexd ~ base, re-rolled `rate` times a second.
float bolt(vec2 p, float d, float base, float t, float rate, float k) {
	float ang = atan(p.y, p.x);
	float step_t = floor(t * rate + k * 3.0);
	float jag = (vnoise(vec2(ang * 7.0 + k * 5.0, step_t * 1.7)) - 0.5) * 0.11
		+ (vnoise(vec2(ang * 23.0, step_t * 3.1 + k)) - 0.5) * 0.04;
	return abs(d - base - jag);
}

vec4 fuse(vec2 p, float d, float t) {
	vec4 acc = vec4(0.0);
	float ang = atan(p.y, p.x);
	// faint charged fill so the hex reads at a glance
	over(acc, glow.rgb, (0.38 + 0.08 * sin(t * 9.0)) * (1.0 - smoothstep(0.6, 0.95, d)));
	for (int i = 0; i < 2; i++) {
		float k = float(i);
		float b = bolt(p, d, 0.84 - 0.08 * k, t, 11.0 + 4.0 * k, k);
		// segments flicker on and off: the arc crawls around the rim
		float seg = step(0.42, vnoise(vec2(ang * 2.2 + t * (1.5 + k), floor(t * 9.0 + k * 4.0))));
		float halo = 1.0 - smoothstep(0.0, 0.08, b);
		float under = 1.0 - smoothstep(0.024, 0.045, b);
		float line = 1.0 - smoothstep(0.006, 0.016, b);
		over(acc, glow.rgb, halo * 0.6 * seg);
		over(acc, ink.rgb, under * 0.9 * seg);
		over(acc, mix(glow.rgb, vec3(1.0), 0.45), line * seg);
	}
	// an occasional arc jumping across the face
	float st = floor(t * 3.0);
	float jump = step(0.72, hash11(st + seed * 5.0));
	vec2 a = vec2(cos(hash11(st) * FX_TAU), sin(hash11(st) * FX_TAU)) * 0.8;
	vec2 dir = normalize(-a + vec2(hash11(st + 1.0) - 0.5, hash11(st + 2.0) - 0.5));
	float along = dot(p - a, dir);
	float perp = abs(dot(p - a, vec2(-dir.y, dir.x)) - (vnoise(vec2(along * 9.0, st)) - 0.5) * 0.14);
	float j = (1.0 - smoothstep(0.008, 0.024, perp)) * step(0.0, along) * step(along, 1.2);
	over(acc, vec3(1.0), j * jump * (1.0 - fract(t * 3.0)));
	// ink under-stroke on the rim so purple reads on white
	over(acc, ink.rgb, (1.0 - smoothstep(0.0, 0.025, abs(d - 0.93))) * 0.5);
	return acc;
}

vec4 gale(vec2 p, float d, float t) {
	vec4 acc = vec4(0.0);
	float r = length(p);
	float ang = atan(p.y, p.x);
	float g2 = gale_size;
	float spin = 1.0 + 0.45 * g2;
	// Three comma-shaped gust strokes orbiting the centre (gale 2: four,
	// wider, thicker and longer-tailed, out to the rim).
	for (int i = 0; i < 4; i++) {
		float k = float(i);
		if (i == 3 && g2 < 0.5) {
			break;
		}
		float rr = mix(0.32 + 0.22 * k, 0.26 + 0.2 * k, g2);
		float a0 = t * (1.6 - mix(0.35, 0.3, g2) * k) * spin + k * mix(2.1, 1.571, g2);
		float da = mod(ang - a0 + FX_TAU * 4.0, FX_TAU);         // 0 at the head, grows behind it
		float tail = 1.0 - smoothstep(0.0, 3.4 + 1.4 * g2, da);
		float spiral = rr - (0.05 + 0.02 * g2) * da;
		float w = 1.0 + 0.6 * g2;
		float line = 1.0 - smoothstep(0.03 * w, 0.03 * w + 0.02 + 0.02 * tail, abs(r - spiral));
		over(acc, ink.rgb, line * tail * 0.85);
		float core = 1.0 - smoothstep(0.012 * w, 0.028 * w, abs(r - spiral));
		over(acc, glow.rgb, core * tail);
	}
	// small eddies: curls drifting round
	for (int i = 0; i < 3; i++) {
		float k = float(i);
		float a = t * 0.7 * spin + k * 2.094;
		vec2 c = vec2(cos(a), sin(a)) * 0.62;
		vec2 q = p - c;
		float qr = length(q);
		float qa = atan(q.y, q.x) - t * 4.0;
		float curl = abs(qr - (0.03 + 0.025 * fract(qa / FX_TAU)));
		over(acc, ink.rgb, (1.0 - smoothstep(0.012, 0.03, curl)) * step(qr, 0.08));
		over(acc, glow.rgb, (1.0 - smoothstep(0.006, 0.016, curl)) * step(qr, 0.07));
	}
	if (g2 > 0.5) {
		// gale 2: a broken gust ring racing round the rim
		float seg = step(0.5, fract((ang / FX_TAU) * 5.0 - t * 1.3));
		float ring = 1.0 - smoothstep(0.02, 0.045, abs(d - 0.88));
		over(acc, ink.rgb, ring * seg);
		over(acc, glow.rgb, (1.0 - smoothstep(0.008, 0.02, abs(d - 0.88))) * seg);
	}
	over(acc, glow.rgb, (0.3 + 0.12 * g2) * (1.0 - smoothstep(0.55, 0.95, d)));
	return acc;
}

vec4 stasis(vec2 p, float d, float t) {
	vec4 acc = vec4(0.0);
	float r = length(p);
	// Fold into one 60-degree wedge, mirrored: a six-fold rime crystal.
	float ang = atan(p.y, p.x) + 0.5236;                   // spokes toward the corners
	float wedge = mod(ang, 1.0472) - 0.5236;
	vec2 q = vec2(cos(wedge), abs(sin(wedge))) * r;
	float spoke = q.y * step(0.18, q.x) * step(q.x, 0.8);
	float l = 1.0 - smoothstep(0.012, 0.03, spoke);
	// side branches every 0.14 along the spoke, at 60 degrees
	float bx = mod(q.x - 0.25, 0.14);
	float br = abs(q.y - (bx) * 1.15) ;
	float branch = (1.0 - smoothstep(0.01, 0.025, br)) * step(0.25, q.x) * step(q.x, 0.74) * step(bx, 0.09);
	float frost_n = smoothstep(0.62, 0.85, fbm(p * 8.0 + seed));
	float ring = 1.0 - smoothstep(0.0, 0.03, abs(d - 0.84));
	float lines = clamp(l + branch + ring, 0.0, 1.0);
	over(acc, glow.rgb, 0.16 * (1.0 - smoothstep(0.7, 0.95, d)) + frost_n * 0.25);
	// teal under-stroke, then the pale crystal
	float under = clamp((1.0 - smoothstep(0.02, 0.05, spoke)) * step(0.16, q.x) * step(q.x, 0.82) + ring, 0.0, 1.0);
	over(acc, ink.rgb, under * 0.75);
	over(acc, mix(glow.rgb, vec3(1.0), 0.5), lines);
	// glint sweeping across
	float gl = 1.0 - smoothstep(0.0, 0.08, abs(p.x + p.y * 0.4 - (fract(t * 0.18 + seed) * 3.0 - 1.5)));
	over(acc, vec3(1.0), gl * lines * 0.8);
	return acc;
}

void fragment() {
	if (tier <= 0.001) {
		discard;
	}
	float t = fx_time(TIME);
	float d = hexd(lp);
	vec4 acc = mode == 0 ? fuse(lp, d, t) : (mode == 1 ? gale(lp, d, t) : stasis(lp, d, t));
	acc *= t1();
	vec3 col;
	float alpha;
	fx_out(acc, d, col, alpha);
	ALBEDO = col;
	ALPHA = alpha;
}
