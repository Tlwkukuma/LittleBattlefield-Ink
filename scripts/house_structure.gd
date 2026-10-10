extends RefCounted
## Slabs connect to surviving walls; upper walls and furnishings require real support.
var revision=-1

static func supported(world,o: Dictionary,point: Vector2,radius: float=.23) -> bool:
	# A wooden handrail or cabinet may hold a soldier, but cannot bear a masonry storey.
	var slab=o.get("house_role","") in ["floor","roof"]
	var role="wall" if slab else "floor"
	var level=int(o.get("storey",0))-(1 if slab else 0)
	var filter=func(candidate):return candidate.owner==o.owner and candidate.get("house_role","")==role and candidate.get("storey",0)==level
	return world.ground_height(point,radius,float(o.elevation)+.004,filter)>=float(o.elevation)-.04

static func break_whole(world,o: Dictionary):
	if not o.destructible:return
	for row in range(o.rows):
		for col in range(o.columns):
			if o.hp[row*o.columns+col]>0:world.damage_cell(o,col,row,o.max_hp+1,o.position,true)

func resolve(world):
	if world.houses.is_empty() or revision==world.topology_revision:return
	var by_id={}
	for o in world.objects:by_id[o.id]=o
	for level in [1,2]:
		var tiles={};var connected={};var queue=[]
		for o in world.objects:
			if not o.alive or o.get("house_role","") not in ["floor","roof"] or o.get("storey",0)!=level:continue
			tiles[o.id]=o
			var anchored=false
			for x in [-.48,0,.48]:
				for z in [-.48,0,.48]:
					var p: Vector2=o.position+Vector2(o.size.x*x,o.size.y*z).rotated(o.angle)
					if supported(world,o,p,.20):anchored=true
			if anchored:connected[o.id]=true;queue.append(o.id)
		var cursor=0
		while cursor<queue.size():
			var id: String=queue[cursor];cursor+=1
			for neighbor in tiles[id].get("floor_neighbors",[]):
				if tiles.has(neighbor) and not connected.has(neighbor):connected[neighbor]=true;queue.append(neighbor)
		for id in tiles:
			if not connected.has(id) and tiles[id].destructible:break_whole(world,tiles[id])
		# Removing slab support also invalidates the bottom seeds of upper wall grids.
		for o in world.objects:
			if o.get("house_role","")=="wall" and o.get("storey",0)==level and o.alive:world.support_dirty[o.id]={"object":o,"origin":o.position}
		world.resolve_support()
	for o in world.objects:
		if not o.alive or not o.get("house",false):continue
		if o.has("support_parent") and by_id.has(o.support_parent) and not by_id[o.support_parent].alive:break_whole(world,o)
		elif o.get("house_role","") in ["furniture","guard"] and o.get("storey",0)>0:
			var stable=false
			for x in [-.38,0,.38]:
				for z in [-.38,0,.38]:
					if supported(world,o,o.position+Vector2(o.size.x*x,o.size.y*z).rotated(o.angle)):stable=true
			if not stable and o.destructible:break_whole(world,o)
	revision=world.topology_revision
