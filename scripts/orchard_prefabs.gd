extends RefCounted
## Dedicated templates derived from the immutable authored wall/door coordinates.
const GROUPS={"house-a":"building.orchard-house-a","house-b":"building.orchard-house-b","house-c":"building.orchard-house-c","barn":"building.orchard-barn","compound":"rural.orchard-stone-yard"}

static func register(catalog):
	var scenes=catalog.read("scenes.json").scenes
	var original: Dictionary={}
	for scene in scenes:
		if scene.id=="level-01":original=scene;break
	if original.is_empty():return
	for prefix in GROUPS:
		var segments: Array=original.looseSegments.filter(func(s):return str(s.id).begins_with(prefix+"-"))
		var rect=Rect2(Vector2(segments[0].x1,segments[0].y1),Vector2.ZERO);var ids=[]
		for s in segments:
			rect=rect.expand(Vector2(s.x1,s.y1)).expand(Vector2(s.x2,s.y2));ids.append(s.id)
		var origin=rect.get_center();var half=rect.size*.5;var id: String=GROUPS[prefix]
		var footprint=[[-half.x,-half.y],[half.x,-half.y],[half.x,half.y],[-half.x,half.y]]
		catalog.prefabs[id]={"id":id,"label":"石墙果园 · "+{"house-a":"农舍 A","house-b":"农舍 B","house-c":"农舍 C","barn":"双门谷仓","compound":"石砌围院"}[prefix],"footprint":footprint,"source_origin":[origin.x,origin.y],"source_ids":ids,"godot_height":1.1 if prefix=="compound" else 2.8,"orchard":true}
		var walls=[]
		for s in segments:
			if catalog.components.get(s.componentId,{}).get("role","")=="opening":continue
			var a=Vector2(s.x1,s.y1);var b=Vector2(s.x2,s.y2);var direction=(b-a).normalized();var length=a.distance_to(b);var intervals=[]
			for door in original.looseSegments:
				if catalog.components.get(door.componentId,{}).get("role","")!="opening":continue
				var da=Vector2(door.x1,door.y1);var db=Vector2(door.x2,door.y2)
				if absf((db-da).normalized().dot(direction))<.94:continue
				if absf(((da+db)*.5-a).cross(direction))>float(s.thickness)*.5+float(door.get("thickness",18))*.5+10:continue
				intervals.append(Vector2(clampf(minf((da-a).dot(direction),(db-a).dot(direction))-4,0,length),clampf(maxf((da-a).dot(direction),(db-a).dot(direction))+4,0,length)))
			intervals.sort_custom(func(x,y):return x.x<y.x);intervals.append(Vector2(length,length))
			var cursor=0.0;var index=0
			for interval in intervals:
				if interval.x-cursor>2:
					var span=interval.x-cursor;var center=a+direction*(cursor+span*.5)-origin
					walls.append({"id":str(s.id)+"_"+str(index),"source_id":s.id,"mapKitComponentId":s.componentId,"x":center.x-span*.5,"y":center.y-float(s.thickness)*.5,"w":span,"h":s.thickness,"angle":direction.angle()})
				cursor=maxf(cursor,interval.y);index+=1
		catalog.templates[id]={"walls":walls,"trees":[],"world":{"groundFeatures":[]}}

static func convert_plan(plan: Dictionary,catalog) -> Dictionary:
	var result=plan.duplicate(true);var removed={}
	if not result.has("instances"):result.instances=[]
	for prefix in GROUPS:
		var spec: Dictionary=catalog.prefabs[GROUPS[prefix]];var present={}
		for s in result.get("looseSegments",[]):present[s.id]=true
		if not spec.source_ids.all(func(id):return present.has(id)):continue
		for id in spec.source_ids:removed[id]=true
		result.instances.append({"id":"orchard-"+prefix,"prefabId":spec.id,"x":spec.source_origin[0],"y":spec.source_origin[1],"rotation":0,"scale":1,"godot3d":{"windows":false,"height":spec.godot_height,"roof":prefix!="compound"}})
	result.looseSegments=result.get("looseSegments",[]).filter(func(s):return not removed.has(s.id))
	return result
