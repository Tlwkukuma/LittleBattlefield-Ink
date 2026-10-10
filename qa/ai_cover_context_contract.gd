extends SceneTree
## Cache-key identity only; no combat, perception queries or movement.
const Tactics=preload("res://scripts/campaign_tactics.gd")
var checks=0
var failures=0
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize():
	var unit={"elevation":0.0};var goal=Vector2(10,5)
	var contact={"id":7,"spawn_epoch":1,"position":Vector2(5,5),"elevation":0.0,"muzzle_height":1.33,"head_height":1.7,"penetration_estimate":42}
	var key=Tactics.cover_key(unit,contact,goal,false,1)
	check(key==Tactics.cover_key(unit,contact,goal,false,1),"unchanged threat reuses cache")
	for change in [{"elevation":3.4},{"muzzle_height":.4},{"head_height":.5},{"penetration_estimate":100},{"spawn_epoch":2},{"id":8}]:
		var next=contact.duplicate();next.merge(change,true)
		check(key!=Tactics.cover_key(unit,next,goal,false,1),"observed context invalidates cover: "+str(change))
	unit.elevation=3.4
	check(key!=Tactics.cover_key(unit,contact,goal,false,1),"observer floor change invalidates cached cover")
	unit.elevation=0.0
	check(key!=Tactics.cover_key(unit,contact,goal,false,2),"topology revision still invalidates cover")
	check(key!=Tactics.cover_key(unit,contact,goal,true,1),"advance and hold remain distinct")
	contact.muzzle_height=1.34;contact.observed_at=10.0
	check(key==Tactics.cover_key(unit,contact,goal,false,1),"small animation jitter and refreshed report clock do not restart search")
	var source=FileAccess.get_file_as_string("res://scripts/campaign_tactics.gd")
	check(source.contains("if cover_work>=1:return false"),"single cover-search quota is preserved")
	print("AI_COVER_CONTEXT checks=%d failures=%d; cache math only"%[checks,failures])
	quit(0 if failures==0 else 1)
