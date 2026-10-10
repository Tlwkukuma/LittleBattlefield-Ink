extends RefCounted
## Range 02 is a small playable material reference using the existing prefab catalogue.
const Ground=preload("res://scripts/terrain_ground.gd")
const Art=preload("res://scripts/ink_art.gd")
const Geometry=preload("res://scripts/terrain_art.gd")
static func point(at: Vector2) -> Vector2:return at*40+Vector2(960,800)

static func area(p: Dictionary,id: String,from: Vector2,to: Vector2):
	var a=point(from);var b=point(to)
	p.world.groundFeatures.append({"kind":"area","componentId":id,"points":[[a.x,a.y],[b.x,a.y],[b.x,b.y],[a.x,b.y]]})

static func polygon(p: Dictionary,id: String,points: Array,tint: String):
	var outline=[]
	for at in points:
		var v=point(at);outline.append([v.x,v.y])
	p.world.groundFeatures.append({"kind":"area","componentId":id,"points":outline,"mapKitVisual":{"fill":tint,"alpha":1}})

static func instance(p: Dictionary,id: String,prefab: String,at: Vector2,angle: float=0.0,scale: float=1.0):
	var pos=point(at)
	p.instances.append({"id":id,"prefabId":prefab,"x":pos.x,"y":pos.y,"rotation":angle,"scale":scale,"godot3d":{}})

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
	# Irregular compacted aprons and an eroded yard edge, instead of full-screen bands.
	polygon(p,"terrain.red-earth",[Vector2(-24,-20),Vector2(24,-20),Vector2(23,-13),Vector2(12,-11),Vector2(9,-14),Vector2(-18,-14),Vector2(-24,-7)],"#af8665")
	polygon(p,"terrain.yard-concrete",[Vector2(-20,-14),Vector2(-8,-14),Vector2(-5,-6),Vector2(-4,7),Vector2(-7,9),Vector2(-19,9),Vector2(-20,1)],"#a9a08d")
	polygon(p,"terrain.yard-concrete",[Vector2(-5,-13),Vector2(10,-12),Vector2(12,-8),Vector2(11,1),Vector2(8,8),Vector2(-4,8),Vector2(-6,0)],"#a5a394")
	polygon(p,"terrain.sand",[Vector2(-24,10),Vector2(-18,8),Vector2(-6,10),Vector2(-2,15),Vector2(8,20),Vector2(-24,20)],"#b59d76")
	# Separate firing lanes, with room around every breakable panel.
	segment(p,"r2-brick","wall.brick",Vector2(-3,-4),Vector2(.1,-4),.24,1.8)
	segment(p,"r2-concrete","wall.concrete",Vector2(2,-4),Vector2(5,-4),.20,1.45)
	segment(p,"r2-timber","wall.wood-fence",Vector2(7,-4),Vector2(10,-4),.12,1.15)
	segment(p,"r2-sandbags","wall.sandbag",Vector2(-5,-11),Vector2(3,-11),.5,.8)
	segment(p,"r2-yard-back","wall.concrete",Vector2(-5,-13),Vector2(10,-13),.35,1.3)
	segment(p,"r2-yard-left","wall.brick",Vector2(-21,-15),Vector2(-21,-2),.30,1.5)
	instance(p,"r2-workshop","building.shed",Vector2(-13,-10.5))
	segment(p,"r2-container","prop.container",Vector2(-18,-6),Vector2(-18,-.5),2.4,2.6)
	segment(p,"r2-service-barrier","obstacle.concrete-barrier",Vector2(-18,10),Vector2(-14,10),.55,.75)
	segment(p,"r2-light-left","prop.road-light",Vector2(-18.4,-14),Vector2(-18.1,-14),.2,4.2)
	segment(p,"r2-light-back","prop.road-light",Vector2(9.5,-12),Vector2(9.8,-12),.2,4.0)
	segment(p,"r2-crate-a","prop.crate",Vector2(-12,-4),Vector2(-11,-4),.85,.8)
	segment(p,"r2-crate-b","prop.crate",Vector2(-14,-4.5),Vector2(-13,-4.5),.9,1.2)
	segment(p,"r2-drum-a","prop.barrel",Vector2(-10,-7),Vector2(-9.7,-7),.65,.92)
	segment(p,"r2-drum-b","prop.barrel",Vector2(-11,-6),Vector2(-10.7,-6),.65,.92)
	for i in range(3):segment(p,"r2-drum-storage-"+str(i),"prop.barrel",Vector2(-15.5+i*.8,-6),Vector2(-15.2+i*.8,-6),.65,.92)
	segment(p,"r2-crate-storage","prop.crate",Vector2(-9,-10),Vector2(-8,-10),.8,1.4)
	# Existing nature prefabs, with original collision/support geometry.
	var nature=[["tree.dry-acacia",Vector2(15,-4),.2,1.0],["rock.sandstone-layers",Vector2(17,2),.1,1.15],["rock.granite-low",Vector2(12,7),-.4,1.0],["rock.red-mesa",Vector2(17,-12),.3,1.55],["rock.sandstone-layers",Vector2(21,-6),-.3,1.3],["rock.sandstone-arch",Vector2(16,11),.2,1.0],["tree.dead-snag",Vector2(20,6),.3,1.0],["rock.scree",Vector2(10,11),.4,1.0],["rock.red-mesa",Vector2(-16,-18),-.3,1.5],["rock.sandstone-layers",Vector2(-8,-17),.2,1.2]]
	for i in range(nature.size()):
		var spec: Array=nature[i]
		instance(p,"r2-nature-"+str(i),preload("res://scripts/nature_library.gd").single_id(spec[0]),spec[1],spec[2],spec[3])
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
	var cream=Color("bdb18c");var ink=Color("383c3b");var ochre=Color("b99348")
	# Ground-only grime and repair scars are static paint, not persistent prop shadows.
	for spec in [[-15.0,1.8,1.6,.6],[-9.0,1.8,1.5,.65],[-11.5,-5.5,1.4,.7],[-3.0,-10.0,1.8,.55]]:
		Ground.disc(v,n,c,Vector2(spec[0],spec[1]),Vector2(spec[2],spec[3]),.020,Color("706c5c"),int(spec[0]*3))
	for x in [-16.0,-10.0]:
		for j in range(16):
			var at=Vector2(x+sin(j*.13)*.35,7-j*.38)
			Ground.strip(v,n,c,at,at+Vector2(.35,-.10),.045,.022,Color("8c806a"))
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
