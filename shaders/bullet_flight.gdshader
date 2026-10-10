shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;
varying vec4 flight_data;
void vertex() { flight_data=INSTANCE_CUSTOM; }
void fragment() {
	float t=UV.y;
	float head_size=flight_data.x;
	float nose=sqrt(clamp(t/max(head_size*.28,.01),0.0,1.0));
	float taper=mix(.09,1.0,pow(1.0-t,.42));
	float x=abs(UV.x*2.0-1.0)/max(.015,nose*taper);
	float edge=1.0-smoothstep(.62,1.0,x);
	float core=(1.0-smoothstep(.15,.57,x))*(1.0-smoothstep(head_size*.40,.93,t));
	float fade=pow(1.0-t,.75)*smoothstep(0.0,.025,t);
	// Preserve caliber hue in the bright core instead of whitening every round.
	ALBEDO=mix(COLOR.rgb,mix(COLOR.rgb,vec3(1.0,.98,.92),.36),core);
	EMISSION=ALBEDO*core*.17;
	ALPHA=edge*fade*flight_data.y;
	if(ALPHA<.015)discard;
}
