extends SceneTree
## Legacy value-only regression. Current runtime is covered by campaign_3d_contract.
const Bounding=preload("res://scripts/campaign_bounding.gd")
var checks=0
var failures=0
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize():run.call_deferred()
func run():
	var point={"position":Vector2.ZERO,"radius":5.0}
	var shooter={"id":1,"alive":true,"player":false,"mounted":-1,"position":Vector2(0,16),"ai_visible":true,"ai_target":9,"ai_last_shot_target":9,"ai_last_shot_at":10.0,"ai_stress":0.1,"ai_contacts":{9:{"source":"vision","position":Vector2(0,8),"observed_at":10.0,"confidence":.9}}}
	var mover={"id":2,"alive":true,"player":false,"mounted":-1,"position":Vector2(2,16),"ai_stress":.1}
	var members=[shooter,mover]
	var opened=Bounding.choose(members,point,10.1,{})
	check(opened.cover_id==1 and opened.until>10.1,"fresh shot plus visual contact opens one cover window")
	check(Bounding.choose(members,point,10.5,opened)==opened,"window does not churn")
	var cleared=Bounding.choose(members,point,12.6,opened)
	check(cleared.cover_id==-1,"expired fire cannot pin squad")
	shooter.ai_last_shot_at=12.6;shooter.ai_contacts[9].observed_at=12.6
	check(Bounding.choose(members,point,12.65,cleared).cover_id==-1,"same shooter has bounded cooldown")
	shooter.ai_last_shot_at=13.5;shooter.ai_contacts[9].observed_at=13.5
	check(Bounding.choose(members,point,13.5,cleared).cover_id==1,"fresh fire can reopen after cooldown")
	shooter.ai_contacts[9].source="hearing"
	check(Bounding.choose(members,point,13.5,{}).cover_id==-1,"hearing is not a firing window")
	shooter.ai_contacts[9].source="vision";mover.position=Vector2(25,25)
	check(Bounding.choose(members,point,13.5,{}).cover_id==-1,"isolated shooter cannot stall advance")
	mover.position=Vector2(2,16);shooter.position=Vector2(0,6)
	check(Bounding.choose(members,point,13.5,{}).cover_id==-1,"capture entry cancels bounding")
	print("CAMPAIGN_BOUNDING_CONTRACT checks=%d failures=%d"%[checks,failures]);quit(0 if failures==0 else 1)
