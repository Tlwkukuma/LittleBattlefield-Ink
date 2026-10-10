shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform vec4 ink : source_color = vec4(.28,.25,.35,1.0);
void fragment() {
	vec2 p = abs(UV*2.0-1.0);
	float rounded = pow(pow(p.x,4.0)+pow(p.y,4.0),.25);
	float contact = 1.0-smoothstep(.63,.98,rounded);
	ALBEDO = ink.rgb;
	ALPHA = contact*.19;
}
