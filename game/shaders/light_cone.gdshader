// A fake volumetric light (D83): spotlight cones and window shafts in the
// downtime hall. Additive and unshaded; brightest where the eye looks through
// the most "air" (the middle of the silhouette), fading at the rim, at the
// source and a little toward the floor. A slow drift of dust in the beam.
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;

uniform float height = 6.0;            // source-to-floor height of the beam
uniform float top = 3.0;               // local y of the source
uniform float intensity = 0.16;
uniform float dust = 0.35;
instance uniform float strength = 1.0;

varying float t;
varying vec3 wpos;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	t = clamp((top - VERTEX.y) / height, 0.0, 1.0);    // 0 at the source, 1 at the floor
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float core = pow(facing, 2.2);
	float along = smoothstep(0.0, 0.22, t) * (0.65 + 0.35 * t) * (1.0 - 0.25 * smoothstep(0.85, 1.0, t));
	vec3 g = floor(wpos * 9.0 + vec3(0.0, -TIME * 0.6, 0.0));
	float speck = step(0.985, hash3(g)) * dust;
	float a = intensity * strength * along * (core + speck * core);
	ALBEDO = vec3(1.0);
	ALPHA = clamp(a, 0.0, 1.0);
}
