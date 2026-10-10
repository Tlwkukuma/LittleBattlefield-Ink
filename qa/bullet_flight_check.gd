extends SceneTree
## Resource / geometry / bounded lifetime checks. No input or live game simulation.
const Flight=preload("res://scripts/bullet_flight_visual.gd")
const Batch=preload("res://scripts/bullet_flight_batch.gd")
const Catalog=preload("res://scripts/source_catalog.gd")
class CollisionFixture extends "res://scripts/proving_world.gd":
	func ray(origin: Vector2,direction: Vector2,distance: float,_height: float,_p: Dictionary={},_solids: bool=false) -> Dictionary:
		var t=(-1-origin.y)/direction.y
		return {"type":"object","distance":t,"target":{"material":"concrete"},"col":0,"row":0} if t>=0 and t<=distance else {}
	func damage_object(_object: Dictionary,_at: Vector2,_height: float,_amount: float,_explosive: bool,_col: int=-1,_row: int=-1,_weapon: Dictionary={},_distance: float=0,_incidence: float=1):pass
var count=0
var failures=[]
func check(value: bool,label: String):
	count+=1
	if not value:failures.append(label);push_error(label)
func projectile(w: Dictionary) -> Dictionary:
	return {"id":1,"weapon":w,"origin":Vector2.ZERO,"start_height":1.0,"position":Vector2(0,-2),"previous":Vector2(0,-1),"height":1.0,"previous_height":1.0,"direction":Vector2.UP,"slope":0.0,"speed":65.0,"source":0,"age":.03,
		"distance":2.0,"remaining":30.0,"alive":true,"penetration":0,"hit":[],"radius":.014}
func _initialize():run.call_deferred()
func run():
	var catalog=Catalog.new();var stage=Node3D.new();root.add_child(stage)
	var camera=Camera3D.new();stage.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=20
	camera.position=Vector3(0,18,18);camera.look_at(Vector3.ZERO)
	for id in ["p92","mp5k","m416","akm","awm","lynx-amr","s1897","o12","vss"]:
		var w: Dictionary=catalog.weapons[id];var style=Flight.profile(w)
		check(Flight.supports(w),"Supported live flight style: "+id)
		for camera_size in [4.0,12.0,20.0,45.0]:
			for angle in [0.0,PI*.25,PI*.5,PI,PI*1.5]:
				for slope in [-4.0,-1.0,0.0,.6,3.0]:
					var p=projectile(w);p.direction=Vector2.from_angle(angle);p.slope=slope
					p.position=p.direction*8;p.previous=p.direction*7;p.height=1+8*slope;p.previous_height=1+7*slope
					var at=Flight.head(p,.5);var data=Flight.geometry(p,at,camera.global_basis,camera_size/900.0)
					check(data.pose.is_finite() and data.width>0 and data.length>0,"Finite nonzero flight geometry")
					check(data.length<=float(style.limit)+.001,"No long world-space trails")
					check(data.length<=at.distance_to(Flight.start(p))+.001,"Cannot draw backward through the muzzle")
					check(absf(data.pose.basis.x.dot(data.pose.basis.y))<.001,"Stable camera-facing ribbon axes")
		var p=projectile(w);var before=p.duplicate(true)
		for blend in [0.0,.2,.5,.9,1.0]:
			var at=Flight.head(p,blend);check(at.z<=-1 and at.z>=-2,"Interpolation never predicts past physics")
		check(p==before,"Presentation cannot change authoritative projectile state")
		p.position=Vector2.ZERO;p.previous=Vector2.ZERO
		check(Flight.geometry(p,Flight.at(p),camera.global_basis,.022).is_empty(),"No stub protrudes behind the barrel at spawn")
	var normal=Flight.profile(catalog.weapons.m416);var pellet=Flight.profile(catalog.weapons.s1897);var slug=Flight.profile(catalog.weapons.o12)
	check(pellet.pixels<normal.pixels*.3 and pellet.width<normal.width,"Shotgun pellets remain separate small lights")
	check(slug.width>pellet.width and slug.pixels>pellet.pixels,"Slug remains distinct from buckshot")
	check(not Flight.supports(catalog.weapons.rpg) and not Flight.supports(catalog.weapons["he-grenade"]),"Explosive models stay on original renderer")
	var batch=Batch.new();stage.add_child(batch);var p=projectile(catalog.weapons.m416)
	batch.refresh([p],camera,.016,.5,0)
	check(batch.instances.visible_instance_count==1 and batch.get_child_count()==1,"Ordinary rounds use a single shared render batch")
	check(batch.instances.mesh.get_surface_count()==1,"One surface and no outline/light pass")
	batch.finish(p);batch.refresh([],camera,.016,1,0)
	check(batch.count==1 and batch.finished.size()==1,"Hit removed between frames still visible once")
	var endpoint=batch.instances.get_instance_transform(0).origin
	batch.refresh([],camera,.016,1,0)
	check(endpoint==batch.instances.get_instance_transform(0).origin,"Final contact never drifts beyond the collision point")
	batch.refresh([],camera,.060,1,0);check(batch.count==0 and batch.finished.is_empty(),"No persistent flight traces after impact")
	for i in range(300):batch.finish(p)
	check(batch.finished.size()==Batch.MAX_FINISHES,"Final contact memory remains bounded")
	batch.finished.clear()
	var crowded=[]
	for i in range(Batch.CAPACITY+10):crowded.append(p)
	batch.refresh(crowded,camera,.016,1,0)
	check(batch.count==Batch.CAPACITY and batch.dropped_visuals==10,"Cosmetic overflow cannot grow renderer or alter damage")
	check(crowded.size()==Batch.CAPACITY+10 and p.alive,"Visual cap leaves every simulation record intact")
	var fixture=CollisionFixture.new();var ended=[]
	fixture.event.connect(func(e):
		if e.type=="round_finished":ended.append(e.round.duplicate()))
	var fast=projectile(catalog.weapons.awm);fast.position=Vector2.ZERO;fast.previous=Vector2.ZERO;fast.distance=0.0
	fixture.advance_round(fast,4.0)
	check(ended.size()==1 and not fast.alive and is_equal_approx(fast.position.y,-1.0),"Fast impact emits verified endpoint once")
	fixture.advance_round(fast,4.0);check(ended.size()==1,"Repeated cleanup cannot duplicate contact presentation")
	stage.free();print("BULLET_FLIGHT_CHECK ",count-failures.size(),"/",count," passed; no gameplay automation");quit(0 if failures.is_empty() else 1)
