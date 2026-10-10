extends SceneTree
const World=preload("res://scripts/proving_world.gd")
const Catalog=preload("res://scripts/source_catalog.gd")
const Level=preload("res://scripts/orchard_level.gd")
const Case=preload("res://scripts/spent_case_motion.gd")
class ProfileWorld extends World:
	var cost={}
	func mark(key: String,start: int):
		if not cost.has(key):cost[key]={"us":0,"calls":0}
		cost[key].us+=Time.get_ticks_usec()-start;cost[key].calls+=1
	func ground_height(point: Vector2,radius: float,below: float,support_filter: Callable=Callable()) -> float:
		var start=Time.get_ticks_usec();var value=super.ground_height(point,radius,below,support_filter);mark("support",start);return value
	func collision_depth(point: Vector2,radius: float,height: float,ignore_vehicle: int=-1,base_height: float=0,first_only: bool=false) -> float:
		var start=Time.get_ticks_usec();var value=super.collision_depth(point,radius,height,ignore_vehicle,base_height,first_only);mark("body",start);return value
	func trace_3d(origin: Vector3,direction: Vector3,distance: float,p: Dictionary={},walls_only: bool=false) -> Dictionary:
		var start=Time.get_ticks_usec();var value=super.trace_3d(origin,direction,distance,p,walls_only);mark("ray",start);return value

func _initialize():
	var catalog=Catalog.new();var world=ProfileWorld.new();world.setup(Level.plan(catalog),catalog)
	var results={}
	for phase in ["move","cases"]:
		var start=Time.get_ticks_usec();world.cost={}
		for repeat in range(40):
			if phase=="move":
				for source in world.units:
					var unit=source.duplicate(true);unit.walk=0.0
					world.move_unit(unit,Vector2(1.2,-2.5),1.0/30.0)
			else:
				var motion=Case.new();motion.begin_frame()
				for i in range(120):
					var unit=world.units[i%60];var node=Node3D.new()
					node.position=Vector3(unit.position.x,unit.elevation+(.05 if i%3==0 else 1.3),unit.position.y);node.scale=Vector3(.022,.022,.06)
					var p={"node":node,"velocity":Vector3(1,-1,2),"gravity":9.8,"spin":Vector3(2,3,4),"presentation":{"case_shape":"rifle"}}
					motion.advance(p,1.0/30.0,world);node.free()
		results[phase]={"total_ms":(Time.get_ticks_usec()-start)/1000.0,"nested":world.cost.duplicate(true),"batches":40}
	print("SECONDARY_PROBE "+JSON.stringify(results));quit()
