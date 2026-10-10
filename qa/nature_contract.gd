extends SceneTree
## Static geometry, catalogue and destruction checks only; no GUI input or screenshots.
const Catalog=preload("res://scripts/source_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
const Library=preload("res://scripts/nature_library.gd")
const Geometry=preload("res://scripts/nature_geometry.gd")
var catalog=Catalog.new()
var checks=0
var failures=[]

func check(ok: bool,label: String):
	checks+=1
	if not ok:failures.append(label);push_error(label)

func fixture(id: String,angle: float=0,scale: float=1) -> Dictionary:
	var plan=catalog.range_plan();plan.instances=[{"id":"nature","prefabId":id,"x":2000,"y":1400,"rotation":angle,"scale":scale}]
	plan.looseSegments=[];plan.trees=[];plan.units.red=[];plan.vehicles=[];plan.emplacements=[];plan.world.groundFeatures=[]
	var world=World.new();var compiled=world.setup(plan,catalog);return {"world":world,"compiled":compiled,"plan":plan}

func _initialize():run.call_deferred()
func run():
	check(Library.SPECS.size()==19 and Library.CLUSTERS.size()==6,"19 single assets and six independently destructible compositions")
	check(catalog.prefabs.size()>=83 and catalog.components.size()>=102,"original catalogue plus natural assets is available in workshop")
	var max_vertices=0
	for component in Library.SPECS:
		var f=fixture(Library.single_id(component));var w=f.world;var o: Dictionary=w.objects[0]
		check(o.has("nature_parts") and not o.nature_solids.is_empty() and o.alive,"real geometry prepared: "+component)
		var finite=true;var convex=true;var inside=true
		for part in o.nature_parts:
			for vertex in part.vertices:
				finite=finite and vertex.is_finite();inside=inside and absf(vertex.x)<=o.size.x*.5+.0001 and absf(vertex.z)<=o.size.y*.5+.0001 and vertex.y<=o.height+.0001
				if part.solid:
					for plane in part.planes:convex=convex and plane.distance_to(vertex)<.0001
			for tri in part.triangles:finite=finite and tri[3].is_finite() and absf(tri[3].length()-1)<.0001
		check(finite and convex and inside,"finite outward faces, convex solids and valid broadphase: "+component)
		var mesh=Geometry.mesh(o);var count=mesh.surface_get_array_len(0);max_vertices=maxi(max_vertices,count)
		check(mesh.get_surface_count()==1 and count>30 and count<10000,"bounded one-surface mesh: "+component)
		var repeated=fixture(Library.single_id(component))
		check(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]==Geometry.mesh(repeated.world.objects[0]).surface_get_arrays(0)[Mesh.ARRAY_VERTEX],"stable identity preserves silhouette on reload: "+component)
		var occupied=false
		for part in o.nature_solids:
			var center=Vector3.ZERO
			for p in part.vertices:center+=p
			center/=part.vertices.size()
			occupied=occupied or (Geometry.depth(o,Vector2(center.x,center.z),.025,center.y-.025,.05)>.001 and not Geometry.ray(o,center+Vector3.LEFT*10,Vector3.RIGHT,10).is_empty())
		check(occupied,"visible solid participates in body and bullet collision: "+component)
	for id in Library.CLUSTERS:
		var f=fixture(id,.63,1.2);var w=f.world
		check(w.objects.size()==Library.CLUSTERS[id].members.size(),"cluster emits each member: "+id)
		w.navigation_dirty=false;var first: Dictionary=w.objects[0]
		w.damage_cell(first,0,0,100000,Vector2.ZERO,true)
		check(not first.alive and w.objects.slice(1).all(func(o):return o.alive) and w.navigation_dirty,"member damage leaves neighbours intact and refreshes navigation: "+id)
		var copy=catalog.compile(JSON.parse_string(JSON.stringify(f.plan)))
		check(copy.objects.size()==w.objects.size() and copy.objects[1].position.distance_to(w.objects[1].position)<.0001,"rotated/scaled JSON composition roundtrip: "+id)
	var f=fixture(Library.single_id("tree.oak-mature"));var w=f.world
	check(w.blocked(Vector2.ZERO,.28,1.95),"oak trunk blocks walking")
	check(not w.blocked(Vector2(1.1,0),.28,1.95),"soldier can walk under overhanging oak canopy")
	check(w.trace_3d(Vector3(1.4,1.5,-5),Vector3.BACK,10,{},true).is_empty(),"empty space beside trunk passes bullets")
	var hit=w.trace_3d(Vector3(0,1.5,-5),Vector3.BACK,10,{},true)
	check(not hit.is_empty() and hit.target.id==w.objects[0].id and hit.normal.is_normalized(),"trunk ray returns actual surface normal")
	check(Geometry.distance_to_solid(w.objects[0],Vector3(.4,.3,0))<.5,"blast measures distance to actual low trunk, not high canopy centre")
	w.blast(Vector2(.55,0),.8,10000,{"kind":"shell"},.30)
	check(not w.objects[0].alive and not w.blocked(Vector2.ZERO,.28,1.95),"small near-root explosion destroys trunk and frees movement")
	for angle in [0.0,.73,PI*.5]:
		f=fixture(Library.single_id("rock.sandstone-arch"),angle);w=f.world
		var a=Vector2(0,-4).rotated(angle);var direction=Vector2.DOWN.rotated(angle)
		check(w.ray(a,direction,8,1.2,{},true).is_empty(),"arch opening passes shots: "+str(angle))
		check(not w.ray(a,direction,8,3.0,{},true).is_empty(),"arch lintel blocks upper shots: "+str(angle))
		check(not w.blocked(Vector2.ZERO,.28,1.95) and w.blocked(Vector2(2.03,0).rotated(angle),.28,1.95),"arch has a walkable opening and solid pillars: "+str(angle))
		check(w.blocked(Vector2.ZERO,.28,1.95,-1,.75),"arch overhead limits body height: "+str(angle))
	f=fixture(Library.single_id("rock.granite-low"));w=f.world
	check(absf(w.ground_height(Vector2.ZERO,.28,1)-.72)<.0001 and not w.blocked(Vector2.ZERO,.28,1.95,-1,.72),"low flat rock supports character on its actual top")
	hit=w.trace_3d(Vector3(0,3,0),Vector3.DOWN,4,{},true)
	check(absf(3-hit.distance-.72)<.0001,"vertical shot agrees with low rock support height")
	check(not w.blocked(Vector2(1.6,1.3),.03,.4),"tapered rock corners are not invisible rectangular blockers")
	w.damage_cell(w.objects[0],0,0,10000,Vector2.ZERO,true)
	check(is_zero_approx(w.ground_height(Vector2.ZERO,.28,1)) and w.ray(Vector2(0,-3),Vector2.DOWN,6,.4,{},true).is_empty(),"destroying rock removes support and cover together")
	var oak=fixture(Library.single_id("tree.oak-mature"));var young=fixture(Library.single_id("tree.oak-young"))
	check(oak.world.objects[0].height>young.world.objects[0].height*1.5 and oak.world.objects[0].size.x>young.world.objects[0].size.x*1.5,"mature and young trees differ in crown and height")
	var fir=fixture(Library.single_id("tree.fir-tall"));var snow=fixture(Library.single_id("tree.snow-fir"))
	check(snow.world.objects[0].nature_parts.size()>fir.world.objects[0].nature_parts.size(),"snow fir includes additional three-dimensional snow layers")
	f=fixture("nature.snow-stand");w=f.world
	check(w.objects.filter(func(o):return o.component_id.begins_with("rock.")).all(func(o):return o.nature_parts.size()>Geometry.Forms.parts(o.component_id,hash(o.id),false).size()),"snow stand rocks have additional geometric snow caps")
	var plan=catalog.range_plan();w=World.new();w.setup(plan,catalog)
	check(w.objects.filter(func(o):return o.has("nature_parts")).size()==19 and plan.id=="godot-proving-ground","all singles share the existing unified range")
	check(not w.blocked(Vector2(16,25),.28,1.95) and not w.blocked(Vector2(42.5,-5),.28,1.95),"both gallery arrivals are clear")
	var in_bounds=true
	for sample in Library.samples():in_bounds=in_bounds and absf(sample.point.x)<50 and absf(sample.point.y)<35
	check(in_bounds,"sample roots stay inside the existing range bounds")
	print("NATURE_CONTRACT %d/%d passed; max_vertices=%d; failures=%s"%[checks-failures.size(),checks,max_vertices,failures])
	quit(0 if failures.is_empty() else 1)
