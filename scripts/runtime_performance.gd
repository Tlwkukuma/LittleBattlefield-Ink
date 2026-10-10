extends RefCounted
## Opt-in live measurements; observes the user's play without driving the game.
const MAX_SAMPLES=4096
const MAX_LOG_BYTES=8*1024*1024
const LOG_PATH="user://runtime-performance.jsonl"
var recording=false
var log_path=LOG_PATH
var log_file: FileAccess
var log_error=""
var last_world
var last_active=false
var session_id=""
var reports_written=0
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
var unit_ray_metadata: Dictionary={}
var ai_query_metadata: Dictionary={}
var viewport_rid: RID
var render_cpu: Array=[]
var render_gpu: Array=[]
var active_intervals: Array=[]
func measure_viewport(viewport: RID):
	viewport_rid=viewport
	RenderingServer.viewport_set_measure_render_time(viewport_rid,true)
func record_physics(started: int,world=null):
	var elapsed=(Time.get_ticks_usec()-started)/1000.0;_sample(physics,elapsed)
	pending_physics_ms+=elapsed;pending_physics_steps+=1
	if world==null:return
	last_world=world
	for key in world.last_step_profile.get("unit_rays",{}):
		var value=world.last_step_profile.unit_rays[key]
		if value is int or value is float:
			unit_ray_totals[key]=float(unit_ray_totals.get(key,0))+float(value)
		else:
			unit_ray_metadata[key]=value.duplicate(true) if value is Dictionary or value is Array else value
	if elapsed>float(worst_physics.get("total_ms",-1)):worst_physics={"total_ms":elapsed,"simulation_time":world.time,"stages":world.last_step_profile.duplicate(true)}
	for key in world.last_step_profile:
		if not str(key).ends_with("_ms") or not (world.last_step_profile[key] is int or world.last_step_profile[key] is float):continue
		if not physics_stages.has(key):physics_stages[key]=[]
		_sample(physics_stages[key],world.last_step_profile[key])
	for key in world.last_step_profile.get("ai_detail",{}):
		var value=world.last_step_profile.ai_detail[key]
		if not (value is int or value is float):
			ai_query_metadata[key]=value.duplicate(true) if value is Dictionary or value is Array else value
			continue
		if not str(key).ends_with("_ms"):
			ai_query_totals[key]=float(ai_query_totals.get(key,0))+float(value)
			continue
		var name="ai_"+str(key)
		if not physics_stages.has(name):physics_stages[name]=[]
		_sample(physics_stages[name],world.last_step_profile.ai_detail[key])
static func summary(values: Array) -> Dictionary:
	if values.is_empty():return {"samples":0}
	var ordered=values.duplicate();ordered.sort()
	return {"samples":ordered.size(),"p50_ms":ordered[ordered.size()/2],"p95_ms":ordered[mini(ordered.size()-1,int(ordered.size()*.95))],"p99_ms":ordered[mini(ordered.size()-1,int(ordered.size()*.99))],"max_ms":ordered[-1]}
func record_frame(started: int,delta: float,world,active_play: bool=true):
	last_world=world;last_active=active_play
	var elapsed_ms=(Time.get_ticks_usec()-started)/1000.0
	_sample(presentation,elapsed_ms);age+=delta
	if elapsed_ms>float(worst_presentation.get("total_ms",-1)):
		worst_presentation={"total_ms":elapsed_ms,"simulation_time":world.time,"stages":last_frame.duplicate(true)}
	for key in last_frame:
		if not str(key).ends_with("_ms") or not (last_frame[key] is int or last_frame[key] is float):continue
		if not stage_samples.has(key):stage_samples[key]=[]
		_sample(stage_samples[key],last_frame[key])
	for key in last_frame.get("render_batches",{}):
		if not (last_frame.render_batches[key] is int or last_frame.render_batches[key] is float):continue
		var name="batch_"+str(key)
		if not stage_samples.has(name):stage_samples[name]=[]
		_sample(stage_samples[name],last_frame.render_batches[key])
	for key in last_frame.get("fx_detail",{}):
		if not str(key).ends_with("_ms") or not (last_frame.fx_detail[key] is int or last_frame.fx_detail[key] is float):continue
		var name="fx_"+str(key)
		if not stage_samples.has(name):stage_samples[name]=[]
		_sample(stage_samples[name],last_frame.fx_detail[key])
	var now=Time.get_ticks_usec()
	if viewport_rid.is_valid():
		_sample(render_cpu,RenderingServer.get_frame_setup_time_cpu()+RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid))
		var gpu_ms=RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid)
		if gpu_ms>0:_sample(render_gpu,gpu_ms)
	if report_started_usec==0:report_started_usec=now
	if last_presented_usec>0:
		var elapsed=(now-last_presented_usec)/1000.0;_sample(frame_intervals,elapsed)
		if active_play and previous_active:_sample(active_intervals,elapsed)
		_sample(physics_per_frame,pending_physics_ms);_sample(physics_steps_per_frame,pending_physics_steps)
		if elapsed>float(worst_frame_interval.get("interval_ms",-1)):
			# Physics and this parent callback belong to this interval. Child callback
			# last_ms values in last_frame describe earlier callbacks, not exact totals.
			worst_frame_interval={"interval_ms":elapsed,"physics_ms":pending_physics_ms,"physics_steps":pending_physics_steps,"parent_process_ms":elapsed_ms,"simulation_time":world.time,"last_frame":last_frame.duplicate(true)}
		if active_play and previous_active and world.player.velocity.length_squared()>.01:_sample(moving_intervals,elapsed)
	pending_physics_ms=0.0;pending_physics_steps=0
	last_presented_usec=now
	# The render monitor describes the preceding presented frame; do not attribute
	# the last menu frame to the first resumed combat frame.
	if active_play and previous_active:_sample(active_draw_calls,int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	previous_active=active_play
	if now-report_started_usec<5000000:return
	flush_report(world,active_play)

func flush_report(world,active_play: bool=false):
	var now=Time.get_ticks_usec()
	var result={"simulation_time":world.time,"fps":Engine.get_frames_per_second(),"physics_hz":Engine.physics_ticks_per_second,"physics":summary(physics),"presentation":summary(presentation),"last_step":world.last_step_profile,"last_frame":last_frame,"units":world.campaign.active_counts() if world.campaign_active() else world.units.size(),"projectiles":world.projectiles.size()}
	result.frame_intervals=summary(frame_intervals);result.moving_intervals=summary(moving_intervals)
	if world.campaign_active():result.vehicle_ai=world.campaign_ai.vehicle_ai.diagnostics()
	result.active_frame_intervals=summary(active_intervals)
	var over_budget: int=0
	for interval: float in active_intervals:
		if interval>15.0:over_budget+=1
	result.frame_budget={"target_ms":15.0,"samples":active_intervals.size(),"over_budget":over_budget,"max_fps":Engine.max_fps}
	result.render_cpu=summary(render_cpu)
	result.render_gpu={"status":"unknown","reason":"unsupported or unavailable"} if render_gpu.is_empty() else summary(render_gpu)
	result.ai_budget_usec=world.ai_budget_usec
	result.parent_presentation=summary(presentation)
	result.sample_limit=MAX_SAMPLES
	result.engine_process_ms=Performance.get_monitor(Performance.TIME_PROCESS)*1000.0
	result.physics_per_frame=summary(physics_per_frame)
	var step_counts={}
	for count in physics_steps_per_frame:step_counts[str(count)]=int(step_counts.get(str(count),0))+1
	result.physics_steps_per_frame=step_counts;result.worst_frame_interval=worst_frame_interval
	result.unit_ray_totals=unit_ray_totals
	result.ai_query_totals=ai_query_totals
	result.unit_ray_metadata=unit_ray_metadata
	result.ai_query_metadata=ai_query_metadata
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
	write_event({"type":"samples","session":session_id,"data":result})
	physics.clear();presentation.clear();frame_intervals.clear();moving_intervals.clear();active_draw_calls.clear();age=0;report_started_usec=now
	worst_presentation={};stage_samples.clear()
	worst_physics={};physics_stages.clear()
	physics_per_frame.clear();physics_steps_per_frame.clear();worst_frame_interval={};unit_ray_totals={}
	ai_query_totals={};unit_ray_metadata={};ai_query_metadata={}
	render_cpu.clear();render_gpu.clear();active_intervals.clear()

static func _sample(values: Array,value):
	if values.size()<MAX_SAMPLES:values.append(value)

func start_session(path: String=LOG_PATH) -> bool:
	# Idempotent enable must never truncate an already-running session.
	if recording:return true
	boundary("pre_recording")
	log_path=path;log_error=""
	log_file=FileAccess.open(log_path,FileAccess.WRITE)
	if log_file==null:log_error="无法写入性能日志";return false
	recording=true;reports_written=0;session_id=str(Time.get_unix_time_from_system())
	boundary("session_start")
	return true

func write_event(data: Dictionary):
	if not recording or log_file==null:return
	var line=JSON.stringify(data)+"\n"
	if log_file.get_position()+line.to_utf8_buffer().size()>MAX_LOG_BYTES:
		log_error="性能日志已达到 8 MiB 上限；请显式开始新录制"
		log_file.flush();log_file.close();log_file=null;recording=false;return
	log_file.store_string(line);log_file.flush();reports_written+=1

func boundary(reason: String):
	if last_world!=null and (not physics.is_empty() or not presentation.is_empty()):flush_report(last_world,last_active)
	write_event({"type":"boundary","reason":reason,"session":session_id,"ticks_usec":Time.get_ticks_usec()})
	last_presented_usec=0;report_started_usec=0;previous_active=false
	pending_physics_ms=0;pending_physics_steps=0;last_frame={};last_world=null

func stop_session():
	boundary("session_stop")
	if log_file!=null:log_file.flush();log_file.close();log_file=null
	recording=false
