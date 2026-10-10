extends SceneTree
## Frozen actual geometry only: no world.step, AI update, driving, firing or input.
const Catalog=preload("res://scripts/source_catalog.gd")
const Chapters=preload("res://scripts/campaign_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
var results=[]
func _initialize():run.call_deferred()
func run():
	var catalog=Catalog.new()
	for number in range(1,11):
		var plan=Chapters.plan(catalog,number);var world=World.new();world.setup(plan,catalog)
		var ai=world.campaign_ai;var vehicle_ai=ai.vehicle_ai
		var result={"chapter":number,"nodes":ai.graph.get_point_count(),"active":world.campaign.active_counts(),"support_posts":[],"fixed_mounts":[],"spawn_conflicts":[],"objective_blocked":false,"initial_unit_conflicts":[],"time":world.time,"shots":world.shots}
		var objective: Vector2=world.campaign.points[0].position
		result.objective_blocked=world.blocked(objective,.31,1.95,-1,world.terrain.height(objective))
		for side in ["blue","red"]:
			for raw in world.plan.deployment[side].spawnPoints:
				var at=catalog.position(raw,plan)
				var blocked=world.blocked(at,.31,1.95,-1,world.terrain.height(at))
				var reachable=ai.capture_goal(at).is_finite()
				if blocked or not reachable:result.spawn_conflicts.append({"side":side,"id":raw.id,"blocked":blocked,"capture_reachable":reachable,"position":[at.x,at.y]})
		for u in world.units:
			if world.blocked(u.position,.31,1.95,-1,u.elevation):result.initial_unit_conflicts.append({"id":u.id,"position":[u.position.x,u.position.y]})
		for lane in ["left","right"]:
			var post=world.campaign_director.plan_executor.support_post(lane)
			var detail={"lane":lane,"raw":[post.x,post.y],"raw_blocked":world.blocked(post,.31,1.95,-1,world.terrain.height(post)),"origins":[]}
			for index in [0,world.plan.deployment.blue.spawnPoints.size()/2,world.plan.deployment.blue.spawnPoints.size()-1]:
				var origin=catalog.position(world.plan.deployment.blue.spawnPoints[int(index)],plan)
				var actual=ai.connected_goal(origin,post)
				detail.origins.append({"spawn":index,"reachable":actual.is_finite(),"resolved":[actual.x,actual.y] if actual.is_finite() else [],"offset":actual.distance_to(post) if actual.is_finite() else -1})
			result.support_posts.append(detail)
		for v in world.vehicles:
			if not v.emplacement:continue
			var points=vehicle_ai.boarding_points(v);var usable=[false,false]
			for u in world.units:
				if not vehicle_ai.eligible(u,v,0):continue
				for at in points:
					if ai.same_component(u.position,at):usable[int(u.team)]=true;break
			result.fixed_mounts.append({"source":v.source_id,"type":v.type,"team":v.team,"ai":v.get("ai_controlled",false),"boarding_points":points.size(),"connected_crew":usable,"firing_sector":vehicle_ai.prepare_mission(v)})
		results.append(result);print("TACTICAL_FROZEN "+JSON.stringify(result))
		world=null
	var file=FileAccess.open("res://qa/iteration_20261009/ten-chapter-tactical-audit.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"\t"));file.close()
	print("TACTICAL_FROZEN_COMPLETE chapters=10; world.time=0 shots=0; reachability is not gameplay success")
	quit()
