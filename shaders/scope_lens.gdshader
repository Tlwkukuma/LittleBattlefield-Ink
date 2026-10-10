shader_type canvas_item;
uniform float kick = 0.0;
void fragment() {
	float radius = length(UV - vec2(0.5)) * 2.0;
	vec4 scene = texture(TEXTURE, UV);
	float edge = smoothstep(0.65, 1.0, radius);
	COLOR = vec4(scene.rgb * (1.0 - edge * (0.28 + kick * 0.15)), scene.a * (1.0 - smoothstep(0.975, 1.0, radius)));
}
