// A shared, single-pass material treatment. No screen/depth copy or extra geometry.
global uniform bool range2_enabled;
global uniform sampler2D range2_wear : filter_linear_mipmap, repeat_enable;

vec3 range2_finish(vec3 base, vec3 world_normal, vec3 view_normal, vec3 view_direction, vec2 surface_uv, float wear) {
	vec3 n = normalize(world_normal);
	float illumination = dot(n, normalize(vec3(-0.50, 0.85, 0.35)));
	float middle = smoothstep(-0.12, -0.04, illumination);
	float bright = smoothstep(0.52, 0.60, illumination);
	float value = dot(base, vec3(0.2126, 0.7152, 0.0722));
	vec3 paint = clamp(mix(vec3(value), base, 1.55) * 1.09 - 0.055, vec3(0.015), vec3(0.96));
	vec3 shaded = paint * (0.44 + middle * 0.30 + bright * 0.30);
	shaded = mix(shaded * vec3(0.79, 0.90, 1.13), shaded * vec3(1.07, 1.025, 0.91), middle);
	// One authored, mip-filtered scratch tile, anchored to the surface, not the screen.
	float marks = (1.0 - texture(range2_wear, surface_uv).r) * wear;
	float facing = abs(dot(normalize(view_normal), normalize(view_direction)));
	float rim = (1.0 - smoothstep(0.035, 0.17, facing)) * 0.78;
	return mix(shaded, vec3(0.035, 0.045, 0.065), clamp(max(rim, marks * (0.20 + (1.0-middle)*0.28)), 0.0, 0.88));
}

// Dominant-axis projection needs one texture lookup and follows authored mesh space.
vec2 range2_projection(vec3 p, vec3 n) {
	vec3 a = abs(n);
	if (a.y >= a.x && a.y >= a.z) return p.xz;
	return a.x > a.z ? p.zy : p.xy;
}
