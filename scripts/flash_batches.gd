extends Node3D
## The original five colored muzzle cones share one normalized cone submission.
# Storage for persistent registration, NOT a per-frame emission/visible-FX budget.
# Cover the existing 128 crowd slots, 32 physical muzzles in the two-team
# vehicle showcase, and the existing 16-deployed-mortar limit. Chapters 01–10
# need at most 80 infantry + 13 mounted channels; replacements reuse slots.
const MAX_INFANTRY=128
const MAX_MOUNTED_MUZZLES=32
const MAX_PIECES_PER_MUZZLE=5
const REGISTRATION_CAPACITY=(MAX_INFANTRY+MAX_MOUNTED_MUZZLES+preload("res://scripts/portable_mortar.gd").LIMIT)*MAX_PIECES_PER_MUZZLE
var entries: Dictionary={}
var pool
var mesh=CylinderMesh.new()
var material=ShaderMaterial.new()
var active=0
var last_ms=0.0
func _ready():
	mesh.bottom_radius=1;mesh.top_radius=0;mesh.height=1;mesh.radial_segments=8
	var shader=Shader.new();shader.code="shader_type spatial;render_mode unshaded;void fragment(){ALBEDO=COLOR.rgb;EMISSION=COLOR.rgb*1.5;}";material.shader=shader
	pool=preload("res://scripts/fx_instance_batches.gd").new(REGISTRATION_CAPACITY);add_child(pool)
func register_tree(root: Node):
	if root.name=="MuzzleFlash":
		if entries.has(root.get_instance_id()):return
		var pieces=[]
		for child in root.get_children():
			if not child is MeshInstance3D or not child.mesh is CylinderMesh:continue
			var source: CylinderMesh=child.mesh;var local=Transform3D(Basis.from_scale(Vector3(source.bottom_radius,source.height,source.bottom_radius)),Vector3.ZERO)
			var handle=pool.add(mesh,material,Transform3D(Basis.from_scale(Vector3.ZERO),Vector3.ZERO),local,child.material_override.albedo_color)
			pieces.append({"node":child,"handle":handle});preload("res://scripts/batched_source.gd").suspend(child);child.set_meta("palette_batched",true)
		entries[root.get_instance_id()]={"root":root,"pieces":pieces,"visible":false,"translation":preload("res://scripts/batch_render_translation.gd").find(root)};return
	for child in root.get_children():register_tree(child)
func _process(_delta: float):refresh()
func unregister_tree(root: Node):
	for id in entries.keys():
		var entry: Dictionary=entries[id]
		if is_instance_valid(entry.root) and (entry.root==root or root.is_ancestor_of(entry.root)):
			var handles=[]
			for piece in entry.pieces:handles.append(piece.handle)
			pool.release(handles);entries.erase(id)
func refresh():
	var started=Time.get_ticks_usec();active=0
	for id in entries.keys():
		var entry: Dictionary=entries[id]
		if not is_instance_valid(entry.root):
			var handles=[]
			for piece in entry.pieces:handles.append(piece.handle)
			pool.release(handles);entries.erase(id);continue
		var visible=entry.root.is_inside_tree() and entry.root.is_visible_in_tree()
		if visible:active+=1
		if not visible and not entry.visible:continue
		entry.visible=visible
		for piece in entry.pieces:
			var pose: Transform3D=piece.node.global_transform if visible else Transform3D(Basis.from_scale(Vector3.ZERO),Vector3.ZERO)
			if visible and entry.translation!=null:pose.origin+=entry.translation.offset
			pool.sync([piece.handle],pose)
	for group in pool.groups.values():group.node.visible=active>0
	last_ms=(Time.get_ticks_usec()-started)/1000.0
