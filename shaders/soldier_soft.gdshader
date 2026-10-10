shader_type spatial;
render_mode unshaded, cull_back;

uniform vec4 pigment : source_color = vec4(0.63,0.70,0.80,1.0);
uniform bool vertex_tint = false;
uniform int garment = 0;
varying vec3 rest_position;

void vertex() { rest_position=VERTEX; }

void fragment() {
	// View-space normals include skinning. Convert back to a fixed world light.
	vec3 n=normalize((INV_VIEW_MATRIX*vec4(normalize(NORMAL),0.0)).xyz);
	float light=dot(n,normalize(vec3(0.65,1.0,0.65)));
	float lit=smoothstep(-0.12,0.10,light);
	if (garment==1) lit=smoothstep(-0.30,0.48,light);
	float highlight=smoothstep(0.64,0.87,light);
	vec3 color=vertex_tint ? COLOR.rgb : pigment.rgb;
	vec3 shadow=color*vec3(0.70,0.72,0.82);
	if (garment==1) shadow=color*vec3(0.78,0.80,0.87);
	vec3 paint=mix(shadow,color,lit);
	paint=mix(paint,color*1.055,highlight*0.65);
	// Broad, restrained cloth shading; no screen-space hatch or ink silhouette.
	if (garment==1) {
		float front=1.0-smoothstep(-0.14,-0.10,rest_position.z);
		float seam=(1.0-smoothstep(0.003,0.007,abs(rest_position.x)))*front*step(1.02,rest_position.y)*step(rest_position.y,1.42);
		paint*=1.0-seam*0.10;
	}
	ALBEDO=paint;
}
