extends CanvasLayer
## A real, independent canvas: no simulation or partial world is needed to draw it.
signal cancel_requested
signal retry_requested
signal home_requested
signal exit_requested
const BUDGET_USEC=6000
const TIMEOUT_MSEC=120000
var content: VBoxContainer
var panel: ColorRect
var title: Label
var detail: Label
var progress: ProgressBar
var cancel_button: Button
var retry_button: Button
var home_button: Button
var state="idle"
var stage_name=""
var completed=0
var total=0
var started=0
var slice_started=0
var cancelled=false
var failure=""
var drawn=false
var events: Array=[]

func _ready():
	name="CampaignLoading";layer=100
	panel=ColorRect.new();panel.color=Color("17232f");panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(panel)
	if ResourceLoader.exists("res://scripts/tactical_ui.gd"):
		var styling=load("res://scripts/tactical_ui.gd");styling.apply(panel);panel.color=styling.PANEL
	var center=CenterContainer.new();center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);panel.add_child(center)
	var box=VBoxContainer.new();content=box;center.add_child(box)
	panel.resized.connect(_layout)
	call_deferred("_layout")
	title=Label.new();title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;title.name="LoadingTitle";title.text="正在准备战场";title.add_theme_font_size_override("font_size",28);box.add_child(title)
	detail=Label.new();detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;detail.name="LoadingDetail";box.add_child(detail)
	progress=ProgressBar.new();progress.name="LoadingProgress";progress.show_percentage=false;box.add_child(progress)
	var buttons=HBoxContainer.new();box.add_child(buttons)
	cancel_button=_button(buttons,"取消",func():cancelled=true;cancel_requested.emit())
	retry_button=_button(buttons,"重试",func():retry_requested.emit())
	home_button=_button(buttons,"返回首页",func():home_requested.emit())
	_button(buttons,"退出游戏",func():exit_requested.emit())
	hide()

func _button(parent: Node,text: String,callback: Callable) -> Button:
	var result=Button.new();result.clip_text=true;result.size_flags_horizontal=Control.SIZE_EXPAND_FILL;result.custom_minimum_size.x=72;result.text=text;result.pressed.connect(callback);parent.add_child(result);return result

func _layout():
	if content!=null:content.custom_minimum_size.x=maxf(0,minf(520,panel.size.x-32))

func begin(label_text: String):
	state="loading";stage_name="";cancelled=false;failure="";drawn=false;events.clear();started=Time.get_ticks_msec();slice_started=Time.get_ticks_usec()
	title.text=label_text;retry_button.text="重试";retry_button.hide();home_button.show();cancel_button.show();show()
	update_stage("等待加载画面",0,0)

func update_stage(label_text: String,done: int,count: int):
	if stage_name!=label_text:
		if not events.is_empty():
			events[-1].finished_ms=Time.get_ticks_msec()-started
			print("CAMPAIGN_LOADING_DONE "+JSON.stringify(events[-1]))
		stage_name=label_text
		var event={"stage":stage_name,"elapsed_ms":Time.get_ticks_msec()-started,"done":done,"total":count}
		events.append(event)
		if events.size()>128:events.pop_front()
		print("CAMPAIGN_LOADING "+JSON.stringify(event))
	if not events.is_empty():events[-1].done=done;events[-1].total=count
	completed=done;total=count
	detail.text="%s  %d / %d"%[stage_name,done,count] if count>0 else stage_name
	progress.max_value=maxi(1,count);progress.value=done

func should_yield() -> bool:
	return Time.get_ticks_usec()-slice_started>=BUDGET_USEC

func valid() -> bool:
	if Time.get_ticks_msec()-started>TIMEOUT_MSEC:failure="加载超时，请重试";return false
	return not cancelled and failure.is_empty()

func fail(reason: String):
	state="cancelled" if cancelled else "failed";failure=reason;title.text="加载已取消" if cancelled else "加载失败"
	detail.text=reason;cancel_button.hide();retry_button.show();show()

func finish():
	print("CAMPAIGN_LOADING_READY "+JSON.stringify({"elapsed_ms":Time.get_ticks_msec()-started,"stages":events,"drawn":drawn}))
	state="ready";hide()
