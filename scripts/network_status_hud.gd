extends Label
## Two lightweight counters remain visible independently of the Debug drawer.
var game
var refresh_usec: int=-1

func _ready():
	name="NetworkStatusHUD";position=Vector2(14,12);z_index=61
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_theme_font_size_override("font_size",16)
	add_theme_color_override("font_color",Color("eef5ff"))
	add_theme_color_override("font_shadow_color",Color(0,0,0,.85))
	add_theme_constant_override("shadow_offset_x",1);add_theme_constant_override("shadow_offset_y",1)
	text="FPS --  |  Ping --"

func _process(_delta: float):
	refresh_at(Time.get_ticks_usec())

func refresh_at(now_usec: int):
	if game==null:return
	if refresh_usec>=0 and now_usec>=refresh_usec and now_usec-refresh_usec<250000:return
	refresh_usec=now_usec
	var ping=game.lan.ping_ms()
	var value="%d ms"%roundi(ping) if ping>=0 else "连接中" if game.lan.mode=="connecting" else "--"
	text="FPS %d  |  Ping %s"%[game.frames_per_second,value]
	var gap=game.lan.state_gap_ms()
	if gap>250:text+="  ·  同步等待 %d ms"%roundi(gap)
	modulate=Color("f0bd75") if gap>250 or ping>150 else Color.WHITE
