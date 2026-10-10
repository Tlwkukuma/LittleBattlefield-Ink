extends RefCounted
## Presentation only: a short camera-readable exposure, not a second ballistic path.
const Ammo=preload("res://scripts/ammo_presentation.gd")
const Weapon=preload("res://scripts/weapon_profile.gd")
static var profiles: Dictionary={}
static func supports(w: Dictionary) -> bool:return w.kind in ["bullet","hitscan","autocannon","canister"]
static func profile(w: Dictionary) -> Dictionary:
	var wp=Weapon.get_profile(w);var a: Dictionary=wp.ammo_visual
	var key=str(w.get("mounted_fire_key",w.get("id",w.get("name",str(w.get("label",w.kind))+"/"+str(w.get("projectileSpeed",0))))))
	if profiles.has(key):return profiles[key]
	# Duckov's ordinary prefab trails retain about .04 / .06 s. Here a compact
	# exposure is capped in pixels too, preserving readability without long ropes.
	var p={"seconds":.035,"width":maxf(5.2,float(a.pixels)+.8),"pixels":25.0,"limit":.90,"color":Color("f5b16b"),"head":.27,"fade":.036}
	if wp.family in ["pistol","smg"]:p.seconds=.040;p.pixels=19.0;p.limit=.64;p.color=Color("f3b56e")
	if wp.family=="sniper":p.seconds=.032;p.pixels=33.0;p.limit=1.20;p.color=Color("ffd292");p.width+=.35
	if w.kind=="autocannon":p.limit=1.25;p.pixels=31.0;p.color=Color("ffc584")
	if a.round_shape=="pellet":p.seconds=.012;p.width=3.7;p.pixels=6.3;p.limit=.16;p.color=Color("e6dec5");p.head=.75;p.fade=.026
	elif a.round_shape=="slug":p.seconds=.022;p.width=6.0;p.pixels=15.0;p.limit=.40;p.color=Color("ffe1a5");p.head=.42
	if a.round_shape not in ["pellet","slug"]:
		p.width=wp.flight_pixels;p.pixels=wp.flight_length;p.color=wp.flight_color
		p.limit=1.10 if w.kind=="autocannon" else .85
		p.head=.35 if wp.flight_identity=="127" else .42 if w.kind=="autocannon" else .27
	if w.kind=="canister":
		p.width=wp.flight_pixels;p.pixels=wp.flight_length;p.color=wp.flight_color;p.limit=.20;p.seconds=.014;p.head=.75
	if wp.suppressed:p.color=p.color.lerp(Color("e1d4ba"),.30)
	profiles[key]=p;return p

static func at(p: Dictionary) -> Vector3:return Vector3(p.position.x,p.height,p.position.y)
static func start(p: Dictionary) -> Vector3:return Vector3(p.origin.x,p.start_height,p.origin.y)
static func head(p: Dictionary,blend: float) -> Vector3:
	if p.has("net_render_head"):return p.net_render_head
	var previous=Vector3(p.previous.x,p.previous_height,p.previous.y)
	return previous.lerp(at(p),presentation_blend(p,blend))

static func presentation_blend(p: Dictionary,physics_blend: float) -> float:
	if p.has("net_received_usec"):
		return clampf((Time.get_ticks_usec()-int(p.net_received_usec))/1000000.0/maxf(.001,float(p.get("net_interval",.1))),0,1)
	return clampf(physics_blend,0,1)

static func geometry(p: Dictionary,where: Vector3,camera_basis: Basis,pixel: float) -> Dictionary:
	var style=profile(p.weapon);var distance=where.distance_to(start(p))
	if distance<.008:return {}
	var direction=Vector3(p.direction.x,float(p.get("slope",0)),p.direction.y).normalized()
	if direction.length_squared()<.5:return {}
	var projected=sqrt(pow(direction.dot(camera_basis.x),2)+pow(direction.dot(camera_basis.y),2))
	var width=maxf(.035,pixel*float(style.width))
	var speed=float(p.get("speed",Weapon.get_profile(p.weapon).speed))*sqrt(1+pow(float(p.get("slope",0)),2))
	var length=minf(float(style.limit),minf(speed*float(style.seconds),pixel*float(style.pixels)/maxf(.50,projected)))
	length=minf(float(style.limit),minf(distance,maxf(width*.9,length)))
	var side=direction.cross(camera_basis.z).normalized();var back=-direction
	# End-on shots use a compact bright oval; never stretch to infinite length.
	if projected<.14:
		side=camera_basis.x;back=camera_basis.y;length=minf(float(style.limit),minf(width*1.05,distance))
	var normal=side.cross(back).normalized()
	return {"pose":Transform3D(Basis(side*width,back*length,normal),where),"width":width,"length":length,"style":style}
