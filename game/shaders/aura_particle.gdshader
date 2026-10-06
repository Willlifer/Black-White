// Aura particle diamonds (BWWeaponView). The same look as the unshaded,
// vertex-coloured, particle-billboard StandardMaterial it replaces, plus the
// project's `dim` instance slot (0), so BWLook.set_dim fades the particles
// with the rest of the figure in the attack cutscene.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

instance uniform float dim : hint_range(0.0, 1.0), instance_index(0) = 0.0;

void vertex() {
	// particle billboard: face the camera, keep the particle's scale and spin
	mat4 m = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	m = m * mat4(vec4(cos(INSTANCE_CUSTOM.x), -sin(INSTANCE_CUSTOM.x), 0.0, 0.0),
			vec4(sin(INSTANCE_CUSTOM.x), cos(INSTANCE_CUSTOM.x), 0.0, 0.0),
			vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * m;
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	ALBEDO = COLOR.rgb * (1.0 - 0.95 * dim);
	ALPHA = COLOR.a * (1.0 - dim);
}
