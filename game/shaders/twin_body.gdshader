// D260: the Twins' bodies. flat_opaque with one solid colour instead of the
// baked vertex colours: Noon all white (ink contour), Dusk all black (white
// contour, D42's rule). Same instance uniforms as flat (dim, tint), so
// BWLook.set_dim fades them for cutscenes like any figure.
shader_type spatial;
render_mode unshaded, cull_back;

uniform vec3 body : source_color = vec3(1.0);
instance uniform vec4 tint : source_color, instance_index(1) = vec4(1.0);
instance uniform float dim : hint_range(0.0, 1.0), instance_index(0) = 0.0;
uniform float dim_floor = 0.012;

void fragment() {
	vec3 c = body * tint.rgb;
	ALBEDO = mix(c, c * dim_floor, dim);
}
