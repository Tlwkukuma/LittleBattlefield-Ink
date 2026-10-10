extends RefCounted
const Art=preload("res://scripts/ink_art.gd")
const Batch=preload("res://scripts/mesh_batch.gd")
const VehicleArt=preload("res://scripts/vehicle_art.gd")
const EmplacementArt=preload("res://scripts/emplacement_art.gd")
const Terrain=preload("res://scripts/terrain_art.gd")
const WeaponProfile=preload("res://scripts/weapon_profile.gd")
const WeaponIdentity=preload("res://scripts/weapon_identity.gd")
const SpecialGeometry=preload("res://scripts/special_weapon_geometry.gd")
static var weapon_cache: Dictionary={}
static var weapon_scenes: Dictionary={}
const PALETTE={"ink":Color("302b43"),"dark":Color("554e67"),"metal":Color("9490a6"),"cloth":Color("a7a1b5"),"wood":Color("ad98a4"),"paper":Color("e4e1eb"),"accent":Color("8f9cba"),"glass":Color("6d7795")}

static func append_box(v: PackedVector3Array,n: PackedVector3Array,c: PackedColorArray,center: Vector3,size: Vector3,color: Color,mask: Array=[true,true,true,true,true,true]) -> void:
	var h=size*.5
	var corners=[Vector3(-h.x,-h.y,-h.z),Vector3(h.x,-h.y,-h.z),Vector3(h.x,-h.y,h.z),Vector3(-h.x,-h.y,h.z),Vector3(-h.x,h.y,-h.z),Vector3(h.x,h.y,-h.z),Vector3(h.x,h.y,h.z),Vector3(-h.x,h.y,h.z)]
	var faces=[[0,1,2,3],[4,7,6,5],[0,4,5,1],[3,2,6,7],[1,5,6,2],[0,3,7,4]]
	var normals=[Vector3.DOWN,Vector3.UP,Vector3.FORWARD,Vector3.BACK,Vector3.RIGHT,Vector3.LEFT]
	var shades=[.7,1.02,.83,.94,.85,.92]
	for f in range(6):
		if not mask[f]:continue
		for k in [0,1,2,0,2,3]:v.append(center+corners[faces[f][k]]);n.append(normals[f]);c.append(Color(color.r*shades[f],color.g*shades[f],color.b*shades[f]))

static func mesh_from(v: PackedVector3Array,n: PackedVector3Array,c: PackedColorArray) -> ArrayMesh:
	var mesh=ArrayMesh.new()
	if v.is_empty():return mesh
	var arrays=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=v;arrays[Mesh.ARRAY_NORMAL]=n;arrays[Mesh.ARRAY_COLOR]=c
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

static func wall_mesh(o: Dictionary,cut_height: float=INF) -> ArrayMesh:
	return Terrain.wall_mesh(o,cut_height)

static func append_bag(v: PackedVector3Array,n: PackedVector3Array,c: PackedColorArray,at: Vector3,size: Vector3,color: Color):
	var rings=[]
	for row in range(5):
		var t=float(row)/4;var radius=.66+sin(t*PI)*.34;var ring=[]
		for i in range(12):
			var angle=i*TAU/12;var x=signf(cos(angle))*pow(absf(cos(angle)),.42)*size.x*.5*radius;var z=signf(sin(angle))*pow(absf(sin(angle)),.42)*size.z*.5*radius
			ring.append(at+Vector3(x,(t-.5)*size.y,z))
		rings.append(ring)
	for row in range(4):
		for i in range(12):
			var next=(i+1)%12;var corners=[rings[row][i],rings[row][next],rings[row+1][next],rings[row+1][i]]
			var normal=(corners[1]-corners[0]).cross(corners[2]-corners[0]).normalized()
			for k in [0,1,2,0,2,3]:v.append(corners[k]);n.append(normal);c.append(color.darkened((1-maxf(0,normal.y))*.12))
	for row in [0,4]:
		for i in range(1,11):
			for k in [0,i,i+1]:v.append(rings[row][k]);n.append(Vector3.UP if row==4 else Vector3.DOWN);c.append(color)

static func object(parent: Node3D,o: Dictionary) -> Dictionary:
	return Terrain.object(parent,o)

static func weapon(parent: Node3D,w: Dictionary) -> Node3D:
	if weapon_scenes.has(w.id):
		var instance=weapon_scenes[w.id].instantiate();parent.add_child(instance);return instance
	var root=Node3D.new();parent.add_child(root)
	var special=SpecialGeometry.build(root,w)
	if special:pass
	elif w.get("shapes")!=null:
		if not weapon_cache.has(w.id):
			var vertices=PackedVector3Array();var normals=PackedVector3Array();var colors=PackedColorArray()
			for index in range(w.shapes.size()):
				var shape: Dictionary=w.shapes[index]
				var points=PackedVector2Array()
				if shape.op=="poly":
					for p in shape.points:points.append(Vector2(p[0],p[1]))
				elif shape.op=="ellipse":
					for i in range(16):points.append(Vector2(shape.x,shape.y)+Vector2(cos(i*TAU/16)*shape.rx,sin(i*TAU/16)*shape.ry))
				elif shape.op=="line":
					for i in range(shape.points.size()-1):
						var a=Vector2(shape.points[i][0],shape.points[i][1]);var b=Vector2(shape.points[i+1][0],shape.points[i+1][1])
						var perpendicular=Vector2(-(b-a).y,(b-a).x).normalized()*float(shape.get("width",.7))*.5
						var pigment=str(shape.get("stroke","ink"))
						extrude(PackedVector2Array([a+perpendicular,b+perpendicular,b-perpendicular,a-perpendicular]),.039+index*.0004,WeaponIdentity.pigment(w,pigment,PALETTE.get(pigment,Art.INK)),vertices,normals,colors)
					continue
				if not points.is_empty():
					var pigment=str(shape.get("fill","metal"))
					extrude(points,.028+index*.0004,WeaponIdentity.pigment(w,pigment,PALETTE.get(pigment,Color("9991a5"))),vertices,normals,colors)
			weapon_cache[w.id]=mesh_from(vertices,normals,colors)
		var node=Art.mesh_node(root,weapon_cache[w.id],Vector3.ZERO,Color.WHITE)
		node.material_override=Art.ink_material(Color.WHITE,true,.05)
	else:
		match w.kind:
			"melee":
				Art.box(root,Vector3(0,-.05,.05),Vector3(.045,.05,.22),Art.INK)
				if w.name=="Fire Axe":Art.box(root,Vector3(.02,.06,-.20),Vector3(.055,.26,.15),Color("d0c9da"))
				else:Art.box(root,Vector3(0,0,-.20 if w.name=="Army Knife" else -.43),Vector3(.016,.055,.26 if w.name=="Army Knife" else .73),Color("d4ccdc"))
			"rocket":
				var tube=Art.cylinder(root,Vector3(0,0,-.12),.075,.91,Color("8c859a"));tube.rotation.x=PI*.5
				var mouth=Art.cylinder(root,Vector3(0,0,-.59),.088,.04,Art.INK);mouth.rotation.x=PI*.5
				var rim=Art.cylinder(root,Vector3(0,0,-.575),.10,.025,Color("bab1c2"));rim.rotation.x=PI*.5
				Art.box(root,Vector3(.04,-.1,.01),Vector3(.05,.20,.08),Art.INK)
				Art.box(root,Vector3(.055,.095,-.14),Vector3(.045,.06,.23),Color("c5bacb"))
				Art.box(root,Vector3(0,-.08,.18),Vector3(.18,.035,.24),Color("655d73"))
			"mortar":
				var tube=Art.cylinder(root,Vector3(0,.0,-.18),.08,.66,Color("817991"));tube.rotation.x=-.65
				Art.box(root,Vector3(0,-.23,.1),Vector3(.38,.035,.36),Art.INK)
			"grenade":
				Art.loft(root,Vector3(0,-.08,0),[Vector4(0,.045,.045,0),Vector4(.08,.064,.064,0),Vector4(.14,.045,.045,0)],Color("9995aa"),12)
				Art.box(root,Vector3(.018,.09,0),Vector3(.025,.055,.08),Art.INK)
			_:
				Art.box(root,Vector3(0,-.025,.06),Vector3(.18,.20,.34),Color("9f98ad"))
				for i in range(6 if w.name=="Minigun" else 1):
					var tube=Art.cylinder(root,Vector3(cos(i*TAU/6)*.055,sin(i*TAU/6)*.055,-.32),.021,.53,Art.INK);tube.rotation.x=PI*.5
		Batch.collapse(root,[],"range_weapon_"+w.id)
	var scale_factor=.55 if w.get("mechanics",{}).get("pistol",false) else .78 if w.get("archetype","")=="smg" else 1.0
	# Read the real forward end of the rendered barrel, including its vertical offset.
	var muzzle=Vector3(0,0,-.61 if w.kind=="rocket" else -.585)
	if weapon_cache.has(w.id):
		var mesh: ArrayMesh=weapon_cache[w.id];var front=mesh.get_aabb().position.z;var low=INF;var high=-INF
		for surface in range(mesh.get_surface_count()):
			for point in mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				if point.z<=front+.006:low=minf(low,point.y);high=maxf(high,point.y)
		muzzle=Vector3(0,(low+high)*.5 if is_finite(low) else 0.0,front-.004)
	if w.kind=="mortar":muzzle=Vector3(0,.33*cos(.65),-.18-.33*sin(.65))
	if w.kind in ["grenade","melee"]:muzzle=Vector3(0,.08,-.06)
	if not special:WeaponIdentity.details(root,w,muzzle)
	muzzle=root.get_meta("primary_muzzle",muzzle)
	# All added rigid detail shares cached batches, rather than separate runtime draws.
	var rotor=root.get_node_or_null("BarrelRotor")
	var batches=Batch.collapse(root,[rotor] if rotor!=null else [],"weapon_identity_"+str(w.id))
	if rotor!=null:
		batches.append(rotor);Batch.prune_empty(root,[rotor])
	var bounds=AABB();var has_bounds=false
	for node in batches:
		bounds=bounds.merge(node.mesh.get_aabb()) if has_bounds else node.mesh.get_aabb();has_bounds=true
	root.scale=Vector3.ONE*scale_factor
	if has_bounds and WeaponIdentity.LENGTHS.has(w.id):
		root.scale.z=float(WeaponIdentity.LENGTHS[w.id])/maxf(.05,bounds.size.z)
	if has_bounds and w.kind in ["bullet","hitscan"]:root.scale.x=WeaponIdentity.width(w)/maxf(.04,bounds.size.x)
	# Round barrel cluster must not inherit the narrow rifle-width squeeze.
	if rotor!=null:root.scale=Vector3.ONE*root.scale.z
	var socket=Marker3D.new();socket.name="MuzzleSocket";root.add_child(socket);socket.position=muzzle
	if w.kind=="mortar":socket.rotation.x=PI*.5-.65
	var eject=Marker3D.new();eject.name="EjectionSocket";root.add_child(eject);eject.position=root.get_meta("ejection_at",Vector3(.065,.025,-.035))
	var magazine=Marker3D.new();magazine.name="MagazineSocket";root.add_child(magazine);magazine.position=root.get_meta("magazine_at",Vector3(0,-.13,-.17))
	var rear=Marker3D.new();rear.name="BackblastSocket";root.add_child(rear);rear.position=root.get_meta("backblast_at",Vector3(0,0,.345))
	SpecialGeometry.reload_round(root,w)
	root.set_meta("muzzle_z",muzzle.z*root.scale.z)
	root.set_meta("handling",WeaponProfile.get_profile(w))
	# Preserve all sockets, hidden reload parts and shared materials in the same
	# native resource. Reinforcements no longer rebuild model details in play.
	var descendants=[root]
	while not descendants.is_empty():
		var node: Node=descendants.pop_back()
		for child in node.get_children():child.owner=root;descendants.append(child)
	var packed=PackedScene.new()
	if packed.pack(root)==OK:weapon_scenes[w.id]=packed
	return root

static func extrude(points: PackedVector2Array,depth: float,color: Color,v: PackedVector3Array,n: PackedVector3Array,c: PackedColorArray) -> void:
	var tris=Geometry2D.triangulate_polygon(points)
	for side in [-1,1]:
		for i in tris:
			var p=points[i];v.append(Vector3(side*depth,(24-p.y)*.013,-(p.x-36)*.013));n.append(Vector3(side,0,0));c.append(color if side==1 else color.darkened(.08))
	for i in range(points.size()):
		var a=points[i];var b=points[(i+1)%points.size()]
		var corners=[Vector3(-depth,(24-a.y)*.013,-(a.x-36)*.013),Vector3(depth,(24-a.y)*.013,-(a.x-36)*.013),Vector3(depth,(24-b.y)*.013,-(b.x-36)*.013),Vector3(-depth,(24-b.y)*.013,-(b.x-36)*.013)]
		var normal=(corners[1]-corners[0]).cross(corners[2]-corners[0]).normalized()
		for k in [0,1,2,0,2,3]:v.append(corners[k]);n.append(normal);c.append(color.darkened(.12))

static func vehicle(parent: Node3D,v: Dictionary) -> Dictionary:
	return EmplacementArt.build(parent,v) if v.emplacement else VehicleArt.build(parent,v)
