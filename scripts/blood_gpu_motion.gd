extends RefCounted
## Persistent slots: CPU resolves contact once; GPU evaluates the exact visible
## arc, billboard, stretch and fade without uploading every droplet each frame.
const DROP_CAPACITY=192
const STAIN_CAPACITY=96
var image:=Image.create(4,DROP_CAPACITY+STAIN_CAPACITY,false,Image.FORMAT_RGBAF)
var texture: ImageTexture
var materials: Array[ShaderMaterial]=[]
var free_drops: Array[int]=[]
var free_stains: Array[int]=[]
var dirty: bool=false
var uploads: int=0
func _init():
	for i in range(DROP_CAPACITY-1,-1,-1):free_drops.append(i)
	for i in range(STAIN_CAPACITY-1,-1,-1):free_stains.append(DROP_CAPACITY+i)
	texture=ImageTexture.create_from_image(image)
func bind(batch: MultiMesh,stain: bool):
	var material: ShaderMaterial=batch.mesh.material
	material.set_shader_parameter("gpu_motion",true)
	material.set_shader_parameter("flight_data",texture)
	materials.append(material)
	for i in range(batch.instance_count):
		batch.set_instance_transform(i,Transform3D.IDENTITY)
		batch.set_instance_color(i,Color.WHITE)
		batch.set_instance_custom_data(i,Color(i+(DROP_CAPACITY if stain else 0),0,0,0))
func add(p: Dictionary,clock_time: float,stain: bool):
	var slots: Array[int]=free_stains if stain else free_drops
	assert(not slots.is_empty())
	var slot: int=slots.pop_back();p.gpu_slot=slot
	var origin: Vector3=p.position if stain else p.origin
	var velocity:=Vector3(p.angle,0,0) if stain else Vector3(p.velocity)
	image.set_pixel(0,slot,Color(origin.x,origin.y,origin.z,clock_time-float(p.age)))
	image.set_pixel(1,slot,Color(velocity.x,velocity.y,velocity.z,float(p.life)))
	image.set_pixel(2,slot,Color(float(p.radius),0 if stain else float(p.gravity),float(p.seed),2 if stain else 1 if p.splash else 0))
	image.set_pixel(3,slot,Color("752a38") if stain else Color(p.color))
	dirty=true
func release(p: Dictionary,stain: bool):
	if not p.has("gpu_slot"):return
	var slot: int=p.gpu_slot
	image.set_pixel(1,slot,Color(0,0,0,0));dirty=true
	if stain:free_stains.append(slot)
	else:free_drops.append(slot)
	p.erase("gpu_slot")
func refresh(clock_time: float,facing: Basis,pixel: float):
	if dirty:texture.update(image);dirty=false;uploads+=1
	for material in materials:
		material.set_shader_parameter("blood_clock",clock_time)
		material.set_shader_parameter("camera_frame",facing)
		material.set_shader_parameter("pixel_size",pixel)
