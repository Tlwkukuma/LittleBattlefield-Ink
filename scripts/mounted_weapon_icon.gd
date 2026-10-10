extends RefCounted
## Small shared silhouettes for mount channels, which have no handheld atlas entry.
static func draw(canvas: CanvasItem,w: Dictionary,at: Vector2,extent: Vector2,color: Color):
	var kind=str(w.get("kind","bullet"));var scale=minf(extent.x/84.0,extent.y/32.0)
	var body=Rect2(at+Vector2(-24,-6)*scale,Vector2(31,12)*scale)
	if kind in ["vehicleMortar","mortar"]:
		canvas.draw_line(at+Vector2(-22,12)*scale,at+Vector2(6,-13)*scale,color,7*scale,true)
		canvas.draw_line(at+Vector2(-30,13)*scale,at+Vector2(1,13)*scale,color,3*scale,true)
		canvas.draw_line(at+Vector2(-6,-2)*scale,at+Vector2(12,13)*scale,color,2*scale,true)
		return
	canvas.draw_rect(body,color,false,maxf(1,2*scale))
	var cannon=kind in ["shell","canister"]
	canvas.draw_line(at+Vector2(7,0)*scale,at+Vector2(38,0)*scale,color,(7 if cannon else 3)*scale,true)
	if cannon:
		canvas.draw_line(at+Vector2(37,-5)*scale,at+Vector2(37,5)*scale,color,3*scale,true)
		canvas.draw_line(at+Vector2(-5,7)*scale,at+Vector2(-17,14)*scale,color,3*scale,true)
		if kind=="canister":
			for y in [-7,0,7]:canvas.draw_circle(at+Vector2(45,y)*scale,1.5*scale,color)
	elif kind=="vehicleGrenade":
		canvas.draw_circle(at+Vector2(-9,9)*scale,6*scale,color)
		canvas.draw_rect(Rect2(at+Vector2(13,-5)*scale,Vector2(17,10)*scale),color,false,maxf(1,2*scale))
	else:
		canvas.draw_line(at+Vector2(-16,6)*scale,at+Vector2(-19,14)*scale,color,4*scale,true)
		canvas.draw_line(at+Vector2(-25,0)*scale,at+Vector2(-35,0)*scale,color,4*scale,true)
		canvas.draw_rect(Rect2(at+Vector2(-4,6)*scale,Vector2(9,8)*scale),color,false,maxf(1,2*scale))
		if kind=="autocannon":
			for x in [14,22,30]:canvas.draw_line(at+Vector2(x,-4)*scale,at+Vector2(x,4)*scale,color,2*scale,true)
