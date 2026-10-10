extends SceneTree
## Isolated geometry, projection, resource and lifetime checks; no gameplay input.
const Occlusion=preload("res://scripts/player_occlusion.gd")
const Catalog=preload("res://scripts/source_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
const Rig=preload("res://scripts/source_rig_character.gd")
const Pose=preload("res://scripts/combat_pose.gd")
const Visibility=preload("res://scripts/house_visibility.gd")
var checks=0
var failures=[]
class GameFixture extends Node3D:
	var world
	var camera: Camera3D
	var editing=false
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize():call_deferred("run")
func run():
	var stage=Node3D.new();root.add_child(stage)
	var camera=Camera3D.new();stage.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=23;camera.near=.05;camera.far=300
	camera.position=Vector3(0,48,48);camera.look_at(Vector3.ZERO)
	for projection in [Camera3D.PROJECTION_ORTHOGONAL,Camera3D.PROJECTION_PERSPECTIVE]:
		camera.projection=projection
		for point in [Vector3.ZERO,Vector3(8.4,1.1,-5.7),Vector3(-5,3.4,2),Vector3(0,-1.6,0)]:
			var ray=Occlusion.camera_ray(camera,point)
			check((ray.origin+ray.direction*(ray.distance+.12)).distance_to(point)<.002,"projection ray reaches actual sample %s / %s"%[projection,point])
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	var actor=Rig.soldier(stage,0,true);var npc=Rig.soldier(stage,1,false)
	var aid=Occlusion.new();aid.configure(actor,stage)
	var body: MeshInstance3D=actor.model.find_child("Source_Body",true,false)
	var npc_body: MeshInstance3D=npc.model.find_child("Source_Body",true,false)
	check(aid.copies.size()==2,"only source body and helmet receive local draws")
	check(aid.copies[0].mesh==body.mesh and aid.copies[0].skin==body.skin,"body reuses original mesh and Skin")
	check(aid.copies[0].get_node(aid.copies[0].skeleton)==actor.skeleton,"body reuses existing animated skeleton")
	check(aid.copies[0].global_transform==body.global_transform,"source and silhouette transforms agree")
	check(npc_body.material_overlay==null and not npc_body.has_node("PlayerOcclusion"),"no enemy overlay or ghost nodes")
	check(body.material_override==null and body.get_surface_override_material(0)!=aid.material,"source material remains independent")
	body.layers=0;actor.helmet.layers=0
	check(aid.copies[0].layers==1 and aid.copies[1].layers==1,"campaign crowd layers cannot suppress player hint")
	var triangles=0
	for copy in aid.copies:
		check(not copy.visible and copy.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"inactive copy has zero visible/shadow draws")
		for s in range(copy.mesh.get_surface_count()):triangles+=copy.mesh.surface_get_array_index_len(s)/3
	var vertices=aid.marker.mesh.get_faces();var plane=PlaneMesh.new().get_faces()
	var ring_normal=(vertices[1]-vertices[0]).cross(vertices[2]-vertices[0])
	var plane_normal=(plane[1]-plane[0]).cross(plane[2]-plane[0])
	check(ring_normal.dot(plane_normal)>0,"foot ring winding matches built-in upward PlaneMesh")
	check(vertices.size()==192,"foot marker has fixed 64 triangles")
	for i in range(8):aid.advance(1.0/60.0,true)
	check(is_equal_approx(aid.opacity,1.0),"120 ms fade-in reaches visible state")
	for i in range(7):aid.advance(1.0/60.0,false)
	check(aid.blocked and is_equal_approx(aid.opacity,1.0),"short doorway-edge clear interval cannot flicker")
	for i in range(30):aid.advance(1.0/60.0,false)
	check(not aid.blocked and is_zero_approx(aid.opacity),"stable clear view removes hint entirely")
	aid.reset();check(aid.opacity==0 and not aid.marker.visible,"reset clears presentation")
	var catalog=Catalog.new();var plan=catalog.range_plan()
	plan.instances=[{"id":"house","prefabId":"building.residence-two-storey","x":2000,"y":1400}]
	plan.looseSegments=[];plan.trees=[];plan.units.red=[];plan.world.groundFeatures=[]
	var world=World.new();var compiled=world.setup(plan,catalog);var roof=compiled.roofs[0]
	var costs=[]
	for sample in [[Vector3(0,0,-7),true,"north exterior behind tall house"],[Vector3(0,0,9),false,"clear front entrance"],[Vector3(10,3.4,-4),true,"exterior landing behind railing"],[Vector3(12,3.4,-4),false,"clear of exterior railing"],[Vector3(0,6.9,0),false,"above roof"]]:
		var p: Vector3=sample[0];var unit=world.player;unit.position=Vector2(p.x,p.z);unit.elevation=p.y;unit.stance=0;unit.stance_blend=0;unit.hit_shapes=[]
		check(not Visibility.inside(roof,unit.position,p.y),"exterior remains exterior: "+sample[2])
		var sample_costs=[]
		for i in range(20):
			var covered=aid.query(world,camera,unit,Vector3.ZERO);costs.append(aid.last_query_us);sample_costs.append(aid.last_query_us)
			if i==0:check(covered==sample[1],"occlusion geometry: "+sample[2])
			check(aid.last_probe_count<=Occlusion.MAX_PROBES,"bounded player-only query count")
		sample_costs.sort();print("OCCLUSION_COST ",sample[2]," median_us=",sample_costs[10]," max_us=",sample_costs.back())
	# A camera-hidden upper floor remains physically ballistic; camera-only queries
	# observe the cutaway. This isolated fixture never changes game room state.
	var wall_plan={"world":{"w":800,"h":800,"groundFeatures":[]},"instances":[],"looseSegments":[{"id":"panel","componentId":"wall.concrete","x1":300,"y1":400,"x2":500,"y2":400,"thickness":12,"godot3d":{"height":5}}],"trees":[],"deployment":{"player":{"x":400,"y":360}}}
	var wall_world=World.new();wall_world.setup(wall_plan,catalog);var panel=wall_world.objects[0]
	wall_world.player.position=Vector2(0,-1);wall_world.player.elevation=0
	check(aid.query(wall_world,camera,wall_world.player,Vector3.ZERO),"intact tall wall occludes player")
	panel.camera_hidden=true
	check(not aid.query(wall_world,camera,wall_world.player,Vector3.ZERO),"hidden cutaway cannot trigger overlay")
	check(not wall_world.trace_3d(Vector3(0,1,2),Vector3.FORWARD,4,{},true).is_empty(),"hidden wall still blocks real bullets")
	panel.camera_hidden=false;panel.aim_cut_height=.05
	check(not aid.query(wall_world,camera,wall_world.player,Vector3.ZERO),"low cut edge uses actual displayed height")
	panel.aim_cut_height=INF;panel.hp.fill(0)
	check(not aid.query(wall_world,camera,wall_world.player,Vector3.ZERO),"destroyed cells no longer trigger silhouette")
	var game=GameFixture.new();root.add_child(game);game.world=wall_world;game.camera=camera
	actor.root.position=Pose.base(wall_world.player);aid.reset()
	var before=aid.total_probes
	for i in range(600):aid.refresh(game,1.0/60.0)
	check(aid.total_probes-before<=300,"10 simulated seconds add at most 300 rays, independent of actor count")
	check(not aid.marker.visible and not aid.copies[0].visible,"clear view detaches all visible overlay draws")
	aid.advance(.2,true);wall_world.player.alive=false;before=aid.total_probes;aid.refresh(game,.016)
	check(aid.total_probes==before and aid.opacity==0,"death suppresses overlay and probes immediately")
	wall_world.player.alive=true;game.editing=true;aid.refresh(game,.016)
	check(aid.total_probes==before,"scene editor adds no occlusion queries")
	game.free()
	costs.sort()
	print("PLAYER_OCCLUSION_CONTRACT "+JSON.stringify({"checks":checks,"failures":failures,"query_median_us":costs[costs.size()/2],"query_max_us":costs.back(),"extra_source_triangles":triangles,"marker_triangles":64}))
	stage.free();quit(0 if failures.is_empty() else 1)
