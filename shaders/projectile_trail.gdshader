shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
void fragment() {
	float fade=pow(1.0-clamp(UV.y,0.0,1.0),1.15);
	ALBEDO=mix(vec3(.96,.48,.10),vec3(1.0,.87,.45),fade);
	EMISSION=vec3(1.0,.70,.22)*.22;
	ALPHA=fade*.88;
}
