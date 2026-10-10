shader_type spatial;
render_mode unshaded, cull_disabled;
#include "res://shaders/range2_ink.gdshaderinc"

uniform float damage = 0.0;
uniform float hatch_strength = 0.18;
uniform bool line_pass = false;
uniform vec4 paper : source_color = vec4(.81,.80,.86,1.0);
uniform vec4 body_paint : source_color = vec4(.47,.61,.73,1.0);
uniform vec4 panel_paint : source_color = vec4(.67,.76,.83,1.0);
uniform vec4 accent_paint : source_color = vec4(.20,.37,.55,1.0);
uniform vec4 steel : source_color = vec4(.49,.55,.57,1.0);
uniform vec4 rubber : source_color = vec4(.19,.20,.24,1.0);
uniform vec4 glass : source_color = vec4(.23,.39,.47,1.0);
uniform vec4 canvas : source_color = vec4(.68,.62,.48,1.0);
uniform vec4 marking : source_color = vec4(.93,.89,.74,1.0);
uniform vec4 ink : source_color = vec4(.28,.25,.35,1.0);
varying vec3 wear_position;
varying vec3 range2_local_position;
varying vec3 range2_local_normal;

void vertex() {
	range2_local_position=VERTEX;
	range2_local_normal=NORMAL;
	wear_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}

void fragment() {
	// Explicit roles survive batching. Team paint does not dye tires, canvas, glass,
	// exposed steel, brass or lights. Alpha is a role tag; no ALPHA output is used.
	int role = int(floor(COLOR.a * 15.0 + 0.5));
	vec3 wash = mix(COLOR.rgb,paper.rgb,.07);
	if (role == 1) wash = body_paint.rgb;
	else if (role == 2) wash = panel_paint.rgb;
	else if (role == 3) wash = mix(rubber.rgb,steel.rgb,.28);
	else if (role == 4) wash = steel.rgb;
	else if (role == 5) wash = rubber.rgb;
	else if (role == 6) wash = glass.rgb;
	else if (role == 7) wash = canvas.rgb;
	else if (role == 8) wash = accent_paint.rgb;
	else if (role == 9) wash = marking.rgb;
	vec3 n = normalize((INV_VIEW_MATRIX*vec4(normalize(NORMAL),0.0)).xyz);
	vec3 range2_base=wash;
	float shade = 1.0-smoothstep(-.1,.65,dot(n,normalize(vec3(.65,1.0,.65))));
	wash *= 1.0-shade*.18;
	if (role == 4) wash = mix(wash,paper.rgb,(1.0-shade)*.08);
	if (role == 6) wash = mix(wash,panel_paint.rgb,pow(1.0-abs(dot(normalize(NORMAL),normalize(VIEW))),3.0)*.20);
	float coordinate = FRAGCOORD.x + FRAGCOORD.y * 0.25;
	float hatch = (1.0 - smoothstep(0.30, 0.95, mod(coordinate, 3.2)))
		* (1.0 - step(8.0, mod(floor(coordinate / 3.2), 11.0)))
		* shade*hatch_strength;
	float facing = abs(dot(normalize(NORMAL),normalize(VIEW)));
	float contour = (1.0-smoothstep(.055,.18,facing))*.32;
	wash = mix(wash,ink.rgb,clamp(hatch+contour,0.0,.65));
	if (line_pass) wash = mix(paper.rgb,ink.rgb,.72);
	if (range2_enabled) {
		vec2 uv=range2_projection(range2_local_position,range2_local_normal)*.55;
		if (role==1 || role==2 || role==4 || role==8) range2_base=range2_texture(range2_base,uv,2.0,.78,0.0);
		if (role==7) range2_base=range2_texture(range2_base,uv,5.0,.45,.08);
		wash=range2_finish(range2_base,n,NORMAL,VIEW,uv,0.0);
		if (role==4 || role==6) wash=range2_glint(wash,NORMAL,VIEW,n,role==6 ? 1.5 : .9);
		if (line_pass) wash=vec3(.035,.045,.065);
	}
	if(damage>0.001) {
	// Large irregular soot islands and small exposed edges preserve the hull's volume.
	float patches=sin(wear_position.x*3.7+sin(wear_position.z*2.2))*sin(wear_position.z*4.3+wear_position.y*2.8);
	float burnt=smoothstep(-.48,.44,patches+damage*.64);
	vec3 charred=mix(vec3(.18,.16,.19),vec3(.32,.27,.25),burnt*.35);
	float coverage=damage*(.40+burnt*.53);
	if(role==6) coverage=max(coverage,damage*.97);
	if(role==4) coverage*=.76;
	wash=mix(wash,charred,coverage);
	float ash=smoothstep(.64,.90,patches)*damage*max(n.y,0.0)*.18;
	wash+=vec3(.33,.29,.24)*ash;
	}
	ALBEDO = wash;
}
