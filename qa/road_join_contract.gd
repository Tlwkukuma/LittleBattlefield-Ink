extends SceneTree
## Pure road mesh/terrain checks; no simulation, movement or screenshots.
const Catalog=preload("res://scripts/source_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
const Paths=preload("res://scripts/terrain_paths.gd")
const Ground=preload("res://scripts/terrain_ground.gd")
const Terrain=preload("res://scripts/terrain_surface.gd")
var checks=0
var failures=0
func check(ok: bool,label: String):
	checks+=1
	if not ok:
		failures+=1
		if failures<12:push_error(label)
func covered(at: Vector2,vertices: PackedVector3Array) -> bool:
	for i in range(0,vertices.size(),3):
		var a=Vector2(vertices[i].x,vertices[i].z);var b=Vector2(vertices[i+1].x,vertices[i+1].z);var c=Vector2(vertices[i+2].x,vertices[i+2].z)
		if not Rect2(a,Vector2.ZERO).expand(b).expand(c).grow(.00001).has_point(at):continue
		# The engine helper excludes some exact edges. A shared raster edge is covered.
		var edges=[(b-a).cross(at-a),(c-b).cross(at-b),(a-c).cross(at-c)]
		if (edges[0]>=-.000001 and edges[1]>=-.000001 and edges[2]>=-.000001) or (edges[0]<=.000001 and edges[1]<=.000001 and edges[2]<=.000001):return true
	return false
func _initialize():run.call_deferred()
func mesh_for(features: Array,terrain) -> Dictionary:
	var v=PackedVector3Array();var n=PackedVector3Array();var c=PackedColorArray()
	Paths.render_all(features,v,n,c,terrain,Ground.BASE,.013)
	return {"vertices":v,"colors":c}
func fixture(points: PackedVector2Array,mode: String="polyline") -> Dictionary:
	var f={"id":"path.dirt","kind":"path","surface":"track","points":points,"pathMode":mode,"width":2.0,"shoulderWidth":96}
	Paths.prepare(f);return f
func slope_surface():
	var terrain=Terrain.new();terrain.bounds=Vector2(8,8);terrain.cell=.5;terrain.size=Vector2i(32,32);terrain.active=true
	for z in range(33):
		for x in range(33):terrain.heights.append(sin(x*.61)*.28+cos(z*.39)*.37)
	return terrain
func paint_at(at: Vector2,mesh: Dictionary) -> Array:
	var colors=[];var vertices: PackedVector3Array=mesh.vertices
	for i in range(0,vertices.size(),3):
		var a=Vector2(vertices[i].x,vertices[i].z);var b=Vector2(vertices[i+1].x,vertices[i+1].z);var c=Vector2(vertices[i+2].x,vertices[i+2].z)
		if Geometry2D.point_is_inside_triangle(at,a,b,c):colors.append(mesh.colors[i])
	return colors
func run():
	var catalog=Catalog.new();var world=World.new();world.setup(preload("res://scripts/orchard_level.gd").plan(catalog),catalog)
	for f in world.terrain.features:
		if f.get("source_id","")!="farm-access-road":continue
		var v=PackedVector3Array();var n=PackedVector3Array();var c=PackedColorArray();Paths.render(f,v,n,c,world.terrain,Ground.BASE,.013)
		for i in range(1,f.points.size()-1):
			var before=(f.points[i]-f.points[i-1]).normalized();var after=(f.points[i+1]-f.points[i]).normalized()
			var turn=before.cross(after)
			if absf(turn)<.00001:continue
			var outward=Vector2((before+after).y,-(before+after).x).normalized()*signf(turn)
			var probe=f.points[i]+outward*(f.shoulder_m*.5-.02)
			check(Paths.contains(f,probe,f.shoulder_m),"authored corner belongs to road shoulder")
			check(is_zero_approx(world.terrain.height(probe)),"reported corner is already physically level")
			check(covered(probe,v),"farm road outer bend must have connected shoulder geometry "+str(i))
	var terrain=slope_surface()
	var cases=[
		fixture(PackedVector2Array([Vector2(-5,0),Vector2.ZERO,Vector2(0,5)])),
		fixture(PackedVector2Array([Vector2(-5,0),Vector2.ZERO,Vector2(-4,2)])),
		fixture(PackedVector2Array([Vector2(-5,-3),Vector2(-2,1),Vector2(2,-1),Vector2(5,3)]),"curve"),
		fixture(PackedVector2Array([Vector2(-4,-4),Vector2(4,-4),Vector2(4,4),Vector2(-4,4),Vector2(-4,-4)])),
		fixture(PackedVector2Array([Vector2(-5,0),Vector2.ZERO,Vector2.ZERO,Vector2(5,0)]))]
	var largest_error=0.0;var vertices=0
	for index in range(cases.size()):
		var f: Dictionary=cases[index];var mesh=mesh_for([f],terrain);var v: PackedVector3Array=mesh.vertices;vertices+=v.size()
		check(not v.is_empty(),"road fixture produces geometry "+str(index))
		for i in range(f.points.size()-1):
			if f.points[i].distance_squared_to(f.points[i+1])<.00001:continue
			var middle: Vector2=f.points[i].lerp(f.points[i+1],.473)
			var direction: Vector2=(f.points[i+1]-f.points[i]).normalized();var side=Vector2(-direction.y,direction.x)
			for lateral in [-.97,0.031,.97]:check(covered(middle+side*lateral,v),"road cross-section remains connected "+str(index))
		for at in [f.points[0],f.points[-1]]:
			for angle in range(12):check(covered(at+Vector2.from_angle(angle*TAU/12)*1.17,v),"round endpoint coverage "+str(index))
		for i in range(0,v.size(),3):
			var middle=(v[i]+v[i+1]+v[i+2])/3
			largest_error=maxf(largest_error,absf(middle.y-terrain.height(Vector2(middle.x,middle.z))-.013))
		if index==3:check(not covered(Vector2(.123,.127),v),"loop road keeps its grassy interior hole")
	check(largest_error<.00005,"every road fragment follows the same actual terrain plane")
	var junction=[fixture(PackedVector2Array([Vector2(-6,0),Vector2(6,0)])),fixture(PackedVector2Array([Vector2(0,-6),Vector2(0,6)]))]
	var mesh=mesh_for(junction,terrain)
	for x in [-.77,-.19,.23,.79]:
		for y in [-.71,-.17,.31,.83]:
			var paints=paint_at(Vector2(x,y),mesh)
			check(paints.size()==1,"junction has one surface, no coplanar overlap")
			check(paints.size()==1 and paints[0].is_equal_approx(Paths.color(junction[1],Ground.BASE)),"junction has no shoulder cutting through the road")
	# Real entire level: includes the curved main road and its continuous dash phase.
	var roads=[]
	for f in world.terrain.features:
		if f.has("pathMode") or f.get("surface","")=="track":roads.append(f)
	var start=Time.get_ticks_usec();var network=mesh_for(roads,world.terrain)
	print("ROAD_NETWORK triangles=",network.vertices.size()/3," build_ms=",(Time.get_ticks_usec()-start)/1000.0," max_slope_error=",largest_error)
	print("ROAD_JOIN_CONTRACT checks=",checks," failures=",failures," simulation_time=",world.time," shots=",world.shots)
	quit(0 if failures==0 else 1)
