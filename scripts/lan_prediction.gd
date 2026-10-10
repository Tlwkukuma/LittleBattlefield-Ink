extends RefCounted
## Predict only the occupied soldier's presentation with the existing collision solver.
const Traversal=preload("res://scripts/soldier_traversal.gd")
var session
var unit: Dictionary={}
var pending: Array=[]
var last_ack=-1
var correction=Vector3.ZERO
var replaying=false
var enabled=false
var max_error=0.0

func reset():
	clear_presentation()
	unit={};pending.clear();last_ack=-1;correction=Vector3.ZERO;enabled=false

func clear_presentation():
	if unit.is_empty():return
	var world=session.game.world
	var id=int(unit.id)
	if id>=0 and id<world.units.size():world.units[id].erase("net_predicted_position")
	var mount=int(unit.mounted)
	if mount>=0 and mount<world.vehicles.size():
		world.vehicles[mount].erase("net_predicted_turret");world.vehicles[mount].erase("net_predicted_aim")

func submit(control: Dictionary,delta: float):
	if not enabled or unit.is_empty():return
	pending.append({"sequence":int(control._sequence),"control":control.duplicate(false),"delta":delta})
	if pending.size()>30:pending.pop_front()
	if unit.mounted>=0:
		var vehicle: Dictionary=session.game.world.vehicles[int(unit.mounted)]
		var aim: Vector2=control.get("aim",vehicle.position+Vector2.from_angle(vehicle.turret_angle)*8)
		var desired=(aim-vehicle.position).angle()
		if vehicle.emplacement:desired=vehicle.angle+clampf(wrapf(desired-vehicle.angle,-PI,PI),-float(vehicle.profile.traverse),float(vehicle.profile.traverse))
		vehicle.net_predicted_turret=rotate_toward(float(vehicle.get("net_predicted_turret",vehicle.turret_angle)),desired,float(vehicle.profile.get("turretTurnRate",vehicle.profile.get("turnRate",1)))*delta)
		vehicle.net_predicted_aim=Vector3(aim.x,float(control.get("aim_height",unit.aim_height)),aim.y)
	advance(control,delta)
	publish()

func advance(control: Dictionary,delta: float):
	if not unit.alive or unit.mounted>=0 or not unit.get("vehicle_flight",{}).is_empty():return
	unit.aiming=bool(control.get("aiming",false))
	var target: Vector2=control.get("aim",unit.position+unit.facing*8)
	if unit.position.distance_squared_to(target)>.12:
		unit.facing=Vector2.from_angle(rotate_toward(unit.facing.angle(),(target-unit.position).angle(),delta*18))
	unit.aim_point=target
	unit.jump_cooldown=maxf(0,float(unit.jump_cooldown)-delta)
	unit.landing=maxf(0,float(unit.landing)-delta)
	unit.stance_blend=move_toward(unit.stance_blend,float(unit.stance),delta*(2.4 if unit.stance==2 else 3.0))
	var sprint=bool(control.get("sprint",false)) and not unit.aiming and not bool(control.get("trigger",false)) and unit.reload<=0 and unit.get("throw_state",{}).is_empty() and unit.get("melee",{}).is_empty() and unit.get("healing",{}).is_empty()
	Traversal.move(session.game.world,unit,control.get("movement",Vector2.ZERO),delta,sprint,bool(control.get("jump",false)))

func reconcile(authority: Dictionary,ack: int):
	if ack<last_ack:return
	var previous=visual_position() if not unit.is_empty() else Vector3(authority.position.x,authority.elevation,authority.position.y)
	var changed=unit.is_empty() or int(unit.id)!=int(authority.id) or int(unit.mounted)!=int(authority.mounted) or bool(unit.alive)!=bool(authority.alive)
	if changed:clear_presentation()
	unit=authority.duplicate(true);unit.erase("net_predicted_position");unit.erase("net_motion_received_usec")
	last_ack=ack;enabled=true
	while not pending.is_empty() and int(pending[0].sequence)<=ack:pending.pop_front()
	if changed:pending.clear()
	replaying=true
	for input in pending:advance(input.control,float(input.delta))
	replaying=false
	var next=Vector3(unit.position.x,unit.elevation,unit.position.y)
	var error=previous-next;max_error=maxf(max_error,error.length())
	correction=Vector3.ZERO if changed or error.length()>1.5 else error
	publish()

func tick(delta: float):
	correction*=exp(-delta*22)
	publish()

func visual_position() -> Vector3:
	return Vector3(unit.position.x,unit.elevation,unit.position.y)+correction if not unit.is_empty() else Vector3.ZERO

func publish():
	if not enabled or unit.is_empty() or session.assigned_unit!=int(unit.id):return
	var actual: Dictionary=session.game.world.units[int(unit.id)]
	if unit.mounted<0 and unit.alive:actual.net_predicted_position=visual_position()
	else:actual.erase("net_predicted_position")

func render_unit(authority: Dictionary) -> Dictionary:
	if not enabled or unit.is_empty() or int(unit.id)!=int(authority.id):return authority
	# Current combat fields belong to the host; movement and aim are presented locally.
	for key in ["health","ammo","reserve","reload","cooldown","weapon_id","alive","inventory","loadout","shot_index","last_shot","flash","hurt","healing","throw_state","melee","reaction"]:
		if authority.has(key):unit[key]=authority[key]
	unit.net_predicted_position=visual_position()
	return unit
