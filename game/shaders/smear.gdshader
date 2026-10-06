// Weapon smear (BWAnimator): an anime smear frame behind the blade, a
// solid white crescent with an ink edge. UV.x = 0 at the hilt end of the
// trail, 1 on the blade tip's path; UV.y = age (0 at the blade, 1 at the
// tail). The crescent is cut in the fragment: full width at the blade,
// tapering to the tip's path at the tail, so the shape reads as a swept
// blade, not a fog. COLOR.a = the clip's smear channel (fades it in and
// out as a whole). Has the project's `dim` slot so BWLook.set_dim fades it
// with the figure.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

instance uniform float dim : hint_range(0.0, 1.0), instance_index(0) = 0.0;

void fragment() {
	float cut = mix(0.22, 1.0, pow(UV.y, 1.25));
	float amount = smoothstep(0.12, 0.35, COLOR.a);
	if (UV.x < cut || amount <= 0.001) {
		discard;
	}
	float ink_in = 1.0 - smoothstep(cut + 0.02, cut + 0.05, UV.x);
	float ink_out = smoothstep(0.94, 0.975, UV.x);
	ALBEDO = mix(vec3(1.0), vec3(0.0), max(ink_in, ink_out));
	ALPHA = amount * (1.0 - dim);
}
