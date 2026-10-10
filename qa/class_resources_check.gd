extends SceneTree
## Resource/attachment and interaction selection mathematics; no player input,
## gameplay simulation, firing, vehicle driving, screenshots or visual acceptance.
const Source=preload("res://scripts/source_rig_character.gd")
const Motion=preload("res://scripts/source_rig_motion.gd")
const Classes=preload("res://scripts/soldier_classes.gd")
const Interaction=preload("res://scripts/range_interaction.gd")
const Catalog=preload("res://scripts/source_catalog.gd")
class SelectionFixture extends RefCounted:
	var player={"alive":true,"mounted":-1,"grounded":true,"vault":{},"position":Vector2.ZERO,"elevation":0.0}
	var blocked=false
	func trace_3d(_origin: Vector3,_direction: Vector3,_distance: float,_p: Dictionary,_walls: bool) -> Dictionary:return {"distance":.2} if blocked else {}
var checks=0
var failures=[]
func _initialize():run.call_deferred()
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures.append(label);push_error(label)
func count_triangles(node: Node3D) -> int:
	var result=0
	for child in node.get_children():
		if child is MeshInstance3D:
			for surface in range(child.mesh.get_surface_count()):
				var arrays=child.mesh.surface_get_arrays(surface)
				result+=arrays[Mesh.ARRAY_VERTEX].size()/3
	return result
func run():
	var stage=Node3D.new();root.add_child(stage);var maximum_triangles=0
	var catalog=Catalog.new()
	for id in Classes.IDS:check(catalog.weapons.has(Classes.profile(id).weapon),"Showcase weapon is a real original weapon "+id)
	var signatures=[]
	for team in [0,1]:
		var view=Source.soldier(stage,team,true);Motion.sample(view,"Rifle_idle",1.0/24)
		var rig: Skeleton3D=view.skeleton;var body=view.model.find_child("Source_Body",true,false)
		var original_mesh=body.mesh;var skin=body.skin;var skeleton_path=body.skeleton
		var before=[]
		for bone in range(rig.get_bone_count()):before.append([rig.get_bone_rest(bone),rig.get_bone_pose(bone)])
		for id in Classes.IDS:
			Classes.apply(view,id,team)
			var head=view.helmet.get_node("ClassHelmet");var pack=view.backpack.get_node("ClassEquipment")
			var count=count_triangles(head)+count_triangles(pack);maximum_triangles=maxi(count,maximum_triangles)
			if team==0:signatures.append(count)
			check(head.get_child_count()>0 and pack.get_child_count()>0 and count>100,"Distinct equipment exists "+id+" team="+str(team))
			check(body.mesh==original_mesh and body.skin==skin and body.skeleton==skeleton_path and rig.get_bone_count()==41,"Source mesh, skin and 41 bones unchanged "+id)
			var unchanged=true
			for bone in range(rig.get_bone_count()):unchanged=unchanged and rig.get_bone_rest(bone).is_equal_approx(before[bone][0]) and rig.get_bone_pose(bone).is_equal_approx(before[bone][1])
			check(unchanged,"Changing kit never writes the source pose "+id)
			check(head.get_parent()==view.helmet and pack.get_parent()==view.backpack and view.backpack.mesh==null,"Helmet and backpack follow the existing rigid attachments "+id)
			var identity=head.get_instance_id();Classes.apply(view,id,team)
			check(view.helmet.get_node("ClassHelmet").get_instance_id()==identity,"Repeated frame sync reuses kit nodes "+id)
			var copy=head.duplicate();stage.add_child(copy)
			check(count_triangles(copy)==count_triangles(head),"Dropped-helmet copy retains the profession details "+id);copy.free()
			check(head.get_child_count()<=4 and pack.get_child_count()<=12 and count<9000,"Bounded merged kit geometry "+id+" triangles="+str(count))
			check(view.helmet.get_child_count()==1 and view.backpack.get_child_count()==1,"Switching class releases the previous kit "+id)
		view.helmet.hide();Classes.apply(view,"medic",team);check(not view.helmet.visible,"Switching class cannot respawn a lost helmet")
		view.root.free()
	check(signatures.size()==5 and signatures[0]!=signatures[1] and signatures[1]!=signatures[2] and signatures[2]!=signatures[3] and signatures[3]!=signatures[4],"Five different equipment silhouettes/resources")
	var fixture=SelectionFixture.new()
	var close={"kind":"class","class_id":"medic","position":Vector3(.3,.4,.8)}
	var far={"kind":"class","class_id":"engineer","position":Vector3(0,.4,1.6)}
	check(Interaction.nearest(fixture,[far,close]).get("class_id","")=="medic","E chooses only the nearest reachable interaction")
	fixture.blocked=true;check(Interaction.nearest(fixture,[close]).is_empty(),"E cannot interact through a wall");fixture.blocked=false
	fixture.player.position=Vector2(5,0);check(Interaction.nearest(fixture,[close]).is_empty(),"E rejects out-of-range objects");fixture.player.position=Vector2.ZERO
	fixture.player.mounted=0;check(Interaction.nearest(fixture,[close]).is_empty(),"E cannot leave or change kit inside a vehicle");fixture.player.mounted=-1
	fixture.player.vault={"age":.2};check(Interaction.nearest(fixture,[close]).is_empty(),"Climbing blocks world interaction");fixture.player.vault={}
	fixture.player.alive=false;check(Interaction.nearest(fixture,[close]).is_empty(),"Dead players cannot interact")
	stage.free()
	print("CLASS_RESOURCES_CHECK ",checks-failures.size(),"/",checks," passed; max_kit_triangles=",maximum_triangles," failures=",failures)
	quit(0 if failures.is_empty() else 1)
