extends SceneTree
const Schedule=preload("res://scripts/unit_step_schedule.gd")
var checks=0
var failures=0
func check(ok: bool,label: String):
 checks+=1
 if not ok:failures+=1;printerr("FAIL "+label)
func _initialize():
 check(Schedule.use_offline_order(true,true,{}),"offline campaign enables fair order")
 check(not Schedule.use_offline_order(false,true,{}),"training keeps original order")
 check(not Schedule.use_offline_order(true,false,{}),"solo LAN host keeps original order")
 check(not Schedule.use_offline_order(true,true,{2:{}}),"remote input presence conservatively keeps original order")
 for count in [1,2,3,4,5,29,30,59,60,79,80,81,127,128]:
  for phase in [0,1]:
   var units=[];var totals=[];var service={};var order=[];var again=[]
   for id in range(count):
    units.append({"id":id,"player":id==0,"alive":id%7!=3,"mounted":-1,"spawn_epoch":0});totals.append(0.0)
   if count>5:units[5].network_peer_id=2
   for tick in range(1,2*count+1):
    Schedule.fill_offline_order(units,tick,order)
    Schedule.fill_offline_order(units,tick,again)
    check(order==again,"same state produces deterministic order")
    check(order.size()==count,"no actor lost")
    var seen={};var npc_seen=false;var first=-1
    for index in order:
     check(not seen.has(index),"each actor appears exactly once");seen[index]=true
     var u=units[index];var human=u.player or int(u.get("network_peer_id",0))>0
     check(not human or not npc_seen,"all humans precede NPCs")
     npc_seen=npc_seen or not human
     var dt=Schedule.elapsed(u,1.0/60,tick+phase,true);totals[index]+=dt
     if first<0 and not human and u.alive and dt>0:first=index
    if first>=0:service[first]=true
   for u in units:
    if not u.player and not u.has("network_peer_id") and u.alive:check(service.has(u.id),"every eligible NPC first within two roster cycles")
    check(absf(totals[u.id]-2.0*count/60)<=1.0/60+.00001,"original elapsed time and parity preserved")
   # Life reuse changes no cached actor reference; rebuilding resets by tick.
   for u in units:u.spawn_epoch+=1;u.alive=true
   Schedule.fill_offline_order(units,1,order);Schedule.fill_offline_order(units,1,again)
   check(order==again,"epoch reuse and cursor reset deterministic")
   units.append({"id":count,"player":false,"alive":true,"mounted":-1})
   Schedule.fill_offline_order(units,2*count+3,order)
   check(order.size()==count+1 and order.has(count),"spawned roster entry included without stale cache")
 print("OFFLINE_AI_ORDER checks=%d failures=%d; integer order/parity only"%[checks,failures]);quit(0 if failures==0 else 1)
