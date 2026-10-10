extends SceneTree
const Progress=preload("res://scripts/campaign_member_progress.gd")
const Attack=preload("res://scripts/campaign_attack.gd")
const Claims=preload("res://scripts/campaign_goal_reservations.gd")
const Support=preload("res://scripts/campaign_support_wait.gd")
const Perception=preload("res://scripts/campaign_perception.gd")
var checks=0
var failures=0
class ClockWorld extends RefCounted:
	var time=0.0
class RayWorld extends RefCounted:
	const CombatPose=preload("res://scripts/combat_pose.gd")
	var calls=0
	var blocked_call=0
	func trace_3d(_origin: Vector3,_direction: Vector3,_distance: float,_query: Dictionary={},_walls_only: bool=false) -> Dictionary:
		calls+=1
		return {"type":"terrain"} if calls==blocked_call else {}
func check(value: bool,label: String):
	checks+=1
	if not value:failures+=1;push_error(label)
func soldier(id: int) -> Dictionary:
	return {"id":id,"position":Vector2.ZERO,"path":[Vector2(10,0)],"spawn_epoch":0,"alive":true,"mounted":-1,"player":false,"elevation":0.0,"ai_order":{"task":"attack","revision":1},"ai_task":"attack"}
func _initialize():
	var u=soldier(0);var p=Progress.sample(u,{},Vector2(20,0),0)
	for i in range(1,25):
		u.position=Vector2(.15 if i%2 else -.15,1 if i%2 else -1)
		u.path=[Vector2(10,float(i%2))]
		p=Progress.sample(u,p,Vector2(20,0),float(i))
	check(p.at==0.0,"sideways motion and replanned jitter never reset forward clock")
	u.position=Vector2(1,0);p=Progress.sample(u,p,Vector2(20,0),25)
	check(p.at==25.0,"real forward progress updates its own clock")
	u.position=Vector2.ZERO;p=Progress.sample(u,p,Vector2(20,0),26)
	u.position=Vector2(1,0);p=Progress.sample(u,p,Vector2(20,0),27)
	check(p.at==25.0,"back and forth cannot repeatedly earn same progress")
	u.spawn_epoch=1;p=Progress.sample(u,p,Vector2(20,0),28)
	check(p.at==28.0 and p.epoch==1,"new life initializes independent progress")
	u.ai_order.revision=2;p=Progress.sample(u,p,Vector2(20,0),29)
	check(p.at==29.0,"actual new mission initializes its clock")
	var q={};var point={"position":Vector2(20,0),"radius":2.0,"elevation":0.0};var a=soldier(0);var b=soldier(1)
	Attack.checkpoint(q,[a,b],point,0)
	for i in range(1,12):
		a.position=Vector2(float(i)*.7,0)
		Attack.checkpoint(q,[a,b],point,float(i))
	check(q.attack_stalled_ids==[1],"one moving member cannot hide another member stalled for ten seconds")
	check(not Attack.checkpoint(q,[a,b],point,12),"failed member retry is bounded by individual cooldown")
	check(Attack.checkpoint(q,[a,b],point,17),"still stalled member becomes retryable after cooldown")
	var claims=Claims.new();var units=[soldier(0),soldier(1)]
	claims.reserve(units[0],Vector2(3,0),"attack:1",0)
	check(not claims.available(Vector2(3,.9),1),"capture endpoints maintain sparse physical spacing")
	check(claims.available(Vector2(3,1.1),1),"separate legal capture slot remains available")
	units[0].alive=false;claims.prune(units,1)
	check(claims.claims.is_empty(),"death releases endpoint")
	units[0].alive=true;claims.reserve(units[0],Vector2(3,0),"attack:1",0);units[0].spawn_epoch=1;claims.prune(units,1)
	check(claims.claims.is_empty(),"reused unit slot cannot retain old life reservation")
	claims.reserve(units[0],Vector2(3,0),"attack:1",0);units[0].ai_order.revision=2;claims.prune(units,1)
	check(claims.claims.is_empty(),"mission revision releases endpoint")
	claims.reserve(units[0],Vector2(3,0),"attack:2",0);claims.prune(units,3)
	check(claims.claims.is_empty(),"expired endpoint is actually removed")
	units[0].position=Vector2(3,0);claims.reserve(units[0],Vector2(3,0),"attack:2",0);units[0].position=Vector2(6,0);claims.prune(units,1)
	check(claims.claims.is_empty(),"leaving arrived endpoint releases reservation")
	units[0].position=Vector2.ZERO;units[0].ai_order.revision=2
	for second in range(9):
		claims.prune(units,float(second));claims.reserve(units[0],Vector2(20,0),"attack:2",float(second))
	check(claims.claims.has(0) and not claims.available(Vector2(20,0),1),"low-frequency renewal retains a long-route endpoint beyond three seconds")
	units[0].ai_order.revision=3;claims.prune(units,9)
	check(not claims.claims.has(0),"changed mission cannot keep renewing a stale destination")
	claims.reserve(units[0],Vector2(20,0),"attack:3",13)
	for second in range(14,34):
		units[0].ai_last_progress_at=float(second);claims.prune(units,float(second));claims.reserve(units[0],Vector2(20,0),"attack:3",float(second))
	check(claims.claims.has(0),"real independent path progress permits long-distance lease renewal")
	units[0].position=Vector2(20,0);claims.prune(units,33.1);claims.reserve(units[0],Vector2(20,0),"attack:3",33.1)
	units[0].position=Vector2(21.2,0);claims.prune(units,33.2);claims.reserve(units[0],Vector2(20,0),"attack:3",33.2)
	units[0].position=Vector2(23,0);claims.prune(units,33.3)
	check(not claims.claims.has(0),"renewal preserves arrival so gradual departure still releases endpoint")
	var v=soldier(0);v.ai_task="support";v.ammo=30;v.reload=0;v.ai_fire_clear=true;v.ai_support_ray_clear=true
	var seen={"id":9,"source":"vision","observed_at":2.5,"confidence":1.0}
	check(not Support.resume(v,seen,true,0),"first unsupported wait starts finite window")
	check(not Support.resume(v,seen,true,2.9),"wait permits initial reaction and aiming")
	check(Support.resume(v,seen,true,3.01),"clear ray without actual shot cannot hold indefinitely")
	check(Support.resume(v,seen,false,4),"finite resume survives temporary target disappearance")
	v.ai_last_shot_at=7;v.ai_last_shot_target=9;v.ai_last_shot_epoch=0;v.ai_last_shot_target_epoch=0;seen.observed_at=7
	check(Support.effective(v,seen,7),"fresh actual relevant shot with checked lane supports waiting")
	v.ai_fire_clear=false
	check(not Support.effective(v,seen,7),"blocked ray invalidates old active shot support")
	v.ai_fire_clear=true;seen.source="hearing"
	check(not Support.effective(v,seen,7),"sound cannot be support firing evidence")
	seen.source="vision";v.spawn_epoch=1
	check(not Support.effective(v,seen,7),"old-life shot cannot support new soldier")
	var world=ClockWorld.new();var sense=Perception.new();sense.configure(world);var listener=soldier(0)
	Perception.ensure(listener)
	listener.ai_contacts[9]={"id":9,"source":"vision","observed_at":0.0,"position":Vector2(5,0),"confidence":1.0,"initial_confidence":1.0}
	listener.ai_hearing_contacts[9]={"source":"hearing","observed_at":4.0,"position":Vector2(8,3),"confidence":.45,"initial_confidence":.45,"uncertainty":3.0}
	world.time=4.0;sense.tick(listener,0)
	check(listener.ai_contacts[9].observed_at==0.0,"sound does not refresh visual observation timestamp")
	check(sense.best_contact(listener).source=="vision","four-second visual survives a fresh same-source sound")
	world.time=6.01;sense.tick(listener,0)
	check(listener.ai_contacts.is_empty(),"vision expires at six seconds")
	check(sense.best_contact(listener).source=="hearing" and sense.best_contact(listener).position==Vector2(8,3),"expired vision leaves only uncertain sound estimate")
	world.time=7;sense.tick(listener,0)
	check(sense.best_contact(listener).is_empty(),"sound independently expires without resurrecting vision")
	var ray_world=RayWorld.new();var gunner=soldier(0);gunner.stance=0;gunner.facing=Vector2.RIGHT
	var target={"source":"vision","position":Vector2(5,0),"elevation":0.0,"stance":0}
	var Cover=preload("res://scripts/campaign_cover.gd")
	check(Cover.muzzle_clear(ray_world,gunner,target,{}) and gunner.ai_support_ray_clear,"actual unobstructed body and target rays enable support")
	check(ray_world.calls==2,"support evidence reuses exactly existing two firing rays")
	ray_world.calls=0;ray_world.blocked_call=1
	check(not Cover.muzzle_clear(ray_world,gunner,target,{}) and not gunner.ai_support_ray_clear,"barrel inside obstruction cannot support")
	check(ray_world.calls==1,"blocked barrel early-out adds no ray")
	ray_world.calls=0;ray_world.blocked_call=2
	check(not Cover.muzzle_clear(ray_world,gunner,target,{}) and not gunner.ai_support_ray_clear,"target lane obstruction invalidates support evidence")
	check(ray_world.calls==2,"blocked target still preserves firing query count")
	var director=FileAccess.get_file_as_string("res://scripts/campaign_director.gd")
	var bound={"phase":"bound","cover_id":0,"goals":{1:Vector2(4,0)}}
	var Coordinator=preload("res://scripts/campaign_director.gd")
	check(Coordinator.protected_commitment(0,bound),"unrelated laggard retry preserves committed cover")
	check(Coordinator.protected_commitment(1,bound),"unrelated laggard retry preserves committed mover")
	check(not Coordinator.protected_commitment(2,bound),"uncommitted laggard remains eligible for own recovery")
	bound.phase="recover"
	check(not Coordinator.protected_commitment(0,bound),"failed finite commitment no longer blocks recovery")
	check(director.contains('state.maneuver=="bounding" and not entry:'),"laggard stall no longer disables squad bounding, entry priority remains")
	check(director.contains('unit.id not in group.get("attack_stalled_ids",[])'),"live replan filters independent stalled members")
	print("AI_RESTORED_CONTINUITY checks=%d failures=%d; scalar state only, no simulation"%[checks,failures])
	quit(0 if failures==0 else 1)
