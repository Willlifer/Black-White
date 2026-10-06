// D165 Rain of Arrows: the volley's shadow on the ground. A soft ink ellipse
// with streaks of arrow shadows running along the volley's heading; it
// slides in over the area (the node moves), darkens as the arrows come down,
// then lifts. Unlit, alpha-blended, laid flat on a PlaneMesh.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

uniform float fade = 0.0;          // 0..1 overall strength
uniform vec2 heading = vec2(0.0, 1.0);   // the volley's direction in the plane's UV space
uniform float scroll = 0.0;        // seconds: the streaks run along the heading
uniform float seed = 0.0;

float hash(float n) { return fract(sin(n * 91.345 + seed * 17.0) * 43758.5453); }

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float body = 1.0 - smoothstep(0.55, 1.0, r);
	vec2 h = normalize(heading);
	vec2 n = vec2(-h.y, h.x);
	float along = dot(p, h);
	float across = dot(p, n);
	// lanes of arrow shadows: thin dashes with a bright gap between
	float lanes = 26.0;
	float lane = floor(across * lanes);
	float fl = fract(across * lanes);
	float off = hash(lane);
	float ph = fract(along * 3.2 + off - scroll * (1.6 + off));
	float dash = step(ph, 0.22) * (1.0 - smoothstep(0.06, 0.16, abs(fl - 0.5)));
	dash *= step(0.35, hash(lane + 7.0));
	float a = (0.38 * body + 0.5 * dash * body) * fade;
	if (a < 0.003) {
		discard;
	}
	ALBEDO = vec3(0.0);
	ALPHA = a;
}
