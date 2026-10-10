extends RefCounted
const Art=preload("res://scripts/ink_art.gd")
const Geometry=preload("res://scripts/special_weapon_geometry.gd")
const Batch=preload("res://scripts/mesh_batch.gd")

static func node(parent: Node3D,title: String,at: Vector3=Vector3.ZERO) -> Node3D:
	var result=Node3D.new();result.name=title;result.position=at;parent.add_child(result);return result

static func build(parent: Node3D,v: Dictionary) -> Dictionary:
	var root=node(parent,"DeployedMortar");var body=node(root,"Base");var turret=node(root,"Traverse")
	var barrel=node(turret,"Mortar",Vector3(0,.23,0))
	Geometry.build(barrel,v.profile);Batch.collapse(barrel,[],"deployed_mortar")
	var socket=node(barrel,"MuzzleSocket",barrel.get_meta("primary_muzzle"));socket.rotation.x=PI*.5-.65
	var left=node(turret,"LeftGrip",Vector3(-.15,.66,-.16));var right=node(turret,"RightGrip",Vector3(-.07,.75,-.37))
	var load_left=node(turret,"ReloadLeft",left.position)
	var load_right=node(turret,"ReloadRight",Vector3(0,1.10,-.59))
	Geometry.reload_round(turret,v.profile)
	var round=turret.get_node("ReloadRound");Batch.collapse(round,[],"deployed_mortar_round")
	var flash=Art.sphere(socket,Vector3(0,0,-.08),.10,Color("ffe0a5"),Vector3(.8,.8,1.5));flash.hide()
	return {"root":root,"body":body,"turret":turret,"barrel":barrel,"wheels":[],"emplacement":true,
		"grips":[left,right],"reload_left":load_left,"reload_right":load_right,"loading_round":round,
		"muzzle_socket":socket,"muzzle":flash,"ejection_socket":node(barrel,"NoEjection"),"mechanism":node(turret,"Lock")}

static func update(view: Dictionary,v: Dictionary,time: float):
	view.root.position=Vector3(v.position.x,v.elevation,v.position.y)
	view.turret.rotation=Vector3(0,-v.turret_angle-PI*.5,.6 if v.destroyed else 0)
	view.muzzle.visible=v.flash>0 and not v.destroyed
	var state: Dictionary=v.states.primary
	var phase=clampf(1-float(state.reload)/maxf(.05,float(state.reload_duration)),0,1)
	var loading=state.reload>0 and phase>.25 and phase<.78 and not v.destroyed and v.driver
	view.loading_round.visible=loading
	var feed=Vector3(0,1.14,-.59).lerp(Vector3(0,.99,-.59),smoothstep(.58,.78,phase))
	view.loading_round.position=feed;view.loading_round.rotation.x=PI*.5-.65
	view.reload_right.position=feed+Vector3(-.045,.035,.025)
