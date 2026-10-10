extends SceneTree
## Native Control layout only, no World, gameplay or 3D scene construction.
const Presentation=preload("res://scripts/campaign_presentation.gd")
const Chapters=preload("res://scripts/campaign_catalog.gd")
var checks=0
var failures=0
func check(value: bool,label: String):
	checks+=1
	if not value:failures+=1;printerr("FAIL "+label)
func _initialize():call_deferred("run")
func run():
	for width in [960,1178,1440]:
		var ui=Control.new();root.add_child(ui);ui.size=Vector2(width,814)
		var font=SystemFont.new();font.font_names=PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei","Noto Sans CJK SC","PingFang SC"])
		var theme=Theme.new();theme.default_font=font;theme.default_font_size=15
		var style=StyleBoxFlat.new();style.content_margin_left=14;style.content_margin_right=14;style.content_margin_top=12;style.content_margin_bottom=12;theme.set_stylebox("panel","PanelContainer",style);ui.theme=theme
		var panel=PanelContainer.new();ui.add_child(panel);panel.anchor_left=1;panel.anchor_right=1;panel.offset_left=-326;panel.offset_right=-16;panel.offset_top=58;panel.offset_bottom=790
		var scroll=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;panel.add_child(scroll)
		var box=VBoxContainer.new();box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(box)
		var heading=Label.new();heading.add_theme_font_size_override("font_size",20);box.add_child(heading);Presentation.configure_equipment_heading(heading)
		var controls=[]
		for name in ["M416","P92","Army Knife","HE Grenade"]:
			var row=HBoxContainer.new();box.add_child(row)
			var button=Button.new();button.text=name;button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(button);controls.append(button)
			var choice=OptionButton.new();choice.custom_minimum_size.x=95;choice.add_item(name);row.add_child(choice);controls.append(choice)
		for chapter in Chapters.chapters():
			heading.text="第 %02d 关 · %s · 随身装备"%[int(chapter.id),chapter.title]
			for frame in range(3):await process_frame
			check(panel.get_global_rect().end.x<=width-15,"chapter%d panel fits width%d"%[chapter.id,width])
			check(heading.size.x<=282 and heading.size.y>=20,"heading wraps within existing panel")
			for control in controls:check(control.get_global_rect().end.x<=width-15,"equipment remains inside window")
		ui.queue_free();await process_frame
	print("campaign_heading_layout_contract: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
