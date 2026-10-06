// Same as flat.gdshader but blended, for tile glows and highlights.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

instance uniform vec4 tint : source_color, instance_index(1) = vec4(1.0);
instance uniform float dim : hint_range(0.0, 1.0), instance_index(0) = 0.0;
uniform float pulse_speed = 0.0;

void fragment() {
	float p = pulse_speed > 0.0 ? 0.75 + 0.25 * sin(TIME * pulse_speed) : 1.0;
	ALBEDO = tint.rgb * (1.0 - 0.92 * dim);
	ALPHA = tint.a * p * (1.0 - 0.7 * dim);
}
