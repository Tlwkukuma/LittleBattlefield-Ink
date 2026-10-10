extends SceneTree
var checks=0
var failures=0
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize():run.call_deferred()
func run():
	var catalog=preload("res://scripts/source_catalog.gd").new()
	var plan=preload("res://scripts/orchard_level.gd").plan(catalog)
	var compiled=catalog.compile(plan)
	var terrain=preload("res://scripts/terrain_surface.gd").new()
	terrain.configure(compiled,catalog,plan)
	plan.godot3d.battlefield_border=false
	var original=preload("res://scripts/terrain_surface.gd").new()
	original.configure(compiled,catalog,plan)
	check(terrain.size==original.size,"same simulation grid")
	for z in range(terrain.size.y+1):
		for x in range(terrain.size.x+1):
			var p=Vector2(x,z)*terrain.cell-terrain.bounds
			if minf(terrain.bounds.x-absf(p.x),terrain.bounds.y-absf(p.y))>=2:
				check(is_equal_approx(terrain.vertex(x,z).y,original.vertex(x,z).y),"interior unchanged")
	for side in [-1,1]:
		for i in range(-20,21):
			for p in [Vector2(side*(terrain.bounds.x-1),i),Vector2(i,side*(terrain.bounds.y-1))]:
				check(terrain.grade(p)>.82,"physical ridge blocks walking")
				check(not terrain.ray(Vector3(p.x,20,p.y),Vector3.DOWN,30).is_empty(),"ridge ray hit")
	for team in ["blue","red"]:
		for spawn in plan.deployment[team].spawnPoints:
			var p=catalog.position(spawn,plan)
			check(is_equal_approx(terrain.height(p),original.height(p)),"spawn height preserved")
	var v=PackedVector3Array();var n=PackedVector3Array();var c=PackedColorArray()
	preload("res://scripts/battlefield_border.gd").append_exterior(terrain,v,n,c)
	check(v.size()/3==6720,"bounded 6720 exterior triangles")
	for normal in n:check(normal.y>0,"upward nondegenerate exterior")
	for point in v:
		if absf(absf(point.x)-terrain.bounds.x)<.001 or absf(absf(point.z)-terrain.bounds.y)<.001:
			check(absf(point.y-terrain.height(Vector2(point.x,point.z)))<.001,"exact inner seam")
	var mesh=terrain.mesh()
	check(mesh.get_surface_count()==1,"single terrain surface / no extra draw batch")
	print("BATTLEFIELD_BORDER_CONTRACT checks=%d failures=%d exterior_triangles=%d"%[checks,failures,v.size()/3])
	quit(0 if failures==0 else 1)
