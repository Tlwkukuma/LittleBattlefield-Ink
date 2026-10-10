extends RefCounted
## Authored ambush orders. Contacts, aim, cover and path work stay in campaign_ai.
var world_ref: WeakRef
var groups: Array=[]
var revision=0
var previous_stage=""
var order_clock=0.0
var shifted=false

func configure(world) -> void:
	world_ref=weakref(world);groups.clear();revision=0;previous_stage="";order_clock=0.0
	for source in world.plan.hanlueMission.get("deploymentGroups",[]):
		var group=source.duplicate(true);group.members=[]
		for unit in world.units:
			if str(unit.get("campaign_source_id","")) in source.unitIds:
				group.members.append(unit);unit.hanlue_group=str(source.id)
				unit.stance=2;unit.stance_blend=2.0
		groups.append(group)
	issue_orders()

func tick(delta: float) -> void:
	var world=world_ref.get_ref()
	world.campaign_ai.tick_connectivity()
	var stage=str(world.campaign.hanlue.stage)
	if stage!=previous_stage:
		previous_stage=stage
		issue_orders()
	order_clock-=delta
	if order_clock<=0:
		order_clock=1.0
		# These few orders depend on elapsed task time and friendly positions only.
		issue_orders()

func shift_positions() -> void:
	var world=world_ref.get_ref()
	if world.campaign.hanlue.stage in ["withdrawal","result"]:return
	shifted=not shifted;issue_orders()
	world.event.emit({"type":"notice","text":"各组向道路边缘调整观察阵位" if shifted else "各组返回隐蔽阵位"})

func issue_orders() -> void:
	var world=world_ref.get_ref();var mission=world.campaign.hanlue
	revision+=1
	for group in groups:
		for unit in group.members:
			if not world.mission_unit_active(unit) or unit.player:continue
			var goal: Vector2=unit.spawn
			if shifted:goal.y+=.85 if goal.y<0 else -.85
			var task="hold"
			if mission.stage=="withdrawal":goal=mission.extraction_goal(unit);task="attack"
			order(unit,goal,task,str(group.id),mission.stage=="withdrawal")
	for unit in world.units:
		if unit.team!=1 or not world.mission_unit_active(unit) or unit.mounted>=0:continue
		# Dismounted troops first defend their actual dismount location, then a
		# finite part of each crew attempts the authored eastern open road exit.
		var anchor: Vector2=unit.get("hanlue_dismount_position",unit.position)
		if not unit.has("hanlue_dismount_position"):unit.hanlue_dismount_position=anchor;unit.hanlue_dismount_at=world.time
		var goal=anchor;var task="hold";var withdraw=false
		if world.time-float(unit.hanlue_dismount_at)>16.0 and int(unit.campaign_slot)%2==0:
			goal=world.catalog.position(world.plan.hanlueMission.escapeZones[0],world.plan);task="attack";withdraw=true
		order(unit,goal,task,"convoy-"+str(int(unit.campaign_slot)/4),withdraw)
		if withdraw and unit.position.distance_to(goal)<2.8:world.retire_mission_unit(unit,"escaped")

func order(unit: Dictionary,goal: Vector2,task: String,group: String,withdraw: bool) -> void:
	var old: Dictionary=unit.get("ai_order",{})
	if old.get("goal",Vector2.INF)==goal and old.get("task","")==task and bool(old.get("hanlue_withdraw",false))==withdraw:return
	unit.ai_order={"goal":goal,"task":task,"squad_id":group,"revision":revision,"direct":true,"hanlue_withdraw":withdraw}
	unit.path=[];unit.repath=0.0;unit.erase("ai_tactic")

func hold_concealed(unit: Dictionary,delta: float) -> bool:
	var world=world_ref.get_ref()
	if not world.mission_unit_active(unit):return true
	if not world.campaign.hanlue.is_concealed():return false
	world.FireControl.cancel(unit,true);world.ThrowControl.cancel(unit)
	unit.aiming=false;unit.aim_valid=false;unit.ai_state="concealed";unit.ai_target=-1
	if unit.team==0:
		unit.stance=2
		# Small, checked local adjustment never replaces pathfinding with a teleport.
		var goal: Vector2=unit.get("ai_order",{}).get("goal",unit.spawn)
		var move=Vector2.ZERO
		if unit.position.distance_to(goal)>.2 and world.campaign_ai.traversable(world,unit.position,goal):move=(goal-unit.position).normalized()*.55
		world.move_unit(unit,move,delta)
	else:unit.velocity=Vector2.ZERO;unit.requested_velocity=Vector2.ZERO
	return true
