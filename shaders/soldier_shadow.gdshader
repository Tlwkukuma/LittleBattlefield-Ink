shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform vec2 head=vec2(-0.7,-0.5);
uniform vec2 chest=vec2(-0.5,-0.3);
uniform vec2 hip=vec2(-0.3,-0.2);
uniform vec2 left_foot=vec2(-0.18,0.0);
uniform vec2 right_foot=vec2(0.18,0.1);
uniform float softness=0.025;
varying vec2 ground;
float capsule(vec2 p,vec2 a,vec2 b,float r) {
	vec2 ab=b-a;float t=clamp(dot(p-a,ab)/max(dot(ab,ab),0.00001),0.0,1.0);
	return length(p-a-ab*t)-r;
}
void vertex() { ground=VERTEX.xz; }
void fragment() {
	float d=capsule(ground,head,chest,0.265);
	d=min(d,capsule(ground,chest,hip,0.245));
	d=min(d,capsule(ground,hip,left_foot,0.095));
	d=min(d,capsule(ground,hip,right_foot,0.095));
	d=min(d,(length((ground-left_foot)/vec2(0.115,0.18))-1.0)*0.115);
	d=min(d,(length((ground-right_foot)/vec2(0.115,0.18))-1.0)*0.115);
	ALBEDO=vec3(0.24,0.20,0.34);
	ALPHA=(1.0-smoothstep(-softness,softness,d))*0.19;
}
