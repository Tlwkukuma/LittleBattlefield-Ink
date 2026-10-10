extends SceneTree
const Policy=preload("res://scripts/campaign_input_policy.gd")
var checks=0
var failures=0
func check(value: bool,label: String):
	checks+=1
	if not value:failures+=1;printerr("FAIL "+label)
func _initialize():
	var plan={"godot3d":{"campaign_offline":true,"campaign_chapter":2}}
	var key=InputEventKey.new();key.keycode=KEY_F5;key.pressed=true
	check(Policy.retry_shortcut(key,plan,false,false,false,false,false),"offline F5 is available outside Debug")
	for blocked in range(5):
		var states=[false,false,false,false,false];states[blocked]=true
		check(not Policy.retry_shortcut(key,plan,states[0],states[1],states[2],states[3],states[4]),"network/editor/text/loot/wheel blocks retry")
	for code in [KEY_F1,KEY_F2,KEY_F3,KEY_F4,KEY_F8,KEY_TAB]:
		key.keycode=code;check(not Policy.retry_shortcut(key,plan,false,false,false,false,false),"other debug/game keys not exposed")
	key.keycode=KEY_F5;key.echo=true
	check(not Policy.retry_shortcut(key,plan,false,false,false,false,false),"held-repeat cannot rebuild")
	key.echo=false;key.pressed=false
	check(not Policy.retry_shortcut(key,plan,false,false,false,false,false),"key release cannot rebuild")
	key.pressed=true
	check(not Policy.retry_shortcut(key,{},false,false,false,false,false),"training and legacy LAN keep original gate")
	check(not Policy.retry_shortcut(InputEventMouseButton.new(),plan,false,false,false,false,false),"mouse cannot trigger retry")
	print("campaign_retry_key_contract: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
