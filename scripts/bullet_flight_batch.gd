extends Node3D
## One bounded GPU batch for ordinary bullets; collision stays in ProvingWorld.
const Flight=preload("res://scripts/bullet_flight_visual.gd")
const CAPACITY=2048
const MAX_FINISHES=256
var instances=MultiMesh.new()
var finished: Array=[]
var clock_time=0.0
var count=0
var dropped_visuals=0
var bounds=AABB(Vector3(-256,-64,-256),Vector3(512,256,512))

func _ready():
	var mesh=ArrayMesh.new();var arrays=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(-.5,0,0),Vector3(.5,0,0),Vector3(.5,1,0),Vector3(-.5,0,0),Vector3(.5,1,0),Vector3(-.5,1,0)])
	arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,0),Vector2(1,1),Vector2(0,1)])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	instances.transform_format=MultiMesh.TRANSFORM_3D;instances.use_colors=true;instances.use_custom_data=true
	instances.mesh=mesh;instances.instance_count=CAPACITY;instances.visible_instance_count=0;instances.custom_aabb=bounds
	var node=MultiMeshInstance3D.new();node.name="BulletFlightBatch";node.multimesh=instances
	var material=ShaderMaterial.new();material.shader=preload("res://shaders/bullet_flight.gdshader");node.material_override=material
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(node)

func finish(p: Dictionary):
	if not Flight.supports(p.weapon):return
	# Preserve only the final short segment, at the actual contact, for ~one frame.
	# No forward prediction, repeated damage or history of the complete path.
	if finished.size()>=MAX_FINISHES:finished.pop_front()
	finished.append({"round":p.duplicate(),"born":clock_time,"seen":false})

func submit(p: Dictionary,where: Vector3,camera: Camera3D,pixel: float,opacity: float):
	if count>=CAPACITY:dropped_visuals+=1;return
	var data=Flight.geometry(p,where,camera.global_basis,pixel)
	if data.is_empty():return
	instances.set_instance_transform(count,data.pose)
	instances.set_instance_color(count,data.style.color)
	instances.set_instance_custom_data(count,Color(data.style.head,opacity,0,0));count+=1

func refresh(rounds: Array,camera: Camera3D,delta: float,blend: float,player_id: int):
	clock_time+=delta;count=0;dropped_visuals=0
	var pixel=camera.size/maxf(1,get_viewport().get_visible_rect().size.y)
	var screen=get_viewport().get_visible_rect().grow(100)
	# Reserve the cosmetic budget for the player's rounds before background fire.
	for pass_index in range(2):
		for p in rounds:
			if not Flight.supports(p.weapon) or (int(p.get("source",-1))==player_id)!=(pass_index==0):continue
			var point=Flight.head(p,blend)
			if camera.is_position_behind(point) or not screen.has_point(camera.unproject_position(point)):continue
			submit(p,point,camera,pixel,float(p.get("net_opacity",1.0)))
	for i in range(finished.size()-1,-1,-1):
		var entry: Dictionary=finished[i];var p: Dictionary=entry.round;var life=float(Flight.profile(p.weapon).fade)
		# A hit and its removal can occur between two render frames. Always expose
		# its verified final segment once, then fade within the bounded lifetime.
		if not entry.seen:entry.born=clock_time;entry.seen=true
		var age=clock_time-float(entry.born)
		if age>=life:finished.remove_at(i);continue
		var point=Flight.at(p)
		if not camera.is_position_behind(point) and screen.has_point(camera.unproject_position(point)):submit(p,point,camera,pixel,(1-age/life)*.85)
	instances.visible_instance_count=count
