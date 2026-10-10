extends RefCounted
## Chapter checkpoints only. This namespace never replaces legacy game saves.
const VERSION=1
const COUNT=10
const SAVE_PATH="user://campaign_10_v1.json"
var path=SAVE_PATH
var unlocked=1
var selected=1
var completed: Array=[]
var tactic="T01"
var last_error=""
var dirty=false

func _init(save_path: String=SAVE_PATH):
	path=save_path
	load_progress()

static func integer(value,fallback: int) -> int:
	if typeof(value) not in [TYPE_INT,TYPE_FLOAT]:return fallback
	var number=float(value)
	if not is_finite(number) or number!=floor(number) or absf(number)>1000000:return fallback
	return int(number)

func read_document(source: String) -> Dictionary:
	if not FileAccess.file_exists(source):return {}
	var parser=JSON.new()
	if parser.parse(FileAccess.get_file_as_string(source))!=OK:return {}
	var document=parser.data
	if not document is Dictionary:return {}
	if integer(document.get("version",null),-1)!=VERSION or not document.get("completed",null) is Array:return {}
	return document

func load_progress() -> void:
	unlocked=1;selected=1;completed=[];tactic="T01";last_error="";dirty=false
	var document=read_document(path)
	if document.is_empty():
		document=read_document(path+".bak")
		if not document.is_empty():last_error="已恢复上一次完整战役进度。";dirty=true
		elif FileAccess.file_exists(path) or FileAccess.file_exists(path+".bak"):
			last_error="进度文件无法读取，已使用新战役状态；原文件未改动。";return
		else:return
	var seen=[]
	for value in document.completed:
		var number=integer(value,-1)
		if number>=1 and number<=COUNT and number not in seen:seen.append(number)
	# Only the contiguous completed prefix can grant further access.
	for number in range(1,COUNT+1):
		if number not in seen:break
		completed.append(number)
	unlocked=mini(COUNT,completed.size()+1)
	selected=clampi(integer(document.get("selected",unlocked),unlocked),1,unlocked)
	var saved_tactic=document.get("tactic","T01")
	if saved_tactic is String and saved_tactic in ["T01","T02","T03"]:tactic=saved_tactic

func save_progress() -> bool:
	dirty=true
	var temporary=path+".tmp"
	var backup=path+".bak"
	var file=FileAccess.open(temporary,FileAccess.WRITE)
	if file==null:last_error="无法保存战役进度。";return false
	file.store_string(JSON.stringify({"version":VERSION,"completed":completed,"selected":selected,"tactic":tactic},"\t"));file.flush();file.close()
	if read_document(temporary).is_empty():last_error="战役进度写入校验失败。";return false
	# Renaming into an absent target also works on platforms that cannot replace
	# an existing file. A crash between renames recovers from the previous backup.
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(backup):
			var removal=DirAccess.remove_absolute(backup)
			if removal!=OK:last_error="无法更新战役备份（%d）。"%removal;return false
		var moved=DirAccess.rename_absolute(path,backup)
		if moved!=OK:last_error="无法备份战役进度（%d）。"%moved;return false
	var error=DirAccess.rename_absolute(temporary,path)
	if error!=OK:
		if FileAccess.file_exists(backup) and not FileAccess.file_exists(path):DirAccess.rename_absolute(backup,path)
		last_error="无法更新战役进度文件（%d）。"%error;return false
	last_error="";dirty=false;return true

func can_play(number: int) -> bool:
	return number>=1 and number<=unlocked and number<=COUNT

func begin_chapter(number: int,chosen_tactic: String) -> bool:
	if not can_play(number):return false
	selected=number
	if chosen_tactic in ["T01","T02","T03"]:tactic=chosen_tactic
	save_progress()
	return true

func mark_completed(number: int) -> bool:
	if number<1 or number>COUNT or number>unlocked:return false
	if number in completed:return save_progress() if dirty else true
	completed.append(number);completed.sort();unlocked=mini(COUNT,number+1)
	selected=unlocked if number<COUNT else COUNT
	return save_progress()

func finished() -> bool:
	return COUNT in completed
