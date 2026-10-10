extends Node3D
const Profile=preload("res://scripts/combat_feedback_profile.gd")
var world
var camera: Camera3D
var audio
var camera_power=0.0
var camera_born=-100.0
var camera_scale=.5
var frame=-1
var impact_count=0
var muted=false

func _ready():
	audio=preload("res://scripts/combat_audio.gd").new();audio.world=world;audio.camera=camera;add_child(audio);set_process(false)

func camera_kick(power: float):
	var live=camera_power*clampf(1-(float(world.time)-camera_born)/.18,0,1)
	camera_power=minf(2.0,maxf(power,live));camera_born=world.time

func camera_offset() -> Vector2:
	var age=float(world.time)-camera_born
	if age<0 or age>.18:return Vector2.ZERO
	return Vector2(sin(age*48),sin(age*37)*.65)*camera_power*camera_scale*pow(1-age/.18,2)

func allow_impact(e: Dictionary) -> bool:
	if Vector2(e.position).distance_squared_to(world.player.position)>40*40:return false
	var at=Vector3(e.position.x,e.height,e.position.y)
	if camera!=null and (camera.is_position_behind(at) or not get_viewport().get_visible_rect().grow(80).has_point(camera.unproject_position(at))):return false
	var current=Engine.get_process_frames()
	if current!=frame:frame=current;impact_count=0
	if impact_count>=(10 if int(e.get("source_id",-1))==int(world.player.id) else 6):return false
	impact_count+=1;return true

func handle(e: Dictionary):
	audio.muted=muted
	match str(e.type):
		"repair","player_changed":audio.clear();camera_born=-100.0
		"shot":
			var p=Profile.profile(e.weapon);var local=bool(e.unit.player)
			if e.weapon.kind in ["grenade","melee"]:return
			audio.play_shot(e)
			if local and float(p.camera)>0:camera_kick(p.camera)
		"damage":
			if float(e.amount)<=0:return
			var ours=int(e.get("source_id",-1))==int(world.player.id);var hurt=bool(e.unit.player)
			var fatal=bool(e.get("fatal",false));var local=ours or hurt
			audio.play("flesh",e.point,4.0 if local else 1.0,.85 if fatal else 1.08,.72 if local else .43,local,("fatal/" if fatal else "flesh/")+str(e.unit.id))
		"impact":
			var key=Profile.material(str(e.material))
			if key=="flesh":return
			var at=Vector3(e.position.x,e.height,e.position.y);var local=int(e.get("source_id",-1))==int(world.player.id)
			var pitch={"wood":.78,"earth":.63,"stone":.96,"metal":1.08,"glass":1.32}.get(key,1.0)
			var gate="impact/%s/%s/%s"%[key,roundi(at.x*2),roundi(at.z*2)]
			audio.play(key,at,2.5 if local else .6,pitch,.55,local,gate)
		"explosion":
			if e.get("weapon",{}).get("vehicle_detonation",false):return
			var distance: float=e.position.distance_to(world.player.position);var at=Vector3(e.position.x,e.height,e.position.y)
			audio.play("blast",at,3.0,clampf(1.15-float(e.radius)*.055,.66,1.18),.95,false,"blast/%s/%s"%[roundi(at.x),roundi(at.z)])
			if distance<14:camera_kick(minf(2.0,float(e.radius)*.35)*(1-distance/14))
		"vehicle_destroyed":
			var v: Dictionary=e.vehicle;var at=Vector3(v.position.x,float(v.get("elevation",0))+.5,v.position.y)
			audio.play("blast",at,3.5,.72,1.15,false,"wreck/"+str(v.id))
		"melee_swing":audio.play("swing",e.get("point",Vector3.ZERO),1.0,1.0,.6,false)
		"melee_contact":audio.play("melee",e.get("point",Vector3.ZERO),2.0,1.0,.7,false)
