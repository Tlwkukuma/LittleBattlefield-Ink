shader_type spatial;
render_mode unshaded, cull_back, world_vertex_coords;
uniform float effect_clock = 0.0;
varying float effect_age;
varying float effect_life;
varying float effect_kind;
varying float effect_seed;

void vertex() {
	float age=mod(effect_clock-INSTANCE_CUSTOM.x+64.0,64.0);
	float life=INSTANCE_CUSTOM.y;
	float kind=INSTANCE_CUSTOM.z;
	float seed=INSTANCE_CUSTOM.w;
	vec3 center=MODEL_MATRIX[3].xyz;
	vec3 local=VERTEX-center;
	float angle=seed*6.283185;
	vec3 radial=vec3(cos(angle),0.0,sin(angle));
	vec3 displacement=vec3(0.0);
	if(kind<0.5) {
		local*=1.0+age*.44;
		displacement=vec3(.20, .62+seed*.20, .10)*age+radial*age*.12;
	} else if(kind<1.5) {
		local*=max(.02,1.0-age/life*.68);
		local.y*=1.3+.16*sin(age*27.0+angle);
		displacement=vec3(0.0,age*.60,0.0)+radial*age*.10;
	} else if(kind<2.5) {
		local*=1.0+age*4.0;
	} else if(kind<3.5) {
		local*=1.0+age*1.6;
		displacement=radial*age*(2.0+seed*1.8)+vec3(0.0,age*.08,0.0);
	} else {
		float spin=age*(9.0+seed*12.0);
		vec3 axis=normalize(vec3(seed+.2,.7,1.2-seed));
		local=local*cos(spin)+cross(axis,local)*sin(spin)+axis*dot(axis,local)*(1.0-cos(spin));
		displacement=radial*age*(2.0+seed*3.0)+vec3(0.0,age*(3.2+seed*2.0)-5.0*age*age,0.0);
	}
	VERTEX=center+local+displacement;
	effect_age=age;effect_life=life;effect_kind=kind;effect_seed=seed;
}

void fragment() {
	if(effect_age>=effect_life) discard;
	float progress=effect_age/effect_life;
	float fade=1.0-smoothstep(.62,1.0,progress);
	// Opaque screen-door fade keeps depth testing and avoids sorted smoke layers.
	float grain=fract(dot(floor(FRAGCOORD.xy),vec2(.75487766,.56984029)));
	if(grain>fade) discard;
	vec3 color=COLOR.rgb;
	vec3 n=normalize((INV_VIEW_MATRIX*vec4(normalize(NORMAL),0.0)).xyz);
	float face=.72+.28*max(0.0,dot(n,normalize(vec3(-.3,1.0,.5))));
	if(effect_kind>.5 && effect_kind<2.5) {
		color=mix(vec3(1.0,.92,.65),vec3(.78,.26,.075),smoothstep(.04,.65,progress));
		color=mix(color,vec3(.25,.20,.24),smoothstep(.62,1.0,progress)*.7);
		face=.90+.10*face;
	}
	ALBEDO=color*face;
}
