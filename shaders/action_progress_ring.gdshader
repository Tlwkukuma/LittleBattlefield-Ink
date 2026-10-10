shader_type canvas_item;
render_mode unshaded;
uniform float radius_pixels = 28.0;
uniform float progress = 0.0;
uniform float opacity = 1.0;
void fragment() {
	vec2 p = (UV * 2.0 - 1.0) * (radius_pixels + 3.0);
	float distance_to_ring = abs(length(p) - radius_pixels);
	float background = (1.0 - smoothstep(1.75 - .65, 1.75 + .65, distance_to_ring)) * .65;
	float turn = mod(atan(p.x, -p.y) + TAU, TAU) / TAU;
	float foreground = (1.0 - smoothstep(1.0 - .65, 1.0 + .65, distance_to_ring));
	foreground *= (progress > .001 && turn <= progress) ? 1.0 : 0.0;
	float alpha = foreground + background * (1.0 - foreground);
	vec3 ink = vec3(238.0, 232.0, 216.0) / 255.0;
	vec3 color = (ink * foreground + vec3(.10, .11, .12) * background * (1.0 - foreground)) / max(alpha, .00001);
	COLOR = vec4(color, alpha * opacity);
}
