extends RefCounted
## Gameplay contents are independent of corpses and rendering; no per-item nodes.
const Equipment=preload("res://scripts/quick_equipment.gd")
const LIMIT=128
const REACH=2.2
var bags: Array=[]
var sequence=0
var revision=0
var support_cursor=0
var support_clock=0.0

func clear():
	bags.clear();sequence=0;revision+=1;support_cursor=0;support_clock=0.0

func find(id: int) -> Dictionary:
	for bag in bags:
		if bag.id==id:return bag
	return {}

func drop_unit(world,u: Dictionary) -> Dictionary:
	if u.get("loot_dropped",false):return {}
	u.loot_dropped=true
	var items={};var owned: Array=u.get("quick_owned",u.get("loadout",[])).duplicate()
	if u.weapon_id not in owned:owned.append(u.weapon_id)
	for id in owned:
		if id=="portable-mortar" and int(u.get("deployed_mortar",-1))>=0:continue
		if not world.catalog.weapons.has(id):continue
		var w: Dictionary=world.catalog.weapons[id]
		var state: Dictionary=u if id==u.weapon_id else u.inventory.get(id,{"ammo":w.mag,"reserve":w.reserve})
		items["w:"+id]={"kind":"weapon","id":id,"amount":maxi(1,int(u.get("weapon_copies",{}).get(id,1))),"ammo":maxi(0,int(state.ammo)),"reserve":maxi(0,int(state.reserve)),"fire_mode":str(state.get("fire_mode",world.FireControl.default_mode(w)))}
	for id in u.get("medical_stock",{}):
		var count=int(u.medical_stock[id])
		if count>0:items["m:"+id]={"kind":"medical","id":id,"amount":count}
	if items.is_empty():return {}
	# Cap the persistent data and the single visual batch, preferring old distant bags.
	if bags.size()>=LIMIT:
		var remove=0
		for i in range(bags.size()):
			if bags[i].position.distance_to(world.player.position)>REACH*2:remove=i;break
		bags.remove_at(remove)
	sequence+=1
	var spot=placement(world,u)
	var bag={"id":sequence,"position":Vector2(spot.x,spot.z),"elevation":spot.y,"angle":float(sequence)*2.399963,"items":items,"support_revision":world.topology_revision}
	bags.append(bag);revision+=1;return bag

func placement(world,u: Dictionary) -> Vector3:
	var at=Vector2(u.position);var mount=int(u.get("mounted",-1))
	# Beside the body, with no permanent gun/body overlap or placement across a wall.
	for i in range(8):
		var direction=Vector2.from_angle(Vector2(u.facing).angle()-PI*.5+i*TAU/8)
		var candidate=at+direction*.58
		if mount>=0 and mount<world.vehicles.size():candidate=world.VehicleDimensions.exit_point(world.vehicles[mount],direction,.30)
		var height=world.ground_height(candidate,.16,float(u.elevation)+.08)
		if mount<0:
			var origin=Vector3(at.x,u.elevation+.20,at.y);var target=Vector3(candidate.x,u.elevation+.20,candidate.y)
			if not world.trace_3d(origin,(target-origin).normalized(),origin.distance_to(target),{},true).is_empty():continue
		if not world.blocked(candidate,.22,.35,-1,height):return Vector3(candidate.x,height,candidate.y)
	return Vector3(at.x,world.ground_height(at,.12,float(u.elevation)+.06),at.y)

func available(world,u: Dictionary) -> bool:
	return Equipment.available(u) and u.get("grounded",true) and (not world.campaign_active() or world.campaign.phase=="playing")

func in_range(u: Dictionary,bag: Dictionary) -> bool:
	return not bag.is_empty() and Vector2(u.position).distance_squared_to(bag.position)<=REACH*REACH and absf(float(u.elevation)-float(bag.elevation))<.75

func can_access(world,u: Dictionary,bag: Dictionary) -> bool:
	if not available(world,u) or not in_range(u,bag):return false
	var origin=Vector3(u.position.x,u.elevation+.38,u.position.y)
	var target=Vector3(bag.position.x,bag.elevation+.28,bag.position.y);var delta=target-origin
	if delta.length()<.12:return true
	var hit: Dictionary=world.trace_3d(origin,delta.normalized(),delta.length(),{"source":u.id},true)
	return hit.is_empty() or float(hit.get("distance",INF))>=delta.length()-.06

func nearest(world,u: Dictionary) -> Dictionary:
	if not available(world,u):return {}
	var candidates=[]
	for bag in bags:
		if in_range(u,bag):candidates.append(bag)
	candidates.sort_custom(func(a,b):return u.position.distance_squared_to(a.position)<u.position.distance_squared_to(b.position))
	# Only the closest two candidates get an occlusion test (also respects floors).
	for i in range(mini(2,candidates.size())):
		if can_access(world,u,candidates[i]):return candidates[i]
	return {}

func take(world,u: Dictionary,bag_id: int,key: String) -> bool:
	var bag=find(bag_id)
	if not can_access(world,u,bag) or not bag.items.has(key):return false
	transfer(world,u,bag.items[key]);bag.items.erase(key);finish(bag);return true

func take_all(world,u: Dictionary,bag_id: int) -> bool:
	var bag=find(bag_id)
	if not can_access(world,u,bag):return false
	for item in bag.items.values():transfer(world,u,item)
	bag.items.clear();finish(bag);return true

func transfer(world,u: Dictionary,item: Dictionary):
	var id=str(item.id)
	if item.kind=="medical":
		u.medical_stock[id]=int(u.medical_stock.get(id,0))+int(item.amount);return
	var owned=id in u.quick_owned
	if not u.has("weapon_copies"):u.weapon_copies={}
	u.weapon_copies[id]=int(u.weapon_copies.get(id,1 if owned else 0))+int(item.amount)
	if owned:
		if id==u.weapon_id:u.reserve+=int(item.ammo)+int(item.reserve)
		else:
			var w: Dictionary=world.catalog.weapons[id]
			var stored: Dictionary=u.inventory.get(id,{"ammo":int(w.mag),"reserve":int(w.reserve)})
			stored.reserve+=int(item.ammo)+int(item.reserve);u.inventory[id]=stored
	else:
		u.quick_owned.append(id)
		u.inventory[id]={"ammo":int(item.ammo),"reserve":int(item.reserve),"fire_mode":item.fire_mode,"cooldown_until":world.time}
		var w: Dictionary=world.catalog.weapons[id]
		if Equipment.tactical(w):
			if str(u.quick_tactical).is_empty():u.quick_tactical=id
		else:
			var empty=u.quick_slots.find("")
			if empty>=0:u.quick_slots[empty]=id
	# Campaign ownership checks must accept actually looted equipment.
	if u.has("loadout") and id not in u.loadout:u.loadout.append(id)

func finish(bag: Dictionary):
	if bag.items.is_empty():bags.erase(bag)
	revision+=1

func tick(world,delta: float):
	if bags.is_empty():return
	support_clock-=delta
	if support_clock>0:return
	support_clock=.1
	# Sleeping bags only recheck support after real terrain/building destruction.
	for i in range(mini(4,bags.size())):
		support_cursor=posmod(support_cursor,bags.size());var bag: Dictionary=bags[support_cursor];support_cursor+=1
		if bag.support_revision==world.topology_revision:continue
		bag.support_revision=world.topology_revision
		var height=world.ground_height(bag.position,.12,float(bag.elevation)+.06)
		if not is_equal_approx(height,bag.elevation):bag.elevation=height;revision+=1
