shader_type spatial;
render_mode unshaded, cull_disabled, world_vertex_coords;
uniform float effect_clock=0.0;
varying float age;
varying float life;
varying float kind;
varying float seed;
float hash21(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise2(vec2 p) {
 vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
 return mix(mix(hash21(i),hash21(i+vec2(1,0)),f.x),mix(hash21(i+vec2(0,1)),hash21(i+vec2(1)),f.x),f.y);
}
void vertex() {
 age=effect_clock-INSTANCE_CUSTOM.x;life=INSTANCE_CUSTOM.y;
 kind=INSTANCE_CUSTOM.z;seed=INSTANCE_CUSTOM.w;
 vec3 center=MODEL_MATRIX[3].xyz;
 vec3 local=VERTEX-center;
 float power=COLOR.a;
 float t=max(0.0,age),progress=t/max(.001,life);
 float angle=seed*6.283185;
 vec3 radial=vec3(cos(angle),0.0,sin(angle));
 vec3 displacement=vec3(0.0);
 vec3 right=INV_VIEW_MATRIX[0].xyz,up=INV_VIEW_MATRIX[1].xyz;
 vec2 size=vec2(length(MODEL_MATRIX[0].xyz),length(MODEL_MATRIX[1].xyz));
 if(kind<3.5 || kind>4.5) local=(right*(UV.x-.5)*size.x+up*(.5-UV.y)*size.y);
 if(kind<.5) {
  float growth=1.0-exp(-t*4.0);
  local*=.48+growth*1.35;
  displacement=radial*(1.0-exp(-t*2.3))*.55*power+vec3(.10,.40+seed*.22,.04)*t*power;
 } else if(kind<1.5) {
  local*=.25+1.25*(1.0-exp(-t*22.0));
  displacement=(radial*.35+vec3(0,.35,0))*t*power;
 } else if(kind<2.5) {
  local*=.55+min(t*24.0,1.0);
 } else if(kind<3.5) {
  local*=.6+min(t*2.0,1.4);
  displacement=radial*(1.0-exp(-t*4.0))*power*1.25;
 } else if(kind<4.5) {
  float spin=t*(12.0+seed*10.0);
  vec3 axis=normalize(vec3(.3+seed,.7,1.1-seed));
  local=local*cos(spin)+cross(axis,local)*sin(spin)+axis*dot(axis,local)*(1.0-cos(spin));
  displacement=radial*t*(2.0+seed*3.0)*power+vec3(0,t*(3.5+seed*2.0)*power-4.9*t*t,0);
 } else {
  vec3 launch=radial*(1.4+seed)*power+vec3(0,(2.5+seed)*power,0);
  vec3 velocity=launch-vec3(0,5.0*t,0);
  vec2 axis=normalize(vec2(dot(velocity,right),dot(velocity,up))+vec2(.001));
  vec3 long_axis=right*axis.x+up*axis.y;
  vec3 side_axis=right*axis.y-up*axis.x;
  local=(side_axis*(UV.x-.5)*size.x+long_axis*(.5-UV.y)*size.y)*(.4+progress*.8);
  displacement=launch*t+vec3(0,-2.5*t*t,0);
 }
 VERTEX=center+local+displacement;
 if(life<=0.0 || age<0.0 || age>=life) VERTEX=center;
}
void fragment() {
 if(life<=0.0 || age<0.0 || age>=life) discard;
 float progress=age/life;
 vec2 p=UV*2.0-1.0;
 float density=1.0;
 float roll=.5;
 float coverage=1.0;
 if(kind<3.5 || kind>4.5) {
  float r=length(p);
  if(r>1.04) discard;
  vec2 drift=vec2(seed*13.0,-age*.55);
  roll=noise2(p*3.6+drift)*.70+noise2(p*8.0+drift*1.3)*.30;
  float lobes=.06*sin(atan(p.y,p.x)*5.0+seed*21.0+age*.8);
  density=1.0-r+(roll-.5)*.33+lobes;
  coverage=smoothstep(.01,.24,density);
 }
 float fade=1.0-smoothstep(.40,1.0,progress);
 if(kind<.5) fade*=smoothstep(0.0,.07,progress)*.91;
 if(kind>2.5 && kind<3.5) fade*=.63;
 if(kind>4.5) fade*=.85;
 float grain=fract(dot(floor(FRAGCOORD.xy),vec2(.75487766,.56984029)));
 if(grain>coverage*fade) discard;
 vec3 color=COLOR.rgb;
 float shade=.78+.18*(1.0-UV.y)+.18*(roll-.5);
 if(kind>.5 && kind<2.5) {
  float heat=clamp(density*.9+(1.0-progress)*.7,0.0,1.0);
  color=mix(vec3(.36,.22,.12),vec3(.96,.47,.12),smoothstep(.18,.52,heat));
  color=mix(color,vec3(1.0,.90,.58),smoothstep(.65,.92,heat));
  if(kind>1.5) color=vec3(1.0,.93,.72);
  shade=1.0;
 } else if(kind>3.5 && kind<4.5) {
  vec3 n=normalize((INV_VIEW_MATRIX*vec4(normalize(NORMAL),0.0)).xyz);
  shade=.70+.30*max(0.0,dot(n,normalize(vec3(-.3,1,.5))));
 }
 ALBEDO=color*shade;
}
