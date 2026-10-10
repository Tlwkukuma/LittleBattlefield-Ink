// A clean palette for the original round soldier. No extra textures or passes.
vec3 round_soldier_helmet(bool enemy) {
	return enemy ? vec3(.69,.36,.29) : vec3(.28,.47,.53);
}

vec3 round_soldier_body(vec3 source,bool enemy) {
	float value=dot(source,vec3(.2126,.7152,.0722));
	// The supplied atlas has blue cloth, warm skin and purple-gray boots/ink.
	// Restrict masks by both hue and value so dark seams cannot become cloth.
	float cloth=smoothstep(.035,.13,source.b-source.r)*smoothstep(.30,.49,value);
	float skin=smoothstep(.055,.20,source.r-source.b)*smoothstep(.025,.12,source.g-source.b)*smoothstep(.30,.50,value);
	float detail=mix(.82,1.04,smoothstep(.22,.82,value));
	vec3 uniform_color=enemy ? vec3(.77,.69,.61) : vec3(.60,.72,.75);
	vec3 color=mix(vec3(.80,.78,.69),uniform_color,cloth);
	color=mix(color,vec3(.93,.72,.53),skin)*detail;
	float dark=1.0-smoothstep(.18,.42,value);
	color=mix(color,vec3(.22,.26,.28)*mix(.72,1.05,smoothstep(.09,.38,value)),dark);
	// Preserve eyes and deepest source lines, without tinting the whole face.
	return mix(color,vec3(.105,.12,.13),1.0-smoothstep(.075,.18,value));
}

vec3 round_soldier_part(vec3 source,int part,bool enemy) {
	vec3 helmet=round_soldier_helmet(enemy);
	if (part==1) return helmet;
	if (part==2) return vec3(.87,.83,.68); // small cream recognition stripe
	if (part==3) return helmet*.68; // original rim, never misclassified as stripe
	if (part==4) return vec3(.63,.57,.43);
	if (part==5) return vec3(.69,.62,.47);
	if (part==6) return vec3(.25,.28,.28);
	return source;
}

vec3 round_soldier_kit(vec3 source) {
	float value=dot(source,vec3(.2126,.7152,.0722));
	float spread=max(source.r,max(source.g,source.b))-min(source.r,min(source.g,source.b));
	if (value<.37) return mix(vec3(.20,.23,.24),vec3(.32,.35,.35),smoothstep(.12,.37,value));
	if (value>.72 && spread<.08) return vec3(.89,.86,.76)*mix(.90,1.05,smoothstep(.72,.95,value));
	// Warm canvas, while keeping green medical markings and the team tabs intact.
	if (source.r-source.b>.055 && source.g-source.b>.045) return mix(source,vec3(.64,.56,.40)*clamp(value/.57,.72,1.16),.38);
	return source;
}

vec3 round_soldier_finish(vec3 color,vec3 world_n,vec3 view_n,vec3 view_dir) {
	float light=smoothstep(-.30,.88,dot(normalize(world_n),normalize(vec3(-.5,.85,.35))));
	vec3 shaded=color*(.76+.24*light)*mix(vec3(.95,.98,1.025),vec3(1.01,1.0,.97),light);
	float facing=abs(dot(normalize(view_n),normalize(view_dir)));
	float edge=(1.0-smoothstep(.035,.15,facing))*.30;
	return mix(shaded,vec3(.16,.19,.20),edge);
}
