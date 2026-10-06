// flat.gdshader without the ALPHA write. Writing ALPHA (even 1.0) moves a
// material onto Godot's transparent pipeline: no depth writes, sorted per
// object, so inside one skinned mesh the black limbs drew over the white head.
// Same uniforms as flat (tint, dim, dim_floor) so BWLook.set_dim and tints
// work unchanged. Used by BWCharacterRig; anything opaque can use it.
shader_type spatial;
render_mode unshaded, cull_back;

instance uniform vec4 tint : source_color, instance_index(1) = vec4(1.0);
instance uniform float dim : hint_range(0.0, 1.0), instance_index(0) = 0.0;
uniform float dim_floor = 0.012;

void fragment() {
	vec3 c = COLOR.rgb * tint.rgb;
	ALBEDO = mix(c, c * dim_floor, dim);
}
