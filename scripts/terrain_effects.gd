extends RefCounted
const Terrain=preload("res://scripts/terrain_art.gd")

static func impact(fx,e: Dictionary):
	var raw=str(e.get("material","concrete"));var material=preload("res://scripts/combat_feedback_profile.gd").material(raw)
	var power=float(preload("res://scripts/combat_feedback_profile.gd").profile(e.get("weapon",{"kind":"bullet"})).power)
	var metal=material=="metal";var wood=material=="wood"
	var color=Color("edd5a0") if metal else Color("a77e52") if wood else Color("c7dedd") if material=="glass" else Terrain.pigment(raw).lightened(.12)
	if material=="earth" and fx.world!=null:
		var surface=fx.world.terrain.profile_at(e.position)
		if surface.id=="terrain.snow":color=Color("e0e7e5")
		elif surface.id=="terrain.desert":color=Color("d1b98e")
		elif surface.id=="terrain.red-earth":color=Color("b9856a")
	var away=Vector3(-cos(float(e.get("angle",0))),.3,-sin(float(e.get("angle",0))))
	var normal: Vector3=e.get("normal",Vector3.ZERO)
	if normal.length_squared()>.1:away=normal.normalized()
	var at=Vector3(e.position.x,e.height,e.position.y)
	var count=4 if metal else 3
	if power>1.6:count+=1
	for i in range(count):
		var velocity=(away*fx.rng.randf_range(.8,1.8)+Vector3(fx.rng.randf_range(-.4,.4),fx.rng.randf_range(.25,.9),fx.rng.randf_range(-.4,.4)))*minf(1.5,power)
		var size=Vector3(.016,.020,.10) if metal else Vector3(.022,.018,.11) if wood else Vector3(.06,.015,.04) if material=="glass" else Vector3.ONE*.045
		fx.piece(at+away*.012,size*minf(1.35,power),color,velocity,.14 if metal else .48,false,7,"spark" if metal else "debris")
	if not metal and material!="glass":fx.piece(at+away*.025,Vector3(.13,.10,.13)*minf(1.5,power),color,away*.16+Vector3(0,.12,0),.28 if wood else .38,true,0,"smoke")

static func fracture(fx,e: Dictionary):
	var material=str(e.object.material);var wood="wood" in material;var metal="metal" in material
	var color=Terrain.pigment(material);var count=3 if not e.explosive else 5
	var away: Vector2=(e.position-e.origin).normalized()
	if away.length_squared()<.01:away=Vector2.from_angle(float(e.object.angle)+PI*.5)
	var at=Vector3(e.position.x,e.height,e.position.y)
	for i in range(count):
		var size: Vector3=e.size*Vector3(fx.rng.randf_range(.22,.42),fx.rng.randf_range(.22,.46),fx.rng.randf_range(.28,.54))
		if wood:size=Vector3(minf(.065,size.x),size.y*1.6,minf(.065,size.z))
		elif metal:size.z=minf(.025,size.z)
		var speed=fx.rng.randf_range(1.5,4.0) if e.explosive else fx.rng.randf_range(.5,1.8)
		fx.piece(at,size,color.darkened((i%3)*.045),Vector3(away.x*speed,fx.rng.randf_range(.5,2.0),away.y*speed),18)
	if not metal:
		fx.piece(at,Vector3(.30,.22,.30),color.lightened(.15),Vector3(away.x*.15,.24,away.y*.15),.70,true,0,"smoke")
