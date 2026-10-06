// Weapon fill (BWWeaponView). Unlit, opaque, colour from the vertex COLOR the
// build script bakes (white body, grey grips, steel-grey edge bevels, dark
// gems). The `accent` surface (edges, gems, striking faces) can be tinted
// per weapon instance: accent.rgb is the colour, accent.a how much of it.
// BWWeaponView.set_aura() drives it with the element colour.
//
// Instance-uniform indices are pinned so this fill and outline.gdshader
// (which declares only `dim`, index 0) agree on `dim` inside one instance.
shader_type spatial;
render_mode unshaded, cull_back;

uniform bool is_accent = false;
uniform float dim_floor = 0.012;
instance uniform float dim : hint_range(0.0, 1.0), instance_index(0) = 0.0;
instance uniform vec4 tint : source_color, instance_index(1) = vec4(1.0);
instance uniform vec4 accent : source_color, instance_index(2) = vec4(1.0, 1.0, 1.0, 0.0);

void fragment() {
	vec3 c = COLOR.rgb;
	if (is_accent) {
		c = mix(c, accent.rgb, accent.a);
	}
	c *= tint.rgb;
	ALBEDO = mix(c, c * dim_floor, dim);
}
