extends SceneTree
## Pure state and frozen geometry only: never calls world.step, AI update or fire.
const Roster=preload("res://scripts/campaign_roster.gd")
const Maneuver=preload("res://scripts/campaign_maneuver.gd")
const Penetration=preload("res://scripts/cover_penetration.gd")
const Zone=preload("res://scripts/capture_zone.gd")
var checks=0
var failures=0
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize():run.call_deferred()
func soldier(id: int,at: Vector2) -> Dictionary:
	return {"id":id,"team":0,"alive":true,"player":false,"mounted":-1,"spawn_epoch":0,"recruit_cohort":-1,"position":at,"ammo":30,"reload":0.0,"ai_stress":.1,"grounded":true,"ai_target":8,"ai_contacts":{8:{"source":"vision","position":Vector2(0,-5),"observed_at":10.0,"confidence":1.0}},"ai_support_ready":true,"ai_support_checked_at":10.0,"ai_last_shot_at":10.0}
func run():
	check(Roster.cohort(0)==Roster.cohort(2) and Roster.cohort(3)==Roster.cohort(5),"wave and recruit group are separate")
	var units=[soldier(0,Vector2.ZERO),soldier(1,Vector2(1,0)),soldier(2,Vector2(2,0)),soldier(3,Vector2(30,0))]
	var state={"size":3,"squads":{},"next_squad":0}
	Roster.reconcile(state,units,0,0,{})
	check(state.squads.size()==2,"near three form a squad, distant soldier stays separate")
	var q: Dictionary=state.squads.values()[0];q.task="attack:0";var key=str(q.id)
	units[0].position=Vector2(10,0);Roster.reconcile(state,units,0,1,{})
	check(units[0].squad_id==key and state.squads[key].task=="attack:0","living veteran retains squad and task")
	units[0].spawn_epoch=1;units[0].recruit_cohort=4;units[0].position=Vector2(35,0)
	Roster.reconcile(state,units,0,2,{})
	check(units[0].squad_id!=key and units[1].squad_id==key,"new life cannot rejoin distant veteran slot")
	Roster.reconcile(state,units,0,3,{1:{}})
	check(not state.squads[key].members.has(1),"reserved crew leaves infantry roster")
	var cover=soldier(1,Vector2.ZERO);var mover=soldier(2,Vector2(1,0))
	mover.ai_bound_candidate=Vector2(3,0);mover.ai_bound_candidate_at=10.0;mover.ai_bound_protected=true
	var deployed=Maneuver.advance({},[cover,mover],10.0)
	check(deployed.get("phase","")=="deploy","contact deploys support before movement")
	var bound=Maneuver.advance(deployed,[cover,mover],10.1)
	check(bound.get("phase","")=="bound" and bound.effect=="cover-active","shots alone are unconfirmed cover")
	var waiting=Maneuver.advance(bound,[cover,mover],10.2)
	check(waiting.phase=="bound","time alone never signals arrival")
	mover.position=Vector2(3,0)
	var handoff=Maneuver.advance(bound,[cover,mover],10.3)
	check(handoff.phase=="handoff" and handoff.cover_id==2,"real arrival plus readiness transfers support")
	cover.position=handoff.goals[1]
	check(Maneuver.advance(handoff,[cover,mover],10.4).phase=="idle","old support physically arrives before cycle completes")
	cover.reload=1.0
	check(Maneuver.advance(bound,[cover,mover],10.4).phase=="recover","reload releases unsupported movement")
	cover.reload=0
	check(Maneuver.advance(deployed,[cover,mover],14.0).phase=="recover","deployment has a finite timeout")
	check(Maneuver.advance(bound,[cover,mover],10.95).phase=="recover","expired support readiness releases movement")
	cover.alive=false
	check(Maneuver.advance(bound,[cover,mover],10.3).phase=="recover","support casualty releases movers")
	cover.alive=true;cover.spawn_epoch=1
	check(Maneuver.advance(bound,[cover,mover],10.3).phase=="recover","new life cannot inherit support commitment")
	var timber={"id":"wood","cover_material":{"resistance":10,"thickness_m":.06,"penetrated_damage_scale":.55}}
	var weapon={"cover_ammo":{"lane":"kinetic","penetration":42}}
	var hit={"type":"object","target":timber,"distance":1.0,"exit_distance":1.06}
	var response=Penetration.response(weapon,hit,Vector3.RIGHT,42)
	check(response.get("pass",false) and is_equal_approx(response.remaining,32),"thin wood consumes material budget")
	hit.exit_distance=1.6
	check(not Penetration.response(weapon,hit,Vector3.RIGHT,42).get("pass",false),"thick timber stops same rifle")
	hit.exit_distance=1.06
	check(Penetration.response(weapon,hit,Vector3(1,1,0),42).cost>10,"physical chord includes sloping flight")
	check(not Penetration.response(weapon,{"type":"terrain"},Vector3.RIGHT,1000).get("pass",false),"terrain never gets implicit penetration")
	var first=Penetration.response(weapon,hit,Vector3.RIGHT,42)
	var second=Penetration.response(weapon,hit,Vector3.RIGHT,first.remaining)
	check(is_equal_approx(second.remaining,22) and first.damage_scale*second.damage_scale<first.damage_scale,"separate layers spend remaining energy and attenuate damage")
	check(Penetration.key(hit)=="object:wood","adjacent cells share only the current solid-exit exclusion")
	check(is_equal_approx(Penetration.segment_limit({"a":2.5},1.0,9),1.5),"solid exit caps the next query segment")
	check(is_equal_approx(Penetration.segment_limit({"a":2.5,"b":1.7},1.0,9),.7),"overlapping solids resume at the first exit")
	check(is_equal_approx(Penetration.segment_limit({"a":.5},1.0,9),9),"expired exclusion cannot shorten future flight")
	var parts={"id":"house","columns":1,"solid_parts":[{"at":Vector3(0,1,1),"size":Vector3(2,2,.06)},{"at":Vector3(0,1,3),"size":Vector3(2,2,.06)}]}
	var first_piece=preload("res://scripts/house_geometry.gd").hit(parts,Vector3(0,1,0),Vector3.BACK,1.0,0,true)
	check(is_equal_approx(first_piece.exit_distance,1.03),"first-contact limit does not truncate material thickness")
	var next_piece=preload("res://scripts/house_geometry.gd").hit(parts,Vector3(0,1,1.0301),Vector3.BACK,4,0,true)
	check(next_piece.piece==1,"a second wall of the same house remains in geometry queries")
	var catalog=preload("res://scripts/source_catalog.gd").new()
	var plan=preload("res://scripts/orchard_level.gd").plan(catalog)
	var world=preload("res://scripts/proving_world.gd").new();world.setup(plan,catalog)
	check(world.campaign_ai.connectivity.ready,"initial navigation components are complete")
	var claims=world.campaign_ai.tactics
	check(claims.reserve_position(1,Vector2.ZERO,1.0),"first movable endpoint reserves a standpoint")
	check(not claims.reserve_position(2,Vector2(.2,0),1.0),"another mover cannot reserve the same body space")
	var old_epoch=int(world.units[1].spawn_epoch);world.units[1].spawn_epoch=old_epoch+1
	check(claims.reserve_position(2,Vector2(.2,0),1.0),"a previous life cannot retain a future standpoint")
	world.units[1].spawn_epoch=old_epoch;claims.standpoints.clear()
	for team in world.campaign_director.teams:
		for group in team.squads.values():
			check(group.members.size()<=3,"default infantry groups at most three")
			for id in group.members:
				var u: Dictionary=world.units[id]
				if u.ai_order.task in ["attack","hold"]:
					check(Zone.contains(world.campaign.points[0],u.ai_order.goal,world.terrain.height(u.ai_order.goal)),"capture/guard goal inside actual footprint")
					check(world.campaign_ai.same_component(u.position,u.ai_order.goal),"capture/guard goal belongs to reachable component")
	var executor=world.campaign_director.plan_executor
	check(not executor.site.is_empty(),"T02 finds a legal current-wall staging site")
	if not executor.site.is_empty():
		var site: Dictionary=executor.site
		print("TACTICAL_BREACH_SITE at=",site.target," stage=",site.stage," inside=",site.inside)
		check(not world.campaign_ai.traversable(world,site.outside,site.inside),"intact east wall never counts as a breach")
		check(world.campaign_ai.same_component(site.stage,site.inside),"breach staging remains connected to the original gate route")
		check(not world.blocked(site.stage,.31,1.95,-1,world.terrain.height(site.stage)),"grenadier stage has actual standing clearance")
	check(executor.select("T02"),"existing mission accepts T02")
	var breach_groups=0
	for group in world.campaign_director.teams[0].squads.values():
		if group.get("plan_lane","")=="breach":
			breach_groups+=1
			check(executor.has_grenades(group),"breach group uses existing finite ammunition")
			var instruction=executor.update_breach(group)
			check(not instruction.is_empty() and not instruction.open and instruction.thrower>=0,"intact wall selects one real thrower instead of declaring success")
			if not instruction.is_empty() and instruction.thrower>=0:
				var unit: Dictionary=world.units[instruction.thrower];var grenade=executor.grenade_id(unit)
				var stock: Dictionary=unit.inventory.duplicate(true)
				unit.inventory[grenade]={"ammo":0,"reserve":0}
				check(executor.grenade_id(unit).is_empty(),"spent grenade is never recreated from catalog defaults")
				unit.inventory=stock
				var w: Dictionary=catalog.weapons[grenade];var stage: Vector2=executor.site.stage
				var direction=(Vector2(executor.site.target)-stage).normalized()
				var origin=Vector3(stage.x,world.terrain.height(stage)+1.3,stage.y)+Vector3(direction.x,0,direction.y)*.4
				var target=Vector3(executor.site.target.x,world.terrain.height(executor.site.target)+.25,executor.site.target.y)
				var preview=world.Grenade.preview(world,world.Grenade.solve(origin,target,w,0,false,direction))
				var radius=float(w.get("blastRadius",140))/40
				check(stage.distance_to(executor.site.target)>=radius+1,"grenadier stage is outside its authored blast safety margin")
				check(not preview.hit.is_empty() and Vector2(preview.point.x,preview.point.z).distance_to(executor.site.target)<radius*.65,"read-only real grenade sweep reaches the selected wall")
	check(breach_groups==1,"T02 initially assigns exactly one breach group")
	check(executor.select("T03"),"existing mission accepts T03")
	var trench_groups=0
	for group in world.campaign_director.teams[0].squads.values():
		if group.get("plan_lane","")=="main":
			trench_groups+=1
			for id in group.members:check(world.units[id].ai_order.mandatory_route and world.units[id].ai_order.route_index==1,"T03 requires the actual trench and forest route")
	check(trench_groups>0,"T03 has an assault group")
	check(executor.select("T01"),"default plan can be restored before start")
	var defender: Dictionary={}
	for u in world.units:
		if u.team==1 and not u.player:defender=u;break
	defender.ai_breach_observed={"position":executor.site.target,"source":"hearing","observed_at":0,"wall_id":executor.site.wall.id,"revision":0}
	world.campaign_director.accept_breach_report()
	var redirects=0
	for qd in world.campaign_director.teams[1].squads.values():
		if qd.get("watch_until",0)>0:redirects+=1
	check(redirects==0,"fracture sound alone never confirms a passable breach")
	defender.ai_breach_observed.source="vision"
	world.campaign_director.assign_orders(1);redirects=0
	for qd in world.campaign_director.teams[1].squads.values():
		if qd.get("watch_until",0)>0:
			redirects+=1
			for id in qd.members:check(Zone.contains(world.campaign.points[0],world.units[id].ai_order.goal,world.terrain.height(world.units[id].ai_order.goal)),"redirected defenders still guard actual capture footprint")
	check(redirects==1,"one confirmed local report redirects one nearby guard group")
	check(not Zone.contains(world.campaign.points[0],world.campaign.points[0].position,world.terrain.height(world.campaign.points[0].position)+4),"roof elevation cannot count as a capture entry")
	# Query original object geometry without launching or advancing any projectile.
	var wall: Dictionary={}
	for o in world.objects:
		if o.get("source_id","")=="compound-right":wall=o;break
	if not wall.is_empty():
		var normal=Vector2.from_angle(wall.angle).orthogonal()
		var start=Vector3(wall.position.x+normal.x*2,wall.elevation+1.0,wall.position.y+normal.y*2)
		var ray=Vector3(-normal.x,0,-normal.y)
		var actual=world.trace_3d(start,ray,4,{"weapon":weapon},true)
		check(actual.get("type","")=="object" and actual.target.id==wall.id,"physical material query finds the actual wall")
		if actual.get("type","")=="object" and actual.target.id==wall.id:
			check(actual.exit_distance>actual.distance and is_equal_approx(actual.exit_distance-actual.distance,float(wall.size.y)),"ray exit is full solid thickness even past the first contact")
			check(not Penetration.response(weapon,actual,ray,42).get("pass",false),"full 2.2 m stone wall is not rifle-proof by a label alone")
	var fence={"id":"fence","component_id":"wall.metal-fence","size":Vector2(2,.4),"height":1.5,"columns":4,"rows":3,"cell_width":.5,"cell_height":.5,"hp":[100,100,100,100,100,100,100,100,100,100,100,100]}
	preload("res://scripts/metal_fence.gd").prepare(fence)
	var fence_hit=preload("res://scripts/house_geometry.gd").hit(fence,Vector3(-.96,.75,-1),Vector3.BACK,2,0,true)
	check(not fence_hit.is_empty() and fence_hit.exit_distance>fence_hit.distance,"indexed fence bars keep physical exit metadata")
	var lan=preload("res://scripts/lan_session.gd").new()
	var packet=lan.copy_fields({"id":1,"source_epoch":2,"cover_budget":32.0,"cover_layers":1,"cover_damage_scale":.55,"cover_inside":{"object:wall":1.3}},lan.ROUND_FIELDS)
	var decoded=bytes_to_var(var_to_bytes(packet))
	check(decoded.source_epoch==2 and decoded.cover_inside["object:wall"]==1.3,"existing LAN round serialization retains life and solid-exit state")
	lan.free()
	var components=preload("res://scripts/campaign_connectivity.gd").new();components.begin(world.campaign_ai.graph)
	var slices=0;var graph_started=Time.get_ticks_usec()
	while not components.ready and slices<512:components.pump(world.campaign_ai.graph,1024,450);slices+=1
	check(components.ready and components.labels.size()==world.campaign_ai.connectivity.labels.size(),"budgeted pure graph slices reconstruct complete navigation components")
	print("TACTICAL_COMPONENT_SLICES count=",slices," total_ms=",(Time.get_ticks_usec()-graph_started)/1000.0)
	check(world.time==0 and world.shots==0,"contract never advances combat")
	print("CAMPAIGN_3D_CONTRACT checks=%d failures=%d"%[checks,failures]);quit(0 if failures==0 else 1)
