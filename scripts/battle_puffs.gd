extends Node3D
## Cosmetic smoke/fire/sparks: one bounded GPU card batch, no particle scene nodes.
const CAPACITY=192
var data:=Image.create(5,CAPACITY,false,Image.FORMAT_RGBAF)
var texture: ImageTexture
var instances: MultiMesh
var material: ShaderMaterial
var clock: float=0
var cursor: int=0
var cloud_cursor: int=0
var dirty: bool=false
var last_expiry: float=0
var writes: int=0
var bounds:=Vector2(128,128)

func _ready():
	texture=ImageTexture.create_from_image(data)
	material=ShaderMaterial.new();material.shader=preload("res://shaders/battle_puffs.gdshader")
	material.set_shader_parameter("particles",texture)
	var quad=QuadMesh.new();quad.size=Vector2.ONE
	instances=MultiMesh.new();instances.transform_format=MultiMesh.TRANSFORM_3D
	instances.use_custom_data=true;instances.mesh=quad;instances.instance_count=CAPACITY
	instances.custom_aabb=AABB(Vector3(-bounds.x-20,-64,-bounds.y-20),Vector3(bounds.x*2+40,256,bounds.y*2+40))
	for i in range(CAPACITY):instances.set_instance_custom_data(i,Color(i,0,0,0))
	var node=MultiMeshInstance3D.new();node.name="BattlePuffCards";node.multimesh=instances
	node.material_override=material;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(node)
	# Degenerate empty slot warms the GPU shader before the first firefight.
	instances.visible_instance_count=1
	RenderingServer.frame_post_draw.connect(func():instances.visible_instance_count=0,CONNECT_ONE_SHOT)

func emit(at: Vector3,size: Vector3,color: Color,velocity: Vector3,life: float,gravity: float,kind: String):
	# Smoke-grenade clouds have their own 48 slots; tiny muzzle/impact bursts
	# cannot evict a still-active long-lived cloud.
	var slot: int
	if life>=5:
		slot=cloud_cursor;cloud_cursor=(cloud_cursor+1)%48
	else:
		slot=48+cursor;cursor=(cursor+1)%(CAPACITY-48)
	data.set_pixel(0,slot,Color(at.x,at.y,at.z,clock))
	data.set_pixel(1,slot,Color(velocity.x,velocity.y,velocity.z,maxf(.001,life)))
	data.set_pixel(2,slot,Color(size.x,size.y,size.z,gravity))
	data.set_pixel(3,slot,color)
	data.set_pixel(4,slot,Color(0 if kind=="smoke" else 2 if kind=="spark" else 1,float(slot)*2.399963,0,0))
	dirty=true;last_expiry=maxf(last_expiry,clock+life)

func advance(delta: float):
	clock+=delta
	if dirty:texture.update(data);dirty=false;writes+=1
	material.set_shader_parameter("elapsed",clock)
	instances.visible_instance_count=CAPACITY if clock<last_expiry else 0
