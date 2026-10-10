extends MultiMeshInstance3D
## Three original impact marks per cell; a single shared flat decal batch.
var active: Dictionary={}
var zero:=Transform3D(Basis.from_scale(Vector3.ZERO),Vector3.ZERO)
func configure(capacity: int,bounds: AABB):
	name="WallImpactInk"
	multimesh=MultiMesh.new();multimesh.transform_format=MultiMesh.TRANSFORM_3D;multimesh.use_colors=true
	var quad=QuadMesh.new();quad.size=Vector2(.085,.075);multimesh.mesh=quad
	multimesh.instance_count=capacity;multimesh.visible_instance_count=0;multimesh.custom_aabb=bounds.grow(.2)
	for i: int in range(capacity):multimesh.set_instance_transform(i,zero)
	var shader=Shader.new();shader.code="""shader_type spatial;
render_mode unshaded, cull_disabled;
void fragment() {
	vec2 p=abs(UV-vec2(.5));
	ALBEDO=(p.x<.211765 && p.y<.213333) ? vec3(.345098,.364706,.341176) : COLOR.rgb;
}"""
	material_override=ShaderMaterial.new();material_override.shader=shader
	cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Compile the flat-mark shader before combat, using an invisible zero-size slot.
	if capacity>0:
		multimesh.visible_instance_count=1
		RenderingServer.frame_post_draw.connect(func():
			if active.is_empty():multimesh.visible_instance_count=0,CONNECT_ONE_SHOT)
func write(slot: int,marks: Array,object: Dictionary,index: int,pose: Transform3D,cut: float):
	for i: int in range(3):
		var at: int=slot+i
		if not object.alive or object.hp[index]<=0 or i>=marks.size() or marks[i].y>=cut:
			if active.has(at):multimesh.set_instance_transform(at,zero);active.erase(at)
			continue
		var mark: Vector3=marks[i];var side: float=signf(mark.z)
		var local=Transform3D(Basis.from_scale(Vector3(1,1,side)),Vector3(mark.x,mark.y,side*(object.size.y*.5+.012)))
		multimesh.set_instance_transform(at,pose*local)
		multimesh.set_instance_color(at,preload("res://scripts/terrain_art.gd").pigment(object.material).darkened(.30))
		active[at]=true
func finish():
	var last: int=-1
	for slot: int in active:last=maxi(last,slot)
	multimesh.visible_instance_count=last+1
