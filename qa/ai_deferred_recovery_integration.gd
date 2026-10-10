extends SceneTree
var failures=0
func check(ok: bool,label: String):
 if not ok:failures+=1;printerr("FAIL "+label)
func _initialize():run.call_deferred()
func run():
 var catalog=load("res://scripts/source_catalog.gd").new();var world=load("res://scripts/proving_world.gd").new()
 world.setup(load("res://scripts/campaign_catalog.gd").plan(catalog,4),catalog)
 for other in world.units:other.alive=false
 var u=world.units[36];u.alive=true;u.position=Vector2(-.8060292,-1.9811842);u.elevation=0;u.requested_velocity=Vector2.ZERO;u.velocity=Vector2.ZERO
 var goal=Vector2(0,1);u.path=world.campaign_ai.path_between(u.position,goal);u.ai_path_goal=goal;u.repath=1;u.brain=100;u.ai_target=-1;u.ai_visible=false;u.ai_contacts={};u.ai_tactic={"goal":goal,"hold":false,"state":"advance","stance":0};u.ai_order={}
 u.ai_tactic_signature="0:::"+str(Vector2.ZERO)+":false:false:false"
 u.ai_stuck=2;u.ai_progress_origin=u.position;u.ai_recover_after=0;world.time=1;world.ai_budget_usec=0
 var before=u.path.duplicate();world.campaign_ai.update(u,1.0/30)
 check(not before.is_empty(),"fixture begins with actual valid frozen-world path")
 check(u.has("ai_recovery_search") and int(u.ai_recovery_search.next)==0,"zero budget defers recovery without candidate work")
 check(not u.path.is_empty(),"deferred recovery preserves valid movement path")
 check(u.repath>0,"deferred recovery does not force a duplicate path search")
 check(world.ai_budget_usec==0,"zero-budget recovery does not add work or allowance")
 print("DEFERRED_RECOVERY failures=%d before=%s after=%s repath=%s search=%s"%[failures,str(before),str(u.path),str(u.repath),str(u.get("ai_recovery_search",{}))])
 world.campaign_director.cancel();quit(0 if failures==0 else 1)
