extends RefCounted
## Editable acceptance layout; the same catalog/prefab pipeline is used by the normal range.

static func point(at: Vector2) -> Vector2:return at*40+Vector2(1200,900)

static func segment(plan: Dictionary,id: String,component: String,at: Vector2,length: float,thickness: float,height: float):
	var p=point(at)
	plan.looseSegments.append({"id":id,"componentId":component,"x1":p.x-length*20,"y1":p.y,"x2":p.x+length*20,"y2":p.y,"thickness":thickness*40,"godot3d":{"height":height}})

static func plan(catalog) -> Dictionary:
	var p=catalog.range_plan()
	p.id="terrain-outpost-review";p.title="林地前哨 · 地形与破坏"
	p.world={"w":2400,"h":1800,"seed":260926,"theme":"outpost","groundFeatures":[]}
	p.instances=[];p.looseSegments=[];p.trees=[];p.vehicles=[];p.emplacements=[];p.units.red=[]
	p.godot3d={"range":false,"terrain_review":true}
	var spawn=point(Vector2(-5,12));p.deployment.player={"x":spawn.x,"y":spawn.y}
	for spec in [["grass",Vector2(-27,-20),Vector2(-16,20)],["grass",Vector2(17,-20),Vector2(27,20)],["yard-concrete",Vector2(-15,-13),Vector2(14,-3)]]:
		var a=point(spec[1]);var b=point(spec[2])
		p.world.groundFeatures.append({"kind":"area","componentId":"terrain."+spec[0],"points":[[a.x,a.y],[b.x,a.y],[b.x,b.y],[a.x,b.y]]})
	for route in [[Vector2(-3,20),Vector2(-3,-15),5.0],[Vector2(-18,-1),Vector2(17,-1),4.0]]:
		var a=point(route[0]);var b=point(route[1])
		p.world.groundFeatures.append({"kind":"path","componentId":"path.dirt-road","points":[[a.x,a.y],[b.x,b.y]],"width":route[2]*40})
	for spec in [["brick-sample","wall.brick",Vector2(-9,5),3.8,.40,2.4],["concrete-sample","wall.concrete",Vector2(-3,5),3.8,.45,2.4],["timber-sample","wall.wood-fence",Vector2(3,5),3.6,.30,1.65],["sandbag-sample","wall.sandbag",Vector2(9,5),3.6,.60,.95]]:
		segment(p,spec[0],spec[1],spec[2],spec[3],spec[4],spec[5])
	for spec in [["guard-house","building.guard-post",Vector2(-9,-8),2.8],["work-shed","building.shed",Vector2(8,-8),2.65]]:
		var at=point(spec[2])
		p.instances.append({"id":spec[0],"prefabId":spec[1],"x":at.x,"y":at.y,"rotation":0,"scale":1,"godot3d":{"height":spec[3],"roof":true,"windows":true}})
	segment(p,"supply-container","prop.container",Vector2(17,-10),5.2,2.4,2.5)
	segment(p,"yard-crates","prop.crate",Vector2(4,-8),1.15,1.0,.9)
	segment(p,"outer-crate","prop.crate",Vector2(-15,-1),1.2,.9,.85)
	segment(p,"fuel-drum","prop.barrel",Vector2(-14,-3),.7,.7,.95)
	segment(p,"yard-barrier","obstacle.concrete-barrier",Vector2(14,0),2.5,.55,.9)
	for i in range(10):
		var side=-1 if i<5 else 1;var at=point(Vector2(side*(20.5+float(i%2)*2),-15+float(i%5)*6.4))
		p.trees.append({"id":"forest-"+str(i),"x":at.x,"y":at.y,"radius":34,"mapKitComponentId":"tree.conifer" if i%3!=0 else "tree.broadleaf","godot3d":{"height":3.3+float(i%3)*.3}})
	for i in range(3):segment(p,"forest-rock-"+str(i),"obstacle.rock-large",Vector2(-17.5+i*18,-17),1.8,1.3,.9)
	for i in range(4):
		var at=point(Vector2(-9+i*6,1.3));p.units.red.append({"id":"cover-target-"+str(i),"x":at.x,"y":at.y,"angle":PI*.5})
	return p
