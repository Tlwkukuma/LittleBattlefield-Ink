extends RefCounted
## A legible courtyard objective; imported guns, sandbags and buildings stay intact.
const FLAG=Vector2(2640,1040)
const ZONE=[[2390,900],[2440,850],[2750,850],[2790,890],[2790,1160],[2750,1210],[2440,1210],[2390,1160]]
const FLOORS={"farmhouse-a-floor":"orchard-house-a","farmhouse-b-floor":"orchard-house-b","farmhouse-c-floor":"orchard-house-c","barn-floor":"orchard-barn"}

static func apply(plan: Dictionary,catalog):
	var point: Dictionary=plan.controlPoints[0]
	point.merge({"x":FLAG.x,"y":FLAG.y,"r":260,"shortLabel":"B","label":"果园指挥所","capturePolygon":ZONE.duplicate(true),"captureHeight":1.8},true)
	for feature in plan.world.groundFeatures:
		if not FLOORS.has(feature.id):continue
		for instance in plan.instances:
			if instance.id!=FLOORS[feature.id]:continue
			feature.points=[]
			for p in catalog.prefabs[instance.prefabId].footprint:feature.points.append([p[0]+instance.x,p[1]+instance.y])
	var apron=[]
	for i in range(12):
		var p=FLAG+Vector2.from_angle(i*TAU/12)*47;apron.append([p.x,p.y])
	plan.world.groundFeatures.append({"id":"orchard-flag-apron","kind":"yard","points":apron,"mapKitVisual":{"fill":"#aaa48a","alpha":.62}})
	# Staggered flanking cover leaves the west entry and centre approach open.
	for spec in [{"id":"west","a":[2405,1165],"b":[2460,1165],"h":.85},{"id":"east","a":[2710,885],"b":[2765,885],"h":1.0}]:
		plan.looseSegments.append({"id":"orchard-objective-crate-"+spec.id,"componentId":"prop.crate","x1":spec.a[0],"y1":spec.a[1],"x2":spec.b[0],"y2":spec.b[1],"thickness":40,"godot3d":{"height":spec.h}})
