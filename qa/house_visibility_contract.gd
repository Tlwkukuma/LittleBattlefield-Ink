extends SceneTree
## Static room/height classification only; no game-window input or screenshots.
const Catalog=preload("res://scripts/source_catalog.gd")
const Visibility=preload("res://scripts/house_visibility.gd")
var checks=0
var failures=[]

func check(ok: bool,message: String):
	checks+=1
	if not ok:failures.append(message)

func _initialize():
	var catalog=Catalog.new()
	for transform in [[0.0,Vector2.ONE,Vector2.ZERO,0.0],[.67,Vector2(1.2,1.2),Vector2(3,-2),1.7],[PI*.5,Vector2(1.2,.8),Vector2(-3,2),-.6]]:
		var angle: float=transform[0];var scale: Vector2=transform[1];var origin: Vector2=transform[2];var base: float=transform[3]
		var plan=catalog.range_plan()
		plan.instances=[{"id":"house","prefabId":"building.residence-two-storey","x":2000+origin.x*40,"y":1400+origin.y*40,"rotation":angle,"scaleX":scale.x,"scaleY":scale.y,"godot3d":{"elevation":base}}]
		plan.looseSegments=[];plan.trees=[]
		var compiled=catalog.compile(plan);var roof=compiled.roofs[0];var objects={}
		for o in compiled.objects:objects[o.id]=o
		# Exterior stair/landing/ground, both door thresholds, wall thickness, roof.
		var samples=[
			[Vector2(9,-5.7),1.1,false,"reported exterior corner while airborne"],
			[Vector2(9,3.0),.7,false,"outside lower flight"],
			[Vector2(9,.9),1.72,false,"outside rest landing"],
			[Vector2(9,-1.5),2.56,false,"outside upper flight"],
			[Vector2(9,-4.1),3.4,false,"balcony"],
			[Vector2(8.3,-4.1),3.4,false,"balcony doorway outside"],
			[Vector2(7.95,-4.1),3.4,false,"balcony wall threshold"],
			[Vector2(7.7,-4.1),3.4,true,"balcony doorway inside"],
			[Vector2(0,6.3),.04,false,"front doorstep outside"],
			[Vector2(0,5.95),.04,false,"front wall threshold"],
			[Vector2(0,5.7),.04,true,"front doorway inside"],
			[Vector2(-8.3,0),.04,false,"west exterior wall"],
			[Vector2(0,-6.3),.04,false,"north exterior wall"],
			[Vector2(0,0),.04,true,"ground floor"],
			[Vector2(-6.9,-3),1.72,true,"interior stair landing"],
			[Vector2(0,0),3.4,true,"upper floor"],
			[Vector2(0,0),6.8,false,"standing on roof"],
			[Vector2(0,0),-.5,false,"below house foundation"]]
		for sample in samples:
			var point: Vector2=origin+(sample[0]*scale).rotated(angle);var height: float=base+sample[1]
			var active=Visibility.level(roof,height)
			var wall=Visibility.state(roof,objects["house.north-"+str(active)],point,height,false,0)
			var top=Visibility.state(roof,objects["house.roof-0-0"],point,height,false,0)
			check((wall.cut==1.15)==sample[2] and (top.opacity==0.0)==sample[2],"%s rotation %.2f: wall=%s roof=%s"%[sample[3],angle,wall,top])
		# Manual roof hiding never grants indoor wall cutaways outside.
		for mode in [1,2]:
			var point=origin+(Vector2(9,-4.1)*scale).rotated(angle)
			check(is_inf(Visibility.state(roof,objects["house.north-1"],point,base+3.4,false,mode).cut),"outside wall stays full in roof mode %s"%mode)
		check(is_inf(Visibility.state(roof,objects["house.north-0"],origin,base+.04,true,0).cut),"editor does not use indoor cutaway")
	print("HOUSE_VISIBILITY %d/%d passed; failures=%s"%[checks-failures.size(),checks,failures])
	quit(0 if failures.is_empty() else 1)
