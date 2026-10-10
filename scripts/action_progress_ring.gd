extends Control
## A single reusable quad; the GPU clips the original reload progress and widths.
const SHADER=preload("res://shaders/action_progress_ring.gdshader")
var shader_material:=ShaderMaterial.new()
var radius: float=-1
var progress: float=-1
func _init():
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	shader_material.shader=SHADER;material=shader_material
func refresh(center: Vector2,new_radius: float,new_progress: float,active: bool):
	visible=active
	if not active:return
	position=center-Vector2.ONE*(new_radius+3)
	if radius!=new_radius:
		radius=new_radius;size=Vector2.ONE*(radius+3)*2
		shader_material.set_shader_parameter("radius_pixels",radius);queue_redraw()
	if progress!=new_progress:
		progress=new_progress;shader_material.set_shader_parameter("progress",progress)
func _draw():draw_rect(Rect2(Vector2.ZERO,size),Color.WHITE)
