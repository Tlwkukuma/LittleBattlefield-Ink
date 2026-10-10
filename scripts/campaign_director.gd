extends RefCounted
## Low-frequency orders; only friendly state, public objectives and reported contacts.
const COMMANDER_PATH="res://scripts/campaign_commander.gd"
const Maneuver=preload("res://scripts/campaign_maneuver.gd")
const Roster=preload("res://scripts/campaign_roster.gd")
const Attack=preload("res://scripts/campaign_attack.gd")
const FORMATIONS={"pairs":2,"fireteams":3,"sections":4,"squads":6}
const TASKS=["hold:0","attack:0","control:0","support:0","reserve"]
var world_ref: WeakRef
var commander
var teams: Array=[]
var assign_clock=0.0
var enabled=false
var next_revision=1
var team_cursor=0
var plan_executor=preload("res://scripts/campaign_plan.gd").new()

func configure(world):
	cancel();commander=null;world_ref=weakref(world)
	teams.clear();assign_clock=0;next_revision=1;team_cursor=0
	enabled=laya_requested(world.plan.get("godot3d",{}),OS.get_cmdline_user_args(),OS.get_environment("LAYA_AI_DISABLED"))
	if enabled:
		commander=load(COMMANDER_PATH).new();commander.configure(world)
	for team in range(2):
		teams.append({"posture":"balanced","maneuver":"bounding","formation":"fireteams","size":3,"approach":"split-routes","next_squad":0,
			"source":"fallback","squads":{},"next_at":1.0+team*.25,"phase":"idle","queue":[],"regrouped_at":-30.0,
			"last_result":-1.0,"accepted":0,"rejected":0,"orders_changed":0,"round":0})
		ensure_squads(team)
	plan_executor.configure(world)
	for group in teams[0].squads.values():group.task="";group.issued_at=-100.0;issue(0,group,plan_executor.task(group),"fallback",0)
	assign_orders()

func objective_changed() -> void:
	var world=world_ref.get_ref()
	plan_executor.configure(world)
	for team in range(2):
		for group in teams[team].squads.values():
			for key in ["plan_lane","plan_exploit","plan_started","plan_deployed_at","plan_follow_at","plan_breach_at","bound_state","attack_progress","attack_progress_at","attack_retry_at","watch_until","watch_wall"]:group.erase(key)
			group.task="";group.issued_at=-100.0
		for unit in world.units:
			if int(unit.team)!=team:continue
			unit.path=[];unit.repath=0.0;unit.ai_route_done=false
			for key in ["ai_route_index","ai_order","ai_tactic","ai_cover_key","ai_cover_search","ai_bound_candidate_at"]:unit.erase(key)
		ensure_squads(team)
	assign_orders()

static func laya_requested(settings: Dictionary,args: PackedStringArray,disabled_env: String) -> bool:
	if disabled_env=="1" or "--no-laya" in args:return false
	return "--laya" in args or bool(settings.get("laya_enabled",false))

func cancel():
	if commander!=null:commander.cancel()

func tick(delta: float):
	var world=world_ref.get_ref()
	if world==null:return
	if world.campaign.phase!="playing":cancel();return
	world.campaign_ai.tick_connectivity()
	if enabled and commander!=null:
		commander.tick(delta)
		for result in commander.drain_results():apply_result(result)
	assign_clock-=delta
	if assign_clock<=0 and world.ai_budget_usec>0:
		var started=Time.get_ticks_usec();assign_clock=.325
		ensure_squads(team_cursor);assign_orders(team_cursor);team_cursor=1-team_cursor
		world.ai_budget_usec-=Time.get_ticks_usec()-started
	if not enabled:return
	for team in range(2):
		var state: Dictionary=teams[team]
		if commander.is_busy(team) or world.time<float(state.next_at):continue
		if state.squads.is_empty():state.phase="idle";state.next_at=world.time+4;continue
		if state.phase=="idle":
			state.phase="policy";state.round+=1
			if not commander.submit(team,briefing(team),policy_questions(),{"phase":"policy","round":state.round}):state.phase="idle";state.next_at=world.time+4
		elif state.phase=="missions":
			if state.queue.is_empty():state.phase="idle";state.next_at=world.time+4;continue
			var squad_id: String=state.queue.pop_front()
			if not state.squads.has(squad_id):continue
			commander.submit(team,briefing(team,squad_id),mission_questions(),{"phase":"mission","squad_id":squad_id,"round":state.round})

func ensure_squads(team: int):
	var world=world_ref.get_ref();var state: Dictionary=teams[team]
	var groups: Dictionary=state.squads
	Roster.reconcile(state,world.units,team,world.time,world.campaign_ai.vehicle_ai.reservations,func(a,b):return world.campaign_ai.same_component(a,b) and world.campaign_ai.traversable(world,a,b))
	for group in groups.values():
		if group.task.is_empty():
			var routes: Array=world.campaign_ai.routes[team];var distance=INF
			if int(group.cohort)<0:
				for index in range(routes.size()):
					if routes[index].is_empty():continue
					var d: float=center(group).distance_squared_to(routes[index][0])
					if d<distance:distance=d;group.route=index
			issue(team,group,fallback_task(team,group),"fallback",0)
	merge_remnants(team)

func merge_remnants(team: int):
	var world=world_ref.get_ref();var groups: Dictionary=teams[team].squads
	for q in groups.values():
		if q.members.size()>=int(teams[team].size) or world.time-float(q.formed_at)<1.5 or q.get("bound_state",{}).get("phase","idle") not in ["idle","recover"]:continue
		for donor in groups.values():
			if donor.id==q.id or q.members.size()+donor.members.size()>int(teams[team].size) or world.time-float(donor.formed_at)<1.5:continue
			if donor.task!=q.task or donor.route!=q.route or donor.get("plan_lane","")!=q.get("plan_lane",""):continue
			if donor.get("bound_state",{}).get("phase","idle") not in ["idle","recover"]:continue
			var here=center(q);var there=center(donor)
			if here.distance_squared_to(there)>4.5*4.5 or not world.campaign_ai.same_component(here,there):continue
			if not world.campaign_ai.traversable(world,here,there):continue
			for id in donor.members:q.members.append(id);q.epochs[id]=donor.epochs[id];world.units[id].squad_id=q.id
			groups.erase(donor.id);return

func center(group: Dictionary) -> Vector2:
	return Roster.anchor(group,world_ref.get_ref().units)

func friendly_count(team: int,point: Vector2,radius: float) -> int:
	var world=world_ref.get_ref();var count=0
	for unit in world.units:
		if unit.alive and unit.team==team and unit.position.distance_squared_to(point)<radius*radius:count+=1
	return count

func contacts(team: int) -> Array:
	var world=world_ref.get_ref();var known={}
	# Aggregate exact observed vision first; independent uncertain hearing can
	# inform mission awareness but can never replace a living visual report.
	for source in ["vision","hearing"]:
		for unit in world.units:
			if not unit.alive or unit.team!=team:continue
			var reports: Dictionary=unit.get("ai_contacts" if source=="vision" else "ai_hearing_contacts",{})
			for id in reports:
				var report: Dictionary=reports[id]
				if report.get("source","")!=source or world.time-float(report.get("observed_at",-100))>=(6.0 if source=="vision" else 2.8) or float(report.get("confidence",0))<.2:continue
				if known.has(id) and known[id].source=="vision" and source=="hearing":continue
				if not known.has(id) or float(report.observed_at)>float(known[id].observed_at):known[id]=report
	return known.values()

func counts(team: int) -> Dictionary:
	var result={"hold":0,"attack":0,"control":0,"support":0,"reserve":0}
	for group in teams[team].squads.values():
		var task=str(group.task).get_slice(":",0)
		if result.has(task):result[task]+=1
	return result

func fallback_task(team: int,group: Dictionary) -> String:
	var world=world_ref.get_ref();var point: Dictionary=world.campaign.points[0]
	var assigned=counts(team);var own=int(point.owner)==team;var pressure=point.contested
	var previous=str(group.task).get_slice(":",0)
	if assigned.has(previous):assigned[previous]=maxi(0,int(assigned[previous])-1)
	var slot=int(group.slot);var total=maxi(1,teams[team].squads.size())
	if team==0 and plan_executor.world_ref!=null:return plan_executor.task(group)
	if team==1:
		if point.owner==0 or float(point.progress)>.15:
			# After losing the objective, defenders become actual retaking troops;
			# they must not keep selecting perimeter firing posts as if B were safe.
			return "attack:0" if assigned.attack<maxi(1,ceili(total*.7)) else "hold:0"
		# Objective defenders stay inside the real footprint; at most one wing per side.
		var wing_limit=2 if total>=5 else 0
		if assigned.hold<maxi(1,total-wing_limit):return "hold:0"
		return "control:0" if assigned.control==0 else "support:0"
	if own:
		if assigned.hold<maxi(1,int(ceil(total*.25))):return "hold:0"
		if pressure and assigned.attack<maxi(1,total/3):return "attack:0"
		if assigned.control<maxi(1,total/3):return "control:0"
		return "support:0" if slot%2==0 else "reserve"
	if assigned.attack<maxi(1,int(ceil(total*.6))):return "attack:0"
	return "support:0" if assigned.support<2 else "control:0"

func issue(team: int,group: Dictionary,task: String,source: String,confidence: float):
	var world=world_ref.get_ref()
	if task not in TASKS:return
	var changed=group.task!=task
	if changed and world.time-float(group.issued_at)<8 and source=="fallback":return
	if changed:
		group.task=task;group.issued_at=world.time;group.revision=next_revision;next_revision+=1;teams[team].orders_changed+=1
	group.source=source;group.confidence=confidence
	if source=="laya":group.confirmed_at=world.time
	if changed:world.event.emit({"type":"ai_order","team":team,"squad_id":group.id,"task":task,"source":source,"revision":group.revision,"at":world.time})

func assign_orders(team_filter: int=-1):
	var world=world_ref.get_ref()
	if world.campaign.points.is_empty():return
	var point: Dictionary=world.campaign.points[0]
	if team_filter!=0:accept_breach_report()
	for team in range(2):
		if team_filter>=0 and team!=team_filter:continue
		var state: Dictionary=teams[team]
		for group in state.squads.values():
			group.stale=group.source=="laya" and world.time-float(group.get("confirmed_at",0))>40
			if team==0 and not enabled:
				var planned=plan_executor.task(group)
				if planned!=group.task:issue(team,group,planned,"plan",0)
			if group.source=="fallback" and world.time-float(group.issued_at)>=8:issue(team,group,fallback_task(team,group),"fallback",0)
			var route_count=maxi(1,world.campaign_ai.routes[team].size())
			if team==0 and not enabled:
				group.route=mini(route_count-1,plan_executor.route(group))
			if team==0 and int(group.slot)%3!=2:
				if state.approach=="hill-hook":group.route=mini(1,route_count-1)
				elif state.approach=="trench-hook":group.route=mini(2,route_count-1)
				elif state.approach=="road-push":group.route=0
			var goal=task_goal(team,group,point)
			if team==0 and not enabled:goal=plan_executor.goal(group,goal)
			group.goal=goal
			var task=str(group.task).get_slice(":",0)
			var breach=plan_executor.update_breach(group) if team==0 and not enabled else {}
			var members=[]
			for member_id in group.members:members.append(world.units[member_id])
			var entry=task=="attack" and (Attack.entry_priority(members,point))
			var stalled=task=="attack" and Attack.checkpoint(group,members,point,world.time)
			if stalled:
				for unit in members:
					if unit.id not in group.get("attack_stalled_ids",[]):continue
					var commitment: Dictionary=group.get("bound_state",{})
					if protected_commitment(int(unit.id),commitment):continue
					unit.ai_attack_retry_until=world.time+6
					world.campaign_ai.capture_reservations.claims.erase(unit.id)
					unit.path=[];unit.repath=0;unit.ai_route_done=true
					for key in ["ai_tactic","ai_cover_key","ai_cover_search","ai_bound_candidate_at"]:unit.erase(key)
				world.event.emit({"type":"ai_attack_replan","squad_id":group.id,"at":world.time})
			var previous_bound: Dictionary=group.get("bound_state",{})
			var bound={"phase":"idle","cover_id":-1}
			if task=="attack" and state.maneuver=="bounding" and not entry:
				bound=Maneuver.advance(previous_bound,members,world.time)
				if bound.get("phase","")=="handoff" and previous_bound.get("phase","")!="handoff":
					for mover_id in bound.goals:
						var target=world.campaign_ai.connected_goal(world.units[mover_id].position,bound.goals[mover_id])
						if target.is_finite():bound.goals[mover_id]=target
						else:bound=Maneuver.recover(bound,world.time,"handoff-no-standpoint");break
				if bound.get("phase","") in ["bound","handoff"] and bound.get("phase","")!=previous_bound.get("phase",""):
					for mover_id in bound.goals.keys():
						if not world.campaign_ai.tactics.reserve_position(int(mover_id),bound.goals[mover_id],5):bound.goals.erase(mover_id)
					if bound.goals.is_empty():bound=Maneuver.recover(bound,world.time,"no-reserved-standpoint")
			group.bound_state=bound
			if bound.get("phase","idle")!=previous_bound.get("phase","idle"):
				world.event.emit({"type":"ai_maneuver_phase","team":team,"squad_id":group.id,"phase":bound.get("phase","idle"),"cover_id":bound.get("cover_id",-1),"effect":bound.get("effect","unconfirmed"),"reason":bound.get("reason",""),"at":world.time})
			for index in range(group.members.size()):
				var unit: Dictionary=world.units[group.members[index]]
				var spread=Vector2.from_angle(float(index)*2.39996+float(group.slot))*(.65 if task=="attack" else 1.0)
				var destination=world.campaign_ai.capture_goal(unit.position,int(group.slot)*3+index,0,Vector2.INF,int(unit.id),task+":"+str(group.revision)) if task in ["attack","hold"] else world.campaign_ai.connected_goal(unit.position,goal+spread)
				if team==1 and world.time<float(group.get("watch_until",0)):
					destination=world.campaign_ai.capture_goal(unit.position,int(group.slot)*3+index,0,group.watch_goal,int(unit.id),task+":"+str(group.revision))
				if not destination.is_finite():
					var previous: Vector2=unit.get("ai_order",{}).get("goal",unit.position)
					var node=world.campaign_ai.point_cell(previous)
					destination=previous if node>=0 and not world.campaign_ai.graph.is_point_disabled(node) and world.campaign_ai.capture_reservations.available(previous,int(unit.id)) else unit.position
				var is_thrower=false
				if not breach.is_empty():
					if breach.get("open",false):destination=breach.goal
					else:
						is_thrower=int(breach.get("thrower",-1))==int(unit.id)
						var station: Vector2=breach.stage
						if not is_thrower:station+=Vector2.from_angle(plan_executor.site.wall.angle)*1.5+Vector2(plan_executor.site.normal)*.3
						var legal=world.campaign_ai.connected_goal(unit.position,station)
						if legal.is_finite():destination=legal
				var phase=str(bound.get("phase","idle"));var role=""
				if phase in ["deploy","bound","handoff"]:
					if int(bound.get("cover_id",-1))==int(unit.id):role="cover"
					elif bound.get("goals",{}).has(unit.id):role="move"
					elif phase=="deploy" and unit.position.distance_squared_to(world.units[bound.cover_id].position)<49:role="wait"
				if role.is_empty():world.campaign_ai.tactics.standpoints.erase(unit.id)
				if task not in ["attack","hold"] and world.time>=float(unit.get("ai_support_resume_until",0)):world.campaign_ai.capture_reservations.claims.erase(unit.id)
				unit.task=task;unit.ai_order={"task":task,"goal":destination,"route_index":int(group.route),"squad_id":group.id,"squad_size":int(state.size),"posture":state.posture,
					"lane":group.get("plan_lane","defense"),
					"watch_goal":group.get("watch_goal",destination),"watch_until":group.get("watch_until",0),
					"maneuver":state.maneuver,"approach":state.approach,"source":group.source,"issued_at":group.issued_at,"revision":group.revision,"direct":not breach.is_empty() or state.approach=="rapid-counterattack" or (task!="attack" and team==1),
					"mandatory_route":team==0 and plan_executor.tactic_id=="T03" and group.get("plan_lane","")=="main" and plan_executor.mandatory_approach(world.plan),
					"capture_commit":entry or (task=="attack" and world.time<float(unit.get("ai_attack_retry_until",0))),
					"breach_thrower":is_thrower,"breach_open":bool(breach.get("open",false)),"bound_role":role,"bound_phase":phase,"bound_goal":bound.get("goals",{}).get(unit.id,destination),"bound_cover":role=="cover"}

func accept_breach_report():
	var world=world_ref.get_ref();var report: Dictionary={}
	for unit in world.units:
		if not unit.alive or unit.team!=1 or unit.player or unit.mounted>=0:continue
		var seen: Dictionary=unit.get("ai_breach_observed",{})
		if seen.get("source","")!="vision" or world.time-float(seen.get("observed_at",-100))>2:continue
		if report.is_empty() or seen.observed_at>report.observed_at:report=seen
	if report.is_empty():return
	var chosen: Dictionary={};var distance=14.0*14.0
	for group in teams[1].squads.values():
		if group.task!="hold:0":continue
		if group.get("watch_wall","")==report.wall_id and int(group.get("watch_revision",-1))==int(report.revision):return
		if world.time<float(group.get("watch_until",0)):chosen=group;break
		var d: float=center(group).distance_squared_to(report.position)
		if d<distance:distance=d;chosen=group
	if chosen.is_empty():return
	chosen.watch_wall=report.wall_id;chosen.watch_revision=report.revision;chosen.watch_goal=report.position;chosen.watch_until=world.time+8
	world.event.emit({"type":"ai_defense_breach","squad_id":chosen.id,"position":report.position,"source":"vision","at":world.time})

func valid_goal(goal: Vector2) -> Vector2:
	var world=world_ref.get_ref();var graph: AStar2D=world.campaign_ai.graph
	var nearest=graph.get_closest_point(goal)
	return graph.get_point_position(nearest) if nearest>=0 else goal

func task_goal(team: int,group: Dictionary,point: Dictionary) -> Vector2:
	var world=world_ref.get_ref();var own_base=Vector2.ZERO;var samples=0
	for spawn in world.plan.deployment["blue" if team==0 else "red"].spawnPoints:own_base+=world.catalog.position(spawn,world.plan);samples+=1
	if samples>0:own_base/=samples
	var back=(own_base-Vector2(point.position)).normalized();var side=back.orthogonal()
	var spread=(float(int(group.slot)%3)-1)*2.1
	if str(group.task).get_slice(":",0) in ["attack","hold"]:
		var capture=world.campaign_ai.capture_goal(center(group),int(group.slot))
		return capture if capture.is_finite() else center(group)
	match str(group.task).get_slice(":",0):
		"hold":return valid_goal(point.position+back*1.1+side*spread)
		"control":return valid_goal(point.position-back*(1.5 if point.contested else 5.5)+side*spread)
		"support":return valid_goal(point.position+back*7.2+side*spread*1.8)
		"reserve":return valid_goal(point.position+back*12+side*spread)
	return valid_goal(point.position+Vector2.from_angle(float(group.slot)*2.39996)*float(point.radius)*.45)

func policy_questions() -> Array:
	var approaches=["split-routes","hill-hook","trench-hook","road-push"]
	if world_ref.get_ref().campaign.points[0].contested:approaches.append("rapid-counterattack")
	return [{"name":"posture","description":"Choose tactical risk using known evidence.","options":["aggressive","balanced","cautious"]},
		{"name":"maneuver","description":"Choose movement. Assigned objective tasks have precedence.","options":["direct","flank","bounding","support"]},
		{"name":"formation","description":"Choose infantry group size.","options":["pairs","fireteams","sections","squads"],"criteria":{"pairs":"2 troops","fireteams":"3 troops","sections":"4 troops","squads":"6 troops"}},
		{"name":"approach","description":"Choose approach using real orchard routes; rapid reinforcement applies only to an ongoing contest.","options":approaches,"criteria":{"split-routes":"split road, west hill and west trench approaches","hill-hook":"emphasize west hill","trench-hook":"emphasize protected west trench route","road-push":"short road approach with supporting flanks","rapid-counterattack":"skip deep detours and reinforce allies already contesting the point"}}]

func mission_questions() -> Array:
	return [{"name":"mission","description":"Choose this squad mission; consider current assignments, arrival and capture pressure.","options":TASKS,
		"criteria":{"hold:0":"occupy and guard B inside its circle","attack:0":"advance and capture B inside circle","control:0":"screen enemy approach ahead of B","support:0":"provide covering fire near B","reserve":"stay behind the front as a mobile reserve"}}]

func briefing(team: int,squad_id: String="") -> Dictionary:
	var world=world_ref.get_ref();var state: Dictionary=teams[team];var point: Dictionary=world.campaign.points[0]
	var living=world.campaign.active_counts()[team];var seen=contacts(team);var assigned=counts(team)
	var lines=["Win by capturing B or exhausting enemy reserves. Preserve force and avoid order churn.",
		"Use reported contacts only; hidden enemies are unknown. Support must enable capture, not replace it.",
		"B owner %s; signed blue progress %.2f; contested %s. Our troops inside B: %d."%[["neutral","blue","red"][int(point.owner)+1],float(point.progress),str(point.contested),friendly_count(team,point.position,point.radius)],
		"Our active troops %d, reserves %d, casualties %d; recent contact reports %d."%[living,world.campaign.reserves[team],world.campaign.casualties[team],seen.size()],
		"Assigned squads: attack %d, hold %d, control %d, support %d, reserve %d."%[assigned.attack,assigned.hold,assigned.control,assigned.support,assigned.reserve],
		"Orchard: road is flat; west hill 1.5m; trench 1.6m deep has a 0.6m front soil parapet, a lower rear bank and two open walkable ramps. The recessed lane conceals soldiers; the raised firing ledge exposes them when standing. Gates and walls obstruct movement.",
		"Uncrewed jeep and MGs are not autonomous armor; infantry must not wait for a vehicle."]
	if not squad_id.is_empty() and state.squads.has(squad_id):
		var group: Dictionary=state.squads[squad_id];var hp=0.0;var suppression=0.0;var support=0;var stalled=0
		for id in group.members:
			var unit: Dictionary=world.units[id];hp+=float(unit.health)/maxf(1,unit.max_health);suppression+=float(unit.get("ai_stress",0));support+=int(unit.class_id=="support" or "portable-mortar" in unit.get("loadout",[]))
			if unit.has("ai_last_progress_at") and world.time-float(unit.ai_last_progress_at)>4 and unit.position.distance_to(point.position)>point.radius:stalled+=1
		var n=maxi(1,group.members.size())
		lines.insert(1,"Current squad %s: %d troops, health %.0f%%, suppression %.2f, support weapons %d. B distance %.1fm, shortest walk ETA %.1fs, %d troops not advancing. Current task %s for %.1fs."%[squad_id,n,100*hp/n,suppression/n,support,center(group).distance_to(point.position),arrival_seconds(group,point.position),stalled,group.task,world.time-float(group.issued_at)])
	for index in range(mini(3,seen.size())):
		var report: Dictionary=seen[index];var at: Vector2=report.position
		lines.append("%s report at %.1f,%.1fm, age %.1fs, confidence %.2f."%[report.get("source","reported"),at.x,at.y,world.time-float(report.observed_at),float(report.confidence)])
	return {"commander":"blue" if team==0 else "red","briefing":lines}

func arrival_seconds(group: Dictionary,goal: Vector2) -> float:
	var graph: AStar2D=world_ref.get_ref().campaign_ai.graph
	var start=graph.get_closest_point(center(group));var end=graph.get_closest_point(goal)
	if start<0 or end<0:return -1
	var path=graph.get_point_path(start,end);var distance=0.0
	if path.is_empty():return -1
	for index in range(1,path.size()):distance+=path[index].distance_to(path[index-1])
	return distance/2.25

func apply_result(result: Dictionary):
	if not enabled:return
	var world=world_ref.get_ref();var team=int(result.team);var state: Dictionary=teams[team]
	var accepted: Dictionary=result.get("accepted",{});var metadata: Dictionary=result.get("metadata",{})
	if metadata.has("round") and int(metadata.round)!=int(state.round):return
	state.last_result=world.time;state.accepted+=accepted.size()
	if accepted.is_empty():state.rejected+=1
	if not str(result.get("reason","")).is_empty():
		state.queue=[];state.phase="idle";state.next_at=world.time+4;return
	if metadata.get("phase","")=="policy":
		for key in ["posture","maneuver","approach"]:
			if accepted.has(key):state[key]=str(accepted[key].choice);state.source="laya"
		if accepted.has("formation"):
			var formation=str(accepted.formation.choice)
			if formation!=state.formation and world.time-float(state.regrouped_at)>=30:
				state.formation=formation;state.size=FORMATIONS[formation];state.squads={};state.regrouped_at=world.time;ensure_squads(team)
		state.queue=state.squads.keys();state.phase="missions"
	elif metadata.get("phase","")=="mission":
		var id=str(metadata.get("squad_id",""))
		if state.squads.has(id) and accepted.has("mission"):
			var answer: Dictionary=accepted.mission
			var applied=calibrate(team,state.squads[id],answer)
			issue(team,state.squads[id],applied.choice,"laya",float(applied.get("confidence",0)))
			state.source="laya"
			world.event.emit({"type":"ai_mission_applied","team":team,"squad_id":id,"choice":answer.choice,"appliedChoice":applied.choice,"adjustments":applied.get("adjustments",{}),"source":"laya","request_id":result.get("request_id",-1)})
	assign_clock=0

func calibrate(team: int,group: Dictionary,answer: Dictionary) -> Dictionary:
	var world=world_ref.get_ref();var probabilities: Dictionary=answer.get("probabilities",{})
	if probabilities.is_empty():return answer
	var point: Dictionary=world.campaign.points[0];var assigned=counts(team);var own=int(point.owner)==team
	var previous=str(group.task).get_slice(":",0)
	if assigned.has(previous):assigned[previous]=maxi(0,int(assigned[previous])-1)
	var total_squads=maxi(1,teams[team].squads.size())
	var assault_need=maxi(1,ceili(total_squads*.55))
	var support_need=maxi(1,total_squads/4)
	var weights={};var total=0.0;var scored={}
	for token in TASKS:
		var utility=0.0;var kind=token.get_slice(":",0)
		if own:
			if kind=="hold":utility=.9 if assigned.hold==0 else .1
			elif kind=="control":utility=.7 if assigned.control==0 else .1
			elif kind=="attack":utility=.7 if point.contested else -.45
		else:
			if kind=="attack":utility=.9+absf(float(point.progress))*.5-.25*assigned.attack-maxi(0,assigned.attack-assault_need+1)*2.2
			elif kind=="support":utility=-1.0 if assigned.attack==0 else (1.8 if assigned.support<support_need else -.8*assigned.support)
			elif kind=="control":utility=.8 if assigned.attack>=assault_need and assigned.control==0 else -.3
			elif kind=="hold":utility=-.3
			elif kind=="reserve":utility=-.45
		if token==group.task:utility+=.3*clampf(1.0-(world.time-float(group.issued_at))/18.0,0,1)
		weights[token]=exp(utility*.7);scored[token]=float(probabilities.get(token,0))*weights[token];total+=scored[token]
	if total<=0:return answer
	var chosen=str(answer.choice);var runner=0.0
	for token in scored:scored[token]/=total
	for token in scored:
		if scored[token]>scored[chosen]:chosen=token
	for token in scored:
		if token!=chosen:runner=maxf(runner,scored[token])
	if scored[chosen]<.24 or scored[chosen]-runner<.02:return answer
	return {"choice":chosen,"confidence":scored[chosen],"probabilities":scored,"adjustments":weights}

func diagnostics() -> Dictionary:
	var transport=commander.diagnostics() if commander!=null else {"configured":false,"requests":0,"responses":0,"errors":0,"pending":0,"busy":false,"queued":0,"last_error":""}
	var result={"enabled":enabled,"mode":"laya" if enabled else "local","transport":transport,"teams":[]}
	for state in teams:result.teams.append({"source":state.source,"formation":state.formation,"approach":state.approach,"accepted":state.accepted,"rejected":state.rejected,"orders_changed":state.orders_changed,"last_result":state.last_result})
	return result

func status_text() -> String:
	if teams.is_empty():return "规则指挥"
	if not enabled:
		var phases={};var detail=PackedStringArray()
		for group in teams[0].squads.values():
			var phase=str(group.get("bound_state",{}).get("phase","idle"));phases[phase]=int(phases.get(phase,0))+1
		for phase in phases:detail.append("%s %d"%[phase,phases[phase]])
		return "蓝军战术：%s · %s\n三人组 %d · %s"%[plan_executor.tactic_id,preload("res://scripts/campaign_plan.gd").NAMES[plan_executor.tactic_id],teams[0].squads.size()," / ".join(detail)]
	if teams[0].squads.is_empty():return "蓝军暂无可指挥小队"
	var model=0;var stale=0;var total=teams[0].squads.size()
	for group in teams[0].squads.values():
		if group.source=="laya":model+=1
		if group.get("stale",false):stale+=1
	var transport=commander.diagnostics()
	if enabled and not str(transport.last_error).is_empty():
		return "Laya 连接中断 · 沿用已有命令" if model>0 else "Laya 离线 · 规则指挥"
	if model>0 and stale==model:return "蓝军指挥：沿用 Laya 已有命令"
	if model>0:return "蓝军指挥：Laya · %d / %d 小队已受令"%[model,total]
	if int(teams[0].accepted)>0:return "蓝军指挥：Laya 战术 · 小队沿用规则任务"
	return "蓝军指挥：规则策略 · 等待 Laya 决策"

static func protected_commitment(unit_id: int,bound: Dictionary) -> bool:
	return bound.get("phase","") in ["bound","handoff"] and (int(bound.get("cover_id",-1))==unit_id or bound.get("goals",{}).has(unit_id))
