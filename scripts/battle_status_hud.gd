extends RefCounted
## Original Pixi src/ui.js HUD: centred force bars, lower-left health.
## Appends to CombatActionHUD's existing shape/text batches, no extra draw pass.
const BLUE=Color("628ab0")
const RED=Color("bd6968")
const PAPER=preload("res://scripts/tactical_ui.gd").INK
const BACK=Color(.09,.12,.14,.82)
const VehicleStatus=preload("res://scripts/vehicle_status_hud.gd")

static func signature(game) -> String:
	var u: Dictionary=game.world.player
	var vehicle: Dictionary=game.world.vehicles[u.mounted] if u.mounted>=0 else {}
	return str(u.health,u.max_health,VehicleStatus.signature(vehicle),game.campaign_ui.hud_summary)

static func draw(hud):
	var game=hud.game;var u: Dictionary=game.world.player;var size: Vector2=hud.get_viewport_rect().size
	var at=Vector2(24,size.y-82)
	hud.paint.quad(Rect2(at,Vector2(230,58)),Rect2(),BACK)
	hud.medical_cross(at+Vector2(18,20),5,PAPER)
	hud.text_at(at+Vector2(32,26),"%d / %d"%[maxi(0,int(u.health)),u.max_health],19,PAPER)
	hud.paint.quad(Rect2(at+Vector2(14,40),Vector2(202,5)),Rect2(),Color("363d40"))
	hud.paint.quad(Rect2(at+Vector2(14,40),Vector2(202*clampf(u.health/maxf(1,u.max_health),0,1),5)),Rect2(),hud.DANGER if u.health<u.max_health*.3 else hud.FOCUS)
	if u.mounted>=0:
		var v: Dictionary=game.world.vehicles[u.mounted]
		VehicleStatus.draw(hud,v,at)
	var summary: Dictionary=game.campaign_ui.hud_summary
	if not game.world.campaign_active() or summary.is_empty():return
	var cx=size.x*.5;var width=minf(142,(size.x-220)*.25);var gap=52.0
	var left=cx-gap*.5-width;var right=cx+gap*.5
	for team in range(2):
		var x=left if team==0 else right
		var ratio=clampf(float(summary.remaining[team])/maxf(1,summary.total[team]),0,1)
		hud.paint.quad(Rect2(x,16,width,23),Rect2(),BACK)
		hud.paint.quad(Rect2(x+width*(1-ratio) if team==0 else x,16,width*ratio,23),Rect2(),BLUE if team==0 else RED)
		hud.text_at(Vector2(x+9,33),str(summary.remaining[team]),16,PAPER)
	hud.paint.quad(Rect2(cx-26,16,52,23),Rect2(),BACK)
	hud.text_at(Vector2(cx-16,32),"兵力",13,PAPER)
	var capture: Dictionary=summary.get("capture",{})
	if capture.is_empty():return
	var tint: Color=Color("d6b778") if capture.contested else capture.color
	hud.paint.quad(Rect2(cx-132,47,264,59),Rect2(),BACK)
	diamond(hud,Vector2(cx-108,72),17,tint)
	hud.text_at(Vector2(cx-114,78),str(capture.label),18,PAPER)
	hud.text_at(Vector2(cx-80,65),str(capture.name),14,PAPER)
	var state=str(capture.state)+(" · %d%%"%int(capture.progress*100) if capture.inside else " · "+objective_direction(game))
	hud.text_at(Vector2(cx-80,85),state,12,tint)
	hud.paint.quad(Rect2(cx-80,94,196,4),Rect2(),Color("41484a"))
	hud.paint.quad(Rect2(cx-80,94,196*capture.progress,4),Rect2(),tint)
	# The physical flag locates the objective in the world. Keep this card fixed
	# so moving the camera never invalidates the HUD's cached geometry/text.

static func diamond(hud,at: Vector2,radius: float,tint: Color):
	if not hud.paint.enabled:return
	var outer=PackedVector2Array([at+Vector2(0,-radius),at+Vector2(radius,0),at+Vector2(0,radius),at+Vector2(-radius,0)])
	var inner=PackedVector2Array()
	for p in outer:inner.append(at+(p-at)*.86)
	hud.paint.polygon(inner,Color(.09,.12,.14,tint.a*.9));hud.paint.ring(outer,inner,tint,tint)

static func objective_direction(game) -> String:
	# Only the public active objective and local player's position are read.
	# This is a world compass bearing, independent of camera zoom or occlusion.
	if game.world.campaign.points.is_empty():return ""
	var toward: Vector2=game.world.campaign.points[0].position-game.world.player.position
	var bearing=["东","东南","南","西南","西","西北","北","东北"][posmod(int(round(toward.angle()/(PI/4))),8)]
	return "%s %d m"%[bearing,int(toward.length())]
