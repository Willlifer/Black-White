// Inverted-hull contour for hair, from the same root->tip ramp and vertex
// COLOR.r as hair.gdshader (D146/D147). A colour that reads on the black
// sky gets a darker value of its OWN hue (D52: the panels draw hair with a
// same-hue line); a dark colour (relative luminance below `dark_lum`, the
// light-streak threshold) gets a LIGHTER line of its hue instead (D42:
// dark shapes get a light contour so they read against the black sky; on
// white tiles and the white head it vanishes). It also keeps light streaks
// off the white head. `value` 0 with `lift` 0 gives a plain black contour.
shader_type spatial;
render_mode unshaded, cull_front;

instance uniform vec4 tint : source_color, instance_index(1) = vec4(1.0);
instance uniform float dim : hint_range(0.0, 1.0), instance_index(0) = 0.0;
uniform sampler2D ramp : source_color, filter_linear, repeat_disable;
uniform float width = 0.024;
uniform float value : hint_range(0.0, 1.0) = 0.38;
uniform float saturate = 0.25;
uniform float lift : hint_range(0.0, 1.0) = 0.55;   // toward white, for dark colours
uniform float dark_lum = 0.19;

void vertex() {
	VERTEX += NORMAL * width;
}

void fragment() {
	vec3 h = texture(ramp, vec2(clamp(COLOR.r, 0.0, 1.0), 0.5)).rgb * tint.rgb;
	float lum = dot(h, vec3(0.2126, 0.7152, 0.0722));
	vec3 c = h * pow(value, 2.2);
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = max(mix(vec3(l), c, 1.0 + saturate), vec3(0.0));
	if (lum < dark_lum && value > 0.0) {
		c = mix(h, vec3(1.0), lift);
	}
	ALBEDO = mix(c, c * 0.012, dim);
}
