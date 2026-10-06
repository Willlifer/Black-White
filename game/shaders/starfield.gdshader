// Black sky with stars (brief). Procedural, no textures: hashed cells on the
// sky sphere, a few twinkle.
shader_type sky;

uniform float density = 260.0;
uniform float size = 0.035;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 d = normalize(EYEDIR) * density;
	vec3 cell = floor(d);
	vec3 f = fract(d) - 0.5;
	float h = hash(cell);
	float star = 0.0;
	if (h > 0.985) {
		float r = length(f);
		float tw = 0.7 + 0.3 * sin(TIME * (1.0 + h * 4.0) + h * 40.0);
		star = smoothstep(size * (1.0 + 2.0 * fract(h * 91.0)), 0.0, r) * tw;
	}
	COLOR = vec3(star);
}
