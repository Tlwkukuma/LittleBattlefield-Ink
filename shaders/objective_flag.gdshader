shader_type spatial;
render_mode unshaded,cull_disabled;
uniform vec4 team_color : source_color = vec4(0.74,0.41,0.4,1.0);
uniform float control = 1.0;
uniform bool show_zone = false;
void vertex(){
	if(UV.x>0.5 && UV.x<1.5){
		VERTEX.y += 0.8 + 2.65 * control;
		VERTEX.z += sin(TIME*2.2-UV2.x*5.0+UV2.y)*0.095*UV2.x;
	}
}
void fragment(){
	vec3 paint=COLOR.rgb;
	if(UV.x>1.5){
		if(!show_zone){discard;}
		paint=mix(vec3(0.72,0.71,0.61),team_color.rgb,0.5);
	}else if(UV.x>0.5){
		paint*=team_color.rgb;
		float stripe=UV2.x-UV2.y*0.20;
		if(stripe>0.22 && stripe<0.31){paint=vec3(0.91,0.89,0.80);}
		if(UV2.y<0.025 || UV2.y>0.975 || UV2.x>0.98){paint*=0.40;}
	}
	ALBEDO=paint;
}
