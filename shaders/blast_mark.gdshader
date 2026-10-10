shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float effect_clock=0.0;

float hash21(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise2(vec2 p) {
	vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
	return mix(mix(hash21(i),hash21(i+vec2(1,0)),f.x),mix(hash21(i+vec2(0,1)),hash21(i+vec2(1)),f.x),f.y);
}
void vertex() {
	float angle=atan(UV.y,UV.x),seed=UV2.y*37.0;
	float shape=1.0+.065*sin(angle*5.0+seed)+.035*sin(angle*11.0-seed);
	float r=length(UV)/shape;
	float rim=smoothstep(.52,.69,r)*(1.0-smoothstep(.72,.89,r));
	// Cosmetic relief stays below four centimetres; traversal and support stay shared.
	VERTEX.y+=rim*.035*COLOR.a;
}
void fragment() {
	float age=effect_clock-UV2.x;
	vec2 p=UV;float seed=UV2.y*37.0;
	float radius=length(p),angle=atan(p.y,p.x);
	float coarse=noise2(p*4.5+seed);
	float grit=noise2(p*31.0+seed);
	float shape=1.0+.065*sin(angle*5.0+seed)+.035*sin(angle*11.0-seed);
	float r=radius/shape;
	float edge=1.0-smoothstep(.80,1.17,r+(coarse-.5)*.19);
	float opacity=edge*(1.0-smoothstep(66.0,90.0,age))*smoothstep(0.0,.10,age);
	// Sparse thrown earth separates from a broken outer edge.
	if(r>.78) opacity*=mix(.25,1.0,smoothstep(.22,.63,coarse));
	float screen_grain=fract(dot(floor(FRAGCOORD.xy),vec2(.75487766,.56984029)));
	if(screen_grain>opacity || age<0.0) discard;
	vec3 soil=COLOR.rgb;
	float relief=COLOR.a;
	float bowl=1.0-smoothstep(.20,.60,r);
	float inner_wall=smoothstep(.30,.52,r)*(1.0-smoothstep(.59,.73,r));
	float lip=smoothstep(.52,.69,r)*(1.0-smoothstep(.72,.89,r));
	float facing=dot(normalize(p+vec2(.001)),normalize(vec2(-.5,-.8)));
	// Concave shading reverses on the inside wall; the rim catches the light.
	float light=1.0-bowl*.42-inner_wall*(.16+facing*.22)*relief;
	light+=lip*(.15+facing*.14)*relief;
	light+=(coarse-.5)*.13+(grit-.5)*.16;
	float fissure=1.0-smoothstep(.018,.050,abs(sin(angle*9.0+coarse*2.4+seed)));
	light-=fissure*smoothstep(.43,.65,r)*(1.0-smoothstep(.72,.98,r))*.17*relief;
	vec3 color=soil*light;
	float clod=step(.80,grit)*smoothstep(.57,.72,r)*(1.0-smoothstep(.98,1.13,r));
	color=mix(color,soil*1.18,clod*.55);
	ALBEDO=color;
}
