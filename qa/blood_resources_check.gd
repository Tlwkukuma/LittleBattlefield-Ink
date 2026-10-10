extends SceneTree
## Pure effect trajectories, resource buffers and event merging. No firing, world
## damage, gameplay input, combat stepping, screen capture or visual acceptance.
const Blood=preload("res://scripts/blood_effects.gd")
class GeometryFixture extends RefCounted:
	var bounds=Vector2(50,35)
	var player={"position":Vector2.ZERO,"elevation":0.0}
	var wall=false
	var queries=0
	func ground_height(_at: Vector2,_radius: float,_ceiling: float) -> float:return 0.0
	func trace_3d(at: Vector3,direction: Vector3,distance: float,_p: Dictionary,_walls_only: bool) -> Dictionary:
		queries+=1
		if wall and direction.z<-.0001:
			var t=(-.35-at.z)/direction.z
			if t>=0 and t<=distance:return {"distance":t,"type":"object"}
		return {}
var checks=0
var failures=[]
func _initialize():run.call_deferred()
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures.append(label);push_error(label)
func event(id: int,at: Vector3,direction: Vector3,amount: float=30,fatal: bool=false) -> Dictionary:
	return {"type":"damage","unit":{"id":id},"point":at,"incoming":direction,"amount":amount,"fatal":fatal,"region":"body"}
func run():
	var geometry=GeometryFixture.new();var fx=Blood.new();fx.world=geometry;root.add_child(fx);fx.warming=false
	var normal=event(1,Vector3(2,1.1,3),Vector3.FORWARD);var head=normal.duplicate(true);head.region="head"
	var fatal=head.duplicate(true);fatal.fatal=true
	check(Blood.strength(normal)<Blood.strength(head) and Blood.strength(head)<Blood.strength(fatal),"Head and fatal feedback has bounded stronger intensity")
	for i in range(8):fx.queue_hit(normal)
	fx.queue_hit(fatal)
	check(fx.pending.size()==1 and fx.pending[1].fatal and fx.pending[1].region=="head","Shotgun pellets merge while preserving fatal/head feedback")
	fx.advance(0)
	check(fx.drops.size()==9 and fx.gpu.free_drops.size()==Blood.MAX_DROPS-9,"Merged fatal event occupies exactly nine GPU slots")
	check(geometry.queries<=Blood.MAX_TRACE_PER_FRAME,"Creation sweeps respect their query budget")
	var exact=true
	for p in fx.drops:exact=exact and Vector3(p.origin).is_equal_approx(normal.point)
	check(exact,"Every droplet starts at the real contact point")
	fx.queue_hit(normal);check(fx.pending.is_empty(),"Close repeated hit does not stack a second cloud")
	fx.queue_hit(event(2,Vector3.ZERO,Vector3.FORWARD,0));check(fx.pending.is_empty(),"Zero damage does not create blood")
	fx.free()
	for height in [.18,.55,1.10,1.70]:
		for direction in [Vector3.FORWARD,Vector3.RIGHT,Vector3(1,.4,-1),Vector3.UP,Vector3.ZERO]:
			fx=Blood.new();fx.world=GeometryFixture.new();root.add_child(fx);fx.warming=false
			var contact=Vector3(0,height,0);fx.queue_hit(event(1,contact,direction));fx.advance(0)
			var finite=true;var inherited=true;var landing=false
			for p in fx.drops:
				finite=finite and Vector3(p.velocity).is_finite() and p.life>0 and p.radius>0
				inherited=inherited and Vector3(p.origin).is_equal_approx(contact)
				if p.mark:landing=true;finite=finite and absf(p.landing.y-.025)<.0001
			for frame in range(12):
				fx.advance(.08)
				for p in fx.drops:
					var birth: Color=fx.gpu.image.get_pixel(0,p.gpu_slot)
					finite=finite and Blood.flight(p,p.age).is_finite() and absf(fx.age-birth.a-float(p.age))<.00001
			check(finite and inherited,"Finite contact-height/direction samples h="+str(height)+" dir="+str(direction))
			check(fx.drops.is_empty(),"Airborne ink expires h="+str(height)+" dir="+str(direction))
			check(not landing or not fx.stains.is_empty(),"Only landed droplets retain a floor stain")
			fx.advance(15);check(fx.stains.is_empty() and fx.stain_mesh.visible_instance_count==0,"Stains expire and clear their render slots")
			fx.free()
	geometry=GeometryFixture.new();geometry.wall=true;fx=Blood.new();fx.world=geometry;root.add_child(fx);fx.trace_budget=Blood.MAX_TRACE_PER_FRAME
	var drop={"origin":Vector3(0,1,0),"velocity":Vector3(0,1,-2),"gravity":12.0,"life":.8,"mark":true}
	fx.prepare_flight(drop)
	check(not drop.mark and Blood.flight(drop,drop.life).z>=-.3501,"Blood stops at the near wall face without painting through it")
	geometry.wall=false;fx.trace_budget=Blood.MAX_TRACE_PER_FRAME;drop.life=.8;drop.mark=true
	fx.prepare_flight(drop)
	check(drop.mark and drop.landing.z<-.35,"Removing the wall allows the same arc to land beyond the opening")
	fx.trace_budget=0;drop.life=.8;drop.mark=true;fx.prepare_flight(drop)
	check(not drop.mark and drop.life<=.10,"Exhausted trace budget retains only a short contact flash")
	fx.free()
	fx=Blood.new();fx.world=GeometryFixture.new();root.add_child(fx)
	for round_index in range(18):
		for i in range(100):fx.queue_hit(event(round_index*100+i,Vector3(i*.05,.4,0),Vector3.FORWARD,40,i%5==0))
		fx.world.queries=0;fx.advance(.06)
		check(fx.drops.size()<=Blood.MAX_DROPS and fx.stains.size()<=Blood.MAX_STAINS and fx.world.queries<=Blood.MAX_TRACE_PER_FRAME,"Crowded event buffers and geometry work stay bounded "+str(round_index))
	fx.advance(20)
	check(fx.drops.is_empty() and fx.stains.is_empty() and fx.pending.is_empty() and fx.last_hit.is_empty(),"All temporary data releases after inactivity")
	check(fx.get_child_count()==1,"One shared spray/stain batch; no per-drop node allocation")
	fx.free()
	print("BLOOD_RESOURCES_CHECK ",checks-failures.size(),"/",checks," passed; failures=",failures)
	quit(0 if failures.is_empty() else 1)
