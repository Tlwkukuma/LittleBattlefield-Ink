extends SceneTree
## Alternating policies in one frozen world reduces cross-process timing noise.
## No battle ticks, firing, input, screenshots, or external model requests.
const Catalog=preload("res://scripts/source_catalog.gd")
const Level=preload("res://scripts/orchard_level.gd")
const Pose=preload("res://scripts/combat_pose.gd")
var pairs: Array=[]
var world

class CountWorld:
	extends "res://scripts/proving_world.gd"
	var query_count=0
	func trace_3d(origin: Vector3,direction: Vector3,distance: float,p: Dictionary={},walls_only: bool=false) -> Dictionary:
		query_count+=1
		return super.trace_3d(origin,direction,distance,p,walls_only)

func old_see(unit: Dictionary,target: Dictionary) -> bool:
	if not target.alive or target.team==unit.team or world.enclosed(target):return false
	var rules=world.campaign_ai.perception.profile(world.weapon_for(unit));var offset: Vector2=target.position-unit.position;var distance=offset.length()
	if distance>rules.range+.3:return false
	var allowance=minf(.13,.30/maxf(1.5,distance))
	if absf(wrapf(offset.angle()-unit.facing.angle(),-PI,PI))>rules.half_angle+allowance:return false
	var eye=Vector3(unit.position.x,unit.elevation+(1.62 if unit.stance==0 else 1.15 if unit.stance==1 else .52),unit.position.y)
	var chest=Vector3(target.position.x,target.elevation+world.stance_height(target.stance)*.64,target.position.y)
	var ray=chest-eye
	if world.trace_3d(eye,ray.normalized(),ray.length(),{"source":unit.id,"team":unit.team},true).is_empty():return true
	var blend=float(target.get("stance_blend",target.stance));var prone=clampf(blend-1,0,1)
	var point: Vector2=target.position+target.facing*.61*prone
	var head=Vector3(point.x,target.elevation+(lerpf(1.61,1.17,blend) if blend<=1 else lerpf(1.17,.54,prone)),point.y)
	ray=head-eye
	return world.trace_3d(eye,ray.normalized(),ray.length(),{"source":unit.id,"team":unit.team},true).is_empty()

func measure(current: bool) -> Dictionary:
	world.query_count=0;var seen=0;var start=Time.get_ticks_usec()
	for pair in pairs:seen+=int(world.campaign_ai.perception.can_see(pair[0],pair[1]) if current else old_see(pair[0],pair[1]))
	return {"ms":(Time.get_ticks_usec()-start)/1000.0,"rays":world.query_count,"seen":seen}

func _initialize():
	var catalog=Catalog.new();world=CountWorld.new();world.setup(Level.plan(catalog),catalog)
	for unit in world.units:
		# Reuse static measured capsule positions, not animation/resource evaluation.
		var root=Pose.base(unit);var head=root+Vector3.UP*Pose.HEAD_CENTER[unit.stance]
		unit.hit_shapes=[{"a":root+Vector3.UP*.4,"b":head-Vector3.UP*.3,"radius":.25,"region":"body"},{"a":head,"b":head,"radius":.25,"region":"head"}]
		unit.cover_body_shape=unit.hit_shapes[0];unit.cover_head_shape=unit.hit_shapes[1]
		for target in world.units:
			if target.team!=unit.team:pairs.append([unit,target])
	measure(false);measure(true)
	var old_times=[];var new_times=[];var old_result={};var new_result={}
	for repeat in range(15):
		if repeat%2==0:old_result=measure(false);new_result=measure(true)
		else:new_result=measure(true);old_result=measure(false)
		old_times.append(old_result.ms);new_times.append(new_result.ms)
	old_times.sort();new_times.sort()
	var report={"kind":"frozen_query_comparison_not_battle_fps","units":world.units.size(),"pairs":pairs.size(),"samples_per_policy":15,"before_median_ms":old_times[7],"after_median_ms":new_times[7],"before_rays":old_result.rays,"after_rays":new_result.rays,"before_visible":old_result.seen,"after_visible":new_result.seen,"battle_steps":0,"shots":world.shots}
	report.median_ratio=float(report.after_median_ms)/maxf(.001,float(report.before_median_ms))
	var file=FileAccess.open("res://qa/performance/cover-query-cost.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ")+"\n");file.close()
	print("COVER_QUERY_COST "+JSON.stringify(report));quit()
