extends Node3D
const Dimensions=preload("res://scripts/vehicle_dimensions.gd")
const Ground=preload("res://scripts/vehicle_grounding.gd")
const Offroad=preload("res://scripts/vehicle_offroad.gd")
const Art=preload("res://scripts/ink_art.gd")
const Geometry=preload("res://scripts/terrain_art.gd")
var world
var stamps: Array=[]
var drawing: MeshInstance3D
var dirty=false
var clock=0.0

func _ready():
	drawing=MeshInstance3D.new();drawing.material_override=Art.ink_material(Color.WHITE,true,.035)
	drawing.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(drawing)

func add_vehicle(v: Dictionary) -> Array:
	if v.get("airborne",false):return []
	var contacts=[];var half: Vector2=Dimensions.for_vehicle(v).half
	var forward=Vector2.from_angle(v.angle);var side=Vector2(-forward.y,forward.x)
	var tracks=Ground.tracked(v)
	var sliding=float(v.get("drift",0))>.08 or (float(v.get("handbrake_input",0))>.5 and v.get("velocity",Vector2.ZERO).length()>1.0)
	var travel: Vector2=v.get("velocity",Vector2.ZERO).normalized() if sliding else forward
	for sign_value in [-1,1]:
		var point=v.position+side*sign_value*half.y*.79-forward*half.x*.62*(1 if sliding or v.speed>=0 else -1)
		var support=Offroad.contact(world.terrain,v.get("ground",{}).get("rocks",[]),point,0,v)
		support=Ground.Structure.contact(support,v.get("ground",{}).get("structures",[]),point,0)
		if support.structure or support.height>support.terrain+.04:continue
		var profile=world.terrain.profile_at(point);var id: String=profile.id
		var loose="snow" in id or "desert" in id or "sand" in id or "mud" in id or "earth" in id
		if not loose and not sliding:continue
		var snow="snow" in id
		var color=Color("93aeb3") if snow else Color("a38b63") if "sand" in id or "desert" in id else Color("97795c")
		if not loose:color=Color("68685e") if not tracks else Color("88806a")
		stamps.append({"at":point,"forward":travel,"width":.37 if tracks else .21,"color":color,"time":world.time,"tracks":tracks and not sliding})
		contacts.append({"point":point,"snow":snow,"loose":loose,"sliding":sliding,"forward":travel if sliding else forward*(1 if v.speed>=0 else -1)})
	while stamps.size()>320:stamps.pop_front()
	dirty=not contacts.is_empty() or dirty
	return contacts

func _process(delta: float):
	clock-=delta
	if clock>0:return
	clock=.10
	while not stamps.is_empty() and world.time-float(stamps[0].time)>55:stamps.pop_front();dirty=true
	if not dirty:return
	dirty=false
	var vertices=PackedVector3Array();var normals=PackedVector3Array();var colors=PackedColorArray()
	for stamp in stamps:
		var forward: Vector2=stamp.forward;var side=Vector2(-forward.y,forward.x)
		var strips=3 if stamp.tracks else 1
		for strip in range(strips):
			var center: Vector2=stamp.at+forward*(strip-1)*.11 if stamp.tracks else stamp.at
			var half_length=.037 if stamp.tracks else .17
			var points=[center-side*stamp.width*.5-forward*half_length,center+side*stamp.width*.5-forward*half_length,center+side*stamp.width*.5+forward*half_length,center-side*stamp.width*.5+forward*half_length]
			for index in [0,2,1,0,3,2]:
				var point: Vector2=points[index];vertices.append(Vector3(point.x,world.terrain.height(point)+.012,point.y));normals.append(Vector3.UP);colors.append(stamp.color)
	drawing.mesh=Geometry.mesh_from(vertices,normals,colors) if not vertices.is_empty() else null

static func update_shadow(view: Dictionary,v: Dictionary,terrain) -> void:
	var pose: Transform3D=view.body.global_transform
	if view.get("shadow_pose",Transform3D(Basis.IDENTITY,Vector3.INF))==pose:return
	view.shadow_pose=pose
	var shadow=view.body.get_node_or_null("GroundShadow")
	if shadow==null:return
	var half: Vector2=Dimensions.for_vehicle(v).half*Vector2(1.12,1.20)
	var forward=Vector2.from_angle(v.angle);var side=Vector2(-forward.y,forward.x)
	var vertices=PackedVector3Array();var normals=PackedVector3Array();var uv=PackedVector2Array()
	for x in range(4):
		for z in range(4):
			for corner in [Vector2(0,0),Vector2(1,1),Vector2(1,0),Vector2(0,0),Vector2(0,1),Vector2(1,1)]:
				var tex=(Vector2(x,z)+corner)/4.0;var local=(tex*2-Vector2.ONE)*Vector2(half.y,half.x)
				var point: Vector2=v.position+side*local.x+forward*local.y
				var support=Ground.Structure.contact(Offroad.contact(terrain,v.get("ground",{}).get("rocks",[]),point,0,v),v.get("ground",{}).get("structures",[]),point,0)
				var height: float=support.height
				vertices.append(Vector3(point.x,height+.016,point.y));normals.append(Vector3.UP);uv.append(tex)
	var arrays=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_TEX_UV]=uv
	var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	shadow.mesh=mesh;shadow.global_transform=Transform3D.IDENTITY
