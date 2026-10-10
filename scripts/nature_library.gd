extends RefCounted
## Additive natural assets; imported catalogue and level placements remain intact.
const SPECS={
	"tree.oak-mature":["阔冠老橡树",6.6,Vector2(5.6,5.2),"oak"],
	"tree.oak-young":["幼年橡树",3.7,Vector2(2.5,2.4),"young"],
	"tree.birch-clump":["白桦双干",6.2,Vector2(3.4,3.0),"birch"],
	"tree.poplar-tall":["高瘦白杨",8.2,Vector2(2.7,2.5),"poplar"],
	"tree.fir-tall":["高山冷杉",7.5,Vector2(4.1,3.8),"fir"],
	"tree.snow-fir":["厚雪冷杉",6.3,Vector2(4.5,4.2),"snow-fir"],
	"tree.dead-snag":["枯树断枝",4.8,Vector2(3.2,2.8),"dead"],
	"tree.dry-acacia":["旱地伞冠树",4.7,Vector2(5.6,4.8),"acacia"],
	"tree.desert-palm":["弯干棕榈",6.8,Vector2(4.8,4.5),"palm"],
	"nature.fallen-log":["倒木与断枝",.85,Vector2(4.8,1.2),"log"],
	"nature.root-stump":["断桩与外露树根",.9,Vector2(1.5,1.4),"stump"],
	"rock.granite-boulder":["圆肩花岗岩巨石",2.1,Vector2(3.7,3.0),"granite"],
	"rock.granite-low":["低矮扁石",.72,Vector2(3.2,2.6),"low"],
	"rock.slate-shards":["倾斜板岩石簇",2.65,Vector2(3.6,2.7),"slate"],
	"rock.sandstone-layers":["风蚀层积砂岩",2.4,Vector2(3.8,2.9),"sandstone"],
	"rock.sandstone-arch":["可穿行砂岩拱",3.5,Vector2(5.8,2.3),"arch"],
	"rock.basalt-columns":["六棱玄武岩柱",3.2,Vector2(3.4,2.8),"basalt"],
	"rock.red-mesa":["红土台状岩",2.2,Vector2(4.2,3.0),"mesa"],
	"rock.scree":["松散碎石簇",.52,Vector2(3.8,2.8),"scree"]
}
const CLUSTERS={
	"nature.oak-grove":{"label":"混合林地 · 大小树与倒木","span":Vector2(13,11),"members":[["tree.oak-mature",-3,-2,0],["tree.oak-young",3,1,.4],["tree.birch-clump",3,-3,-.3],["nature.fallen-log",-1,3,.3],["nature.root-stump",-4,3,0],["rock.granite-low",4,4,.5]]},
	"nature.birch-line":{"label":"白桦疏林 · 通行间隙","span":Vector2(13,7),"members":[["tree.birch-clump",-4,-1,.1],["tree.birch-clump",0,1,-.4],["tree.birch-clump",4,-1,.7],["nature.root-stump",-2,2,.3]]},
	"nature.snow-stand":{"label":"积雪松林 · 厚雪枝冠 / 岩石","span":Vector2(13,11),"biome":"snow","members":[["tree.snow-fir",-3,-2,.2],["tree.snow-fir",3,1,.8],["tree.fir-tall",3,-4,.4],["rock.granite-boulder",-3,3,.2],["rock.granite-low",2,4,.6]]},
	"nature.desert-wadi":{"label":"沙漠旱谷 · 伞冠树 / 岩拱","span":Vector2(14,11),"members":[["tree.dry-acacia",-4,-2,.3],["tree.desert-palm",4,-2,.6],["rock.sandstone-arch",0,3,0],["rock.sandstone-layers",4,4,.4]]},
	"nature.red-ridge":{"label":"红土地岩脊 · 台岩 / 枯树","span":Vector2(13,10),"members":[["rock.red-mesa",-3,-2,.2],["rock.slate-shards",3,-2,-.5],["tree.dead-snag",0,3,.3],["rock.scree",-4,3,.4]]},
	"nature.rubble-field":{"label":"山地碎石带 · 高低掩体","span":Vector2(13,10),"members":[["rock.basalt-columns",-3,-2,.2],["rock.granite-boulder",3,-2,.7],["rock.scree",-3,3,.4],["rock.scree",2,3,-.4],["rock.granite-low",4,2,.5]]}
}

static func single_id(component: String) -> String:return "nature.single-"+component.replace(".","-")
static func register(catalog):
	for id in SPECS:
		var s: Array=SPECS[id];var rock=id.begins_with("rock.")
		catalog.components[id]={"id":id,"label":s[0],"primitive":"area","material":"stone" if rock else "wood","defaults":{"length":s[2].x*40,"thickness":s[2].y*40},"runtime":{"kind":"concrete" if rock else "barrier","output":"natural","collision":true,"blocksProjectiles":true,"damageable":true}}
		catalog.prefabs[single_id(id)]={"id":single_id(id),"label":s[0]+" · 单体","nature":true,"godot_height":s[1],"members":[[id,0,0,0]],"footprint":footprint(s[2])}
	for id in CLUSTERS:
		var p: Dictionary=CLUSTERS[id].duplicate(true);p.id=id;p.nature=true;p.godot_height=0.0;p.footprint=footprint(p.span)
		for member in p.members:p.godot_height=maxf(p.godot_height,SPECS[member[0]][1])
		catalog.prefabs[id]=p
	for id in catalog.prefabs:
		if catalog.prefabs[id].get("nature",false):catalog.templates[id]={"walls":[],"trees":[],"world":{"groundFeatures":[]}}

static func footprint(size: Vector2) -> Array:
	return [[-size.x*20,-size.y*20],[size.x*20,-size.y*20],[size.x*20,size.y*20],[-size.x*20,size.y*20]]

static func compile(catalog,plan,out,instance):
	var prefab: Dictionary=catalog.prefabs[instance.prefabId]
	var scale=Vector2(float(instance.get("scaleX",instance.get("scale",1))),float(instance.get("scaleY",instance.get("scale",1))))
	var angle=float(instance.get("rotation",0));var settings: Dictionary=instance.get("godot3d",{})
	var rise=float(settings.get("height",prefab.godot_height))/maxf(.01,prefab.godot_height)*sqrt(absf(scale.x*scale.y))
	for i in range(prefab.members.size()):
		var m: Array=prefab.members[i];var spec: Array=SPECS[m[0]]
		var center=catalog.v(instance)+(Vector2(m[1],m[2])*scale).rotated(angle)*40
		var axis=Vector2(spec[2].x*scale.x*20,0).rotated(angle+float(m[3]))
		var details=settings.duplicate(true);details.height=float(spec[1])*rise
		var o=catalog.object_from_segment(str(instance.id)+"."+str(i),m[0],center-axis,center+axis,float(spec[2].y)*scale.y*40,plan,details,str(instance.id))
		o.nature_biome=prefab.get("biome","");out.objects.append(o)

static func samples() -> Array:
	var result=[];var trees=0;var rocks=0
	for id in SPECS:
		var at: Vector2
		if id.begins_with("rock."):
			at=Vector2(39+7*(rocks%2),-10+8*int(rocks/2));rocks+=1
		else:
			at=Vector2(16+7*(trees%5),21+7*int(trees/5));trees+=1
			if trees==11:at=Vector2(20,32)
		result.append({"component":id,"point":at,"label":SPECS[id][0]})
	return result

static func training(plan):
	for s in samples():
		var p: Vector2=s.point*40+Vector2(plan.world.w,plan.world.h)*.5
		plan.instances.append({"id":"natural-sample-"+s.component,"prefabId":single_id(s.component),"x":p.x,"y":p.y,"rotation":0,"scale":1})
	plan.godot3d.nature_training=true
