extends SceneTree
## Scalar-only targeting/permission regression; no world or combat is instantiated.
const Aim=preload("res://scripts/campaign_directional_aim.gd")
var checks=0
var failures=0
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize():
	var u={"id":1,"ai_target":5,"velocity":Vector2.ZERO,"ai_stress":0.0}
	var contact={"id":5,"spawn_epoch":2,"observed_at":4.0,"position":Vector2(3,4),"elevation":1.0,"stance":1}
	var weapon={"id":"m416","archetype":"assault"}
	check(not Aim.fire_context_matches(u,contact,weapon),"no lane permission exists before an actual check")
	Aim.cache_fire_context(u,contact,weapon)
	check(Aim.fire_context_matches(u,contact,weapon),"matching checked report can use cached permission")
	var next=contact.duplicate();next.id=6
	check(not Aim.fire_context_matches(u,next,weapon),"new target cannot inherit previous lane permission at same timestamp")
	next=contact.duplicate();next.spawn_epoch=3
	check(not Aim.fire_context_matches(u,next,weapon),"reused enemy slot cannot inherit a prior-life lane")
	next=contact.duplicate();next.observed_at=4.5
	check(Aim.fire_context_matches(u,next,weapon),"fresh observation of the same target life retains checked lane permission")
	check(not Aim.fire_context_matches(u,contact,{"id":"rpg"}),"weapon changes invalidate old ballistic lane permission")
	check(not Aim.fire_context_matches(u,{},weapon),"missing report never authorizes fire")
	u.ai_target=-1
	Aim.observe(u,contact,weapon,Vector2.ZERO)
	check(u.ai_aim_contact_id==5 and u.ai_aim_contact_epoch==2,"remembered aiming uses report identity when no current live selection")
	check(u.ai_aim_mark==Vector3(3,1.68,4),"aim mark copies observed position and stance only")
	var source=FileAccess.get_file_as_string("res://scripts/campaign_ai.gd")
	check(source.contains("DirectionalAim.fire_context_matches(unit,contact,weapon)"),"live firing gate checks matching context")
	check(source.contains("ai_aim_contact_epoch"),"aim interpolation refreshes on new life identity")
	u.ai_tactic={};u.ai_tactic_signature="same"
	var ai=preload("res://scripts/campaign_ai.gd")
	var deferred=contact.duplicate();deferred.observed_at=4.5;deferred.id=9
	check(not ai.tactics_due(u,deferred,weapon,"same",false,true,0),"zero shared budget defers unchecked report")
	check(ai.tactics_due(u,deferred,weapon,"same",false,true,1),"positive residual time budget permits bounded atomic check")
	check(ai.tactics_due(u,deferred,weapon,"same",false,true,2000),"same observation recovers on next available tick without new perception")
	Aim.cache_fire_context(u,deferred,weapon)
	check(not ai.tactics_due(u,deferred,weapon,"same",false,true,2000),"checked context does not busy-loop or request another check")
	check(not ai.tactics_due(u,{},weapon,"same",false,false,2000),"lost/removed contact cannot resurrect lane retry")
	deferred.spawn_epoch=3
	check(not Aim.fire_context_matches(u,deferred,weapon),"new target life still lacks permission after deferred recovery")
	check(ai.tactics_due(u,deferred,weapon,"same",false,true,2000),"observed new life requires a new bounded check")
	check(source.contains("if tactics_due(unit,contact,weapon,signature,decide,visible,int(world.ai_budget_usec)):"),"live tactical decision uses the tested budget gate")
	print("AI_FIRE_CONTEXT checks=%d failures=%d; scalar state only"%[checks,failures])
	quit(0 if failures==0 else 1)
