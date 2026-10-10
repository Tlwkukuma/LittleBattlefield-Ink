extends SceneTree
## Analytic geometry, contact and state-machine fixtures only. No game input/scene.
const Ball=preload("res://scripts/grenade_ballistics.gd")
const Throw=preload("res://scripts/grenade_throw_control.gd")
const Catalog=preload("res://scripts/source_catalog.gd")
class Ground extends RefCounted:
	var active=false
	var level=0.0
	func ray(at: Vector3,direction: Vector3,distance: float) -> Dictionary:
		var t=INF
		if at.y<level-.001:t=0.0
		elif direction.y<-.000001:t=(level-at.y)/direction.y
		return {"type":"terrain","distance":maxf(0,t),"normal":Vector3.UP,"target":{"component_id":"terrain.concrete"}} if t>=-.00001 and t<=distance else {}
class Space extends RefCounted:
	var terrain=Ground.new()
	var wall=false
	var wall_height=5.0
	var window=false
	var casts=0
	func trace_3d(at: Vector3,direction: Vector3,distance: float,options: Dictionary,_only_solids: bool) -> Dictionary:
		casts+=1;var hit=terrain.ray(at,direction,distance)
		if wall and absf(direction.x)>.000001:
			var radius=float(options.get("radius",0));var face=5.0-radius if direction.x>0 else 5.0+radius
			var t=(face-at.x)/direction.x;var height=at.y+direction.y*t
			if t>=0 and t<=distance and height>=-radius and height<=wall_height+radius and not (window and height>.9+radius and height<2.2-radius):
				if t<float(hit.get("distance",INF)):return {"type":"object","distance":t,"normal":Vector3.LEFT if direction.x>0 else Vector3.RIGHT,"target":{"kind":"concrete"}}
		return hit
var checks=0
var failures=[]
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures.append(label);push_error(label)
func soldier() -> Dictionary:return {"throw_state":{},"throw_lock":false,"ammo":1,"reserve":6,"reload":0.0,"cooldown":0.0,"stance":0}
func _initialize():
	var catalog=Catalog.new();var fixture=Space.new()
	for id in ["he-grenade","smoke-grenade"]:
		var w: Dictionary=catalog.weapons[id]
		for stance in range(3):
			for low in [false,true]:
				for distance in [.0,.3,2.0,6.0,12.0,30.0]:
					for height in [-2.0,0.0,2.8,6.0]:
						for angle in [0.0,PI*.25,PI,PI*1.5]:
							var dir=Vector2.from_angle(angle);var origin=Vector3(0,1.30,0)
							var s=Ball.solve(origin,Vector3(dir.x*distance,height,dir.y*distance),w,stance,low)
							check(Vector3(s.velocity).is_finite() and is_finite(s.flight) and s.flight>0,"Finite lob solution")
							check(Ball.position_at(origin,s.velocity,s.flight).distance_to(s.target)<.0001,"Analytic endpoint matches selected height / range")
							check(s.aim_distance<=Ball.max_range(w,stance,low or stance==2)+.001,"Stance and low-throw aim distance cap")
							check(Vector3(s.velocity).length()<=Ball.speed_limit(w,stance,low or stance==2)+.001,"Elevated / unreachable targets cannot exceed physical release speed")
							check(s.power>=0 and s.power<=1,"Bounded strength readout")
		var origin=Vector3(0,1.3,0);var near=Ball.solve(origin,Vector3(2,0,0),w,0,false);var far=Ball.solve(origin,Vector3(12,0,0),w,0,false)
		check(near.power<far.power and Vector3(near.velocity).length()<Vector3(far.velocity).length(),"Distance determines effort: "+id)
		var low=Ball.solve(origin,Vector3(8,0,0),w,0,true);var high=Ball.solve(origin,Vector3(8,0,0),w,0,false)
		check(low.velocity.y<high.velocity.y and low.flight<high.flight,"Low throw has a lower / faster arc: "+id)
		check(Throw.fuse(w)>high.flight+.3,"Fuse permits useful flight and bounce time: "+id)
		check(near.flight<.65 and near.velocity.y*near.velocity.y/(2*Ball.GRAVITY)<.25,"Near toss no longer floats over a metre above the hand")
		check(far.flight<1.1 and far.velocity.y*far.velocity.y/(2*Ball.GRAVITY)<1.6,"Medium throw has a direct, quicker ballistic arc")
		check(low.limited and low.speed<high.speed,"Underarm cannot become a full-power far throw")
		for distance in [2.0,6.0,12.0,19.5]:
			var s=Ball.solve(origin,Vector3(distance,0,0),w,0,false)
			print("THROW_TUNING id=",id," distance=",distance," speed=",snappedf(s.speed,.01)," seconds=",snappedf(s.flight,.01)," rise=",snappedf(s.velocity.y*s.velocity.y/(2*Ball.GRAVITY),.01))
		for fps in [30,60,120]:
			var s=Ball.motion(high);var elapsed=0.0
			while elapsed<.3:
				Ball.advance(s,fixture,1.0/fps);elapsed+=1.0/fps
			check(Vector3(s.at).distance_to(Ball.position_at(high.origin,high.velocity,elapsed))<.001,"Flight independent of frame rate: %s @ %d"%[id,fps])
			for i in range(fps*6):Ball.advance(s,fixture,1.0/fps)
			check(s.settled and s.at.y>=Ball.RADIUS-.001 and s.at.y<Ball.RADIUS+.025,"Settles above floor without sinking: %s @ %d"%[id,fps])
			fixture.terrain.level=-2.0
			for i in range(fps*3):Ball.advance(s,fixture,1.0/fps)
			check(s.at.y<-.9 and s.at.y>=-2+Ball.RADIUS-.001,"Removed support / negative elevation resumes fall")
			fixture.terrain.level=0.0
	var w: Dictionary=catalog.weapons["he-grenade"]
	var solution=Ball.solve(Vector3(0,1.3,0),Vector3(8,0,0),w,0,false)
	fixture.casts=0;var guide=Ball.preview(fixture,solution)
	check(fixture.casts<=80 and guide.points.size()<=81,"Bounded preview sweep budget")
	check(guide.point.distance_to(solution.target)<.025,"Flat-ground first contact agrees with selected target")
	fixture.wall=true
	guide=Ball.preview(fixture,solution)
	check(guide.hit.type=="object" and guide.point.x<5.0,"Guide stops at wall face")
	var s=Ball.motion(solution);var bounced=false
	for i in range(90):
		var contacts=Ball.advance(s,fixture,1.0/60)
		if not contacts.is_empty() and s.at.x>4.6:bounced=Vector3(s.velocity).x<0
		check(s.at.x<5.0,"No tunnelling through wall")
	check(bounced,"Reflection reverses only the approach into wall")
	fixture.wall_height=1.15;guide=Ball.preview(fixture,solution)
	check(guide.hit.type=="terrain" and guide.point.x>7,"High lob crosses low cover")
	fixture.wall_height=5.0;fixture.window=true
	guide=Ball.preview(fixture,Ball.solve(Vector3(0,1.3,0),Vector3(8,0,0),w,0,true))
	check(guide.hit.type=="terrain","Low lob fits window opening")
	check(Ball.box_normal(Vector3(1,.2,0),Vector3(-1,-1,-1),Vector3(1,1,1))==Vector3.RIGHT,"Contact face normal on box")
	var house={"position":Vector2(9,4),"angle":PI*.25,"elevation":3.4,"solid_parts":[
		{"at":Vector3(0,.1,0),"size":Vector3(4,.2,4)},
		{"at":Vector3(1,1.0,0),"size":Vector3(.1,1.8,4)}]}
	for pair in [[Vector3(0,.2+Ball.RADIUS,0),Vector3.UP],[Vector3(0,-Ball.RADIUS,0),Vector3.DOWN],
		[Vector3(1.05+Ball.RADIUS,1,0),Vector3.RIGHT],[Vector3(.95-Ball.RADIUS,1,0),Vector3.LEFT]]:
		var flat=Vector2(pair[0].x,pair[0].z).rotated(house.angle)+house.position
		var face=Ball.normal_for(fixture,{"type":"object","target":house},Vector3(flat.x,pair[0].y+house.elevation,flat.y),Vector3.DOWN,Ball.RADIUS)
		var expected: Vector3=pair[1].rotated(Vector3.UP,-house.angle)
		check(face.distance_to(expected)<.001,"Rotated upstairs part chooses actual contacted face")
	var velocity=Vector3(7,-3,2);var reflected=Ball.response(velocity,Vector3.LEFT)
	check(reflected.x<0 and reflected.y<0 and reflected.z>0 and reflected.length()<velocity.length(),"Reflection preserves tangent direction and dissipates energy")
	var u=soldier();var target=Vector3(8,0,0)
	check(not Throw.update(u,w,.016,true,true,target,true) and u.ammo==1,"Press starts preparation without consuming a grenade")
	for i in range(360):check(not Throw.update(u,w,1.0/60,true,false,target,true),"Holding never releases / cooks automatically")
	check(u.ammo==1 and u.throw_state.target==target,"Long preview hold retains grenade and selected target")
	Throw.update(u,w,.016,false,false,target,true);var requests=0
	for i in range(30):
		if Throw.update(u,w,1.0/60,false,false,target,true):requests+=1;Throw.released(u);u.ammo-=1;u.reload=1
	check(requests==1 and u.ammo==0,"Release produces one hand-release request, not multiple")
	for interrupt in ["menu","focus","vault","ladder","death"]:
		u=soldier();Throw.update(u,w,.016,true,true,target,true)
		Throw.update(u,w,.016,true,false,target,false)
		check(u.throw_state.is_empty() and u.ammo==1,"Cancellation consumes no grenade: "+interrupt)
		check(not Throw.update(u,w,.016,true,false,target,true) and u.throw_state.is_empty(),"Holding through interruption cannot arm: "+interrupt)
	u=soldier();Throw.update(u,w,.016,false,true,target,true)
	check(u.throw_state.phase=="windup","Quick click retains release even between physics ticks")
	u=soldier();u.reload=1;Throw.update(u,w,.016,true,true,target,true)
	check(u.throw_state.is_empty(),"Cannot prepare during resupply")
	print("GRENADE_MATH_CHECK ",checks-failures.size(),"/",checks," passed; no gameplay automation")
	quit(0 if failures.is_empty() else 1)
