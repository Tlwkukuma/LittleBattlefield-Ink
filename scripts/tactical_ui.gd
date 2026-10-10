extends RefCounted
## Shared, immutable UI resources. World materials and semantic team colours stay independent.
const BACKGROUND=Color("10171c")
const PANEL=Color("182229")
const SURFACE=Color("222f38")
const HOVER=Color("304954")
const BORDER=Color("526570")
const INK=Color("edf4f6")
const MUTED=Color("a7b9c2")
const ACCENT=Color("79d5e3")
const WARNING=Color("e5bf79")
const DANGER=Color("e8957d")
static var cached_theme: Theme
static var cached_font: SystemFont
static var cached_styles: Dictionary={}
static var build_count=0

static func font_resource() -> SystemFont:
	if cached_font==null:
		cached_font=SystemFont.new()
		cached_font.font_names=PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei","Noto Sans CJK SC","PingFang SC"])
		cached_font.multichannel_signed_distance_field=false
	return cached_font

static func panel_style(role: String="panel") -> StyleBoxFlat:
	if cached_styles.has(role):return cached_styles[role]
	var box=StyleBoxFlat.new()
	box.bg_color=HOVER if role in ["hover","pressed","selected"] else SURFACE if role in ["normal","chip"] else PANEL
	box.border_color=ACCENT if role in ["hover","pressed","focus","selected"] else BORDER
	box.set_border_width_all(1);box.set_corner_radius_all(1)
	box.content_margin_left=12;box.content_margin_right=12
	box.content_margin_top=6;box.content_margin_bottom=6
	if role=="disabled":box.bg_color=BACKGROUND;box.border_color=BORDER.darkened(.4)
	if role=="focus":box.bg_color=Color.TRANSPARENT;box.set_border_width_all(2)
	cached_styles[role]=box
	return box

static func theme_resource() -> Theme:
	if cached_theme!=null:return cached_theme
	build_count+=1
	cached_theme=Theme.new();cached_theme.default_font=font_resource();cached_theme.default_font_size=15
	for type in ["Label","RichTextLabel","Button","OptionButton","CheckButton","CheckBox","LineEdit","TextEdit","ItemList","PopupMenu","TabContainer","TabBar","ProgressBar"]:
		cached_theme.set_color("font_color",type,INK)
		cached_theme.set_color("font_hover_color",type,INK)
		cached_theme.set_color("font_pressed_color",type,INK)
		cached_theme.set_color("font_focus_color",type,INK)
		cached_theme.set_color("font_disabled_color",type,MUTED.darkened(.25))
	for type in ["Button","OptionButton","CheckButton","CheckBox"]:
		for state in ["normal","hover","pressed","disabled","focus"]:cached_theme.set_stylebox(state,type,panel_style(state))
	for type in ["Panel","PanelContainer","PopupMenu","ItemList","TabContainer"]:cached_theme.set_stylebox("panel",type,panel_style())
	for type in ["LineEdit","TextEdit"]:
		for state in ["normal","focus","read_only"]:cached_theme.set_stylebox(state,type,panel_style(state))
		cached_theme.set_color("font_placeholder_color",type,MUTED)
		cached_theme.set_color("caret_color",type,ACCENT)
		cached_theme.set_color("selection_color",type,HOVER)
	for state in ["selected","selected_focus","hovered"]:cached_theme.set_stylebox(state,"ItemList",panel_style("selected"))
	cached_theme.set_color("font_selected_color","ItemList",INK)
	cached_theme.set_color("font_unselected_color","TabContainer",MUTED)
	for type in ["TabContainer","TabBar"]:
		for state in ["tab_selected","tab_hovered","tab_unselected","tab_disabled","tab_focus"]:
			cached_theme.set_stylebox(state,type,panel_style("selected" if state=="tab_selected" else "normal"))
	cached_theme.set_stylebox("background","ProgressBar",panel_style())
	var fill=panel_style("progress");fill.bg_color=ACCENT;fill.border_color=ACCENT
	cached_theme.set_stylebox("fill","ProgressBar",fill)
	return cached_theme

static func apply(control: Control) -> void:
	control.theme=theme_resource()
