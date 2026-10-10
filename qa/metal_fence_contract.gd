extends SceneTree
const Catalog=preload("res://scripts/source_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
const TerrainArt=preload("res://scripts/terrain_art.gd")
var checks=0
var failures=[]
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures.append(label);push_error(label)
func mesh_hit(mesh: ArrayMesh,point: Vector3) -> bool:
	if mesh.get_surface_count()==0:return false
	var vertices=mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for i in range(0,vertices.size(),3):
		if Geometry3D.ray_intersects_triangle(point,Vector3.FORWARD,vertices[i],vertices[i+1],vertices[i+2])!=null:return true
	return false
func _initialize():
	var catalog=Catalog.new()
	for angle in [0.0,.67]:
		var a=Vector2(-1,0).rotated(angle)*40;var b=-a
		var plan={"world":{"w":800,"h":800,"groundFeatures":[]},"instances":[],"looseSegments":[{"id":"fence","componentId":"wall.metal-fence","x1":400+a.x,"y1":400+a.y,"x2":400+b.x,"y2":400+b.y,"thickness":16,"godot3d":{"height":1.45}}],"trees":[],"deployment":{"player":{"x":600,"y":600}}}
		var world=World.new();world.setup(plan,catalog);var o=world.objects[0];var mesh=TerrainArt.wall_mesh(o)
		check(o.ballistic and o.has("fence_cells") and mesh.get_surface_count()==1,"fence uses one rod mesh and cell-owned physical bars")
		var maximum=0
		for cell in o.fence_cells:maximum=maxi(maximum,cell.size())
		check(maximum<=16,"narrow-phase rods are bounded per intersected cell")
		if angle==0:print("FENCE_GEOMETRY surfaces=",mesh.get_surface_count()," triangles=",mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()/3," max_parts_per_cell=",maximum)
		var gap=Vector3(-.90,.25,2);var post=Vector3(-.96,.25,2)
		var direction=Vector2(0,-1).rotated(angle)
		for sample in [[gap,false],[post,true],[Vector3(-.90,.10,2),true]]:
			var p: Vector3=sample[0];var flat=Vector2(p.x,p.z).rotated(angle)
			var hit=world.trace_3d(Vector3(flat.x,p.y,flat.y),Vector3(direction.x,0,direction.y),4,{},true)
			check((not hit.is_empty())==sample[1] and mesh_hit(mesh,p)==sample[1],"render/shot agree on aperture, post and rail")
		check(world.blocked(Vector2(-.90,0).rotated(angle),.28,1.95,-1,0),"soldier cannot fit through intact wire grid")
		var before=mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
		for col in [0,1,2]:
			for row in range(o.rows):world.damage_cell(o,col,row,o.max_hp+1,o.position,true)
		world.resolve_support();mesh=TerrainArt.wall_mesh(o)
		check(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()<before,"local destruction removes matching rod mesh")
		check(not world.blocked(Vector2(-.45,0).rotated(angle),.28,1.95,-1,0),"destroyed columns create a real passage")
		var flat=Vector2(post.x,post.z).rotated(angle)
		check(world.trace_3d(Vector3(flat.x,post.y,flat.y),Vector3(direction.x,0,direction.y),4,{},true).is_empty() and not mesh_hit(mesh,post),"destroyed post no longer draws or blocks shots")
		check(world.ground_height(Vector2(-.45,0).rotated(angle),.1,3)==0,"destroyed rods do not retain invisible support")
	print("METAL_FENCE %d/%d passed; failures=%s"%[checks-failures.size(),checks,failures])
	quit(0 if failures.is_empty() else 1)
