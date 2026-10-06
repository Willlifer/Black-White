// Billboard card clusters for the tile FX that stand up off the hex
// (fire flames / smoke / sparks, the light column and motes, abyss tendrils).
// BWTileFX.card_mesh() builds one shared mesh: ten cards (centre, an inner
// ring of 3, a rim ring of 6). All four corners of a card sit on its pivot
// on the tile top; UV is the corner (0..1, v up), CUSTOM0 carries
// (width, height scale, card seed, ring 0/1/2). The vertex stage spreads each
// card around its pivot facing the camera about the vertical axis, so flames
// stay upright from any orbit angle. Include after tile_fx.gdshaderinc and
// compute the card height (world units, 0 = hidden) and pass it in.

varying vec2 cuv;        // x -1..1 across the card, y 0..1 up it
varying vec4 cdat;       // CUSTOM0
varying float ch;        // the card's height this frame (world units)

// Offset of one card corner from its pivot: across the card facing the
// camera (about the vertical axis), and h up it. vertex() assigns the
// varyings itself (Godot only allows that in the stage functions):
//   VERTEX += card_offset(UV, CUSTOM0.x, INV_VIEW_MATRIX, h);
//   cuv = vec2(UV.x * 2.0 - 1.0, UV.y); cdat = CUSTOM0; ch = h;
vec3 card_offset(vec2 uv, float w, mat4 inv_view, float h) {
	vec3 right = inv_view[0].xyz;
	right.y = 0.0;
	right = length(right) > 1e-4 ? normalize(right) : vec3(1.0, 0.0, 0.0);
	return right * (uv.x - 0.5) * w + vec3(0.0, uv.y * h, 0.0);
}
