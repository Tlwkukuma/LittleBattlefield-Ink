shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_prepass_alpha;

varying vec4 ink_data;
uniform bool gpu_motion = false;
uniform sampler2D flight_data : filter_nearest, repeat_disable;
uniform float blood_clock = 0.0;
uniform mat3 camera_frame;
uniform float pixel_size = 0.015;
void vertex() {
	ink_data = INSTANCE_CUSTOM;
	if (gpu_motion) {
		int slot = int(INSTANCE_CUSTOM.x);
		vec4 origin = texelFetch(flight_data, ivec2(0, slot), 0);
		vec4 motion = texelFetch(flight_data, ivec2(1, slot), 0);
		vec4 style = texelFetch(flight_data, ivec2(2, slot), 0);
		COLOR = texelFetch(flight_data, ivec2(3, slot), 0);
		float age = max(0.0, blood_clock - origin.w);
		float ratio = age / max(0.001, motion.w);
		if (style.w > 1.5) {
			vec2 point = VERTEX.xy * vec2(style.x, style.x * 0.65);
			float c = cos(motion.x); float s = sin(motion.x);
			VERTEX = origin.xyz + vec3(c * point.x - s * point.y, 0.0, -s * point.x - c * point.y);
			ink_data = vec4((1.0 - smoothstep(motion.w - 2.0, motion.w, age)) * 0.78, style.z, 1.0, 0.0);
		} else {
			vec3 velocity = motion.xyz - vec3(0.0, style.y * age, 0.0);
			vec2 projected = vec2(dot(velocity, camera_frame[0]), dot(velocity, camera_frame[1]));
			float angle = dot(projected, projected) > 0.001 ? atan(projected.y, projected.x) - 1.57079632679 : 0.0;
			float radius = max(style.x, min(0.085, pixel_size * 1.8));
			float scale_factor = style.w > 0.5 ? mix(0.65, 1.25, smoothstep(0.0, 0.45, ratio)) : 1.0;
			vec2 point = VERTEX.xy * vec2(radius, radius * (style.w > 0.5 ? 1.3 : 1.9)) * scale_factor;
			float c = cos(angle); float s = sin(angle);
			vec2 rotated = vec2(c * point.x - s * point.y, s * point.x + c * point.y);
			vec3 position = origin.xyz + motion.xyz * age - vec3(0.0, style.y * age * age * 0.5, 0.0);
			VERTEX = position + camera_frame * vec3(rotated, 0.025);
			ink_data = vec4(1.0 - smoothstep(0.55, 1.0, ratio), style.z, 0.0, 0.0);
		}
		if (motion.w <= 0.0 || age >= motion.w) { VERTEX = vec3(0.0); ink_data.x = 0.0; }
	}
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float angle = atan(p.y, p.x);
	float edge = 0.80 + 0.07 * sin(angle * 5.0 + ink_data.y * 19.0)
		+ 0.04 * sin(angle * 9.0 - ink_data.y * 13.0);
	// A tapered ink droplet, with a rounded irregular stain variant.
	p.x /= mix(0.80 + 0.20 * (1.0 - UV.y), 1.0, ink_data.z);
	float radius = length(p);
	float coverage = 1.0 - smoothstep(edge - 0.05, edge, radius);
	float rim = smoothstep(edge - 0.18, edge - 0.03, radius);
	ALBEDO = mix(COLOR.rgb, COLOR.rgb * 0.46, rim * 0.72);
	ALPHA = coverage * ink_data.x;
	ROUGHNESS = 1.0;
}
