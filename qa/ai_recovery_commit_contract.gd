extends SceneTree
const AI=preload("res://scripts/campaign_ai.gd")
var checks=0
var failures=0
func check(ok: bool,label: String):
 checks+=1
 if not ok:failures+=1;push_error(label)
func _initialize():
 var u={"position":Vector2.ZERO,"path":[Vector2(1,0),Vector2(2,0)],"repath":.7,"ai_recovery_search":{"next":0}}
 AI.accept_recovery(u,Vector2.ZERO,2)
 check(u.path.size()==2,"pending keeps movement route")
 check(u.repath==.7,"pending keeps repath timer")
 check(is_equal_approx(u.ai_recover_after,2.04),"pending uses original bounded retry delay")
 check(not u.has("ai_recovery_goal"),"pending grants no unvalidated escape")
 u.ai_recovery_search.next=8;AI.accept_recovery(u,Vector2(4,0),3)
 check(u.path.size()==2 and not u.has("ai_recovery_goal"),"partial candidate cannot commit before checked search completes")
 u.erase("ai_recovery_search");AI.accept_recovery(u,Vector2(1,0),4)
 check(u.path.is_empty() and u.repath==0,"completed recovery invalidates route")
 check(u.ai_recovery_goal==Vector2(1,0) and is_equal_approx(u.ai_recovery_until,4.65),"completed checked escape retains original duration")
 check(is_equal_approx(u.ai_recover_after,5.4),"completed search retains original cooldown")
 var failed={"position":Vector2.ZERO,"path":[Vector2(1,0)],"repath":.7}
 AI.accept_recovery(failed,Vector2.ZERO,6)
 check(failed.path.is_empty() and failed.repath==0,"completed no-candidate permits ordinary replan")
 check(is_equal_approx(failed.ai_recover_after,7.4),"completed failure does not enter fast retry loop")
 check(not failed.has("ai_recovery_goal"),"completed failure fabricates no movement")
 print("AI_RECOVERY_COMMIT checks=%d failures=%d; scalar state only"%[checks,failures]);quit(0 if failures==0 else 1)
