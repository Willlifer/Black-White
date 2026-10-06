// One-shot tile events (BWBoardView.burst). `age` 0..1 over the event's life,
// one shared material per `mode`:
//   0 detonation ring: a purple-white shock ring bursting onto the six
//     neighbours, six bolts to their centres, the blasted hex flashing white
//   1 gale gust ring: green gust strokes blowing outward to the neighbours
//   2 flash: a camera-facing burst (detonation purple-white, ignition orange)
//   3 ignition ring: a quick orange flare on the ground (grass catching)
// Ground modes draw on a flat disc of radius 2.6 (reaching just past the
// neighbours' centres at 1.73; BWBoardView scales it for a wider splash);
// the flash on a 2x2 quad.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

#include "res://shaders/tile_fx.gdshaderinc"

uniform int mode = 0;
uniform vec4 glow : source_color = vec4(0.608, 0.302, 1.0, 1.0);

varying vec2 lp;

void vertex() {
	lp = VERTEX.xz;
	if (mode == 2) {
		lp = VERTEX.xy;
		// billboard, keeping the node's scale
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	}
}

void fragment() {
	float a = clamp(age, 0.0, 1.0);
	float r = length(lp);
	float ang = atan(lp.y, lp.x);
	vec3 white = lin(vec3(1.0, 0.97, 1.0));
	vec4 acc = vec4(0.0);
	if (mode == 0) {
		float R = (0.2 + 1.75 * pow(a, 0.55));
		float ring = 1.0 - smoothstep(0.0, 0.16 + 0.16 * a, abs(r - R));
		float lead = 1.0 - smoothstep(0.0, 0.06, abs(r - R - 0.06));
		// the whole splash area flashes purple-white for the first beat
		over(acc, mix(white, glow.rgb, 0.35), step(r, R) * 0.55 * (1.0 - smoothstep(0.0, 0.3, a)));
		float fade = 1.0 - smoothstep(0.55, 1.0, a);
		over(acc, glow.rgb, ring * 0.85 * fade);
		over(acc, white, lead * fade);
		// six bolts out to the neighbour centres (edge normals: 0, 60, ... deg)
		float wedge = mod(ang + 0.5236, 1.0472) - 0.5236;
		float jag = (vnoise(vec2(r * 9.0, floor(TIME * 20.0) + seed)) - 0.5) * 0.12;
		float bolt = abs(sin(wedge) * r + jag);
		float bl = (1.0 - smoothstep(0.02, 0.05, bolt)) * step(r, R) * step(0.25, r);
		over(acc, white, bl * (1.0 - smoothstep(0.2, 0.7, a)));
		over(acc, glow.rgb, (1.0 - smoothstep(0.0, 0.1, bolt)) * step(r, R) * 0.75 * (1.0 - smoothstep(0.2, 0.7, a)));
		// the blasted hex itself flashes
		float core = 1.0 - smoothstep(0.0, 1.0, hexd(lp));
		over(acc, white, smoothstep(0.0, 0.2, core) * (1.0 - smoothstep(0.0, 0.35, a)));
	} else if (mode == 1) {
		float R = 0.3 + 1.6 * a;
		float fade = 1.0 - smoothstep(0.5, 1.0, a);
		// broken arcs (gust strokes) blowing outward, slightly sheared round
		float sh = ang + r * 0.9;
		float strokes = step(0.45, fract(sh * 6.0 / FX_TAU + 0.15));
		float band = 1.0 - smoothstep(0.0, 0.1, abs(r - R));
		float trail = (1.0 - smoothstep(0.0, 0.35, R - r)) * step(r, R) * 0.4;
		over(acc, lin(vec3(0.03, 0.25, 0.08)), band * strokes * 0.6 * fade);
		over(acc, glow.rgb, (band * strokes + trail * strokes) * fade);
	} else if (mode == 2) {
		float spikes = 0.45 + 0.55 * pow(abs(cos(ang * 3.0 + seed)), 10.0) + 0.25 * pow(abs(sin(ang * 3.0 + seed)), 12.0);
		float edge = spikes * (0.95 - 0.3 * a);
		if (r > edge) {
			discard;
		}
		vec3 c = r > edge * 0.6 ? glow.rgb : white;
		float hole = step(0.5, a) * (1.0 - step((a - 0.5) * 1.6, r));
		over(acc, c, (1.0 - hole) * (1.0 - smoothstep(0.7, 1.0, a)));
	} else {
		float R = 0.15 + 0.85 * pow(a, 0.6);
		float ring = 1.0 - smoothstep(0.0, 0.08, abs(r - R));
		float fade = 1.0 - smoothstep(0.4, 1.0, a);
		float fill = (1.0 - smoothstep(0.0, R, r)) * (1.0 - smoothstep(0.0, 0.5, a));
		over(acc, lin(vec3(1.0, 0.86, 0.36)), fill * 0.7);
		over(acc, glow.rgb, ring * fade);
	}
	ALBEDO = (acc.a > 0.0001 ? acc.rgb / acc.a : vec3(0.0)) * (1.0 - 0.9 * dim);
	ALPHA = clamp(acc.a * (1.0 - 0.85 * dim), 0.0, 1.0);
}
