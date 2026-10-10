extends RefCounted
## Actual user-supplied FBX, edited in Blender; no generated body replacement.
const Style=preload("res://scripts/soldier_style.gd")
const SHADER=preload("res://shaders/tripo_character.gdshader")
const DIRECTORY="res://assets/tripo_soldier/"
static var metadata: Dictionary={}
static var meshes: Dictionary={}
static var materials: Dictionary={}
static func vector(a: Array) -> Vector3:return Vector3(a[0],a[1],a[2])
static func info() -> Dictionary:
	if metadata.is_empty():metadata=JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY+"rig.json"))
	return metadata
static func material(textured: bool,team: int=0) -> ShaderMaterial:
	var key=str(textured)+str(team)
	if not materials.has(key):
		var m=ShaderMaterial.new();m.shader=SHADER;m.set_shader_parameter("textured",textured);m.set_shader_parameter("red_team",team==1)
		if textured:
			var texture: Texture2D=load(DIRECTORY+"body_basecolor.jpg") if ResourceLoader.exists(DIRECTORY+"body_basecolor.jpg") else ImageTexture.create_from_image(Image.load_from_file(DIRECTORY+"body_basecolor.jpg"))
			m.set_shader_parameter("base_texture",texture)
			m.set_shader_parameter("team_tint",Color.WHITE)
		materials[key]=m
	return materials[key]
static func mesh(kind: String) -> ArrayMesh:
	if meshes.has(kind):return meshes[kind]
	var d=JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY+kind+".mesh.json"))
	var a=[];a.resize(Mesh.ARRAY_MAX);var v=PackedVector3Array();var n=PackedVector3Array();var uv=PackedVector2Array();var c=PackedColorArray()
	var center=vector(info().helmet_center) if kind=="helmet" else Vector3.ZERO
	for i in range(d.vertices.size()/3):
		v.append(Vector3(d.vertices[i*3],d.vertices[i*3+1],d.vertices[i*3+2])-center)
		n.append(Vector3(d.normals[i*3],d.normals[i*3+1],d.normals[i*3+2]))
		uv.append(Vector2(d.uvs[i*2],d.uvs[i*2+1]));c.append(Color(d.colors[i*4],d.colors[i*4+1],d.colors[i*4+2],d.colors[i*4+3]))
	a[Mesh.ARRAY_VERTEX]=v;a[Mesh.ARRAY_NORMAL]=n;a[Mesh.ARRAY_TEX_UV]=uv;a[Mesh.ARRAY_COLOR]=c;a[Mesh.ARRAY_INDEX]=PackedInt32Array(d.indices)
	if kind=="body":a[Mesh.ARRAY_BONES]=PackedInt32Array(d.bones);a[Mesh.ARRAY_WEIGHTS]=PackedFloat32Array(d.weights)
	var result=ArrayMesh.new();result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,a);meshes[kind]=result;return result
static func part(parent: Node3D,kind: String,team: int=0) -> MeshInstance3D:
	var node=MeshInstance3D.new();node.name=kind.capitalize();node.mesh=mesh(kind);node.material_override=material(kind=="body",team);parent.add_child(node);return node
static func soldier(parent: Node3D,team: int,controlled: bool) -> Dictionary:
	var data=info();var root=Node3D.new();parent.add_child(root);var body=Node3D.new();root.add_child(body)
	var skeleton=Skeleton3D.new();skeleton.name="TripoSoldierRig";body.add_child(skeleton)
	var points=[]
	for p in data.points:points.append(vector(p))
	for i in range(data.bones.size()):
		skeleton.add_bone(data.bones[i]);skeleton.set_bone_parent(i,int(data.parents[i]));var origin: Vector3=points[i]-(points[int(data.parents[i])] if int(data.parents[i])>=0 else Vector3.ZERO)
		skeleton.set_bone_rest(i,Transform3D(Basis.IDENTITY,origin))
	skeleton.reset_bone_poses()
	var skin=Skin.new()
	for i in range(points.size()):skin.add_bind(i,Transform3D(Basis.IDENTITY,-points[i]))
	var character=part(body,"body",team);character.skin=skin;character.skeleton=character.get_path_to(skeleton)
	var chest=BoneAttachment3D.new();skeleton.add_child(chest);chest.bone_name="chest"
	var torso=Node3D.new();chest.add_child(torso);torso.position=-points[7];part(torso,"backpack",team)
	var head=BoneAttachment3D.new();skeleton.add_child(head);head.bone_name="neck"
	var helmet=part(head,"helmet",team);helmet.position=vector(data.helmet_center)-points[12]
	var shadow=Style.shadow(root)
	return {"root":root,"body":body,"skeleton":skeleton,"shadow":shadow,"helmet":helmet,"weapon_parent":torso,"rig_points":points,"grips":[vector(data.grips[0]),vector(data.grips[1])],"rifle_rest":vector(data.rifle_rest),"tripo":true}
