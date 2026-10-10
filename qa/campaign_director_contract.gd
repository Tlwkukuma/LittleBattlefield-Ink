extends SceneTree
const Catalog=preload("res://scripts/source_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
const Orchard=preload("res://scripts/orchard_level.gd")
const Director=preload("res://scripts/campaign_director.gd")
var checks=0
var failures=0
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures+=1;printerr("FAIL "+label)
func _initialize():
	var catalog=Catalog.new();var world=World.new();world.setup(Orchard.plan(catalog),catalog)
	var director=Director.new();director.configure(world)
	check(not director.enabled and director.commander==null,"Default scene needs no Laya transport or service")
	director.tick(.5)
	var local_state=director.diagnostics()
	check(local_state.mode=="local" and local_state.transport.requests==0 and local_state.transport.pending==0,"Local director keeps zero model requests and pending work")
	check(director.status_text().contains("Laya 已关闭"),"HUD explicitly identifies intentional local mode")
	for unit in world.units:
		if unit.alive and not unit.player:check(not unit.get("ai_order",{}).is_empty() and unit.ai_order.source=="fallback","Local AI retains squad orders without model")
	director.apply_result({"team":0,"accepted":{"posture":{"choice":"aggressive"}},"metadata":{"phase":"policy"},"reason":""})
	check(director.teams[0].posture=="balanced" and director.teams[0].accepted==0,"Local mode ignores unsolicited or late model results")
	check(not Director.laya_requested({},[],""),"Missing setting defaults to local")
	check(Director.laya_requested({},["--laya"],""),"Explicit command line enables optional adapter")
	check(Director.laya_requested({"laya_enabled":true},[],""),"Explicit test or scene setting enables adapter")
	check(not Director.laya_requested({"laya_enabled":true},["--laya","--no-laya"],""),"Explicit no-Laya overrides every opt-in")
	check(not Director.laya_requested({},["--laya"],"1"),"Environment kill switch still overrides opt-in")
	world.plan.godot3d.laya_enabled=true;director.configure(world)
	check(director.enabled and director.commander!=null and director.commander.diagnostics().requests==0,"Optional adapter configures without issuing a request")
	var before=JSON.stringify(director.briefing(0))
	for unit in world.units:
		if unit.team==1:unit.position+=Vector2(3,7);unit.health=1
	check(before==JSON.stringify(director.briefing(0)),"unseen enemy positions and health cannot enter commander observations")
	var friend: Dictionary=world.units[1]
	friend.ai_contacts={31:{"position":Vector2(9,12),"observed_at":world.time,"confidence":.7,"source":"vision","elevation":1.5}}
	check(JSON.stringify(director.briefing(0))!=before,"confirmed contact enters observation")
	world.time=7
	check(director.contacts(0).is_empty(),"expired contact omitted")
	world.time=0
	for team in range(2):
		var assigned=director.counts(team)
		check(assigned.attack>0 and assigned.support>0,"fallback gives capture and support roles")
		for group in director.teams[team].squads.values():
			check(group.members.size()<=4,"bounded initial squad size")
			check(group.task in Director.TASKS,"enumerated mission only")
	var group: Dictionary=director.teams[0].squads.values()[0]
	var answer={"choice":"attack:0","confidence":.65,"probabilities":{"hold:0":.05,"attack:0":.65,"control:0":.1,"support:0":.15,"reserve":.05}}
	var scored=director.calibrate(0,group,answer);var total=0.0
	for probability in scored.probabilities.values():total+=probability
	check(absf(total-1)<.00001,"calibrated probabilities normalized")
	check(scored.choice=="attack:0","strong valid model choice preserved")
	for squad in director.teams[0].squads.values():squad.task="attack:0"
	var saturated=director.calibrate(0,group,{"choice":"attack:0","confidence":.5,"probabilities":{"hold:0":.06,"attack:0":.5,"control:0":.15,"support:0":.24,"reserve":.05}})
	check(saturated.choice=="support:0" and saturated.adjustments["attack:0"]<saturated.adjustments["support:0"],"duplicate assault assignments reduce marginal utility in model probabilities")
	var metadata={"phase":"policy","round":1}
	director.teams[0].phase="policy";director.teams[0].round=1
	director.apply_result({"team":0,"accepted":{},"metadata":metadata,"source":"transport","reason":"timeout"})
	check(director.teams[0].phase=="idle" and director.teams[0].next_at==world.time+4,"transport failure ends round with backoff")
	check(director.teams[0].source=="fallback","no response never claims model source")
	director.teams[0].phase="policy"
	director.apply_result({"team":0,"accepted":{},"metadata":metadata,"source":"laya","reason":""})
	check(director.teams[0].phase=="missions","valid low-confidence policy still allows individual missions")
	director.issue(0,group,"attack:0","laya",.8)
	world.time=50;director.assign_orders()
	check(group.task=="attack:0" and group.source=="laya" and group.stale,"aging model orders stay valid and are marked stale")
	world.campaign.points[0].contested=true;group.task="control:0"
	check(director.task_goal(0,group,world.campaign.points[0]).distance_to(world.campaign.points[0].position)<world.campaign.points[0].radius,"control helps inside contested point")
	director.configure(world)
	check(director.teams.size()==2 and director.teams[0].round==0,"reconfigure clears previous teams and rounds")
	director.commander._last_error="connect-timeout"
	check(director.status_text().contains("离线") and director.status_text().contains("规则"),"HUD distinguishes offline fallback")
	var retained: Dictionary=director.teams[0].squads.values()[0]
	director.issue(0,retained,"attack:0","laya",.7)
	check(director.status_text().contains("连接中断") and director.status_text().contains("已有命令"),"HUD identifies retained commands during disconnection")
	var old_transport=director.commander
	old_transport.submit(0,{"briefing":["frozen fixture"]},director.policy_questions(),{})
	world.plan.godot3d.laya_enabled=false;director.configure(world)
	check(not director.enabled and director.commander==null and old_transport.pending==0 and old_transport._client==null,"Reconfigure to local cancels queued adapter work and releases it")
	check(director.teams[0].accepted==0 and director.teams[0].source=="fallback","Switching to local clears old model tactics")
	check(is_zero_approx(world.time-50) and world.shots==0,"Contract does not step the battle or fire shots")
	director.cancel()
	print("DIRECTOR_CONTRACT checks=%d failures=%d; no battle steps or network requests"%[checks,failures])
	quit(0 if failures==0 else 1)
