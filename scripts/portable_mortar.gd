extends RefCounted
const KIND="portableMortar"
const LIMIT=16
const Emplacement=preload("res://scripts/emplacement_profile.gd")

static func deploy(world,u: Dictionary,w: Dictionary) -> bool:
	if int(u.get("deployed_mortar",-1))>=0:return false
	if not u.alive or not u.grounded or u.mounted>=0 or u.stance==2 or not u.vault.is_empty() or not u.ladder.is_empty():return false
	var count=0
	for vehicle in world.vehicles:
		if vehicle.type==KIND:count+=1
	if count>=LIMIT:return reject(world,u,"已达到迫击炮部署上限")
	var angle: float=u.facing.angle()
	var at: Vector2=u.position+u.facing*.85
	var height: float=world.ground_height(at,.20,float(u.elevation)+.20)
	var proposed={"type":KIND,"position":at,"turret_angle":angle}
	var operator=Emplacement.operator_position(proposed)
	var operator_height: float=world.ground_height(operator,.30,height+.20)
	if absf(height-float(u.elevation))>.20 or absf(operator_height-height)>.15:return reject(world,u,"此处地面不平，无法部署迫击炮")
	for offset in [Vector2.ZERO,Vector2(.25,0),Vector2(-.25,0),Vector2(0,-.40)]:
		var point=at+offset.rotated(angle+PI*.5)
		var floor_y: float=world.ground_height(point,.05,height+.15)
		if absf(floor_y-height)>.10 or "water" in world.terrain.material_at(point) or world.blocked(point,.14,1.05,-1,height+.035):return reject(world,u,"此处空间不足，无法部署迫击炮")
	if world.blocked(operator,.31,world.stance_height(1),-1,operator_height):return reject(world,u,"操作位被挡住，无法部署迫击炮")
	var start=Vector3(u.position.x,u.elevation+.60,u.position.y);var end=Vector3(at.x,height+.60,at.y);var line=end-start
	if not world.trace_3d(start,line.normalized(),line.length(),{},true).is_empty():return reject(world,u,"无法隔着障碍部署迫击炮")
	# The operator must be able to reach the crouched seat along a body-width path.
	for i in range(1,6):
		var t=float(i)/5;var next: Vector2=u.position.lerp(operator,t)
		if world.blocked(next,.28,world.stance_height(1),-1,lerpf(u.elevation,operator_height,t)):return reject(world,u,"无法到达迫击炮操作位")
	var profile=w.duplicate(true)
	profile.merge({"label":"便携迫击炮","health":280.0,"radius":22,"traverse":1.55,"turnRate":1.5,"visionRange":1420,"visionHalfAngle":.75},true)
	world.FireControl.bind_mounted_weapon(profile,"portableMortar/primary")
	var point: Vector2=world.catalog.original_point(at,world.plan)
	var v: Dictionary=world.add_vehicle({"id":"deployed_mortar_"+str(u.id),"type":KIND,"emplacement":true,"profile_override":profile,"x":point.x,"y":point.y,"angle":angle,"team":u.team})
	if v.is_empty():return false
	v.elevation=height;v.spawn_elevation=height;v.deployed=true;v.owner_id=u.id
	v.states.primary.ammo=u.ammo;v.states.primary.reserve=u.reserve;v.states.primary.cooldown=maxf(0,float(u.cooldown))
	u.deployed_mortar=v.id;u.ammo=0;u.reserve=0;u.reload=0.0;u.holstered=true;u.flash=0.0
	world.FireControl.cancel(u,true)
	u.inventory.erase(w.id);u.quick_owned.erase(w.id)
	if u.has("loadout"):u.loadout.erase(w.id)
	if u.quick_tactical==w.id:u.quick_tactical=""
	for candidate in u.quick_owned:
		if world.Equipment.tactical(world.catalog.weapons[candidate]):u.quick_tactical=candidate;break
	world.event.emit({"type":"mortar_deployed","vehicle":v,"unit":u})
	if not u.player:world.mount_unit(u,int(v.id))
	return true

static func reject(world,u: Dictionary,text: String) -> bool:
	if u.player:world.event.emit({"type":"notice","text":text})
	return false

static func operator_height(world,v: Dictionary,at: Vector2) -> float:
	return world.ground_height(at,.30,float(v.elevation)+.20) if v.type==KIND else world.terrain.height(at)
