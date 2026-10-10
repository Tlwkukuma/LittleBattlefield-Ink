extends PanelContainer
## Lightweight view of the same monitors used by Godot's Debugger > Monitors.
## No scene traversal, GPU synchronization, or external process polling.

const REFRESH_USEC=250000
const MIB=1048576.0
var values: Dictionary={}
var latest: Dictionary={}
var sampled_at=0
var previous_frame=0
var frame_count=0
var frame_total_usec=0
var frame_max_usec=0
var reported=false
var frame_history: Array=[]
var game

func _ready():
	name="PerformanceOverlay"
	position=Vector2(16,90)
	custom_minimum_size.x=340
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	process_mode=Node.PROCESS_MODE_ALWAYS
	z_index=20
	var style=StyleBoxFlat.new()
	style.bg_color=Color(.045,.055,.075,.92)
	style.border_color=Color(.35,.57,.62,.7)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left=12;style.content_margin_right=12
	style.content_margin_top=10;style.content_margin_bottom=10
	add_theme_stylebox_override("panel",style)
	var box=VBoxContainer.new();box.mouse_filter=Control.MOUSE_FILTER_IGNORE;box.add_theme_constant_override("separation",5);add_child(box)
	var title=_label("性能监视  /  GODOT",16);title.add_theme_color_override("font_color",Color("8bd4df"));box.add_child(title)
	var hint=_label("F4 显示 / 隐藏",11);box.add_child(hint)
	var grid=GridContainer.new();grid.columns=2;grid.mouse_filter=Control.MOUSE_FILTER_IGNORE;grid.add_theme_constant_override("h_separation",18);grid.add_theme_constant_override("v_separation",3);box.add_child(grid)
	for row in [["fps","帧率"],["frame","帧间隔 / 最慢"],["process","主循环耗时"],["physics","物理耗时 / 频率"],["draw_calls","Draw Call"],["primitives","三角面 / 图元"],["render_objects","绘制对象"],["vram","显存 · 引擎资源"],["textures","纹理显存"],["buffers","缓冲显存"],["ram","运存 · 引擎分配"],["ram_peak","运存分配峰值"],["nodes","节点 / 资源"]]:
		grid.add_child(_label(row[1],14))
		var value=_label("—",14);value.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;value.size_flags_horizontal=Control.SIZE_EXPAND_FILL;grid.add_child(value);values[row[0]]=value
	var note=_label("图元含重复绘制；内存非进程总占用\n每 0.25 秒刷新，部分引擎数据每秒更新",11)
	grid.add_child(_label("帧耗时 P95 / P99",14))
	var tail_value=_label("采样中",14);tail_value.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;grid.add_child(tail_value);values["tails"]=tail_value
	for row in [["fx_batch","特效批次 / 实例"],["fx_sleep","特效活动 / 休眠"]]:
		grid.add_child(_label(row[1],14))
		var value=_label("—",14);value.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;grid.add_child(value);values[row[0]]=value
	note.add_theme_color_override("font_color",Color("abb9c8"));box.add_child(note)
	previous_frame=Time.get_ticks_usec();sampled_at=previous_frame
	visibility_changed.connect(_reset_interval)

func _label(text: String,font_size: int) -> Label:
	var result=Label.new();result.text=text;result.mouse_filter=Control.MOUSE_FILTER_IGNORE
	result.add_theme_font_size_override("font_size",font_size);result.add_theme_color_override("font_color",Color("e8edf4"))
	return result

func _reset_interval():
	previous_frame=Time.get_ticks_usec();sampled_at=previous_frame
	frame_count=0;frame_total_usec=0;frame_max_usec=0
	frame_history.clear()

func _process(_delta: float):
	if not visible:return
	var now=Time.get_ticks_usec()
	var elapsed=now-previous_frame;previous_frame=now
	frame_history.append(elapsed/1000.0)
	if frame_history.size()>300:frame_history.pop_front()
	frame_count+=1;frame_total_usec+=elapsed;frame_max_usec=maxi(frame_max_usec,elapsed)
	if now-sampled_at<REFRESH_USEC:return
	var ordered=frame_history.duplicate();ordered.sort()
	var p95=float(ordered[mini(ordered.size()-1,int(ordered.size()*.95))]);var p99=float(ordered[mini(ordered.size()-1,int(ordered.size()*.99))])
	values.tails.text="%.1f / %.1f ms"%[p95,p99]
	values.tails.add_theme_color_override("font_color",Color("e8957d") if maxf(p95,p99)>15.0 else Color("8bd4df"))
	latest={
		"fps":int(Performance.get_monitor(Performance.TIME_FPS)),
		"frame_ms":frame_total_usec/1000.0/maxi(1,frame_count),"frame_max_ms":frame_max_usec/1000.0,
		"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,
		"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,
		"physics_hz":Engine.physics_ticks_per_second,
		"draw_calls":int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"primitives":int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"render_objects":int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"vram":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
		"textures":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),
		"buffers":Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED),
		"ram":Performance.get_monitor(Performance.MEMORY_STATIC),
		"ram_peak":Performance.get_monitor(Performance.MEMORY_STATIC_MAX),
		"nodes":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"resources":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))}
	values.fps.text="%d FPS"%latest.fps
	values.fps.add_theme_color_override("font_color",Color("8be3b0") if latest.fps>=55 else Color("ffd17c") if latest.fps>=30 else Color("ff8a8a"))
	values.frame.text="%.1f / %.1f ms"%[latest.frame_ms,latest.frame_max_ms]
	values.process.text="%.2f ms"%latest.process_ms
	values.physics.text="%.2f ms / %d Hz"%[latest.physics_ms,latest.physics_hz]
	for key in ["draw_calls","primitives","render_objects"]:values[key].text=String.num_int64(int(latest[key]))
	for key in ["vram","textures","buffers"]:values[key].text="%.1f MiB"%(latest[key]/MIB) if latest[key]>0 else "引擎未提供"
	for key in ["ram","ram_peak"]:values[key].text="%.1f MiB"%(latest[key]/MIB) if OS.is_debug_build() else "发行版未提供"
	values.nodes.text="%d / %d"%[latest.nodes,latest.resources]
	if game!=null and is_instance_valid(game.fx):
		var fx_stats: Dictionary=game.fx.batching_stats()
		values.fx_batch.text="%d / %d"%[fx_stats.batches,fx_stats.instances]
		values.fx_sleep.text="%d / %d"%[fx_stats.active,fx_stats.resting]
	if not reported and latest.fps>0 and latest.draw_calls>0 and "--startup-watch" in OS.get_cmdline_user_args():
		reported=true
		print("PERFORMANCE_OVERLAY_READY "+JSON.stringify({"visible":visible,"position":position,"size":size,"metrics":latest}))
	sampled_at=now;frame_count=0;frame_total_usec=0;frame_max_usec=0
