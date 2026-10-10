extends SceneTree
const Counter=preload("res://scripts/wall_fps_counter.gd")
const HUD=preload("res://scripts/network_status_hud.gd")
class FakeLAN:
	extends RefCounted
	var mode="offline"
	var reads=0
	func ping_ms():reads+=1;return -1.0
	func state_gap_ms():return 0.0
var checks=0
var failures=0
func check(value: bool,label: String):
	checks+=1
	if not value:failures+=1;printerr("FAIL "+label)
func _initialize():
	var previous=Engine.time_scale
	for scale in [1.0,.2,0.0]:
		Engine.time_scale=scale
		var slow=Counter.new();slow.sample(0)
		for frame in range(1,5):check(slow.sample(frame*1000000)==1,"one wall frame per second independent of scaled/clamped delta")
		var fast=Counter.new();fast.sample(0)
		for frame in range(1,61):fast.sample(roundi(frame*1000000.0/60.0))
		check(fast.value==60,"sixty wall frames per second independent of time scale")
		var hud=HUD.new();var lan=FakeLAN.new();hud.game={"lan":lan,"frames_per_second":1}
		hud.refresh_at(0);check(hud.text.contains("FPS 1 "),"normal HUD draws true one FPS")
		hud.refresh_at(249999);check(lan.reads==1,"quarter-second throttle uses wall time")
		hud.refresh_at(250000);check(lan.reads==2,"wall-clock quarter second refreshes at any time scale")
		hud.refresh_at(1250000);check(lan.reads==3,"slow frame still refreshes immediately when available")
		hud.free()
	Engine.time_scale=previous
	print("wall_fps_contract: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
