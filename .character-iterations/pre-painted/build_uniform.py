"""Bake continuous clothing surfaces using smooth distance fields.

No downloads or external models. Requires only numpy. The resulting small JSON
meshes are engine-independent and are skinned to Godot bones at import time.
"""
from pathlib import Path
import json
import numpy as np

ROOT = Path(__file__).resolve().parents[1]


def smooth_union(a, b, k=.055):
    h = np.clip(.5 + .5 * (b - a) / k, 0., 1.)
    return b * (1 - h) + a * h - k * h * (1 - h)


def ellipsoid(p, center, radii):
    q = p - np.asarray(center)
    r = np.asarray(radii)
    k0 = np.linalg.norm(q / r, axis=-1)
    k1 = np.linalg.norm(q / (r * r), axis=-1)
    return k0 * (k0 - 1.) / np.maximum(k1, 1e-8)


def sleeve(p, a, b, ra, rb, phase=0):
    a, b = np.asarray(a), np.asarray(b)
    axis = b - a
    t = np.clip(np.sum((p - a) * axis, axis=-1) / np.sum(axis * axis), 0., 1.)
    radial = p - (a + t[..., None] * axis)
    # Irregular broad fabric folds, concentrated around the bent joints.
    angle = np.arctan2(radial[..., 0], radial[..., 2])
    folds = .007 * np.sin(t * 19. + angle * 2. + phase) * np.sin(t * np.pi)
    radius = ra * (1 - t) + rb * t + folds
    return np.linalg.norm(radial, axis=-1) - radius


def jacket(p):
    d = ellipsoid(p, (0, 1.235, -.015), (.222, .29, .162))
    d = smooth_union(d, ellipsoid(p, (0, 1.02, .016), (.205, .13, .152)), .07)
    d = smooth_union(d, ellipsoid(p, (0, 1.455, -.042), (.237, .090, .142)), .045)
    segments = [
        ((-.205, 1.438, -.038), (-.290, 1.218, -.200), .111, .093, 0),
        ((-.290, 1.218, -.200), (.025, 1.302, -.565), .094, .059, 1.4),
        ((.205, 1.438, -.038), (.310, 1.198, .006), .111, .089, 2.1),
        ((.310, 1.198, .006), (.133, 1.275, -.255), .089, .056, 3.2),
    ]
    for a, b, ra, rb, phase in segments:
        d = smooth_union(d, sleeve(p, a, b, ra, rb, phase), .049)
    # Fine nonuniform gathering at the waist, with no disconnected sleeve caps.
    angle = np.arctan2(p[..., 0], p[..., 2] + .015)
    gather = .003 * np.sin(angle * 9 + p[..., 1] * 30)
    d += gather * np.exp(-((p[..., 1] - 1.06) / .095) ** 2)
    return d


def trousers(p):
    d = ellipsoid(p, (0, .905, .026), (.209, .172, .152))
    for side in [-1, 1]:
        hip = (side * .115, .90, .03)
        knee = (side * .160, .52, -.105 if side == -1 else .015)
        ankle = (side * .185, .15, -.02 if side == -1 else .160)
        d = smooth_union(d, sleeve(p, hip, knee, .129, .104, side), .045)
        d = smooth_union(d, sleeve(p, knee, ankle, .105, .071, side + 2), .052)
    # Terminate the cuff inside the boot shaft; no ankle gap while walking.
    return np.maximum(d, .125 - p[..., 1])


def build(name, sdf, lower, upper, step=.018):
    axes = [np.arange(a, b + step, step) for a, b in zip(lower, upper)]
    grid = np.stack(np.meshgrid(*axes, indexing='ij'), axis=-1)
    field = sdf(grid)
    offsets = [(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0),
               (0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)]
    shape = np.asarray(field.shape) - 1
    corners = np.stack([grid[x:x+shape[0], y:y+shape[1], z:z+shape[2]].reshape(-1, 3)
                        for x, y, z in offsets], axis=1)
    values = np.stack([field[x:x+shape[0], y:y+shape[1], z:z+shape[2]].reshape(-1)
                       for x, y, z in offsets], axis=1)
    crossing = (values.min(axis=1) <= 0) & (values.max(axis=1) > 0)
    corners, values = corners[crossing], values[crossing]
    pieces = []
    for tetra in [(0,5,1,6),(0,1,2,6),(0,2,3,6),(0,3,7,6),(0,7,4,6),(0,4,5,6)]:
        c, v = corners[:, tetra], values[:, tetra]
        codes = np.sum((v < 0) * np.array([1, 2, 4, 8]), axis=1)
        for code in range(1, 15):
            chosen = codes == code
            if not chosen.any():
                continue
            cc, vv = c[chosen], v[chosen]
            inside = [i for i in range(4) if code & (1 << i)]
            outside = [i for i in range(4) if not code & (1 << i)]
            def edge(a, b):
                t = vv[:, a] / (vv[:, a] - vv[:, b])
                return cc[:, a] + t[:, None] * (cc[:, b] - cc[:, a])
            if len(inside) == 1:
                tri = [edge(inside[0], j) for j in outside]
                pieces.append(np.stack(tri, axis=1))
            elif len(inside) == 3:
                tri = [edge(outside[0], j) for j in inside]
                pieces.append(np.stack(tri, axis=1))
            else:
                a, b = inside
                c0, d0 = outside
                ac, ad, bc, bd = edge(a,c0), edge(a,d0), edge(b,c0), edge(b,d0)
                pieces.extend([np.stack([ac,ad,bc],axis=1),np.stack([ad,bd,bc],axis=1)])
    triangles = np.concatenate(pieces)
    positions, inverse = np.unique(np.round(triangles.reshape(-1,3),6), axis=0, return_inverse=True)
    eps = .001
    normals = np.stack([(sdf(positions + np.eye(3)[axis] * eps) -
                         sdf(positions - np.eye(3)[axis] * eps)) / (2*eps)
                        for axis in range(3)], axis=-1)
    normals /= np.maximum(np.linalg.norm(normals,axis=-1,keepdims=True),1e-8)
    indices = inverse.reshape(-1,3)
    p = positions[indices]
    geometric_normal = np.cross(p[:,1]-p[:,0],p[:,2]-p[:,0])
    expected_normal = normals[indices].mean(axis=1)
    reverse = np.sum(geometric_normal * expected_normal, axis=1) > 0
    indices[reverse] = indices[reverse][:,[0,2,1]]  # Godot clockwise front faces.
    result = {"generator":"tools/build_uniform.py", "vertices":positions.reshape(-1).tolist(),
              "normals":np.round(normals,5).reshape(-1).tolist(),"indices":indices.reshape(-1).tolist()}
    out = ROOT / 'assets' / (name + '.mesh.json')
    out.write_text(json.dumps(result,separators=(',',':')),encoding='utf-8')
    print(f'{name}: {len(positions)} vertices, {len(indices)} triangles, {out.stat().st_size} bytes')


if __name__ == '__main__':
    build('uniform_jacket_lod',jacket,(-.45,.82,-.69),(.47,1.60,.25),step=.040)
    build('uniform_trousers_lod',trousers,(-.34,.10,-.26),(.34,1.12,.30),step=.040)
    build('uniform_jacket',jacket,(-.45,.82,-.69),(.47,1.60,.25))
    build('uniform_trousers',trousers,(-.34,.10,-.26),(.34,1.12,.30))
