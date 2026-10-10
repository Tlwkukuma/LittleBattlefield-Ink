shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D particles : filter_nearest, repeat_disable;
uniform float elapsed=0.0;
varying vec4 tint;
varying float effect_kind;
varying float seed;
void vertex(){
	int slot=int(INSTANCE_CUSTOM.x);
	vec4 origin=texelFetch(particles,ivec2(0,slot),0);
	vec4 motion=texelFetch(particles,ivec2(1,slot),0);
	vec4 shape=texelFetch(particles,ivec2(2,slot),0);
	tint=texelFetch(particles,ivec2(3,slot),0);
	vec4 style=texelFetch(particles,ivec2(4,slot),0);effect_kind=style.x;seed=style.y;
	float age=max(0.0,elapsed-origin.w);
	float live=step(age,motion.w)*step(.0001,motion.w);
	float scale=(1.0+age*(effect_kind<.5?.55:2.5))*clamp((motion.w-age)/max(.001,min(.25,motion.w)),0.0,1.0)*live;
	vec3 center=origin.xyz+motion.xyz*age-vec3(0,shape.w*age*age*.5,0);
	vec4 view_center=VIEW_MATRIX*vec4(center,1);
	vec2 size=vec2(max(shape.x,shape.z),max(shape.y,shape.z))*scale;
	vec2 local=VERTEX.xy;
	if(effect_kind>1.5){
		vec2 direction=(VIEW_MATRIX*vec4(motion.xyz,0)).xy;
		direction=length(direction)>.0001?normalize(direction):vec2(0,1);
		size=vec2(min(shape.x,shape.y),max(shape.x,shape.z))*live;
		local=vec2(-direction.y,direction.x)*local.x*size.x+direction*local.y*size.y;
	}else{local*=size;}
	POSITION=PROJECTION_MATRIX*(view_center+vec4(local,0,0));
}
void fragment(){
	vec2 p=UV*2.0-1.0;
	float d=dot(p,p);
	if(effect_kind>1.5){if(abs(p.x)>.85)discard;}
	else{float edge=1.0+.06*sin(atan(p.y,p.x)*7.0+seed);if(d>edge)discard;}
	ALBEDO=tint.rgb*(1.0-.10*smoothstep(.1,1.0,d));
}
