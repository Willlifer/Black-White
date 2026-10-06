// Shared helpers for the tile FX set (tile_*.gdshader, D82).
//
// Every tile FX layer is unlit and alpha-blended (never additive: additive
// vanishes on a white tile). Instance-uniform slots are fixed project-wide
// (D55): dim = 0 (BWLook.set_dim, the attack cutscene), then the tile FX
// slots 3..7. `tier` is a float 0..3 that BWBoardView animates over ~0.3 s,
// so every feature below fades in by its own tier band and nothing pops:
//   t1 = clamp(tier, 0, 1), t2 = clamp(tier - 1, 0, 1), t3 = clamp(tier - 2, 0, 1)
// A layer at tier 0 draws nothing at all.
//
// Geometry: face layers are a flat pointy-top hex of circumradius 1 in the
// node's local XZ plane (BWBoardView puts the node on the tile top), so
// `hexd(p)` is 1.0 on the outer edge of the black tile border and 0.93 where
// the white cap meets it.

instance uniform float dim : hint_range(0.0, 1.0), instance_index(0) = 0.0;
instance uniform float tier : instance_index(3) = 0.0;
instance uniform float seed : instance_index(4) = 0.0;
instance uniform float frost : instance_index(5) = 0.0;   // under a glaze: 1 = dimmed to 60 % and slowed
instance uniform float crack : instance_index(6) = 0.0;   // glaze in its last cycle
instance uniform float age : instance_index(7) = 0.0;     // one-shots / glaze forming: 0..1

const float FX_TAU = 6.2831853;
const float APOTHEM = 0.8660254;

// Colour literals in these shaders are written as sRGB (what you see) and
// converted here: the project renders linear (BWLook.starfield_environment),
// so a raw vec3(0.42, 0.25, 0.72) would show as a pastel lilac.
vec3 lin(vec3 c) { return pow(max(c, vec3(0.0)), vec3(2.2)); }

float t1() { return clamp(tier, 0.0, 1.0); }
float t2() { return clamp(tier - 1.0, 0.0, 1.0); }
float t3() { return clamp(tier - 2.0, 0.0, 1.0); }

// Glazed layers keep moving, slowly: the element is frozen in place, not out.
float fx_time(float time) { return time * mix(1.0, 0.12, frost) + seed * 13.7; }

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float hash11(float x) { return fract(sin(x * 127.1 + 11.3) * 43758.5453); }

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.7);
		a *= 0.5;
	}
	return s;
}

// 0 at the centre, 1 on the hex's outer edge (pointy-top, corners at -30 + 60k deg).
float hexd(vec2 p) {
	p = abs(p);
	float a = max(p.x, dot(p, vec2(0.5, APOTHEM)));
	return max(a, abs(dot(p, vec2(-0.5, APOTHEM)))) / APOTHEM;
}

// Premultiplied "over" compositing into an accumulator.
void over(inout vec4 acc, vec3 c, float a) {
	a = clamp(a, 0.0, 1.0);
	acc.rgb = c * a + acc.rgb * (1.0 - a);
	acc.a = a + acc.a * (1.0 - a);
}

// Final write: un-premultiply, glaze dimming, cutscene dim, hex clip.
void fx_out(vec4 acc, float clip_d, out vec3 albedo, out float alpha) {
	float a = acc.a * (1.0 - 0.4 * frost) * (1.0 - smoothstep(0.985, 1.0, clip_d));
	albedo = (acc.a > 0.0001 ? acc.rgb / acc.a : vec3(0.0)) * (1.0 - 0.9 * dim);
	alpha = clamp(a * (1.0 - 0.85 * dim), 0.0, 1.0);
}

// Where a view ray through local point p would hit a floor `depth` below the
// face (parallax): the tile face reads as sunk. `wv` = view dir in world space
// (towards the camera), the node carries no rotation or scale.
vec2 sink(vec2 p, vec3 wv, float depth) {
	return p - wv.xz / max(wv.y, 0.2) * depth;
}
