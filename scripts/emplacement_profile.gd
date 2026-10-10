extends RefCounted
## Fixed weapons have exposed operators and their own mechanism/pose timing.
const CASE_EJECT_PHASE=.22

static func operator_offset(kind: String) -> Vector3:
	if kind=="portableMortar":return Vector3(-.56,0,-.05)
	return Vector3(-.87,0,.67) if kind=="fieldGun" else Vector3(0,0,.78)

static func operator_position(v: Dictionary, angle: float = INF) -> Vector2:
	var offset=operator_offset(v.type).rotated(Vector3.UP,-(v.turret_angle if is_inf(angle) else angle)-PI*.5)
	return v.position+Vector2(offset.x,offset.z)

static func pulse(age: float, rise: float, settle: float) -> float:
	if age<0 or age>=settle:return 0.0
	if age<rise:return sin(age/rise*PI*.5)
	var t=(age-rise)/(settle-rise)
	return (1.0-t)*(1.0-t)*(1.0+2.0*t)

static func response(v: Dictionary, time: float) -> Dictionary:
	var cannon: bool=v.type=="fieldGun"
	var age: float=time-float(v.get("shot_time",-100.0))
	var state: Dictionary=v.states[v.modes[v.mode]]
	var reload_phase=clampf(1.0-float(state.reload)/maxf(.05,float(state.reload_duration)),0,1)
	return {"age":age,"slide":pulse(age,.045 if cannon else .014,.68 if cannon else .105)*(.29 if cannon else .012),
		"body":pulse(age-(.035 if cannon else .012),.085 if cannon else .025,.88 if cannon else .17),
		"reload":reload_phase,"loading":float(state.reload)>0,"cannon":cannon}

static func dimensions(kind: String) -> Dictionary:
	if kind=="portableMortar":return {"model_scale":Vector3.ONE,"half":Vector2(.65,.28),"deck":.05,"top":1.03,"turret":Vector2(.65,.1),"cabin":false}
	if kind=="fieldGun":
		return {"model_scale":Vector3.ONE,"half":Vector2(1.68,.85),"deck":.34,"top":1.26,"turret":Vector2(.70,.63),"cabin":false}
	return {"model_scale":Vector3.ONE,"half":Vector2(.53,.47),"deck":.18,"top":1.22,"turret":Vector2(.55,.20),"cabin":false}

static func hit_boxes(v: Dictionary) -> Array:
	if not v.has("emplacement_boxes"):
		var shapes: Array=[]
		if v.type=="portableMortar":
			shapes.append({"offset":Vector2(-.02,0),"yaw":0.0,"moving":true,"half":Vector2(.19,.22),"bottom":0.0,"top":.05})
			for i in range(5):
				shapes.append({"offset":Vector2(-.10+i*.16,0),"yaw":0.0,"moving":true,"half":Vector2(.11,.085),"bottom":.04+i*.18,"top":.30+i*.18})
		elif v.type=="fieldGun":
			shapes.append({"offset":Vector2(-.02,0),"yaw":0.0,"moving":false,"half":Vector2(.42,.77),"bottom":.02,"top":.85})
			for side in [-1,1]:
				var a=Vector2(-.16,side*.22);var b=Vector2(-1.51,side*.51)
				shapes.append({"offset":(a+b)*.5,"yaw":(b-a).angle(),"moving":false,"half":Vector2(a.distance_to(b)*.5,.085),"bottom":.04,"top":.35})
				shapes.append({"offset":Vector2(.25,side*.36),"yaw":0.0,"moving":true,"half":Vector2(.065,.24),"bottom":.55,"top":1.26})
			shapes.append({"offset":Vector2(0,0),"yaw":0.0,"moving":true,"half":Vector2(.57,.19),"bottom":.70,"top":1.29})
		else:
			shapes.append({"offset":Vector2(0,0),"yaw":0.0,"moving":false,"half":Vector2(.52,.47),"bottom":0.0,"top":.16})
			shapes.append({"offset":Vector2(0,0),"yaw":0.0,"moving":false,"half":Vector2(.08,.08),"bottom":.16,"top":1.06})
			shapes.append({"offset":Vector2(.04,0),"yaw":0.0,"moving":true,"pitch":true,"half":Vector2(.30,.13),"bottom":1.04,"top":1.25})
			shapes.append({"offset":Vector2(.025,-.30),"yaw":0.0,"moving":true,"half":Vector2(.19,.14),"bottom":.875,"top":1.16})
		v.emplacement_boxes=shapes
	for box in v.emplacement_boxes:
		if not box.has("local_bottom"):box.local_bottom=box.bottom;box.local_top=box.top
		box.bottom=box.local_bottom+float(v.get("elevation",0));box.top=box.local_top+float(v.get("elevation",0))
		if box.get("pitch",false):
			if not box.has("local_half"):box.local_half=box.half;box.local_offset=box.offset
			var pitch=float(v.get("gun_pitch",0));var cs=cos(pitch);var sn=sin(pitch)
			var half_height=(float(box.local_top)-float(box.local_bottom))*.5
			var y=(float(box.local_top)+float(box.local_bottom))*.5-1.16
			var height=1.16+sn*box.local_offset.x+cs*y+float(v.get("elevation",0))
			var extent=absf(sn)*box.local_half.x+absf(cs)*half_height
			box.offset=Vector2(cs*box.local_offset.x-sn*y,box.local_offset.y)
			box.half=Vector2(absf(cs)*box.local_half.x+absf(sn)*half_height,box.local_half.y)
			box.bottom=height-extent;box.top=height+extent
		var angle: float=v.turret_angle if box.moving else v.angle
		box.center=v.position+box.offset.rotated(angle);box.angle=angle+box.yaw
	return v.emplacement_boxes
