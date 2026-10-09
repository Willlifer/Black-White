// D215: the floating HP bar over a unit (BWHPBar3D), drawn in one quad.
// D495: coloured by TEAM, not HP: an ally's (the player's side, `ally`) fill
// is BLACK with WHITE pips over a dark-grey empty well; an enemy's is WHITE
// with BLACK pips over a light-grey well. Pips sit at every 10% of max HP
// (9 internal ticks). The lost chunk lingers (`ghost`, a grey on the far
// side of the well's) before it drains. A two-ring outline (the fill's
// opposite inside, the fill's own colour outside) lets a black bar read on
// the black sky and a white bar on white tiles. Greys: BWWidgets.HPBar.palette.
// Rings and pips are sized in screen pixels (fwidth), so they stay crisp
// at any zoom. `dim` (instance) fades the bar with BWLook.set_dim.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_mix, shadows_disabled;

instance uniform float dim : hint_range(0.0, 1.0) = 0.0;
uniform vec2 bar_size = vec2(1.25, 0.13);
uniform float pad = 0.06;
uniform float fill : hint_range(0.0, 1.0) = 1.0;
uniform float ghost : hint_range(0.0, 1.0) = 1.0;
uniform bool ally = true;                        // D495: the player's side

void vertex() {
	// billboard, keeping the node's scale (the Giant's bar is 2.6x)
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(MAIN_CAM_INV_VIEW_MATRIX[0], MAIN_CAM_INV_VIEW_MATRIX[1],
		MAIN_CAM_INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 full = bar_size + 2.0 * pad;
	vec2 p = UV * full - pad;                    // bar space: (0,0)..bar_size
	vec2 px = max(fwidth(p), vec2(1e-5));        // world units per screen pixel
	float fc = ally ? 0.0 : 1.0;                 // fill colour (screen grey): D495 by team
	float oc = 1.0 - fc;                         // its opposite: pips, inner ring
	vec2 dout = max(max(-p, p - bar_size), vec2(0.0)) / px;
	float d = max(dout.x, dout.y);
	float g;
	if (d > 0.0) {
		if (d <= 1.4) {
			g = oc;
		} else if (d <= 2.8) {
			g = fc;
		} else {
			discard;
		}
	} else {
		float x = p.x / bar_size.x;
		g = ally ? 0.36 : 0.64;                  // the empty well (BWWidgets.HPBar.palette)
		if (x < ghost) {
			g = ally ? 0.68 : 0.32;              // the chunk just lost: a grey past the well's
		}
		if (x < fill) {
			g = fc;
		}
		float t = x * 10.0;
		float k = round(t);
		float dist = abs(t - k) * (bar_size.x / 10.0) / px.x;   // pixels to the nearest tick
		if (k >= 1.0 && k <= 9.0 && dist < 0.6) {
			g = oc;
		}
	}
	vec3 c = vec3(pow(g, 2.2));
	ALBEDO = mix(c, c * 0.012, dim);
	ALPHA = 1.0 - dim;
}
