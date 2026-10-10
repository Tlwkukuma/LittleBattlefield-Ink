extends RefCounted
const Particle=preload("res://scripts/fx_particle_state.gd")
## Lightweight cosmetic motion; no rigid bodies and no gameplay collision changes.
var sweep_budget: int=12

func begin_frame():sweep_budget=12

static func extent(node: Node3D) -> float:
	# Case meshes occupy the unit cylinder along local Z.
	var basis: Basis=node.basis
	return (absf(basis.x.y)+absf(basis.y.y)+absf(basis.z.y))*.5

static func soften(material: String) -> float:
	if "snow" in material or "sand" in material:return .25
	if "grass" in material or "jungle" in material or "mud" in material:return .42
	if "dirt" in material or "red" in material:return .60
	return 1.0

static func resting_orientation(basis: Basis) -> Quaternion:
	var axis: Vector3=basis.z;var yaw: float=atan2(axis.x,axis.z)
	return Quaternion.from_euler(Vector3(0,yaw,0))

func advance(p: Dictionary,delta: float,world) -> Dictionary:
	var state:=Particle.new(p);var contact:=advance_particle(state,delta,world)
	state.motion_to_dictionary(p);return contact

func advance_particle(p: Particle,delta: float,world) -> Dictionary:
	var node: Node3D=p.node;var data: Dictionary=p.presentation
	if not p.motion_initialized:
		p.settled=false;p.rolling=false;p.bounces=0;p.support_age=0.0;p.floor=node.position.y-1.0;p.softness=1.0
		p.motion_initialized=true
	p.support_age+=delta
	if p.settled:
		# Resting cases wake if their support is destroyed; otherwise sleep.
		if world!=null and p.support_age>.22:
			p.support_age=0.0
			var support: float=world.ground_height(Vector2(node.position.x,node.position.z),.025,node.position.y+.04)
			if support<float(p.floor)-.035:p.settled=false;p.rolling=false;p.gravity=9.8
			p.floor=support
		if p.settled:
			node.position.y=float(p.floor)+extent(node)+.008
			return {}
	# Keep the original Node3D Euler/quaternion setters (including their continuity)
	# but do integration in typed local values, not repeated Variant sub-properties.
	var old: Vector3=node.position;var velocity: Vector3=p.velocity;var spin: Vector3=p.spin
	var rolling: bool=p.rolling
	if not rolling:velocity.y-=float(p.gravity)*delta
	var next: Vector3=old+velocity*delta
	var step: Vector3=next-old
	if world!=null and not rolling and step.length_squared()>.00001 and sweep_budget>0:
		sweep_budget-=1
		var collision: Dictionary=world.trace_3d(old,step.normalized(),step.length(),{},true)
		if not collision.is_empty() and collision.type!="terrain":
			# A short reverse and damping keep empty cases off walls/vehicle hulls.
			next=old+step.normalized()*maxf(0,float(collision.distance)-.015)
			velocity.x*=-.30;velocity.z*=-.30;spin*=.55
	if not rolling:node.rotation+=spin*delta
	var floor_height: float=world.ground_height(Vector2(next.x,next.z),.025,maxf(old.y,next.y)+.04) if world!=null else 0.0
	p.floor=floor_height
	var top: float=floor_height+extent(node)+.008
	if rolling and next.y>top+.08:
		rolling=false;p.rolling=false;p.gravity=9.8
	if not rolling and next.y>top:
		node.position=next;p.velocity=velocity;p.spin=spin;return {}
	var surface: String="concrete"
	if world!=null and absf(floor_height-world.terrain.height(Vector2(next.x,next.z)))<.08:
		surface=world.terrain.material_at(Vector2(next.x,next.z))
	var softness: float=soften(surface);p.softness=softness
	var impact: float=absf(velocity.y);var sound: Dictionary={}
	if not rolling:
		var bounces: int=int(p.bounces)+1;p.bounces=bounces
		if impact>.65 and bounces<=2:
			sound={"pitch":float(data.get("sound_pitch",1.0))*(.94 if bounces==2 else 1.0),
				"gain":lerpf(.12,.65,softness)*clampf(impact/2.4,.2,1.0)*(1.0 if bounces==1 else .4),
				"key":"case_soft" if data.case_shape=="shell" or softness<.7 else "case"}
		velocity.y=impact*float(data.get("bounce",.25))*softness
		var ground_drag: float=data.get("ground_drag",.52)
		velocity.x*=ground_drag;velocity.z*=ground_drag;spin*=float(data.get("spin_drag",.42))
		if velocity.y<.45 or bounces>=3:
			rolling=true;p.rolling=true;velocity.y=0;p.gravity=0;p.rest_rotation=resting_orientation(node.basis)
	if rolling:
		var scale: Vector3=node.scale
		node.quaternion=node.quaternion.slerp(p.rest_rotation,1-exp(-delta*14));node.scale=scale
		var drag: float=lerpf(14,5,softness);velocity.x*=exp(-delta*drag);velocity.z*=exp(-delta*drag)
		if Vector2(velocity.x,velocity.z).length()<.025 and node.quaternion.angle_to(p.rest_rotation)<.02:
			node.quaternion=p.rest_rotation;node.scale=scale;velocity=Vector3.ZERO;spin=Vector3.ZERO;p.settled=true
	next.y=floor_height+extent(node)+.008;node.position=next
	p.velocity=velocity;p.spin=spin
	return sound
