// Armour pieces (BWEquipmentView). flat_opaque plus one per-material colour:
// `paint` is white on the greyscale `armour` surface and the element colour
// (or neutral grey) on the `accent` surface. Vertex COLOR carries the baked
// facet tone from build_equipment.py, so the accent keeps its facets too.
// Opaque (no ALPHA write) for the same depth-sorting reason as flat_opaque.
// `dim` is pinned to instance index 0 to match outline.gdshader, so the fill
// and its hull pass share the slot and BWLook.set_dim fades both.
shader_type spatial;
render_mode unshaded, cull_back;

instance uniform float dim : hint_range(0.0, 1.0), instance_index(0) = 0.0;
instance uniform vec4 tint : source_color, instance_index(1) = vec4(1.0);
uniform vec4 paint : source_color = vec4(1.0);
uniform float dim_floor = 0.012;

void fragment() {
	vec3 c = COLOR.rgb * paint.rgb * tint.rgb;
	ALBEDO = mix(c, c * dim_floor, dim);
}
