extends SceneTree
const Catalog=preload("res://scripts/source_catalog.gd")
const Surface=preload("res://scripts/terrain_surface.gd")
var failures=[]
func check(ok: bool,label: String):
	if not ok:failures.append(label);push_error(label)
func _initialize():
	var catalog=Catalog.new()
	var plan={"world":{"w":1200,"h":1000,"groundFeatures":[{"id":"cut","componentId":"landform.trench-network","points":[[300,740],[580,500],[850,500],[950,240]],"depth_m":1.6,"bottom_width_m":2.4,"bank_run_m":1,"corner_radius_m":2,"parapet_height_m":.6,"parados_height_m":.3}]},"instances":[],"looseSegments":[],"trees":[]}
	var terrain=Surface.new();terrain.configure(catalog.compile(plan),catalog,plan)
	var heights=terrain.heights.duplicate();var started=Time.get_ticks_usec();var mesh=terrain.mesh();var build_ms=(Time.get_ticks_usec()-started)/1000.0
	var arrays=mesh.surface_get_arrays(0);var vertices=arrays[Mesh.ARRAY_VERTEX];var colors=arrays[Mesh.ARRAY_COLOR];var normals=arrays[Mesh.ARRAY_NORMAL]
	check(vertices.size()==terrain.size.x*terrain.size.y*6,"no extra triangles")
	check(mesh.get_surface_count()==1,"one terrain surface")
	check(terrain.heights==heights,"render bake cannot change physical height field")
	var shared={};var mismatches=0;var geometry_errors=0;var smooth_slopes=0
	for i in range(vertices.size()):
		var point: Vector3=vertices[i];var flat=Vector2(point.x,point.z)
		if absf(point.y-terrain.height(flat))>.0001:geometry_errors+=1
		if "trench" not in terrain.material_at(flat):continue
		if shared.has(point):
			if not normals[i].is_equal_approx(shared[point][0]) or not colors[i].is_equal_approx(shared[point][1]):mismatches+=1
		else:shared[point]=[normals[i],colors[i]]
		if normals[i].y<.99:smooth_slopes+=1
	check(geometry_errors==0,"render vertices match physical terrain")
	check(mismatches==0,"all shared trench vertices have identical color and normal")
	check(smooth_slopes>100,"slopes retain readable depth rather than flattening terrain")
	print("TRENCH_SURFACE ",JSON.stringify({"failures":failures,"triangles":vertices.size()/3,"shared_trench_vertices":shared.size(),"build_ms":build_ms,"checks":6}))
	quit(0 if failures.is_empty() else 1)
