extends SceneTree
const Schedule=preload("res://scripts/unit_step_schedule.gd")
const RenderMotion=preload("res://scripts/render_motion.gd")
var failures=0
var checks=0
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures+=1;printerr("FAIL "+label)
func _initialize():
	var units=[];var total=[];var counts=[]
	for id in range(60):units.append({"id":id,"player":id==0});total.append(0.0);counts.append(0)
	for tick in range(1,601):
		var active=0
		for unit in units:
			var elapsed=Schedule.elapsed(unit,1.0/60,tick,true)
			total[unit.id]+=elapsed
			if elapsed>0:counts[unit.id]+=1;active+=1
		check(active<=31,"at most half NPCs plus player per tick")
	for id in range(60):
		check(absf(total[id]-10)<=1.0/60+.00001,"elapsed time preserved %d"%id)
		check(counts[id]==(600 if id==0 else 300),"player 60 Hz and each NPC 30 Hz %d"%id)
	var actor={"position":Vector2.ZERO,"elevation":0.0,"alive":true,"mounted":-1}
	RenderMotion.before_unit(actor);actor.position=Vector2(1,0);RenderMotion.after_unit(actor,1,1.0/30)
	check(RenderMotion.sample(actor,.5,1)==Vector3(.25,0,0),"NPC first rendered half tick")
	check(RenderMotion.sample(actor,.5,1+1.0/60).distance_to(Vector3(.75,0,0))<.00001,"NPC idle simulation tick still interpolates")
	check(RenderMotion.sample(actor,1,1)==Vector3(1,0,0),"paused render uses exact current position")
	actor.position=Vector2(10,0)
	check(RenderMotion.sample(actor,.5,1)==Vector3(10,0,0),"teleport never interpolates old segment")
	print("UNIT_SCHEDULE checks=%d failures=%d"%[checks,failures]);quit(0 if failures==0 else 1)
