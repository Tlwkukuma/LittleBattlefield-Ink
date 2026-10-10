uniform sampler2D bone_palette : filter_nearest, repeat_disable;
varying vec4 crowd_style;
varying vec3 crowd_color;
varying vec3 crowd_rest_normal;
varying float crowd_team;
mat4 crowd_bone(int slot,int bone) {
	int row=slot*64+bone;
	vec4 a=texelFetch(bone_palette,ivec2(0,row),0);
	vec4 b=texelFetch(bone_palette,ivec2(1,row),0);
	vec4 c=texelFetch(bone_palette,ivec2(2,row),0);
	return mat4(vec4(a.x,b.x,c.x,0.0),vec4(a.y,b.y,c.y,0.0),vec4(a.z,b.z,c.z,0.0),vec4(a.w,b.w,c.w,1.0));
}
mat4 crowd_pose(int slot,uvec4 bones,vec4 weights) {
	mat4 pose=crowd_bone(slot,int(bones.x))*weights.x;
	if(weights.y>0.0) pose+=crowd_bone(slot,int(bones.y))*weights.y;
	if(weights.z>0.0) pose+=crowd_bone(slot,int(bones.z))*weights.z;
	if(weights.w>0.0) pose+=crowd_bone(slot,int(bones.w))*weights.w;
	return pose;
}
