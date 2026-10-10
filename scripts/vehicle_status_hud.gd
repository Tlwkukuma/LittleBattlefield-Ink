extends RefCounted
## Compact damage panel within the existing HUD batches; no extra Control/camera.
const Durability=preload("res://scripts/vehicle_durability.gd")
const BACK=Color(.09,.12,.14,.88)
const PAPER=Color("eae6d6")

static func signature(v: Dictionary) -> String:
	return str(v.get("id",-1),v.get("type",""),v.get("health",0),v.get("max_health",0),v.get("track_health",0),v.get("max_track",0))

static func tint(hud,ratio: float,gear: bool) -> Color:
	return hud.DANGER if ratio<(.35 if gear else .30) else hud.GOLD if ratio<.68 else hud.FOCUS

static func draw(hud,v: Dictionary,health_origin: Vector2):
	if v.emplacement:
		hud.paint.quad(Rect2(health_origin+Vector2(0,-31),Vector2(230,26)),Rect2(),BACK)
		hud.text_at(health_origin+Vector2(12,-12),"炮位  %d / %d"%[v.health,v.max_health],13,PAPER)
		return
	var at=health_origin-Vector2(0,144)
	hud.paint.style(hud.card_style,Rect2(at,Vector2(270,136)))
	hud.text_at(at+Vector2(12,21),str(v.profile.label),15,PAPER,242)
	row(hud,at+Vector2(0,43),"装甲",float(v.health),float(v.max_health),false)
	if v.max_track>0:row(hud,at+Vector2(0,91),Durability.gear_name(v),float(v.track_health),float(v.max_track),true)

static func row(hud,at: Vector2,label: String,value: float,maximum: float,gear: bool):
	var ratio=clampf(value/maxf(1,maximum),0,1);var color=tint(hud,ratio,gear)
	hud.text_at(at+Vector2(40,0),label,15,PAPER)
	var numbers="%d / %d"%[ceili(maxf(0,value)),int(maximum)]
	var width=hud.get_theme_default_font().get_string_size(numbers,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x
	hud.text_at(at+Vector2(256-width,0),numbers,16,color)
	hud.paint.quad(Rect2(at+Vector2(40,9),Vector2(216,6)),Rect2(),Color("363d40"))
	hud.paint.quad(Rect2(at+Vector2(40,9),Vector2(216*ratio,6)),Rect2(),color)
	hud.text_at(at+Vector2(40,31),Durability.condition(ratio,gear),12,color)
	if not hud.paint.enabled:return
	var center=at+Vector2(23,6)
	if not gear:
		var outline=PackedVector2Array([center+Vector2(-8,-13),center+Vector2(8,-13),center+Vector2(8,1),center+Vector2(0,9),center+Vector2(-8,1)])
		for i in range(outline.size()):hud.paint.line(outline[i],outline[(i+1)%outline.size()],color,1.5,true)
	elif label=="轮胎":
		hud.paint.arc(center,9,0,TAU,16,color,2,true)
		hud.paint.arc(center,4,0,TAU,12,color,1.5,true)
	else:
		var outline=PackedVector2Array([center+Vector2(-10,-8),center+Vector2(7,-8),center+Vector2(11,-3),center+Vector2(7,5),center+Vector2(-7,5),center+Vector2(-11,0)])
		for i in range(outline.size()):hud.paint.line(outline[i],outline[(i+1)%outline.size()],color,1.5,true)
		for x in [-5,1,6]:hud.paint.arc(center+Vector2(x,-1),2.3,0,TAU,8,color,1,true)
