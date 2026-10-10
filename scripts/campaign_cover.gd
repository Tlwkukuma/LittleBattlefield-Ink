extends RefCounted
const Penetration=preload("res://scripts/cover_penetration.gd")

static func line(world,origin: Vector3,target: Vector3,weapon: Dictionary) -> Dictionary:
	var direction=target-origin
	if direction.length_squared()<.0001:return {}
	return world.trace_3d(origin,direction.normalized(),direction.length(),{"weapon":weapon},true)

static func stopped(world,origin: Vector3,target: Vector3,budget: float=75.0) -> bool:
	var estimate={"cover_ammo":{"lane":"kinetic","penetration":budget}}
	var hit=line(world,origin,target,estimate)
	if hit.is_empty():return false
	return not bool(Penetration.response(estimate,hit,(target-origin).normalized(),budget).get("pass",false))

static func muzzle_clear(world,u: Dictionary,contact: Dictionary,weapon: Dictionary,stance: int=-1,point: Vector2=Vector2.INF) -> bool:
	if contact.is_empty():return false
	var at: Vector2=u.position if not point.is_finite() else point
	var elevation=float(u.elevation) if not point.is_finite() else world.terrain.height(at)
	var posture=int(u.stance) if stance<0 else stance
	var direction: Vector2=(Vector2(contact.position)-at).normalized()
	var reach=1.53 if posture==2 else .95
	var muzzle=world.CombatPose.muzzle(u) if stance<0 and not point.is_finite() else Vector3(at.x+direction.x*reach,elevation+world.CombatPose.MUZZLE_HEIGHT[posture],at.y+direction.y*reach)
	var body=Vector3(at.x,elevation+world.CombatPose.MUZZLE_HEIGHT[posture],at.y)
	# A socket on the other side of a wall is never an eligible support position.
	if not line(world,body,muzzle,weapon).is_empty():return false
	var target=Vector3(contact.position.x,float(contact.get("elevation",0))+[.96,.68,.30][clampi(int(contact.get("stance",0)),0,2)],contact.position.y)
	var hit=line(world,muzzle,target,weapon)
	if hit.is_empty():return true
	return bool(Penetration.response(weapon,hit,(target-muzzle).normalized(),float(weapon.get("cover_ammo",{}).get("penetration",0))).get("pass",false))

static func pose(world,u: Dictionary,contact: Dictionary,weapon: Dictionary,shelter: bool,support: bool) -> int:
	var at: Vector2=u.position;var elevation=float(u.elevation)
	var threat=Vector3(contact.position.x,float(contact.get("elevation",0))+float(contact.get("muzzle_height",1.33)),contact.position.y)
	var budget=float(contact.get("penetration_estimate",75))
	var best=int(u.stance);var score=-INF
	var started=Time.get_ticks_usec();var limit=mini(450,int(world.ai_budget_usec))
	var choices=[int(u.stance)]
	for candidate in [0,1,2]:
		if candidate not in choices:choices.append(candidate)
	for stance in choices:
		if Time.get_ticks_usec()-started>=limit:break
		if world.blocked(at,.31,world.stance_height(stance),-1,elevation):continue
		if stance==2 and world.terrain.grade(at)>.45:continue
		var head=world.CombatPose.candidate_head(at,elevation,stance)
		var protected=stopped(world,threat,head,budget)
		var fires=muzzle_clear(world,u,contact,weapon,stance)
		var value=(3.2 if protected else 0.0)+(1.2 if fires and support else 0.0)-float(stance)*(.25 if shelter else .75)
		if support and not shelter and not fires:continue
		if stance==2 and not protected:
			value+=1.05 if shelter else 1.8 if world.Handling.profile(weapon).get("bipod",false) and Vector2(u.velocity).length_squared()<.02 else 0.0
		if stance==int(u.stance):value+=.2
		if value>score:score=value;best=stance
	return best

static func friendly_masked(world,u: Dictionary,target: Vector2) -> bool:
	var forward=(target-Vector2(u.position)).normalized();var distance=minf(8,Vector2(u.position).distance_to(target))
	var suppressive=preload("res://scripts/campaign_suppression.gd").machinegun(world.weapon_for(u))
	var muzzle=world.CombatPose.muzzle(u);var target_height=float(u.get("aim_height",muzzle.y))
	if target_height<0:target_height=muzzle.y
	for friend in world.nearby_units(u.position,distance):
		if not friend.alive or friend.id==u.id or friend.team!=u.team or absf(float(friend.elevation)-float(u.elevation))>1.5:continue
		var delta: Vector2=friend.position-u.position;var along=delta.dot(forward)
		var width=.5+(along*tan(preload("res://scripts/campaign_suppression.gd").YAW_CONE) if suppressive else 0.0)
		if along>.3 and along<distance and absf(delta.cross(forward))<width:
			var height=lerpf(muzzle.y,target_height,clampf(along/maxf(.1,Vector2(u.position).distance_to(target)),0,1))
			if height>=float(friend.elevation) and height<float(friend.elevation)+world.stance_height(friend.stance):return true
	return false
