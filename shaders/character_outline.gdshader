shader_type spatial;
render_mode unshaded, cull_front;
uniform vec4 ink : source_color = vec4(.28,.25,.35,1.0);
uniform float width_pixels = 1.1;
void vertex() {
	vec4 clip=PROJECTION_MATRIX*MODELVIEW_MATRIX*vec4(VERTEX,1.0);
	vec3 normal_view=normalize(MODELVIEW_NORMAL_MATRIX*NORMAL);
	vec2 direction=(PROJECTION_MATRIX*vec4(normal_view,0.0)).xy;
	direction/=max(length(direction),.00001);
	clip.xy+=direction*2.0*width_pixels/VIEWPORT_SIZE*clip.w;
	clip.z+=.00001*clip.w;
	POSITION=clip;
}
void fragment() { ALBEDO=ink.rgb; }
