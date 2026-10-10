shader_type spatial;
render_mode unshaded, fog_disabled, cull_back, depth_test_disabled, depth_draw_never;

uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec4 tint : source_color = vec4(0.48, 0.80, 0.94, 1.0);
uniform float visibility = 0.0;
uniform bool foot_marker = false;

void fragment() {
	if (foot_marker) {
		ALBEDO = tint.rgb;
		ALPHA = visibility * 0.78;
	} else {
		float depth = textureLod(scene_depth, SCREEN_UV, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
#else
		vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#endif
		vec4 surface = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
		// Compare metres in view space, independent of reversed Z / projection.
		float behind = -VERTEX.z + surface.z / surface.w;
		if (behind <= 0.065) discard;
		float rim = 1.0 - smoothstep(0.10, 0.62, abs(dot(normalize(NORMAL), normalize(VIEW))));
		ALBEDO = mix(tint.rgb * 0.82, tint.rgb, rim);
		ALPHA = visibility * mix(0.24, 0.76, rim) * smoothstep(0.065, 0.14, behind);
	}
}
