extends RefCounted
## Typed per-particle state: no hash lookup for every position/velocity component.
var node: Node3D
var velocity:=Vector3.ZERO
var spin:=Vector3.ZERO
var age: float=0
var life: float=4
var gravity: float=9.8
var size:=Vector3.ONE
var bounds:=AABB(Vector3.ONE*-.5,Vector3.ONE)
var kind: String="debris"
var bounced: bool=false
var presentation: Dictionary={}
var batch: Array=[]
var motion_age: float=0
var motion_wait: float=0
var settled: bool=false
var rolling: bool=false
var bounces: int=0
var support_age: float=0
var floor: float=0
var softness: float=1
var rest_rotation:=Quaternion.IDENTITY
var support_stamp: int=-1
var draw_scale:=Vector3.ZERO
var motion_initialized: bool=false

func _init(data: Dictionary={}):
	for key in data:set(key,data[key])
	motion_initialized=data.has("settled")

func motion_to_dictionary(data: Dictionary):
	# Compatibility for existing mathematical fixtures and external dictionary users.
	# The runtime calls advance_particle directly and never performs this copy.
	for key in ["velocity","spin","settled","rolling","bounces","support_age","floor","softness","gravity"]:data[key]=get(key)
	if rolling or settled:data.rest_rotation=rest_rotation
