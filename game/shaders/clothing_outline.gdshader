// Clothing contour: inverted hull like outline.gdshader, but
//  - the colour is palette row 2 for the instance's shade, which the build
//    fills by the contour rule (fill value < 0.5 -> white, else black; D42);
//  - the push is scaled by vertex COLOR.g, so decals (fold lines, rips,
//    drawstrings) carry no contour of their own.
// Instance slots follow the project pin: dim 0; shade = 3.
shader_type spatial;
render_mode unshaded, cull_front;

uniform float width = 0.02;
uniform sampler2D palette : source_color, filter_nearest;
instance uniform float dim : hint_range(0.0, 1.0), instance_index(0) = 0.0;
instance uniform float shade : instance_index(3) = 1.0;

void vertex() {
	VERTEX += NORMAL * width * COLOR.g;
}

void fragment() {
	int s = clamp(int(shade + 0.5), 0, 2);
	vec3 c = texelFetch(palette, ivec2(s, 2), 0).rgb;
	ALBEDO = mix(c, c * 0.012, dim);
}
