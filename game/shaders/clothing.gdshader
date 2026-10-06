// Clothing fill (clothing lane, design/art/CLOTHING.md). Unlit and flat like
// the rest of the figure. Colour comes from the 3x3 palette texture
// art/clothing/clothing_palette.png, column = the character's clothing_shade
// (0 dark, 1 mid, 2 light), picked per instance by `shade`:
//   row 0 fill, row 1 fold/seam line, row 2 contour (used by clothing_outline)
// Vertex COLOR.r selects the channel: 1 fill, 0.5 fold line, 0 ink (black rips).
// Two-sided: the inside of a hem or neckline shows the fold colour, so open
// garment ends read as an interior instead of a hole.
// Instance slots follow the project pin: dim 0, tint 1, accent 2; shade = 3.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D palette : source_color, filter_nearest;
uniform float dim_floor = 0.012;
instance uniform float dim : hint_range(0.0, 1.0), instance_index(0) = 0.0;
instance uniform vec4 tint : source_color, instance_index(1) = vec4(1.0);
instance uniform float shade : instance_index(3) = 1.0;

void fragment() {
	int s = clamp(int(shade + 0.5), 0, 2);
	vec3 fill = texelFetch(palette, ivec2(s, 0), 0).rgb;
	vec3 fold = texelFetch(palette, ivec2(s, 1), 0).rgb;
	float ch = COLOR.r;
	vec3 c = ch > 0.75 ? fill : (ch > 0.1 ? fold : vec3(0.0));
	if (!FRONT_FACING && ch > 0.75) {
		c = fold;
	}
	c *= tint.rgb;
	ALBEDO = mix(c, c * dim_floor, dim);
}
