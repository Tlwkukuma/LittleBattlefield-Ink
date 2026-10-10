extends SceneTree
## Renderer ownership and physical door checks; never sends game-window input.
const Catalog=preload("res://scripts/source_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
const TerrainArt=preload("res://scripts/terrain_art.gd")
const Art=preload("res://scripts/ink_art.gd")
const Visibility=preload("res://scripts/house_visibility.gd")
const Structure=preload("res://scripts/house_structure.gd")
var checks=0
var failures=[]

func check(ok: bool,message: String):
	checks+=1
	if not ok:failures.append(message);push_error(message)

func opaque(material: ShaderMaterial) -> bool:
	# Headless rendering may return null for an unset shader uniform (default is 1).
	return material.get_shader_parameter("cutaway_opacity") in [null,1.0]

func front_layers(mesh: ArrayMesh,origin: Vector3,direction: Vector3) -> int:
	# A visible point must not have multiple coplanar triangles fighting for depth.
	var nearest=INF;var layers=0
	for surface in range(mesh.get_surface_count()):
		var vertices=mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for i in range(0,vertices.size(),3):
			var hit=Geometry3D.ray_intersects_triangle(origin,direction,vertices[i],vertices[i+1],vertices[i+2])
			if hit==null:continue
			var distance=origin.distance_to(hit)
			if distance<nearest-.00001:nearest=distance;layers=1
			elif absf(distance-nearest)<.00001:layers+=1
	return layers

func _initialize():run.call_deferred()
func run():
	var catalog=Catalog.new();var plan=catalog.range_plan()
	plan.instances=[{"id":"house","prefabId":"building.residence-two-storey","x":2000,"y":1400}]
	plan.looseSegments=[];plan.trees=[];plan.units.red=[];plan.world.groundFeatures=[]
	var world=World.new();var compiled=world.setup(plan,catalog)
	var stage=Node3D.new();root.add_child(stage)
	var views={};var objects={}
	for o in world.objects:
		views[o.id]=TerrainArt.object(stage,o);objects[o.id]=o
	var game={"world":world,"object_views":views,"editing":false,"roof_mode":0,"pending_rebuild":{},"actors":{}}
	var house_view={"data":compiled.roofs[0]}
	var lower=views["house.south-left-0"];var upper=views["house.south-1"]
	# First reproduce the old failure with two nodes using the same cached material.
	var shared=Art.ink_material(Color.WHITE,true,.11)
	var control=TerrainArt.object(stage,objects["house.south-left-0"])
	control.mesh.material_override=shared
	shared.set_shader_parameter("cutaway_opacity",0.0)
	check(not opaque(control.mesh.material_override),"shared-material control reproduces an invisible intact lower wall")
	shared.set_shader_parameter("cutaway_opacity",1.0);control.root.free()
	world.player.position=Vector2.ZERO;world.player.elevation=.04
	Visibility.apply(game,house_view)
	check(lower.root.visible,"occupied-floor wall node stays visible")
	check(opaque(lower.materials[0]),"hiding upper walls does not erase lower walls")
	check(not upper.root.visible,"upper floor remains hidden indoors")
	check(lower.materials[0]!=upper.materials[0],"floor visibility uses independently owned materials")
	check(opaque(Art.ink_material(Color.WHITE,true,.11)),"cutaway never changes shared outdoor wall material")
	world.player.elevation=3.4;Visibility.apply(game,house_view)
	check(upper.root.visible and upper.materials[0].get_shader_parameter("cutaway_opacity")==1.0,"upstairs reveals its own walls")
	world.player.elevation=.04;Visibility.apply(game,house_view)
	check(opaque(lower.materials[0]),"returning downstairs keeps visible boundaries")
	world.player.position=Vector2(0,8);Visibility.apply(game,house_view)
	check(is_inf(lower.cut_height) and upper.root.visible,"leaving restores complete building")
	# Repeated doorway crossings must restore walls, upper floors and camera picking.
	for position in [Vector2(0,5.7),Vector2(9,-5.7),Vector2(0,5.7),Vector2(9,-4.1)]:
		world.player.position=position;world.player.elevation=1.1 if position==Vector2(9,-5.7) else .04
		Visibility.apply(game,house_view)
		var exterior=position.x>8
		check(house_view.interior!=exterior,"HUD shares actual interior classification at %s"%position)
		check(upper.root.visible==exterior and objects["house.south-1"].camera_hidden!=exterior,"exterior restores upper wall drawing and camera picking at %s"%position)
		check(is_inf(lower.cut_height)==exterior and opaque(lower.materials[0]),"doorway crossing restores full walls without shared-material changes at %s"%position)
	world.player.position=Vector2(9,-4.1);world.player.elevation=3.4;Visibility.apply(game,house_view)
	check(not house_view.interior and is_inf(upper.cut_height) and upper.root.visible,"standing on balcony keeps the upper exterior wall intact")
	for x in [-.82,0,.82]:
		for z in [5.7,6.0,6.3,6.7,7.25]:
			check(not world.blocked(Vector2(x,z),.28,1.95,-1,.04),"front entrance admits standing soldier at %s"%Vector2(x,z))
	for x in [-1.65,1.65]:check(world.blocked(Vector2(x,6),.28,1.95,-1,.04),"visible front wall still blocks beside entrance")
	for z in [-4.75,-4.1,-3.4]:
		for x in [7.7,8.0,8.3]:check(not world.blocked(Vector2(x,z),.28,1.95,-1,3.4),"balcony doorway admits standing soldier at %s"%Vector2(x,z))
	check(world.blocked(Vector2(8,-4.1),.28,1.95,-1,.04),"balcony doorway does not create a false ground-floor exit")
	for door in [[Vector2(1.7,-.45),.04],[Vector2(.8,-.6),3.4]]:
		check(not world.blocked(door[0],.28,1.95,-1,door[1]),"interior doorway stays open on its floor")
	check(is_equal_approx(world.ground_height(Vector2(0,6.7),.28,.221),.04),"entrance paving is a genuine low walkable surface")
	check(world.trace_3d(Vector3(0,1,7.4),Vector3.FORWARD,2.4,{},true).is_empty(),"shots pass through front doorway")
	check(not world.trace_3d(Vector3(1.65,1,7.4),Vector3.FORWARD,2.4,{},true).is_empty(),"shots still hit wall alongside doorway")
	var wall=objects["house.south-left-0"]
	var cut_mesh=TerrainArt.wall_mesh(wall,1.15)
	for o in world.objects:
		for edge in o.get("door_jambs",[]):
			for cut in [1.15,INF]:
				var mesh=TerrainArt.wall_mesh(o,cut)
				check(front_layers(mesh,Vector3(edge*(o.size.x*.5+1),.67,.031),Vector3(-edge,0,0))==1,"one visible doorway end face: %s cut=%s"%[o.id,cut])
				var top=minf(o.height,cut)
				check(front_layers(mesh,Vector3(edge*(o.size.x*.5-.073),top+1,.031),Vector3.DOWN)==1,"one visible jamb top: %s cut=%s"%[o.id,cut])
				check(front_layers(mesh,Vector3(edge*(o.size.x*.5-.27),top+1,.031),Vector3.DOWN)==1,"one visible wall section top: %s cut=%s"%[o.id,cut])
	# Existing mortar strokes / chipped edges extend by at most 6 mm beyond the solid.
	check(absf(cut_mesh.get_aabb().end.y-1.15)<.006,"readable wall section and jamb stop at cutaway height: %s"%cut_mesh.get_aabb())
	var col=int(wall.columns)-1
	for row in range(wall.rows):world.damage_cell(wall,col,row,wall.max_hp+1,wall.position,true)
	cut_mesh=TerrainArt.wall_mesh(wall,1.15)
	check(cut_mesh.get_aabb().end.x<=wall.size.x*.5-wall.cell_width+.006,"destroyed door-edge column removes its jamb and section cap: %s"%cut_mesh.get_aabb())
	Structure.break_whole(world,wall)
	check(TerrainArt.wall_mesh(wall,1.15).get_surface_count()==0,"destroyed wall leaves no false architectural boundary")
	world.player.position=Vector2.ZERO;world.player.elevation=.04;Visibility.apply(game,house_view)
	check(not lower.root.visible,"floor visibility cannot resurrect a destroyed wall")
	stage.free()
	print("HOUSE_READABILITY %d/%d passed; failures=%s"%[checks-failures.size(),checks,failures])
	quit(0 if failures.is_empty() else 1)
