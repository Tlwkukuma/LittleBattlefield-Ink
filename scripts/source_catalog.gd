extends RefCounted
const SCALE=40.0
var data: Dictionary
var components: Dictionary={}
var prefabs: Dictionary={}
var templates: Dictionary
var scenes: Array
var weapons: Dictionary={}
var atlas: Dictionary

func _init() -> void:
	data=read("catalog.json")
	preload("res://scripts/vehicle_durability.gd").bind(data)
	preload("res://scripts/weapon_fire_control.gd").bind_mounted(data)
	for item in read("components.json").components:components[item.id]=item
	components["wall.metal-fence"].runtime.blocksProjectiles=true
	for item in read("prefabs.json").prefabs:prefabs[item.id]=item
	preload("res://scripts/terrain_biomes.gd").register(self)
	templates=read("compiled-prefabs.json")
	preload("res://scripts/terrain_biomes.gd").register_prefabs(self)
	preload("res://scripts/house_prefabs.gd").register(self)
	preload("res://scripts/nature_library.gd").register(self)
	preload("res://scripts/orchard_prefabs.gd").register(self)
	preload("res://scripts/terrain_landforms.gd").register(self)
	preload("res://scripts/trench_prefabs.gd").register(self)
	scenes=read("scenes.json").scenes
	atlas=read("weapon-atlas.json")
	for item in data.weapons:weapons[item.id]=item
	preload("res://scripts/cover_rules.gd").bind(self)

static func read(file: String):
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/original/"+file))

static func v(point) -> Vector2:
	if point is Array:return Vector2(float(point[0]),float(point[1]))
	return Vector2(float(point.get("x",0)),float(point.get("y",0)))

func position(point,plan: Dictionary) -> Vector2:
	return (v(point)-Vector2(plan.world.w,plan.world.h)*.5)/SCALE

func original_point(point: Vector2,plan: Dictionary) -> Vector2:
	return point*SCALE+Vector2(plan.world.w,plan.world.h)*.5

func default_height(component_id: String) -> float:
	if preload("res://scripts/nature_library.gd").SPECS.has(component_id):return preload("res://scripts/nature_library.gd").SPECS[component_id][1]
	if component_id.begins_with("furniture."):return preload("res://scripts/house_furniture.gd").default_height(component_id)
	if component_id=="structure.floor":return .22
	if component_id=="structure.stair":return .17
	if component_id=="structure.rail":return 1.02
	if component_id=="terrain.snow":return 1.6
	if component_id=="terrain.desert":return 2.3
	if component_id=="landform.mountain":return 3.4
	if component_id=="landform.trench":return 1.65
	if component_id=="landform.low-hill":return 1.5
	if component_id=="landform.trench-network":return 1.3
	if component_id=="landform.level-pad":return 0
	if component_id=="defense.trench-firing-step":return .36
	if component_id=="defense.trench-revetment":return 1.1
	if component_id.begins_with("door."):return 2.25
	if component_id in ["wall.sandbag","wall.stone","wall.ruin","obstacle.concrete-barrier"]:return 1.1
	if component_id in ["wall.wood-fence","wall.metal-fence","wall.hedge"]:return 1.45
	if component_id.begins_with("wall."):return 2.8
	if component_id=="prop.container":return 2.6
	if component_id in ["prop.utility-pole","prop.road-light"]:return 4.0
	if component_id=="prop.barrel":return .95
	if component_id=="prop.crate":return .8
	if component_id=="tree.broadleaf-small":return 2.45
	if component_id=="tree.broadleaf":return 3.65
	if component_id.begins_with("tree."):return 3.2
	return .65

func compile(plan: Dictionary) -> Dictionary:
	var out={"objects":[],"ground":[],"ladders":[],"houses":[],"roofs":[],"vehicles":[],"targets":[],"bounds":Vector2(plan.world.w,plan.world.h)/SCALE*.5}
	for feature in plan.world.get("groundFeatures",[]):
		if feature.get("componentId",feature.get("mapKitComponentId","")) in preload("res://scripts/trench_prefabs.gd").IDS:
			preload("res://scripts/trench_prefabs.gd").compile_feature(self,plan,out,feature)
		else:out.ground.append(feature.duplicate(true))
	for instance in plan.get("instances",[]):
		if instance.prefabId in preload("res://scripts/trench_prefabs.gd").IDS:
			preload("res://scripts/trench_prefabs.gd").compile_instance(self,plan,out,instance);continue
		if prefabs.get(instance.prefabId,{}).get("nature",false):
			preload("res://scripts/nature_library.gd").compile(self,plan,out,instance);continue
		if instance.prefabId==preload("res://scripts/house_prefabs.gd").ID:
			preload("res://scripts/house_prefabs.gd").compile(self,plan,out,instance);continue
		if not templates.has(instance.prefabId):continue
		var source: Dictionary=templates[instance.prefabId]
		var scale=Vector2(float(instance.get("scaleX",instance.get("scale",1))),float(instance.get("scaleY",instance.get("scale",1))))
		var angle=float(instance.get("rotation",0))
		var offset=v(instance)
		for wall in source.walls:
			var centre=Vector2(wall.x+wall.w*.5,wall.y+wall.h*.5)
			var along=Vector2(cos(wall.angle),sin(wall.angle))*wall.w*.5
			var a=((centre-along)*scale).rotated(angle)+offset
			var b=((centre+along)*scale).rotated(angle)+offset
			var id=str(instance.id)+"."+str(wall.id)
			var component=str(wall.mapKitComponentId)
			var details: Dictionary=instance.get("godot3d",{}).duplicate(true)
			if str(instance.prefabId).begins_with("building.") and component.begins_with("wall.") and not details.has("height"):details.height=2.8
			var object=object_from_segment(id,component,a,b,float(wall.h)*scale.y,plan,details,str(instance.id))
			object.source_id=wall.get("source_id",wall.id)
			object.windows=str(instance.prefabId).begins_with("building.") and bool(instance.get("godot3d",{}).get("windows","bunker" not in str(instance.prefabId)))
			out.objects.append(object)
		for tree in source.get("trees",[]):
			var p=(v(tree)*scale).rotated(angle)+offset
			var component=str(tree.get("mapKitComponentId","tree.broadleaf"))
			out.objects.append(object_from_segment(str(instance.id)+"."+str(tree.id),component,p,p+Vector2(1,0),float(tree.get("radius",35))*2,plan,instance.get("godot3d",{}),str(instance.id)))
		for feature in source.world.get("groundFeatures",[]):
			var f=feature.duplicate(true)
			if str(instance.prefabId).begins_with("biome."):
				f.width=float(f.get("width",80))*scale.y
				if instance.get("godot3d",{}).has("height"):f.godot3d={"height":instance.godot3d.height}
			if f.has("points"):
				f.points=f.points.map(func(p):var t=(v(p)*scale).rotated(angle)+offset;return [t.x,t.y])
			elif f.has("x"):
				var p=(v(f)*scale).rotated(angle)+offset
				f.x=p.x;f.y=p.y
			out.ground.append(f)
		for ladder in source.get("ladders",[]):
			var low=(v(ladder.a)*scale).rotated(angle)+offset;var high=(v(ladder.b)*scale).rotated(angle)+offset
			out.ladders.append({"id":str(instance.id)+"."+str(ladder.id),"a":position_point(low,plan),"b":position_point(high,plan),"width":float(ladder.width)*scale.x/SCALE})
		var prefab: Dictionary=prefabs[instance.prefabId]
		if prefab.has("footprint") and str(prefab.id).begins_with("building."):
			var points=[]
			for p in prefab.footprint:points.append(position_point((v(p)*scale).rotated(angle)+offset,plan))
			var elevation=float(instance.get("godot3d",{}).get("elevation",0))
			out.roofs.append({"id":instance.id,"points":points,"height":elevation+float(instance.get("godot3d",{}).get("height",2.8)),"elevation":elevation,"style":str(instance.prefabId),"enabled":bool(instance.get("godot3d",{}).get("roof",true))})
	var loose: Array=plan.get("looseSegments",[])
	for item in loose:
		var component: Dictionary=components.get(item.componentId,{})
		if component.is_empty() or component.get("role","")=="opening":continue
		var a=Vector2(item.x1,item.y1)
		var b=Vector2(item.x2,item.y2)
		if item.componentId=="access.ladder":
			out.ladders.append({"id":item.id,"a":position_point(a,plan),"b":position_point(b,plan),"width":float(item.get("thickness",32))/40})
			continue
		if item.componentId in preload("res://scripts/trench_prefabs.gd").IDS:
			var feature=item.get("godot3d",{}).duplicate(true);feature.id=item.id;feature.componentId=item.componentId;feature.points=[[a.x,a.y],[b.x,b.y]]
			preload("res://scripts/trench_prefabs.gd").compile_feature(self,plan,out,feature);continue
		var runtime: Dictionary=component.get("runtime",{})
		var output=runtime.get("output","obstacle")
		if output in ["ground","decal","water"]:
			out.ground.append({"kind":"path","points":[[a.x,a.y],[b.x,b.y]],"width":item.get("thickness",component.defaults.get("thickness",40)),"mapKitVisual":component.get("visual",{}),"componentId":component.id,"godot3d":item.get("godot3d",{}).duplicate(true)})
			if output!="water":continue
		var thickness=float(item.get("thickness",component.get("defaults",{}).get("thickness",30)))
		# Match the original editor: door segments carve intervals out of their host wall.
		var intervals: Array=[]
		var direction=(b-a).normalized()
		var length=a.distance_to(b)
		for door in loose:
			if components.get(door.componentId,{}).get("role","")!="opening":continue
			var da=Vector2(door.x1,door.y1)
			var db=Vector2(door.x2,door.y2)
			if absf((db-da).normalized().dot(direction))<.94:continue
			if absf(((da+db)*.5-a).cross(direction))>thickness*.5+float(door.get("thickness",18))*.5+10:continue
			intervals.append(Vector2(clampf(minf((da-a).dot(direction),(db-a).dot(direction))-4,0,length),clampf(maxf((da-a).dot(direction),(db-a).dot(direction))+4,0,length)))
		intervals.sort_custom(func(x,y):return x.x<y.x)
		intervals.append(Vector2(length,length))
		var cursor=0.0
		var index=0
		for interval in intervals:
			if interval.x-cursor>2:
				out.objects.append(object_from_segment(str(item.id)+"_"+str(index),item.componentId,a+direction*cursor,a+direction*interval.x,thickness,plan,item.get("godot3d",{}),str(item.id)))
			cursor=maxf(cursor,interval.y);index+=1
	for tree in plan.get("trees",[]):
		var p=v(tree)
		out.objects.append(object_from_segment(str(tree.get("id","tree"))+"_tree",str(tree.get("mapKitComponentId","tree.broadleaf")),p,p+Vector2(1,0),float(tree.get("radius",30))*2,plan,tree.get("godot3d",{}),str(tree.get("id","tree"))))
	for vehicle in plan.get("vehicles",[]):out.vehicles.append(vehicle.duplicate(true))
	for mount in plan.get("emplacements",[]):
		var item=mount.duplicate(true);item.emplacement=true;out.vehicles.append(item)
	preload("res://scripts/campaign_water.gd").compile(self,plan,out)
	for target in plan.get("units",{}).get("red",[]):out.targets.append(target.duplicate(true))
	return out

func position_point(point: Vector2,plan: Dictionary) -> Vector2:
	return (point-Vector2(plan.world.w,plan.world.h)*.5)/SCALE

func object_from_segment(id: String,component_id: String,a: Vector2,b: Vector2,thickness: float,plan: Dictionary,details: Dictionary,owner: String) -> Dictionary:
	var component: Dictionary=components.get(component_id,{})
	var runtime: Dictionary=component.get("runtime",{})
	var kind=str(runtime.get("kind","barrier"))
	if details.has("material"):kind={"wood":"barrier","brick":"building","metal":"wreck"}.get(details.material,details.material)
	var position=position_point((a+b)*.5,plan)
	var size=Vector2(maxf(a.distance_to(b),thickness if component.get("primitive","")=="point" else 2),thickness)/SCALE
	return {"id":id,"owner":owner,"component_id":component_id,"position":position,"size":size,"angle":(b-a).angle(),
		"crown_radius":thickness/SCALE*.5,
		"height":float(details.get("height",default_height(component_id))),"elevation":float(details.get("elevation",0)),
		"kind":kind,"material":str(details.get("material",component.get("material","concrete"))),
		"destructible":bool(details.get("destructible",runtime.get("damageable",true))),"health_scale":float(details.get("health_scale",1)),
		"collision":bool(runtime.get("collision",true)),"ballistic":bool(runtime.get("blocksProjectiles",true)),"output":runtime.get("output","obstacle"),
		"color":component.get("color","#aaa4b9"),"detail":component.get("visual",{}).get("detail","")}

func range_plan() -> Dictionary:
	var plan={"format":"endless-war-scene-plan","version":"2.0.0","id":"godot-proving-ground","levelId":0,"title":"联合演武场",
		"world":{"w":4000,"h":2800,"seed":260925,"theme":"outpost","groundFeatures":[]},"instances":[],"looseSegments":[],"trees":[],"vehicles":[],"emplacements":[],"units":{"blue":[],"red":[]},
		"deployment":{"player":{"x":2000,"y":1660},"blue":{"initialCount":1,"spawnPoints":[]},"red":{"initialCount":0,"spawnPoints":[]}},"godot3d":{"range":true},"controlPoints":[]}
	for i in range(6):plan.units.red.append({"id":"target-"+str(i),"x":1740+i*110,"y":1080-(i%2)*80,"angle":PI*.5,"class_id":["assault","medic","engineer","support","recon"][i%5]})
	var materials=["wall.wood-fence","wall.brick","wall.concrete","wall.sandbag","wall.metal-fence","prop.barrel","prop.crate"]
	for i in range(materials.size()):
		var x=1460+i*180
		# Material targets use real reference thickness, not the former shared 80 cm slab.
		plan.looseSegments.append({"id":"destruction-"+str(i),"componentId":materials[i],"x1":x,"y1":1390,"x2":x+(70 if i>=5 else 120),"y2":1390,"thickness":[2.4,9.6,8,20,16,48,48][i],"godot3d":{"height":[1.5,1.5,1.5,1.0,1.45,1.0,1.0][i]}})
	plan.instances.append({"id":"training-house","prefabId":"building.residence-two-storey","x":2800,"y":1100,"rotation":0,"scale":1,"godot3d":{"height":2.8,"roof":true}})
	plan.instances.append({"id":"trench","prefabId":"defense.u-position","x":1180,"y":1070,"rotation":0,"scale":.75,"godot3d":{"height":.9}})
	for i in range(4):
		plan.looseSegments.append({"id":"traversal-"+str(i),"componentId":"wall.concrete" if i>=2 else "wall.brick","x1":1600,"y1":1660+i*280,"x2":1760,"y2":1660+i*280,"thickness":20,"godot3d":{"height":[.65,1.15,1.85,2.5][i]}})
	var index=0
	for id in data.vehicles:
		# Matched blue/red rows, with room to walk between the larger hulls.
		for team in ["blue","red"]:
			plan.vehicles.append({"id":"park-"+team+"-"+id,"type":id,"team":team,"x":560 if team=="blue" else 880,"y":1200+index*232,"angle":-PI*.5})
		index+=1
	index=0
	for id in data.emplacements:
		for team in ["blue","red"]:
			plan.emplacements.append({"id":"park-"+team+"-"+id,"type":id,"team":team,"x":2680 if team=="blue" else 2920,"y":1740+index*240,"angle":-PI*.5})
		index+=1
	preload("res://scripts/terrain_biomes.gd").training(plan)
	preload("res://scripts/nature_library.gd").training(plan)
	return plan
