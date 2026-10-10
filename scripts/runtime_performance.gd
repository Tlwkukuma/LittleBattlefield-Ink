extends RefCounted
## Opt-in live measurements; observes the user's play without driving the game.
var physics: Array=[]
var presentation: Array=[]
var age=0.0
var last_frame: Dictionary={}
var frame_intervals: Array=[]
var moving_intervals: Array=[]
var last_presented_usec=0
var report_started_usec=0
var active_draw_calls: Array=[]
var previous_active=false
var worst_presentation: Dictionary={}
var stage_samples: Dictionary={}
var physics_stages: Dictionary={}
var worst_physics: Dictionary={}
var pending_physics_ms=0.0
var pending_physics_steps=0
var physics_per_frame: Array=[]
var physics_steps_per_frame: Array=[]
var worst_frame_interval: Dictionary={}
var unit_ray_totals: Dictionary={}
var ai_query_totals: Dictionary={}
var viewport_rid: RID
var render_cpu: Array=[]
var render_gpu: Array=[]
var active_intervals: Array=[]
func measure_viewport(viewport: RID):
	viewport_rid=viewport
	RenderingServer.viewport_set_measure_render_time(viewport_rid,true)
func record_physics(started: int,world=null):
	var elapsed=(Time.get_ticks_usec()-started)/1000.0;physics.append(elapsed)
	pending_physics_ms+=elapsed;pending_physics_steps+=1
	if world==null:return
	for key in world.last_step_profile.get("unit_rays",{}):
		unit_ray_totals[key]=float(unit_ray_totals.get(key,0))+float(world.last_step_profile.unit_rays[key])
	if elapsed>float(worst_physics.get("total_ms",-1)):worst_physics={"total_ms":elapsed,"simulation_time":world.time,"stages":world.last_step_profile.duplicate(true)}
	for key in world.last_step_profile:
		if not str(key).ends_with("_ms"):continue
		if not physics_stages.has(key):physics_stages[key]=[]
		physics_stages[key].append(world.last_step_profile[key])
	for key in world.last_step_profile.get("ai_detail",{}):
		if not str(key).ends_with("_ms"):
			ai_query_totals[key]=float(ai_query_totals.get(key,0))+float(world.last_step_profile.ai_detail[key])
			continue
		var name="ai_"+str(key)
		if not physics_stages.has(name):physics_stages[name]=[]
		physics_stages[name].append(world.last_step_profile.ai_detail[key])
static func summary(values: Array) -> Dictionary:
	if values.is_empty():return {"samples":0}
	var ordered=values.duplicate();ordered.sort()
	return {"samples":ordered.size(),"p50_ms":ordered[ordered.size()/2],"p95_ms":ordered[mini(ordered.size()-1,int(ordered.size()*.95))],"p99_ms":ordered[mini(ordered.size()-1,int(ordered.size()*.99))],"max_ms":ordered[-1]}
func record_frame(started: int,delta: float,world,active_play: bool=true):
	var elapsed_ms=(Time.get_ticks_usec()-started)/1000.0
	presentation.append(elapsed_ms);age+=delta
	if elapsed_ms>float(worst_presentation.get("total_ms",-1)):
		worst_presentation={"total_ms":elapsed_ms,"simulation_time":world.time,"stages":last_frame.duplicate(true)}
	for key in last_frame:
		if not str(key).ends_with("_ms"):continue
		if not stage_samples.has(key):stage_samples[key]=[]
		stage_samples[key].append(last_frame[key])
	for key in last_frame.get("render_batches",{}):
		var name="batch_"+str(key)
		if not stage_samples.has(name):stage_samples[name]=[]
		stage_samples[name].append(last_frame.render_batches[key])
	for key in last_frame.get("fx_detail",{}):
		if not str(key).ends_with("_ms"):continue
		var name="fx_"+str(key)
		if not stage_samples.has(name):stage_samples[name]=[]
		stage_samples[name].append(last_frame.fx_detail[key])
	var now=Time.get_ticks_usec()
	if viewport_rid.is_valid():
		render_cpu.append(RenderingServer.get_frame_setup_time_cpu()+RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid))
		render_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid))
	if report_started_usec==0:report_started_usec=now
	if last_presented_usec>0:
		var elapsed=(now-last_presented_usec)/1000.0;frame_intervals.append(elapsed)
		if active_play and previous_active:active_intervals.append(elapsed)
		physics_per_frame.append(pending_physics_ms);physics_steps_per_frame.append(pending_physics_steps)
		if elapsed>float(worst_frame_interval.get("interval_ms",-1)):
			# Physics and this parent callback belong to this interval. Child callback
			# last_ms values in last_frame describe earlier callbacks, not exact totals.
			worst_frame_interval={"interval_ms":elapsed,"physics_ms":pending_physics_ms,"physics_steps":pending_physics_steps,"parent_process_ms":elapsed_ms,"simulation_time":world.time,"last_frame":last_frame.duplicate(true)}
		if active_play and world.player.velocity.length_squared()>.01:moving_intervals.append(elapsed)
	pending_physics_ms=0.0;pending_physics_steps=0
	last_presented_usec=now
	# The render monitor describes the preceding presented frame; do not attribute
	# the last menu frame to the first resumed combat frame.
	if active_play and previous_active:active_draw_calls.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	previous_active=active_play
	if now-report_started_usec<5000000:return
	var result={"simulation_time":world.time,"fps":Engine.get_frames_per_second(),"physics_hz":Engine.physics_ticks_per_second,"physics":summary(physics),"presentation":summary(presentation),"last_step":world.last_step_profile,"last_frame":last_frame,"units":world.campaign.active_counts() if world.campaign_active() else world.units.size(),"projectiles":world.projectiles.size()}
	result.frame_intervals=summary(frame_intervals);result.moving_intervals=summary(moving_intervals)
	if world.campaign_active():result.vehicle_ai=world.campaign_ai.vehicle_ai.diagnostics()
	result.active_frame_intervals=summary(active_intervals)
	var over_budget: int=0
	for interval: float in active_intervals:
		if interval>15.0:over_budget+=1
	result.frame_budget={"target_ms":15.0,"samples":active_intervals.size(),"over_budget":over_budget,"max_fps":Engine.max_fps}
	result.render_cpu=summary(render_cpu);result.render_gpu=summary(render_gpu)
	result.engine_process_ms=Performance.get_monitor(Performance.TIME_PROCESS)*1000.0
	result.physics_per_frame=summary(physics_per_frame)
	var step_counts={}
	for count in physics_steps_per_frame:step_counts[str(count)]=int(step_counts.get(str(count),0))+1
	result.physics_steps_per_frame=step_counts;result.worst_frame_interval=worst_frame_interval
	result.unit_ray_totals=unit_ray_totals
	result.ai_query_totals=ai_query_totals
	result.worst_presentation=worst_presentation;result.presentation_stages={}
	for key in stage_samples:result.presentation_stages[key]=summary(stage_samples[key])
	result.worst_physics=worst_physics;result.physics_stages={}
	for key in physics_stages:result.physics_stages[key]=summary(physics_stages[key])
	var moving=0;var fighting=0
	for unit in world.units:
		if unit.alive and unit.velocity.length_squared()>.01:moving+=1
		if unit.alive and float(unit.get("last_shot",-100))>world.time-.5:fighting+=1
	result.moving_units=moving;result.firing_units=fighting
	result.real_fps=frame_intervals.size()*1000000.0/maxf(1,now-report_started_usec)
	result.player_speed=world.player.velocity.length()
	result.active_play=active_play
	result.draw_calls=int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	if not active_draw_calls.is_empty():
		active_draw_calls.sort();var count=active_draw_calls.size()
		result.active_draw_calls={"samples":count,"min":active_draw_calls[0],"p95":active_draw_calls[mini(count-1,int(count*.95))],"max":active_draw_calls[-1]}
	result.primitives=int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	if world.campaign_active():
		var ai=world.campaign_director.diagnostics()
		result.ai_mode=ai.mode;result.laya_requests=ai.transport.requests;result.laya_responses=ai.transport.responses;result.laya_pending=ai.transport.pending
	print("RUNTIME_PERF "+JSON.stringify(result))
	physics.clear();presentation.clear();frame_intervals.clear();moving_intervals.clear();active_draw_calls.clear();age=0;report_started_usec=now
	worst_presentation={};stage_samples.clear()
	worst_physics={};physics_stages.clear()
	physics_per_frame.clear();physics_steps_per_frame.clear();worst_frame_interval={};unit_ray_totals={}
	ai_query_totals={}
	render_cpu.clear();render_gpu.clear();active_intervals.clear()
