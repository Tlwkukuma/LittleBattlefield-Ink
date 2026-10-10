shader_type canvas_item;
render_mode unshaded;

// UI mask only. No screen texture, second camera or second world render.
uniform vec2 viewport_size = vec2(1440.0, 900.0);
uniform vec2 lens_center = vec2(720.0, 450.0);
uniform float lens_radius = 260.0;
uniform float opacity = 0.0;
uniform float outside_alpha = 0.56;

void fragment() {
	float distance_px = length(UV * viewport_size - lens_center);
	float outside = smoothstep(lens_radius - 2.0, lens_radius + 10.0, distance_px);
	float inner_edge = smoothstep(lens_radius * 0.80, lens_radius - 2.0, distance_px) * (1.0 - outside);
	COLOR = vec4(vec3(0.035, 0.042, 0.055), opacity * (outside * outside_alpha + inner_edge * 0.12));
}
