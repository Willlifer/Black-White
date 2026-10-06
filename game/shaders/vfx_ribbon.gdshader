// D167-D169 ribbons (BWVfxCasts): afterimage limbs (Hundred Fists), tracers
// (Empty the Chamber) and the Ley Line's racing line. UV.y runs across the
// strip (0..1), UV.x along it; vertex COLOR.rgb is the element hue and
// COLOR.a how much of it tints the white body. Ink rims both edges. `age`
// (slot 7) fades the whole strip; `tier` (slot 3) is its opacity.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

instance uniform float tier : instance_index(3) = 1.0;
instance uniform float age : instance_index(7) = 0.0;

void fragment() {
	float e = abs(UV.y - 0.5) * 2.0;
	float fw = max(fwidth(e) * 1.2, 0.02);
	vec3 c = mix(vec3(1.0), COLOR.rgb, COLOR.a);
	c = mix(c, vec3(0.0), smoothstep(0.62, 0.62 + fw, e));
	float a = (1.0 - smoothstep(1.0 - fw, 1.0, e)) * (1.0 - clamp(age, 0.0, 1.0)) * tier;
	ALBEDO = c;
	ALPHA = clamp(a, 0.0, 1.0);
}
