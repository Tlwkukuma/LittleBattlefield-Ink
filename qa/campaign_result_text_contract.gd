extends SceneTree
const Presentation=preload("res://scripts/campaign_presentation.gd")
func _initialize():
	var cases=[
		["won","",{"owner":0},"阵地已夺取"],
		["won","",{"owner":-1},"敌军兵力已耗尽"],
		["lost","",{},"没有存活的蓝军队友可供接管"],
		["won","全部阶段目标已完成",{},"全部阶段目标已完成"],
		["playing","",{},""]]
	var failures=0
	for c in cases:
		if Presentation.result_reason(c[0],c[1],c[2])!=c[3]:failures+=1
	print("campaign_result_text_contract: %d checks, %d failures"%[cases.size(),failures]);quit(1 if failures else 0)
