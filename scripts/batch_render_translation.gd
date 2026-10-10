extends RefCounted
## Interpolation translates the submitted instances, without dirtying every
## bone/socket/source mesh in an NPC's disabled renderer hierarchy each frame.
var offset:=Vector3.ZERO
static func find(node: Node):
	while node!=null:
		if node.has_meta("batch_render_translation"):return node.get_meta("batch_render_translation")
		node=node.get_parent()
	return null
