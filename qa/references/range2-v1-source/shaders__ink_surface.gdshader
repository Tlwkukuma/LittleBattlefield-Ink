shader_type spatial;
render_mode unshaded, cull_disabled;
#include "res://shaders/range2_ink.gdshaderinc"

// Palette and 3.2 px broken hatching follow Bihai's ShipDepth/InkFleet renderer.
uniform vec4 pigment : source_color = vec4(0.8, 0.8, 0.85, 1.0);
uniform bool vertex_tint = false;
uniform float hatch_strength = 0.32;
uniform float paper_strength = 0.018;
uniform bool silhouette = false;
uniform int garment = 0;
uniform float cutaway_opacity = 1.0;
varying vec3 local_normal;
varying vec3 local_position;

void vertex() {
	local_normal = NORMAL;
	local_position = VERTEX;
}

void fragment() {
	// Ordered opaque dithering avoids transparent-object sorting and alpha overdraw.
	float threshold=fract(dot(mod(floor(FRAGCOORD.xy),vec2(4.0)),vec2(.25,.5625)));
	if (cutaway_opacity <= threshold) discard;
	vec3 col = vertex_tint ? COLOR.rgb : pigment.rgb;
	if (range2_enabled) {
		vec3 world_n=normalize((INV_VIEW_MATRIX*vec4(normalize(NORMAL),0.0)).xyz);
		ALBEDO=range2_finish(col,world_n,NORMAL,VIEW,range2_projection(local_position,local_normal)*0.48,0.8);
	} else {
	if (garment > 0) {
		float lighting = dot(normalize(local_normal),normalize(vec3(-0.5,0.85,0.3)));
		float wash = 0.76 + smoothstep(-0.36,0.03,lighting)*0.10 + smoothstep(0.34,0.55,lighting)*0.14;
		col *= wash;
		float stitch = 0.0;
		if (garment == 1) {
			float front = 1.0 - smoothstep(-0.13,-0.10,local_position.z);
			float placket = (1.0 - smoothstep(0.002,0.005,abs(local_position.x))) * step(1.04,local_position.y) * step(local_position.y,1.49) * front;
			float back = smoothstep(0.075,0.12,local_position.z);
			float yoke = (1.0-smoothstep(0.002,0.005,abs(local_position.y-1.40))) * step(abs(local_position.x),0.195) * back;
			stitch = max(placket,yoke);
		} else {
			float side = smoothstep(0.6,0.8,abs(normalize(local_normal).x));
			stitch = (1.0-smoothstep(0.002,0.005,abs(local_position.z-0.045))) * side;
		}
		col *= 1.0-stitch*0.4;
	}
	float slope = 1.0 - abs(local_normal.y);
	float coordinate = FRAGCOORD.x + FRAGCOORD.y * 0.25;
	float stripe = mod(coordinate, 3.2);
	float intermittent = 1.0 - step(8.0, mod(floor(coordinate / 3.2), 11.0));
	float hatch = (1.0 - smoothstep(0.35, 0.95, stripe)) * intermittent * slope;
	float grain = fract(sin(dot(floor(FRAGCOORD.xy), vec2(12.9898,78.233))) * 43758.5453);
	ALBEDO = col * (1.0 - hatch * hatch_strength) + (grain - 0.5) * paper_strength * 0.35;
	if (silhouette) {
		float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
		ALBEDO = mix(vec3(0.10, 0.085, 0.15), ALBEDO, smoothstep(0.04, 0.24, facing));
	}
	}
}
