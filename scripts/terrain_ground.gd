extends RefCounted
const Art=preload("res://scripts/ink_art.gd")
const Geometry=preload("res://scripts/terrain_art.gd")
const Paths=preload("res://scripts/terrain_paths.gd")
const BASE=Color("a7af97")

static func color_for(id: String) -> Color:
	if "water" in id or "creek" in id:return Color("819e9e")
	if "asphalt" in id or id in ["path.road","road"]:return Color("808b87")
	if "concrete" in id or "yard" in id:return Color("babcb0")
	if "wood" in id or "boardwalk" in id:return Color("a39171")
	if "red-earth" in id:return Color("b9856a")
	if "mountain" in id:return Color("a7afa0")
	if "desert" in id:return Color("d2bc8c")
	if "sand" in id:return Color("c6bea1")
	if "snow" in id:return Color("d8ddd3")
	if "mud" in id or "trench" in id:return Color("9a9783")
	if "grass" in id or "field" in id or "marsh" in id:return Color("98a486")
	if "rock" in id or "cobble" in id:return Color("adae9f")
	return Color("b7ad92")

static func patch(v: PackedVector3Array,n: PackedVector3Array,c: PackedColorArray,points: PackedVector2Array,height: float,color: Color):
	if points.size()<3:return
	var tris=Geometry2D.triangulate_polygon(points)
	for i in tris:v.append(Vector3(points[i].x,height,points[i].y));n.append(Vector3.UP);c.append(color)

static func disc(v: PackedVector3Array,n: PackedVector3Array,c: PackedColorArray,at: Vector2,radius: Vector2,height: float,color: Color,seed_value: int=0):
	var points=PackedVector2Array()
	for i in range(12):
		var angle=i*TAU/12;var irregular=1.0+sin(i*7.31+seed_value)*.075
		points.append(at+Vector2(cos(angle),sin(angle))*radius*irregular)
	patch(v,n,c,points,height,color)

static func strip(v: PackedVector3Array,n: PackedVector3Array,c: PackedColorArray,a: Vector2,b: Vector2,width: float,height: float,color: Color):
	var side=Vector2(-(b-a).y,(b-a).x).normalized()*width*.5
	patch(v,n,c,PackedVector2Array([a-side,a+side,b+side,b-side]),height,color)

static func build(game,parent: Node3D):
	var v=PackedVector3Array();var n=PackedVector3Array();var c=PackedColorArray()
	var bounds: Vector2=game.world.bounds
	if not game.world.terrain.active:patch(v,n,c,PackedVector2Array([Vector2(-bounds.x,-bounds.y),Vector2(bounds.x,-bounds.y),bounds,Vector2(-bounds.x,bounds.y)]),0,BASE)
	var rng=RandomNumberGenerator.new();rng.seed=int(game.plan.world.get("seed",260925))
	# Broad low-contrast ground variation; no full-screen graph-paper grid during play.
	for i in range(0 if game.world.terrain.active else 70):
		var at=Vector2(rng.randf_range(-bounds.x+3,bounds.x-3),rng.randf_range(-bounds.y+3,bounds.y-3))
		disc(v,n,c,at,Vector2(rng.randf_range(.8,3),rng.randf_range(.5,1.9)),.001+i*.00001,BASE.darkened(.016 if i%2==0 else .03),i)
	var layer=.004
	if game.world.terrain.active:
		var relief=Art.mesh_node(parent,game.world.terrain.mesh(),Vector3.ZERO,Color.WHITE)
		relief.name="TerrainRelief"
		var ground_material=ShaderMaterial.new();ground_material.shader=preload("res://shaders/terrain_surface.gdshader")
		relief.material_override=ground_material
	# Joined network masks are clipped to the real terrain triangles in one bake.
	# The mesh is not rebuilt per frame and shares this existing ground draw call.
	var roads=[]
	for f in game.world.terrain.features:
		if f.has("path_lengths"):roads.append(f)
	Paths.render_all(roads,v,n,c,game.world.terrain,BASE,layer+.009)
	for feature in ([] if game.world.terrain.active else game.compiled.ground):
		if Paths.is_path(feature):continue
		layer+=.000025
		var id=str(feature.get("componentId",feature.get("mapKitComponentId",feature.get("kind","soil"))))
		var color=color_for(id);var points=PackedVector2Array()
		for p in feature.get("points",[]):points.append(game.catalog.position_point(game.catalog.v(p),game.plan))
		if points.is_empty() and feature.has("x"):
			var at=game.catalog.position_point(Vector2(feature.x,feature.y),game.plan)
			var size=Vector2(float(feature.get("w",feature.get("width",120))),float(feature.get("h",feature.get("height",120))))/40
			points=PackedVector2Array([at,at+Vector2(size.x,0),at+size,at+Vector2(0,size.y)])
		var path=feature.get("kind","") in ["path","road"] or points.size()==2
		if path:
			var width=float(feature.get("width",80))/40
			for i in range(points.size()-1):
				var a=points[i];var b=points[i+1]
				strip(v,n,c,a,b,width+.24,layer,color.lerp(BASE,.50))
				strip(v,n,c,a,b,width,layer+.00001,color)
				if i>0:disc(v,n,c,a,Vector2.ONE*width*.5,layer+.00001,color)
				if "road" in id and not "dirt" in id:
					var dir=(b-a).normalized()
					for step in range(int(a.distance_to(b)/2)):
						var start=a+dir*(step*2+.35)
						strip(v,n,c,start,start+dir*.80,.065,layer+.00002,Color("d4ceac"))
		else:
			patch(v,n,c,points,layer,color)
			if "grass" in id or "field" in id:
				grass(v,n,c,points,layer,rng)
	# A visible floor under each prefab prevents the building from reading as a hollow box on grass.
	for roof in game.compiled.roofs:
		# Elevated structures currently have no physical floor slab. Do not draw a walkable-looking floating floor.
		if float(roof.get("elevation",0))>.01:continue
		patch(v,n,c,PackedVector2Array(roof.points),float(roof.get("elevation",0))+.012,Color("c6c3b2"))
		var points=PackedVector2Array(roof.points)
		for i in range(points.size()):strip(v,n,c,points[i],points[(i+1)%points.size()],.10,float(roof.get("elevation",0))+.013,Color("9d9f90"))
	if game.editing:
		for x in range(-mini(100,int(bounds.x)),mini(100,int(bounds.x))+1,2):strip(v,n,c,Vector2(x,-bounds.y),Vector2(x,bounds.y),.012,.017,Color("929b88"))
		for y in range(-mini(100,int(bounds.y)),mini(100,int(bounds.y))+1,2):strip(v,n,c,Vector2(-bounds.x,y),Vector2(bounds.x,y),.012,.017,Color("929b88"))
	var node=Art.mesh_node(parent,Geometry.mesh_from(v,n,c),Vector3.ZERO,Color.WHITE)
	node.material_override=Art.ink_material(Color.WHITE,true,.04)

static func grass(v: PackedVector3Array,n: PackedVector3Array,c: PackedColorArray,points: PackedVector2Array,height: float,rng: RandomNumberGenerator):
	if points.size()<3:return
	var rect=Rect2(points[0],Vector2.ZERO)
	for p in points:rect=rect.expand(p)
	var count=mini(260,int(rect.get_area()*2))
	for i in range(count):
		var at=rect.position+Vector2(rng.randf(),rng.randf())*rect.size
		if not Geometry2D.is_point_in_polygon(at,points):continue
		var h=rng.randf_range(.045,.16);var color=Color("7e9170").lightened(rng.randf()*.13)
		for direction in [Vector2(.06,0),Vector2(0,.06)]:
			for p in [Vector3(at.x-direction.x,height,at.y-direction.y),Vector3(at.x+direction.x,height,at.y+direction.y),Vector3(at.x+.018,height+h,at.y+.02)]:v.append(p);n.append(Vector3.UP);c.append(color)

static func roof_mesh(roof: Dictionary) -> ArrayMesh:
	var v=PackedVector3Array();var n=PackedVector3Array();var c=PackedColorArray()
	var points=PackedVector2Array(roof.points);var height=float(roof.height)+.08
	var color=Color("89978f") if roof.get("style","")!="building.shed" else Color("9c9b89")
	patch(v,n,c,points,height,color)
	for i in range(points.size()):
		var a=points[i];var b=points[(i+1)%points.size()]
		var corners=[Vector3(a.x,height-.14,a.y),Vector3(a.x,height,a.y),Vector3(b.x,height,b.y),Vector3(b.x,height-.14,b.y)]
		var normal=Vector3(-(b-a).y,0,(b-a).x).normalized()
		for k in [0,1,2,0,2,3]:v.append(corners[k]);n.append(normal);c.append(color.darkened(.25))
		strip(v,n,c,a,b,.065,height+.002,Color("c1c6b5"))
	# Standing seams are clipped to the actual polygon, including concave/L-shaped roofs.
	var rect=Rect2(points[0],Vector2.ZERO)
	for p in points:rect=rect.expand(p)
	var seam_count=mini(150,int(rect.size.x/.52))
	for i in range(1,seam_count):
		var x=rect.position.x+i*.52;var crossings: Array=[]
		for edge in range(points.size()):
			var a=points[edge];var b=points[(edge+1)%points.size()]
			if (a.x<=x and b.x>x) or (b.x<=x and a.x>x):crossings.append(lerpf(a.y,b.y,(x-a.x)/(b.x-a.x)))
		crossings.sort()
		for j in range(0,crossings.size()-1,2):strip(v,n,c,Vector2(x,crossings[j]),Vector2(x,crossings[j+1]),.018,height+.003,color.darkened(.20))
	return Geometry.mesh_from(v,n,c)
