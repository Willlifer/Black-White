// D266 the ice/water spine's board marks (BWIceWaterView).
//   mode 0  RINK SHEEN on a slippery (glazed) hex: two bright glint streaks
//           sliding across the face along `heading`, thin ink speed lines,
//           a white gloss rim. Flat hex of circumradius 1 (BWTileFX.hex_mesh).
//   mode 1  STEAM WISP: a billboard quad; a lumpy white ink puff with a grey
//           ink contour that drifts up and breathes.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

#include "res://shaders/tile_fx.gdshaderinc"

uniform int mode = 0;
uniform vec4 glow : source_color = vec4(0.373, 0.847, 0.941, 1.0);
uniform vec4 ink : source_color = vec4(0.04, 0.38, 0.5, 1.0);

varying vec2 lp;

void vertex() {
	lp = VERTEX.xz;
	if (mode == 1) {
		lp = UV * 2.0 - 1.0;
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
}

void fragment() {
	vec4 acc = vec4(0.0);
	float t = TIME + seed * 17.0;
	if (mode == 0) {
		float d = hexd(lp);
		if (d > 0.93) {
			discard;
		}
		vec2 dir = normalize(vec2(0.82, -0.57));
		vec2 nrm = vec2(-dir.y, dir.x);
		float along = dot(lp, dir);
		float across = dot(lp, nrm);
		// two glints sweeping across, a little apart
		for (int i = 0; i < 2; i++) {
			float ph = fract(t * 0.28 + float(i) * 0.5);
			float c = mix(-1.3, 1.3, ph);
			float band = 1.0 - smoothstep(0.0, 0.07 + 0.04 * float(i), abs(across + along * 0.35 - c));
			over(acc, vec3(1.0), band * 0.75);
		}
		// ink speed lines (the slide's direction)
		float lines = 0.0;
		for (int k = 0; k < 3; k++) {
			float y = -0.42 + 0.42 * float(k) + 0.05 * sin(seed * 40.0 + float(k));
			float x0 = -0.55 + 0.25 * hash21(vec2(seed, float(k)));
			float seg = step(x0, along) * step(along, x0 + 0.5 + 0.2 * hash21(vec2(float(k), seed)));
			lines = max(lines, seg * (1.0 - smoothstep(0.0, 0.022, abs(across - y))));
		}
		over(acc, lin(ink.rgb), lines * 0.8);
		// gloss rim just inside the cap
		float rim = smoothstep(0.80, 0.86, d) * (1.0 - smoothstep(0.88, 0.93, d));
		over(acc, vec3(1.0), rim * 0.7);
	} else {
		vec2 p = lp;
		p.y -= 0.06 * sin(t * 0.7);
		float ang = atan(p.y, p.x);
		float r = length(p);
		float edge = 0.62 + 0.10 * sin(ang * 3.0 + t * 0.9) + 0.07 * sin(ang * 5.0 - t * 1.3)
			+ 0.08 * (vnoise(p * 3.0 + vec2(0.0, -t * 0.35)) - 0.5);
		float body = 1.0 - smoothstep(edge - 0.03, edge, r);
		float line = (1.0 - smoothstep(0.0, 0.035, abs(r - edge + 0.035))) * step(r, edge + 0.02);
		// a curl of ink inside the puff
		float curl = (1.0 - smoothstep(0.0, 0.03, abs(r - 0.32 - 0.05 * sin(ang * 2.0 + t)))) * step(0.0, sin(ang + t * 0.5));
		over(acc, vec3(1.0), body * 0.88);
		over(acc, lin(vec3(0.35, 0.37, 0.4)), (line + curl * 0.6) * 0.9);
	}
	if (acc.a <= 0.002) {
		discard;
	}
	ALBEDO = acc.rgb / acc.a * (1.0 - 0.9 * dim);
	ALPHA = clamp(acc.a * (1.0 - 0.85 * dim), 0.0, 1.0);
}
