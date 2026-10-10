extends RefCounted
## Range 02 is a small playable material reference using the existing prefab catalogue.
const Ground=preload("res://scripts/terrain_ground.gd")
const Art=preload("res://scripts/ink_art.gd")
const Geometry=preload("res://scripts/terrain_art.gd")
static func point(at: Vector2) -> Vector2:return at*40+Vector2(960,800)

static func area(p: Dictionary,id: String,from: Vector2,to: Vector2):
	var a=point(from);var b=point(to)
	p.world.groundFeatures.append({"kind":"area","componentId":id,"points":[[a.x,a.y],[b.x,a.y],[b.x,b.y],[a.x,b.y]]})

static func segment(p: Dictionary,id: String,component: String,a: Vector2,b: Vector2,width: float,height: float):
	var start=point(a);var end=point(b)
	p.looseSegments.append({"id":id,"componentId":component,"x1":start.x,"y1":start.y,"x2":end.x,"y2":end.y,"thickness":width*40,"godot3d":{"height":height}})

static func plan(_catalog) -> Dictionary:
	var p={"format":"endless-war-scene-plan","version":"2.0.0","id":"proving-ground-2","levelId":0,"title":"演武场2 · 荒原墨线",
		"world":{"w":1920,"h":1600,"seed":260929,"theme":"outpost","groundFeatures":[]},"instances":[],"looseSegments":[],"trees":[],"vehicles":[],"emplacements":[],"units":{"blue":[],"red":[]},
		"deployment":{"player":{"x":960,"y":1040},"blue":{"initialCount":1,"spawnPoints":[]},"red":{"initialCount":0,"spawnPoints":[]}},"godot3d":{"range":false,"style_range":true},"controlPoints":[]}
	area(p,"terrain.sand",Vector2(-24,-20),Vector2(24,20))
	# Real low dunes at the nature edge; the paved test lanes stay genuinely level.
	area(p,"terrain.desert",Vector2(12,-16),Vector2(23,10))
	p.world.groundFeatures[-1].godot3d={"height":.8}
	area(p,"terrain.red-earth",Vector2(-22,-18),Vector2(22,-11))
	area(p,"terrain.yard-concrete",Vector2(-18,-9),Vector2(10,11))
	area(p,"path.asphalt",Vector2(-4,-20),Vector2(3,20))
	# Separate firing lanes, with room around every breakable panel.
	segment(p,"r2-brick","wall.brick",Vector2(-3,-4),Vector2(.1,-4),.24,1.8)
	segment(p,"r2-concrete","wall.concrete",Vector2(2,-4),Vector2(5,-4),.20,1.45)
	segment(p,"r2-timber","wall.wood-fence",Vector2(7,-4),Vector2(10,-4),.12,1.15)
	segment(p,"r2-sandbags","wall.sandbag",Vector2(-5,-11),Vector2(3,-11),.5,.8)
	segment(p,"r2-yard-back","wall.concrete",Vector2(-20,-17),Vector2(19,-17),.35,2.6)
	segment(p,"r2-yard-left","wall.brick",Vector2(-21,-16),Vector2(-21,6),.30,1.8)
	segment(p,"r2-container","prop.container",Vector2(-17,-9),Vector2(-12,-9),2.4,2.4)
	segment(p,"r2-crate-a","prop.crate",Vector2(-12,-4),Vector2(-11,-4),.85,.8)
	segment(p,"r2-crate-b","prop.crate",Vector2(-14,-4.5),Vector2(-13,-4.5),.9,1.2)
	segment(p,"r2-drum-a","prop.barrel",Vector2(-10,-7),Vector2(-9.7,-7),.65,.92)
	segment(p,"r2-drum-b","prop.barrel",Vector2(-11,-6),Vector2(-10.7,-6),.65,.92)
	# Existing nature prefabs, with original collision/support geometry.
	for spec in [["tree.dry-acacia",Vector2(15,-4),.2],["rock.sandstone-layers",Vector2(17,2),.1],["rock.granite-low",Vector2(12,7),-.4],["tree.broadleaf",Vector2(17,-12),0.0]]:
		var at=point(spec[1])
		if spec[0]=="tree.broadleaf":p.trees.append({"id":"r2-leaf-tree","x":at.x,"y":at.y,"radius":46,"mapKitComponentId":spec[0],"godot3d":{"height":3.8}})
		else:p.instances.append({"id":"r2-"+spec[0],"prefabId":preload("res://scripts/nature_library.gd").single_id(spec[0]),"x":at.x,"y":at.y,"rotation":spec[2],"scale":1,"godot3d":{}})
	for spec in [["armedJeep","blue",Vector2(-9,3)],["armedJeep","red",Vector2(-15,3)],["heavyTank","blue",Vector2(-14,11)]]:
		var at=point(spec[2]);p.vehicles.append({"id":"r2-"+spec[1]+"-"+spec[0],"type":spec[0],"team":spec[1],"x":at.x,"y":at.y,"angle":-PI*.5})
	for i in range(5):
		var at=point(Vector2(-2+i*2.6,-7.2))
		p.units.red.append({"id":"r2-target-"+str(i),"x":at.x,"y":at.y,"angle":PI*.5,"class_id":["assault","medic","engineer","support","recon"][i],"team":1})
	for i in range(2):
		var at=point(Vector2(5+i*2.5,3))
		p.units.red.append({"id":"r2-blue-"+str(i),"x":at.x,"y":at.y,"angle":-PI*.5,"class_id":["medic","engineer"][i],"team":0})
	return p

static func decorate(parent: Node3D):
	# Paint only: one static surface, no extra collision nodes or per-frame scripts.
	var v=PackedVector3Array();var n=PackedVector3Array();var c=PackedColorArray()
	var cream=Color("ead7a2");var ink=Color("303943");var ochre=Color("d49d39")
	for x in [-18.0,-12.0,-6.0]:
		Ground.strip(v,n,c,Vector2(x,0),Vector2(x,7),.075,.025,cream)
	Ground.strip(v,n,c,Vector2(-18,7),Vector2(-6,7),.08,.025,cream)
	for lane in range(3):
		var x=-1.5+lane*4.7
		Ground.strip(v,n,c,Vector2(x-1.7,-1.2),Vector2(x+1.7,-1.2),.5,.024,ink)
		for i in range(8):
			var p=Vector2(x-1.6+i*.4,-1.43)
			Ground.strip(v,n,c,p,p+Vector2(.21,.46),.13,.025,ochre)
		# Short lane marks, distressed with deliberately unequal lengths.
		for z in [0.4,2.3,4.2]:Ground.strip(v,n,c,Vector2(x,z),Vector2(x,z+.7),.07,.026,cream)
	# Large stencil 02 in the entrance, built as paint quads in the same batch.
	for spec in [[-2.7,10.0,-1.4,10.0],[-2.7,12.3,-1.4,12.3],[-2.7,10.0,-2.7,12.3],[-1.4,10.0,-1.4,12.3],[.1,10.0,1.4,10.0],[1.4,10.0,1.4,11.1],[.1,11.1,1.4,11.1],[.1,11.1,.1,12.3],[.1,12.3,1.4,12.3]]:
		Ground.strip(v,n,c,Vector2(spec[0],spec[1]),Vector2(spec[2],spec[3]),.20,.027,cream)
	var node=Art.mesh_node(parent,Geometry.mesh_from(v,n,c),Vector3.ZERO,Color.WHITE)
	node.material_override=Art.ink_material(Color.WHITE,true,.04)
