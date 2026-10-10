extends RefCounted
## Authored plans operate on the current 3D geometry, never original pixel targets.
const NAMES={"T01":"西门推进 · 双翼支援","T02":"东墙破障 · 主路牵制","T03":"壕沟接近 · 林翼迂回"}
var world_ref: WeakRef
var tactic_id="T01"
var site: Dictionary={}
var breach_id=""
var next_throw_at=0.0
var last_topology=-1
var breach_verified=false
var follow_id=""

func configure(world):
	world_ref=weakref(world);tactic_id=str(world.plan.godot3d.get("campaign_tactic","T01"))
	if not NAMES.has(tactic_id):tactic_id="T01"
	find_breach_site()

func generic_chapter() -> bool:
	return bool(world_ref.get_ref().plan.godot3d.get("source_layout",false)) or int(world_ref.get_ref().plan.godot3d.get("campaign_chapter",1))>1

static func mandatory_approach(plan: Dictionary) -> bool:
	var settings: Dictionary=plan.get("godot3d",{})
	return (not bool(settings.get("source_layout",false)) and int(settings.get("campaign_chapter",1))<=1) or bool(settings.get("campaign_tactics",{}).get("mandatory_approach",false))

static func names_for(plan: Dictionary) -> Dictionary:
	return plan.get("godot3d",{}).get("campaign_tactic_names",NAMES)

func support_post(lane: String) -> Vector2:
	var world=world_ref.get_ref()
	if generic_chapter():
		var posts: Dictionary=world.plan.godot3d.get("campaign_tactics",{}).get("support_posts",{})
		if posts.has(lane):return world.catalog.position(posts[lane],world.plan)
		return world.campaign.points[0].position
	return world.catalog.position([2090,990] if lane=="left" else [2100,1210],world.plan)

func find_breach_site():
	var world=world_ref.get_ref();site={}
	var settings: Dictionary=world.plan.godot3d.get("campaign_tactics",{})
	var source_id=str(settings.get("breach_source_id","")) if generic_chapter() else "compound-right"
	if source_id.is_empty():return
	for wall in world.objects:
		if wall.get("source_id","")!=source_id or not wall.destructible:continue
		var outward=Vector2.from_angle(wall.angle).orthogonal()
		if outward.dot(wall.position-world.campaign.points[0].position)<0:outward=-outward
		for fraction in [-.15,.0,.15,.3,-.3]:
			var at: Vector2=wall.position+Vector2.from_angle(wall.angle)*(float(wall.size.x)*fraction)
			var outside=at+outward*(float(wall.size.y)*.5+1.25);var inside=at-outward*(float(wall.size.y)*.5+1.0)
			var stage=at+outward*(float(wall.size.y)*.5+2.2)+Vector2.from_angle(wall.angle)*4.3
			if world.blocked(outside,.31,1.95,-1,world.terrain.height(outside)) or world.blocked(inside,.31,1.95,-1,world.terrain.height(inside)):continue
			if world.blocked(stage,.31,1.95,-1,world.terrain.height(stage)):continue
			if not world.campaign_ai.same_component(stage,inside):continue
			site={"wall":wall,"target":at,"outside":outside,"inside":inside,"stage":stage,"normal":outward,"open":false}
			return

func select(id: String) -> bool:
	if not NAMES.has(id):return false
	var world=world_ref.get_ref();tactic_id=id;world.plan.godot3d.campaign_tactic=id
	breach_id="";follow_id="";breach_verified=false;next_throw_at=0.0
	for q in world.campaign_director.teams[0].squads.values():
		for key in ["plan_lane","plan_exploit","plan_started","plan_deployed_at","plan_follow_at","plan_breach_at","bound_state"]:q.erase(key)
		q.task="";q.issued_at=-100.0
	world.campaign_director.ensure_squads(0);world.campaign_director.assign_orders(0)
	return true

func assign_lane(q: Dictionary) -> String:
	if q.has("plan_lane"):return str(q.plan_lane)
	var world=world_ref.get_ref();var lanes={"main":0,"left":0,"right":0,"breach":0}
	for other in world.campaign_director.teams[0].squads.values():
		var lane=str(other.get("plan_lane",""))
		if lanes.has(lane):lanes[lane]+=1
	var lane="main"
	if tactic_id=="T02":
		if not site.is_empty() and lanes.main>=2 and lanes.breach==0 and has_grenades(q):lane="breach";breach_id=q.id
	else:
		var total=lanes.main+lanes.left+lanes.right
		if total>0 and float(lanes.main)/total>=.5:lane="left" if lanes.left<=lanes.right else "right"
	q.plan_lane=lane;q.plan_started=world.time
	return lane

func route(q: Dictionary) -> int:
	var lane=assign_lane(q)
	if tactic_id=="T03" and lane=="main":return 1
	if lane=="left":return 1
	if lane=="right":return 2
	return 0

func task(q: Dictionary) -> String:
	var world=world_ref.get_ref();var lane=assign_lane(q)
	if generic_chapter() and not world.campaign.points.is_empty() and world.campaign.points[0].owner==0:
		return "hold:0" if lane=="main" else "support:0"
	if breach_verified and follow_id.is_empty():
		var best: Dictionary={};var distance=INF
		for candidate in world.campaign_director.teams[0].squads.values():
			if candidate.id==breach_id or candidate.get("plan_lane","")!="main" or candidate.get("plan_exploit",false):continue
			var d: float=world.campaign_director.center(candidate).distance_squared_to(site.outside)
			if d<distance:distance=d;best=candidate
		if not best.is_empty():follow_id=best.id;best.plan_lane="breach-follow"
		lane=str(q.plan_lane)
	if q.get("plan_exploit",false) or lane=="main":return "attack:0"
	if lane=="breach-follow":
		if world.time-float(q.get("plan_follow_at",world.time))>12:q.plan_exploit=true;return "attack:0"
		if not q.has("plan_follow_at"):q.plan_follow_at=world.time
		return "control:0"
	if lane=="breach":
		refresh_breach()
		for id in q.members:
			if not site.is_empty() and world.units[id].position.distance_to(site.stage)<1.4 and not q.has("plan_breach_at"):q.plan_breach_at=world.time
		var expired=(q.has("plan_breach_at") and world.time-float(q.plan_breach_at)>24) or world.time-float(q.plan_started)>65
		if site.is_empty() or expired or (not site.open and not has_grenades(q) and world.time>=next_throw_at):q.plan_exploit=true;return "attack:0"
		return "control:0"
	# A flank is useful only while it supports a related frontage. Finite timeout
	# prevents missing reports or wall-blocked posts from holding troops forever.
	var post=support_post(lane)
	for id in q.members:
		if world.units[id].position.distance_to(post)<3 and not q.has("plan_deployed_at"):q.plan_deployed_at=world.time
	if (q.has("plan_deployed_at") and world.time-float(q.plan_deployed_at)>8) or world.time-float(q.plan_started)>32:q.plan_exploit=true;return "attack:0"
	for id in q.members:
		var u: Dictionary=world.units[id]
		if world.time-float(u.get("ai_effect_at",-100))<1.3 and u.position.distance_to(world.campaign.points[0].position)<15:
			q.plan_exploit=true;return "attack:0"
	return "support:0"

func goal(q: Dictionary,default_goal: Vector2) -> Vector2:
	var world=world_ref.get_ref();var lane=assign_lane(q)
	if q.get("plan_exploit",false) or lane=="main":return default_goal
	if lane in ["breach","breach-follow"] and not site.is_empty():return site.outside if lane=="breach-follow" else site.stage
	return support_post(lane)

func has_grenades(q: Dictionary) -> bool:
	var world=world_ref.get_ref()
	for id in q.members:
		var u: Dictionary=world.units[id]
		if not grenade_id(u).is_empty():return true
	return false

func grenade_id(u: Dictionary) -> String:
	var world=world_ref.get_ref()
	for id in u.get("loadout",[]):
		var w: Dictionary=world.catalog.weapons[id]
		if w.kind!="grenade" or float(w.get("blastDamage",w.get("damage",0)))<=0 or bool(w.get("smoke",false)):continue
		# Existing inventory is lazy: an unselected owned weapon still has its
		# authored first magazine, exactly as equipment and switching code do.
		var state: Dictionary=u if id==u.weapon_id else u.inventory.get(id,{"ammo":int(w.mag),"reserve":int(w.reserve)})
		if int(state.get("ammo",0))+int(state.get("reserve",0))>0:return str(id)
	return ""

func update_breach(q: Dictionary) -> Dictionary:
	var world=world_ref.get_ref()
	if tactic_id!="T02" or str(q.get("plan_lane","")) not in ["breach","breach-follow"] or site.is_empty() or q.get("plan_exploit",false):return {}
	refresh_breach()
	if site.open:
		for id in q.members:
			var u: Dictionary=world.units[id]
			if u.position.distance_to(site.inside)<1.0 and u.grounded:
				q.plan_exploit=true;breach_verified=true
				world.event.emit({"type":"ai_breach_entered","squad_id":q.id,"at":world.time});return {}
		return {"open":true,"goal":site.inside}
	if q.get("plan_lane","")=="breach-follow":return {"open":false,"thrower":-1,"stage":site.outside}
	var best=-1;var distance=INF
	for id in q.members:
		var u: Dictionary=world.units[id]
		if grenade_id(u).is_empty() or float(u.get("ai_stress",0))>.62:continue
		var d: float=u.position.distance_squared_to(site.stage)
		if d<distance:distance=d;best=id
	return {"open":false,"thrower":best,"target":site.target,"stage":site.stage,"next_throw_at":next_throw_at}

func refresh_breach():
	var world=world_ref.get_ref()
	if not site.is_empty() and world.topology_revision!=last_topology:
		last_topology=world.topology_revision
		site.open=world.campaign_ai.traversable(world,site.outside,site.inside)

func prepare_throw(u: Dictionary) -> void:
	var world=world_ref.get_ref();u.ai_breach_ready=false
	if world.ai_budget_usec<=0 or world.time<next_throw_at or site.is_empty() or u.position.distance_to(site.stage)>1.4:return
	if u.weapon_id!=grenade_id(u) or u.ammo<=0 or u.reload>0 or u.cooldown>0:return
	if u.stance!=0 or absf(float(u.stance_blend))>.08 or Vector2(u.velocity).length_squared()>.02:return
	var w: Dictionary=world.weapon_for(u);var radius=float(w.get("blastRadius",140))/40.0
	for friend in world.nearby_units(site.target,radius+1.0):
		if friend.alive and friend.team==u.team and friend.position.distance_to(site.target)<radius+1.0:return
	var started=Time.get_ticks_usec()
	var direction=(Vector2(site.target)-Vector2(u.position)).normalized()
	var origin=Vector3(u.position.x+direction.x*.4,u.elevation+1.3,u.position.y+direction.y*.4)
	var target=Vector3(site.target.x,world.terrain.height(site.target)+.25,site.target.y)
	if world.throw_origin_provider.is_valid():origin=world.throw_origin_provider.call(u,w)
	var job: Dictionary=u.get("ai_breach_preview",{})
	if job.is_empty() or Vector3(job.origin).distance_to(origin)>.12 or job.revision!=world.topology_revision or job.weapon!=u.weapon_id:
		var solution=world.grenade_solution(u,w,target,false,origin)
		var duration=minf(3.2,float(solution.flight)+.7)
		job={"origin":origin,"solution":solution,"revision":world.topology_revision,"weapon":u.weapon_id,"duration":duration,"segments":mini(80,maxi(18,ceili(duration/.035))),"next":1,"last":solution.origin}
		u.ai_breach_preview=job
	# Carry the read-only sweep across decisions inside the existing AI budget.
	var count=0;var limit=mini(350,int(world.ai_budget_usec))
	while int(job.next)<=int(job.segments) and count<12 and Time.get_ticks_usec()-started<limit:
		var point=world.Grenade.position_at(job.solution.origin,job.solution.velocity,job.duration*float(job.next)/job.segments)
		var hit=world.Grenade.sweep(world,job.last,point);job.next+=1;count+=1
		if not hit.is_empty():
			if Vector2(hit.point.x,hit.point.z).distance_to(site.target)<radius*.65:
				u.ai_breach_ready=true;u.ai_breach_target=target;u.ai_breach_expires=world.time+.65
			u.erase("ai_breach_preview");break
		job.last=point
	if int(job.next)>int(job.segments):u.erase("ai_breach_preview")
	world.ai_budget_usec-=Time.get_ticks_usec()-started

func observe_event(event: Dictionary):
	if event.get("type","")!="grenade_throw":return
	var u: Dictionary=event.unit
	if not u.get("ai_order",{}).get("breach_thrower",false):return
	next_throw_at=world_ref.get_ref().time+maxf(3.0,world_ref.get_ref().ThrowControl.fuse(event.weapon))+.8
