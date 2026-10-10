// Authored material detail and broad light, shared by the existing opaque passes.
global uniform bool range2_enabled;
global uniform sampler2D range2_wear : filter_linear_mipmap, repeat_enable;
global uniform sampler2D range2_materials : source_color, filter_linear_mipmap, repeat_disable;

vec3 range2_texture(vec3 base, vec2 uv, float tile, float amount, float color_weight) {
	vec2 cell=vec2(mod(tile,3.0),floor(tile/3.0));
	// Mirror in an inset tile; explicit gradients prevent wrap-boundary LOD spikes.
	vec2 mirrored=1.0-abs(mod(uv,2.0)-1.0);
	vec2 atlas_uv=(cell+mix(vec2(.024),vec2(.976),mirrored))/vec2(3.0,2.0);
	vec3 tex=textureGrad(range2_materials,atlas_uv,dFdx(uv)*.952/vec2(3.0,2.0),dFdy(uv)*.952/vec2(3.0,2.0)).rgb;
	vec3 average=vec3(.63,.44,.25);
	if (tile>.5 && tile<1.5) average=vec3(.47,.44,.38);
	else if (tile>1.5 && tile<2.5) average=vec3(.25,.37,.38);
	else if (tile>2.5 && tile<3.5) average=vec3(.44,.33,.23);
	else if (tile>3.5 && tile<4.5) average=vec3(.63,.49,.32);
	else if (tile>4.5) average=vec3(.50,.43,.31);
	float detail=clamp(dot(tex,vec3(.2126,.7152,.0722))/dot(average,vec3(.2126,.7152,.0722)),.10,1.60);
	return mix(base,mix(base*detail,tex,color_weight),amount);
}

vec3 range2_finish(vec3 base, vec3 world_normal, vec3 view_normal, vec3 view_direction, vec2 surface_uv, float wear) {
	vec3 n = normalize(world_normal);
	float lit=smoothstep(-.40,.86,dot(n,normalize(vec3(-.50,.85,.35))));
	// No saturation boost: skin, cloth, steel and sand keep distinct values.
	vec3 shaded=base*(.43+.57*lit)*mix(vec3(.82,.89,1.06),vec3(1.035,1.005,.94),lit);
	float facing = abs(dot(normalize(view_normal), normalize(view_direction)));
	float width=max(fwidth(facing)*.8,.015);
	float rim=(1.0-smoothstep(.065-width,.065+width,facing))*.78;
	return mix(shaded,vec3(.045,.050,.058),rim);
}

vec3 range2_glint(vec3 color,vec3 view_n,vec3 view_dir,vec3 world_n,float metal) {
	float facing=abs(dot(normalize(view_n),normalize(view_dir)));
	return color+vec3(.16,.19,.20)*pow(1.0-facing,3.0)*metal*max(.0,world_n.y+.25);
}

// Dominant-axis projection needs one texture lookup and follows authored mesh space.
vec2 range2_projection(vec3 p, vec3 n) {
	vec3 a = abs(n);
	if (a.y >= a.x && a.y >= a.z) return p.xz;
	return a.x > a.z ? p.zy : p.xy;
}
