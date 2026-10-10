extends RefCounted
## Authored capture footprint shared by presence, world boundary and HUD.
static func contains(point: Dictionary,at: Vector2,elevation: float) -> bool:
	if absf(elevation-float(point.get("elevation",0)))>float(point.get("capture_height",1.8)):return false
	var polygon: PackedVector2Array=point.get("zone",PackedVector2Array())
	return Geometry2D.is_point_in_polygon(at,polygon) if polygon.size()>=3 else at.distance_squared_to(point.position)<=point.radius*point.radius

static func color(point: Dictionary) -> Color:
	return Color("628ab0") if float(point.progress)>.001 else Color("bd6968") if float(point.progress)<-.001 else Color("b8b6a7")

static func state(point: Dictionary) -> String:
	if point.contested:return "争夺中"
	if point.owner==0:return "我方控制"
	if point.owner==1:return "敌方控制"
	if point.blue>0:return "清除敌方控制" if point.progress<0 else "占领中"
	if point.red>0:return "敌军占领中"
	return "中立" if is_zero_approx(point.progress) else "未完全控制"
