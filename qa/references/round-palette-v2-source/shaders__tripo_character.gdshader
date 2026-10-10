shader_type spatial;
render_mode unshaded, cull_back;
#include "res://shaders/range2_ink.gdshaderinc"
uniform sampler2D base_texture : source_color, filter_linear_mipmap;
uniform bool textured = false;
uniform bool from_material = false;
uniform vec4 solid_color : source_color = vec4(1.0);
uniform bool red_team = false;
uniform vec4 team_tint : source_color = vec4(1.0);
uniform vec4 paper : source_color = vec4(0.81,0.80,0.86,1.0);
uniform vec4 team_paper : source_color = vec4(0.60,0.71,0.85,1.0);
uniform vec4 ink : source_color = vec4(0.28,0.25,0.35,1.0);
uniform float hatch_strength = 0.26;
void fragment() {
	vec3 color=textured ? texture(base_texture,UV).rgb : COLOR.rgb;
	if (!textured && from_material) color=solid_color.rgb;
	if (textured) color*=team_tint.rgb;
	float value=dot(color,vec3(.2126,.7152,.0722));
	// Retain the source eyes, hair, garment seams and pockets as drawn ink values.
	float dark=1.0-smoothstep(.018,.15,value);
	vec3 wash=mix(paper.rgb*.80,paper.rgb,smoothstep(.05,.65,value));
	// Tint the supplied blue cloth, preserving neutral skin, eyes and insignia.
	float cloth=textured ? smoothstep(.015,.09,color.b-color.r) : .68;
	wash=mix(wash,team_paper.rgb*mix(.85,1.0,smoothstep(.05,.65,value)),cloth*.88);
	wash=mix(wash,ink.rgb,dark*.92);
	// A stronger band remains readable when the soldier is small on screen.
	bool band=!textured && color.b>color.r*1.55 && color.b>color.g*1.2;
	if (band) wash=red_team ? vec3(.42,.13,.20) : vec3(.12,.23,.43);
	vec3 n=normalize((INV_VIEW_MATRIX*vec4(normalize(NORMAL),0.0)).xyz);
	float light=dot(n,normalize(vec3(.65,1.0,.65)));
	float shade=1.0-smoothstep(-.1,.65,light);
	wash*=1.0-shade*.10;
	float coordinate=FRAGCOORD.x+FRAGCOORD.y*.25;
	float stripe=1.0-smoothstep(.30,.95,mod(coordinate,3.2));
	float broken=1.0-step(8.0,mod(floor(coordinate/3.2),11.0));
	float hatch=stripe*broken*shade*hatch_strength;
	float edge=0.0;
	if (textured) {
		vec2 dx=dFdx(UV)*.8;vec2 dy=dFdy(UV)*.8;
		vec3 gx=texture(base_texture,UV+dx).rgb-texture(base_texture,UV-dx).rgb;
		vec3 gy=texture(base_texture,UV+dy).rgb-texture(base_texture,UV-dy).rgb;
		edge=smoothstep(.035,.16,max(length(gx),length(gy)))*.48;
	}
	float facing=abs(dot(normalize(NORMAL),normalize(VIEW)));
	float contour=(1.0-smoothstep(.07,.20,facing))*.50;
	ALBEDO=mix(wash,ink.rgb,clamp(max(edge,contour)+hatch,0.0,.85));
	// RANGE2_FINISH: crowd attachment ink is inserted before this shared treatment.
	if (range2_enabled) {
		vec3 team_color=red_team ? vec3(.54,.30,.24) : vec3(.23,.40,.49);
		vec3 graphic_base=mix(color,vec3(.76,.68,.55),.28);
		graphic_base=mix(graphic_base,team_color,cloth*.76);
		graphic_base*=mix(.70,1.05,smoothstep(.05,.65,value));
		graphic_base=mix(graphic_base,vec3(.045,.055,.075),dark*.95);
		if (band) graphic_base=team_color*.42;
		// RANGE2_KIT_BASE
		ALBEDO=range2_finish(graphic_base,n,NORMAL,VIEW,UV,0.0);
	}
}
