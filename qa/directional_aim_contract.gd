extends SceneTree
## Static geometry, snapshot math and query microbenchmarks only. No AI turns,
## world.step, weapon fire, input, damage or playback of a battle.
const Aim=preload("res://scripts/campaign_directional_aim.gd")
const World=preload("res://scripts/proving_world.gd")
const Catalog=preload("res://scripts/source_catalog.gd")
const Level=preload("res://scripts/orchard_level.gd")
const Pose=preload("res://scripts/combat_pose.gd")
const BeforeAI=preload("res://qa/performance/directional-before-source/campaign_ai.gd")
const BeforePerception=preload("res://qa/performance/directional-before-source/campaign_perception.gd")
var checks=0
var failures=0
class CountWorld extends World:
	var ray_count=0
	func trace_3d(origin: Vector3,direction: Vector3,distance: float,p: Dictionary={},walls_only: bool=false) -> Dictionary:
		ray_count+=1
		return super.trace_3d(origin,direction,distance,p,walls_only)

func check(ok: bool,label: String):
	checks+=1
	if not ok:failures+=1;printerr("FAIL "+label)

func _initialize():run.call_deferred()

func measure(world,before_ai,before_perception,pairs: Array,old: bool,fire_aim: bool) -> Dictionary:
	world.ray_count=0;var seen=0;var started=Time.get_ticks_usec()
	for pair in pairs:
		var unit: Dictionary=pair[0];var target: Dictionary=pair[1]
		if old:
			var visible=before_perception.can_see(unit,target);seen+=int(visible)
			if visible and fire_aim:before_ai.visible_aim(unit,target)
		else:
			var visible=world.campaign_ai.perception.can_see(unit,target);seen+=int(visible)
			if visible and fire_aim:
				Aim.observe(unit,{"position":target.position,"elevation":target.elevation,"stance":target.stance,"observed_at":0.0},world.weapon_for(unit),Vector2(.5,-.4))
	# Treat the new observational math as an upper bound: it runs once per report,
	# whereas the previous confirmation/part search ran once per firing attempt.
	return {"ms":(Time.get_ticks_usec()-started)/1000.0,"rays":world.ray_count,"seen":seen}

func run():
	var unit={"position":Vector2.ZERO,"elevation":0.0,"stance":0,"facing":Vector2.LEFT,"velocity":Vector2.ZERO,"ai_stress":0.0,"ai_target":4}
	var weapon={"archetype":"assault"}
	var contact={"source":"vision","position":Vector2(20,0),"elevation":0.0,"stance":0,"observed_at":10.0}
	check(Aim.fresh(contact,10) and Aim.fresh(contact,10.7),"recent visual report usable")
	check(not Aim.fresh(contact,10.76) and not Aim.fresh(contact,9),"stale/future reports cannot authorize fire")
	var heard=contact.duplicate();heard.source="hearing"
	check(not Aim.fresh(heard,10),"hearing is not a firing lock")
	Aim.observe(unit,contact,weapon,Vector2(.7,-.5));var mark: Vector3=unit.ai_aim_mark
	contact.position=Vector2(100,50);contact.elevation=20
	check(unit.ai_aim_mark==mark,"aim holds a copied last observation")
	var angle=unit.facing.angle();check(not Aim.track(unit,1.0/60),"cannot instantly reverse into ready aim")
	check(absf(wrapf(unit.facing.angle()-angle,-PI,PI))<=Aim.TURN_RATE/60+.00001,"turn rate bound")
	var point=unit.aim_point;var facing=unit.facing;Aim.track(unit,0)
	check(unit.facing==facing and unit.aim_point==point,"zero delta does not advance turning")
	for i in range(100):Aim.track(unit,.016)
	check(Aim.track(unit,.016),"direction converges")
	check(absf(unit.facing.angle())>.01,"stationary AI retains observation error")
	var before=unit.aim_point;unit.hit_shapes=[{"a":Vector3(200,200,200)}];unit.cover_head_shape={"a":Vector3(-200,-200,-200)}
	Aim.track(unit,0);check(unit.aim_point==before,"live body parts never redirect aim")
	var standing=Aim.error_degrees(unit,weapon);unit.velocity=Vector2(2.8,0)
	check(Aim.error_degrees(unit,weapon)>standing,"moving accuracy reduced")
	unit.ai_stress=1;check(Aim.error_degrees(unit,weapon)>standing+2.2,"suppression accuracy reduced")
	check(Aim.error_degrees(unit,{"archetype":"sniper"})<Aim.error_degrees(unit,weapon),"weapon family accuracy retained")
	for stance in range(3):
		contact={"source":"vision","position":Vector2(20,0),"elevation":-1.6,"stance":stance,"observed_at":10.0}
		Aim.observe(unit,contact,weapon,Vector2.ZERO)
		check(is_equal_approx(unit.ai_aim_mark.y,-1.6+Aim.AIM_HEIGHT[stance]),"coarse stance height and trench elevation %d"%stance)
	for i in range(120):
		unit.facing=Vector2.from_angle(float(i)*.37);var prior=unit.facing.angle()
		contact.position=Vector2.from_angle(float(i)*.91)*20
		Aim.observe(unit,contact,weapon,Vector2(sin(i),cos(i)));Aim.track(unit,.016)
		check(absf(wrapf(unit.facing.angle()-prior,-PI,PI))<=Aim.TURN_RATE*.016+.00001,"angle wrap turn bound %d"%i)
		check(Vector2(unit.aim_point).is_finite() and is_finite(unit.aim_height),"finite aim %d"%i)
	var catalog=Catalog.new();var world=CountWorld.new();world.setup(Level.plan(catalog),catalog)
	for size in [0,1,2,3,4,7,30,60]:
		var candidates=[]
		for id in range(size):candidates.append({"unit":{"id":id},"distance":float(id)})
		for current in [-1,0,size-1]:
			var visited={}
			for cursor in range(maxi(1,size)):
				var indices=world.campaign_ai.perception.scan_indices(candidates,current,cursor);var unique={}
				for index in indices:unique[index]=true;visited[index]=true
				check(indices.size()<=4 and unique.size()==indices.size(),"bounded unique observation candidates")
				check(current<0 or current>=size or current in indices,"current target retained in scan")
			check(visited.size()==size,"rotating slots eventually cover every candidate")
	for u in world.units:
		var base=Pose.base(u);var head=base+Vector3.UP*Pose.HEAD_CENTER[u.stance]
		u.hit_shapes=[{"a":base+Vector3.UP*.4,"b":head-Vector3.UP*.3,"radius":.25,"region":"body"},{"a":head,"b":head,"radius":.25,"region":"head"}]
		u.cover_body_shape=u.hit_shapes[0];u.cover_head_shape=u.hit_shapes[1]
	var pairs=[]
	for u in world.units:
		for target in world.units:
			if u.team!=target.team:pairs.append([u,target])
	var before_ai=BeforeAI.new();before_ai.configure(world)
	var before_perception=BeforePerception.new();before_perception.configure(world)
	var records=[]
	for fire_aim in [false,true]:
		var old_times=[];var new_times=[];var a={};var b={}
		for repeat in range(27):
			if repeat%2==0:a=measure(world,before_ai,before_perception,pairs,true,fire_aim);b=measure(world,before_ai,before_perception,pairs,false,fire_aim)
			else:b=measure(world,before_ai,before_perception,pairs,false,fire_aim);a=measure(world,before_ai,before_perception,pairs,true,fire_aim)
			if repeat<2:continue
			old_times.append(a.ms);new_times.append(b.ms)
		old_times.sort();new_times.sort()
		records.append({"firing_attempt_queries":fire_aim,"pairs":pairs.size(),"before_p50_ms":old_times[12],"after_p50_ms":new_times[12],"before_rays":a.rays,"after_rays":b.rays,"before_seen":a.seen,"after_seen":b.seen,"samples":25})
	# One real visibility query and no extra ray in directional aiming. No refresh/
	# selection, confirmation, firing, or AI update is executed by this contract.
	for pair in pairs:
		world.ray_count=0;world.campaign_ai.perception.can_see(pair[0],pair[1])
		check(world.ray_count<=1,"single observation ray")
		var u: Dictionary=pair[0];var target: Dictionary=pair[1]
		world.ray_count=0
		Aim.observe(u,{"position":target.position,"elevation":target.elevation,"stance":target.stance,"observed_at":0.0},world.weapon_for(u),Vector2(.4,-.3));Aim.track(u,0)
		check(world.ray_count==0,"no ray for directional aim")
	check(world.time==0 and world.shots==0,"no battle advancement")
	var result={"checks":checks,"failures":failures,"records":records,"battle_steps":0,"shots":world.shots,"max_candidates":world.campaign_ai.perception.MAX_VISUAL_CANDIDATES}
	var file=FileAccess.open("res://qa/performance/directional-aim.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("DIRECTIONAL_AIM "+JSON.stringify(result));quit(0 if failures==0 else 1)
