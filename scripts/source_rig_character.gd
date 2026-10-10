extends RefCounted
## Native GLB preserves the user's 41 bones, bind matrices, skin and animation tracks.
const Style=preload("res://scripts/soldier_style.gd")
const SHADER=preload("res://shaders/tripo_character.gdshader")
const OUTLINE=preload("res://shaders/character_outline.gdshader")
static var packed: PackedScene
static var provenance: Dictionary={}
static var materials: Dictionary={}
const PALETTE_PARTS={"Helmet_BlueGrey":1,"Team_Blue":2,"Helmet_Rim":3,"Canvas_Olive":4,"Canvas_Flap":5,"Webbing_Dark":6}
static func info() -> Dictionary:
	if provenance.is_empty():provenance=JSON.parse_string(FileAccess.get_file_as_string("res://assets/tripo_source/provenance.json"))
	return provenance
static func find_type(node: Node,type: String) -> Node:
	if node.is_class(type):return node
	for child in node.get_children():
		var result=find_type(child,type)
		if result!=null:return result
	return null
static func apply_material(node: MeshInstance3D,team: int,textured: bool):
	for surface in range(node.mesh.get_surface_count()):
		var original: StandardMaterial3D=node.mesh.surface_get_material(surface)
		var key=str(team)+str(textured)+str(original.albedo_color)+original.resource_name
		if not materials.has(key):
			var m=ShaderMaterial.new();m.shader=SHADER;m.set_shader_parameter("textured",textured);m.set_shader_parameter("red_team",team==1)
			m.set_shader_parameter("from_material",true);m.set_shader_parameter("solid_color",original.albedo_color)
			m.set_shader_parameter("range2_part",PALETTE_PARTS.get(original.resource_name,0))
			m.set_shader_parameter("team_paper",Color("d8a0a6") if team==1 else Color("98b5d8"))
			if textured:m.set_shader_parameter("base_texture",original.albedo_texture)
			var outline=ShaderMaterial.new();outline.shader=OUTLINE;m.next_pass=outline
			materials[key]=m
		node.set_surface_override_material(surface,materials[key])
static func soldier(parent: Node3D,team: int,_controlled: bool) -> Dictionary:
	if packed==null:packed=load("res://assets/tripo_source/source-rig-soldier.glb")
	var root=Node3D.new();parent.add_child(root);var body=Node3D.new();root.add_child(body)
	var model=packed.instantiate();body.add_child(model)
	var rig: Skeleton3D=find_type(model,"Skeleton3D")
	var animator: AnimationPlayer=find_type(model,"AnimationPlayer");animator.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var character: MeshInstance3D=model.find_child("Source_Body",true,false);apply_material(character,team,true)
	var helmet: MeshInstance3D=model.find_child("Helmet_Detachable",true,false);apply_material(helmet,team,false)
	var pack: MeshInstance3D=model.find_child("Backpack",true,false);apply_material(pack,team,false)
	var proxy: MeshInstance3D=model.find_child("Rifle_Pose_Prop",true,false)
	var weapon_parent=Node3D.new();proxy.get_parent().add_child(weapon_parent);weapon_parent.transform=proxy.transform;proxy.hide()
	var shadow=Style.shadow(root)
	var indices={}
	for name in ["Root","Hip","Spine02","Head","L_Thigh","L_Calf","L_Foot","L_ToeBase","R_Thigh","R_Calf","R_Foot","R_ToeBase"]:indices[name]=rig.find_bone(name)
	return {"root":root,"body":body,"model":model,"skeleton":rig,"animator":animator,"helmet":helmet,"backpack":pack,"shadow":shadow,"weapon_parent":weapon_parent,"rifle_rest":Vector3.ZERO,"tripo":true,"source_rig":true,"bone_indices":indices,"source_info":info(),"animation_time":0.0,"source_clip":"","speed":0.0,"sprint":0.0,"foot_contact":[false,false],"carry":0.0,"previous_stance":0.0}
