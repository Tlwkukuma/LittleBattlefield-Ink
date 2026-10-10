shader_type spatial;
render_mode unshaded, cull_disabled;
#include "res://shaders/range2_ink.gdshaderinc"
varying vec3 ground_position;
varying vec3 ground_normal;
void vertex() {
	ground_position=VERTEX;
	ground_normal=NORMAL;
}
void fragment() {
	vec3 n=normalize(ground_normal);
	float light=dot(n,normalize(vec3(-.55,.80,.28)));
	float wash=.66+.34*smoothstep(-.25,.80,light);
	vec3 color=COLOR.rgb*wash;
	float grain=fract(sin(dot(floor(ground_position.xz*65.0),vec2(12.9898,78.233)))*43758.5453)-.5;
	if (COLOR.a<.35) {
		// Fine powder, broad cool shadows and smoother banks; compacted trail is in vertex color.
		color+=vec3(.016,.025,.032)*(1.0-wash);
		color+=grain*.012;
	} else if (COLOR.a<.7) {
		// Small wind ribs follow the dune direction and remain surface detail, not fake relief.
		float wave=sin(ground_position.x*24.0+sin(ground_position.z*.8)*2.5);
		float ripple=smoothstep(.48,.92,wave)*(1.0-smoothstep(.4,.9,1.0-n.y));
		color*=1.0-ripple*.042;
		color+=grain*.024;
	} else {
		color+=grain*.008;
	}
	ALBEDO=color;
	if (range2_enabled) ALBEDO=range2_finish(COLOR.rgb,n,NORMAL,VIEW,ground_position.xz*.30,.45);
}
