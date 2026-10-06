// Black | White flat material. Colour comes from vertex COLOR x tint; no
// lighting, so the look is graphic, not shaded. `dim` darkens one instance
// toward black: the attack cutscene uses it to fade everything except the
// attacker, the target and their tiles.
shader_type spatial;
render_mode unshaded, cull_back;

instance uniform vec4 tint : source_color, instance_index(1) = vec4(1.0);
instance uniform float dim : hint_range(0.0, 1.0), instance_index(0) = 0.0;
uniform float dim_floor = 0.012;   // linear: reads ~10% grey on screen

void fragment() {
	vec3 c = COLOR.rgb * tint.rgb;
	ALBEDO = mix(c, c * dim_floor, dim);
	ALPHA = COLOR.a * tint.a;
}
