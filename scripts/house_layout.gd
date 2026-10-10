extends RefCounted
## Shared physical and visual wall layout. Both doorways are 1.6 metres clear.
static func walls(item: Dictionary) -> Array:
	var w = float(item.size[0])
	var d = float(item.size[1])
	var half_side = (w-1.6)*0.5
	var result: Array = []
	for z in [-d*0.5,d*0.5]:
		for side in [-1,1]:
			result.append({"at":Vector2(side*(0.8+half_side*0.5),z),"size":Vector2(half_side,0.22)})
	for x in [-w*0.5,w*0.5]:
		result.append({"at":Vector2(x,0),"size":Vector2(0.22,d)})
	# A partition with a generous central opening, so AI can cross the building.
	for side in [-1,1]:
		result.append({"at":Vector2(side*(0.9+(w*0.5-0.9)*0.5),0),"size":Vector2(w*0.5-0.9,0.16)})
	return result

static func furniture(item: Dictionary) -> Array:
	var w = float(item.size[0])
	var d = float(item.size[1])
	return [{"kind":"bed","at":Vector2(-w*0.5+0.85,-d*0.5+1.0),"size":Vector2(1.05,1.65)},
		{"kind":"desk","at":Vector2(w*0.5-0.8,d*0.5-0.85),"size":Vector2(1.15,0.7)}]
