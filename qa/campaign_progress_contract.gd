extends SceneTree
const Progress=preload("res://scripts/campaign_progress.gd")
var checks=0
var failures=0
const PATH="/tmp/campaign-progress-contract.json"
func check(value: bool,label: String):
	checks+=1
	if not value:failures+=1;printerr("FAIL "+label)
func _initialize():
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(PATH+suffix):DirAccess.remove_absolute(PATH+suffix)
	var state=Progress.new(PATH)
	check(state.unlocked==1 and state.selected==1 and not state.finished(),"new campaign starts at one")
	check(not state.begin_chapter(2,"T01"),"locked entry rejected")
	check(state.begin_chapter(1,"T03"),"first entry accepted")
	check(not state.mark_completed(10),"out-of-order completion rejected")
	for number in range(1,11):
		check(state.mark_completed(number),"completion %d saved"%number)
		check(state.unlocked==mini(10,number+1),"next unlock %d"%number)
		var loaded=Progress.new(PATH)
		check(loaded.completed==state.completed and loaded.unlocked==state.unlocked,"round trip %d"%number)
	check(state.finished(),"final ending unlocked")
	check(state.mark_completed(3) and state.completed.size()==10,"replay idempotent")
	var loaded=Progress.new(PATH)
	check(loaded.tactic=="T03","tactic persists")
	if FileAccess.file_exists(PATH+".bak"):DirAccess.remove_absolute(PATH+".bak")
	var file=FileAccess.open(PATH,FileAccess.WRITE);file.store_string('{"version":1,"completed":[1,3,3,90],"selected":10,"tactic":"BAD"}');file.close()
	loaded=Progress.new(PATH)
	check(loaded.unlocked==2 and loaded.selected==2 and loaded.tactic=="T01","untrusted gaps and values bounded")
	file=FileAccess.open(PATH,FileAccess.WRITE);file.store_string('{"version":99,"completed":[1,2,3]}');file.close()
	loaded=Progress.new(PATH)
	check(loaded.unlocked==1 and not loaded.last_error.is_empty(),"unknown save version preserved")
	check(FileAccess.get_file_as_string(PATH).contains('99'),"unknown save not overwritten on load")
	file=FileAccess.open(PATH,FileAccess.WRITE);file.store_string('broken-json');file.close()
	loaded=Progress.new(PATH)
	check(loaded.unlocked==1 and not loaded.last_error.is_empty(),"corrupt file safe fallback")
	for invalid in [null,{},[],"1",true,1.5]:
		file=FileAccess.open(PATH,FileAccess.WRITE);file.store_string(JSON.stringify({"version":invalid,"completed":[]}));file.close()
		loaded=Progress.new(PATH)
		check(loaded.unlocked==1 and not loaded.last_error.is_empty(),"invalid version type safe")
		file=FileAccess.open(PATH,FileAccess.WRITE);file.store_string(JSON.stringify({"version":1,"completed":[invalid],"selected":invalid,"tactic":invalid}));file.close()
		loaded=Progress.new(PATH)
		check(loaded.unlocked==1 and loaded.selected==1 and loaded.tactic=="T01","invalid member/selection type safe")
	var missing="/tmp/campaign-progress-missing-directory"
	var failed=Progress.new(missing+"/save.json")
	check(not failed.mark_completed(1) and failed.dirty,"write failure stays dirty")
	check(not failed.mark_completed(1) and failed.dirty,"repeated completion retries failed write")
	DirAccess.make_dir_recursive_absolute(missing)
	check(failed.mark_completed(1) and not failed.dirty,"retry succeeds after destination available")
	var recovered=Progress.new(missing+"/save.json")
	check(recovered.completed==[1] and recovered.unlocked==2,"successful retry persists on reopen")
	check(recovered.mark_completed(2),"second save produces backup")
	DirAccess.remove_absolute(missing+"/save.json")
	recovered=Progress.new(missing+"/save.json")
	check(recovered.completed==[1] and recovered.dirty,"interrupted replacement recovers prior backup")
	check(recovered.save_progress() and not recovered.dirty,"recovered backup can be saved")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(missing+"/save.json"+suffix):DirAccess.remove_absolute(missing+"/save.json"+suffix)
	DirAccess.remove_absolute(missing)
	check(Progress.SAVE_PATH=="user://campaign_10_v1.json","separate save namespace")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(PATH+suffix):DirAccess.remove_absolute(PATH+suffix)
	print("campaign_progress_contract: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
