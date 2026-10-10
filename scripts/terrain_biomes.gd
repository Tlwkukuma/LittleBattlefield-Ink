extends RefCounted
## Additive catalogue entries; original imported assets remain untouched.
static func register(catalog):
	for spec in [["terrain.desert","沙漠 · 风蚀沙地",16,14],["terrain.red-earth","红土 · 赭红旱地",16,14],["landform.mountain","山体 · 岩石缓坡",20,18],["landform.trench","壕沟 · 下挖 / 端部坡道",14,6],["access.ladder","梯子 · 连接高低地面",1.7,.8]]:
		catalog.components[spec[0]]={"id":spec[0],"label":spec[1],"primitive":"segment","material":"ground","defaults":{"length":spec[2]*40,"thickness":spec[3]*40},"runtime":{"output":"ground","collision":false,"blocksProjectiles":false,"damageable":false}}

static func register_prefabs(catalog):
	for spec in [["biome.snowfield","积雪 · 雪堆与压实通路","terrain.snow",16,14,1.6],["biome.desert","沙漠 · 双沙丘与丘间通路","terrain.desert",16,14,2.3],["biome.red-earth","红土地块","terrain.red-earth",16,14,0],["biome.mountain","山体 · 缓坡与陡壁","landform.mountain",20,18,3.4],["biome.trench-ladder","壕沟 · 端坡与梯子","landform.trench",14,6,1.65]]:
		var x: float=spec[3]*20;var z: float=spec[4]*20
		catalog.prefabs[spec[0]]={"id":spec[0],"label":spec[1],"footprint":[[-x,-z],[x,-z],[x,z],[-x,z]],"godot_height":spec[5]}
		var ground=[{"kind":"path","componentId":spec[2],"points":[[-x,0],[x,0]],"width":z*2,"godot3d":{"height":spec[5]}}]
		var ladders=[]
		if spec[0]=="biome.trench-ladder":ladders.append({"id":"exit","a":[0,76],"b":[0,140],"width":34})
		catalog.templates[spec[0]]={"walls":[],"trees":[],"world":{"groundFeatures":ground},"ladders":ladders}

static func segment(plan,id: String,component: String,a: Vector2,b: Vector2,width: float,height: float=0):
	var center=Vector2(plan.world.w,plan.world.h)*.5
	a=a*40+center;b=b*40+center
	var item={"id":id,"componentId":component,"x1":a.x,"y1":a.y,"x2":b.x,"y2":b.y,"thickness":width*40}
	if height!=0:item.godot3d={"height":height}
	plan.looseSegments.append(item)

static func training(plan):
	# Northern wing of the SAME proving ground; all original lanes stay in place.
	segment(plan,"biome-snow","terrain.snow",Vector2(-42,-25),Vector2(-24,-25),15)
	segment(plan,"biome-desert","terrain.desert",Vector2(-18,-25),Vector2(0,-25),15)
	segment(plan,"biome-red","terrain.red-earth",Vector2(5,-25),Vector2(25,-25),15)
	segment(plan,"biome-mountain","landform.mountain",Vector2(27,-25),Vector2(47,-25),18,3.4)
	segment(plan,"biome-trench","landform.trench",Vector2(7,-25),Vector2(23,-25),6,1.65)
	# Endpoints run from the trench floor toward its southern rim.
	segment(plan,"biome-ladder","access.ladder",Vector2(15,-23.1),Vector2(15,-21.5),.85)
	segment(plan,"biome-cover-snow","wall.sandbag",Vector2(-35,-27),Vector2(-31,-27),.6,1.0)
	segment(plan,"biome-cover-desert","wall.ruin",Vector2(-12,-26),Vector2(-8,-26),.45,1.4)
	segment(plan,"biome-cover-red","wall.brick",Vector2(9,-20),Vector2(13,-20),.4,2.0)
	segment(plan,"biome-cover-rock","wall.stone",Vector2(33,-15),Vector2(37,-15),.55,1.0)
	for p in [Vector2(-40,-28),Vector2(-26,-29),Vector2(-40,-21)]:
		var at=p*40+Vector2(plan.world.w,plan.world.h)*.5
		plan.trees.append({"id":"snow-pine-"+str(plan.trees.size()),"x":at.x,"y":at.y,"mapKitComponentId":"tree.conifer","radius":28,"godot3d":{"height":3.5}})
	segment(plan,"desert-rock-a","obstacle.rock-large",Vector2(-17,-29),Vector2(-16,-29),1.4,.75)
	segment(plan,"desert-rock-b","obstacle.rock-small",Vector2(-3,-28),Vector2(-2.4,-28),.9,.5)
	plan.godot3d.biome_training=true

static func labels() -> Array:
	return [["雪 地",Vector2(-33,-18.8)],["沙 漠",Vector2(-9,-18.8)],["红 土 / 壕 沟",Vector2(16,-17.8)],["山 体",Vector2(37,-14.5)],["E 梯子 · W 上 / S 下",Vector2(16,-20.3)],["坡道入口",Vector2(6,-25)]]
