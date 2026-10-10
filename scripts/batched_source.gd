extends RefCounted
## Source nodes still own bones, sockets and visibility. Their replacement batch
## owns rendering; sending each hidden source transform to the renderer is waste.
static func suspend(source: GeometryInstance3D):
	source.layers=0
	source.set_notify_transform(false)
