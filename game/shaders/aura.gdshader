// Elemental weapon aura: a fresnel rim on an inflated shell of the weapon's
// OWN mesh (no extra geometry). BWWeaponView.set_aura() puts a copy of each
// weapon MeshInstance3D under the weapon with this as material_override.
//
// Reads on both grounds by construction:
//   * on the black sky the rim is the element colour, lifted (rim_color) for
//     dark hues so purple/indigo still separate from black;
//   * on white tiles alpha blending (not additive) keeps the hue, and the
//     inner `color` is the saturated, slightly deepened element colour.
// The shell breathes (vertex noise) and bands of brightness climb the
// weapon (+Y in weapon space = up the blade), so it reads as energy, not as
// a second outline.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.35, 0.1, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.7, 0.4, 1.0);
uniform float strength : hint_range(0.0, 2.0) = 1.0;
uniform float grow = 0.045;           // shell offset along the normal, weapon units
uniform float rim_power = 1.4;
uniform float base_alpha = 0.16;      // faint body of the shell where it faces the camera
uniform float flicker = 0.45;         // how much the shell breathes
uniform float flow_speed = 1.3;       // bands per second up the weapon
uniform float band_scale = 9.0;
instance uniform float dim : hint_range(0.0, 1.0), instance_index(0) = 0.0;

varying vec3 local_pos;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
	               mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
	           mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
	               mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	local_pos = VERTEX;
	float n = noise3(VERTEX * 6.0 + vec3(0.0, -TIME * flow_speed * 2.0, 0.0));
	float s = clamp(strength, 0.0, 2.0);
	VERTEX += NORMAL * grow * (0.6 + 0.4 * s) * (1.0 + flicker * (n * 2.0 - 1.0));
}

void fragment() {
	float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - ndv, rim_power);
	float n = noise3(local_pos * 5.0 + vec3(0.0, -TIME * flow_speed * 1.5, 0.0));
	float bands = 0.7 + 0.3 * sin(local_pos.y * band_scale - TIME * flow_speed * 6.2831 + n * 3.0);
	float a = (base_alpha + rim * (1.0 - base_alpha)) * bands * clamp(strength, 0.0, 2.0);
	ALBEDO = mix(color.rgb, rim_color.rgb, smoothstep(0.25, 0.95, rim));
	ALPHA = clamp(a, 0.0, 0.92) * (1.0 - dim);
}
