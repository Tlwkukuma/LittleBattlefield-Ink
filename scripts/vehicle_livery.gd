extends RefCounted
## Faction metadata and paint only. Taking a trial seat does not change ownership.
const PALETTES = {
	0:{"body":Color("799bb9"),"panel":Color("abc2d3"),"accent":Color("345f8b")},
	1:{"body":Color("b97980"),"panel":Color("d5a6a7"),"accent":Color("923f50")},
	-1:{"body":Color("929f96"),"panel":Color("bdc7b8"),"accent":Color("54675e")},
}

static func team_id(value: Variant) -> int:
	if typeof(value) in [TYPE_INT,TYPE_FLOAT]:
		return int(value) if int(value) in [0,1] else -1
	match str(value).to_lower():
		"blue","0":return 0
		"red","1":return 1
	return -1

static func key(team: int) -> String:
	return "red" if team==1 else "blue" if team==0 else "neutral"

static func label(team: int) -> String:
	return "敌方 · 红" if team==1 else "我方 · 蓝" if team==0 else "中立"

static func apply(material: ShaderMaterial, team: int) -> void:
	var palette: Dictionary=PALETTES.get(team,PALETTES[-1])
	material.set_shader_parameter("body_paint",palette.body)
	material.set_shader_parameter("panel_paint",palette.panel)
	material.set_shader_parameter("accent_paint",palette.accent)
