// Inverted-hull outline: draw the back faces pushed out along the normal, in
// black. Keeps the bold graphic contour at any camera angle (brief).
shader_type spatial;
render_mode unshaded, cull_front;

uniform float width = 0.025;
uniform vec3 color : source_color = vec3(0.0);
// Follows the cutscene fade like flat.gdshader, so a dimmed figure's white
// contour doesn't stay bright.
instance uniform float dim : hint_range(0.0, 1.0), instance_index(0) = 0.0;

void vertex() {
	VERTEX += NORMAL * width;
}

void fragment() {
	ALBEDO = mix(color, color * 0.012, dim);
}
