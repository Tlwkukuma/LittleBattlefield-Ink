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


def sleeve(p, a, b, ra, rb, phase=0, fold_depth=.005):
    a, b = np.asarray(a), np.asarray(b)
    axis = b - a
    t = np.clip(np.sum((p - a) * axis, axis=-1) / np.sum(axis * axis), 0., 1.)
    radial = p - (a + t[..., None] * axis)
    # Irregular broad fabric folds, concentrated around the bent joints.
    angle = np.arctan2(radial[..., 0], radial[..., 2])
    folds = fold_depth * np.sin(t * 13. + angle * 2. + phase) * np.sin(t * np.pi)
    radius = ra * (1 - t) + rb * t + folds
    return np.linalg.norm(radial, axis=-1) - radius


def jacket_body(p):
    d = ellipsoid(p, (0, 1.235, -.015), (.234, .27, .166))
    d = smooth_union(d, ellipsoid(p, (0, 1.035, .016), (.218, .135, .157)), .06)
    d = smooth_union(d, ellipsoid(p, (0, 1.430, -.042), (.231, .100, .148)), .045)
    # Fine nonuniform gathering at the waist, with no disconnected sleeve caps.
    angle = np.arctan2(p[..., 0], p[..., 2] + .015)
    gather = .003 * np.sin(angle * 9 + p[..., 1] * 30)
    d += gather * np.exp(-((p[..., 1] - 1.06) / .095) ** 2)
    return d


def jacket_sleeve(p, side):
    if side == 0:
        shoulder, elbow, wrist = (-.205, 1.438, -.038), (-.290, 1.218, -.200), (.025, 1.302, -.565)
    else:
        shoulder, elbow, wrist = (.205, 1.438, -.038), (.310, 1.198, .006), (.133, 1.275, -.255)
    # Loose padded cloth: keep volume through the elbow, without anatomy-like
    # tapering or sinusoidal grooves along the biceps and forearm.
    upper = sleeve(p, shoulder, elbow, .128, .130, fold_depth=0)
    lower = sleeve(p, elbow, wrist, .130, .084, fold_depth=0)
    d = smooth_union(upper, lower, .085)
    axis = np.asarray(wrist) - np.asarray(elbow)
    axis /= np.linalg.norm(axis)
    # End fabric underneath the cuff, not as a rounded cap enclosing the hand.
    return np.maximum(d, np.sum((p - np.asarray(wrist)) * axis, axis=-1) + .025)


def trousers(p):
    d = ellipsoid(p, (0, .905, .026), (.225, .170, .169))
    for side in [-1, 1]:
        hip = (side * .115, .90, .03)
        knee = (side * .160, .52, -.105 if side == -1 else .015)
        ankle = (side * .185, .15, -.02 if side == -1 else .160)
        d = smooth_union(d, sleeve(p, hip, knee, .151, .125, side), .050)
        d = smooth_union(d, sleeve(p, knee, ankle, .127, .090, side + 2), .058)
    # Blouse the trousers into the shaft. Fabric must not extend over the boot toe.
    return np.maximum(d, .285 - p[..., 1])


def build(name, sdf, lower, upper, step=.018, write=True):
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
    if write:
        save(name, result)
    return result


def save(name, result):
    out = ROOT / 'assets' / (name + '.mesh.json')
    out.write_text(json.dumps(result,separators=(',',':')),encoding='utf-8')
    print(f'{name}: {len(result["vertices"])//3} vertices, {len(result["indices"])//3} triangles, {out.stat().st_size} bytes')


def build_jacket(name, step):
    # Three disconnected cloth islands, one GPU surface. Only sleeves blend at elbows.
    result = dict(generator='tools/build_uniform.py', vertices=[], normals=[], indices=[], parts=[])
    fields = [jacket_body, lambda p: jacket_sleeve(p, 0), lambda p: jacket_sleeve(p, 1)]
    for part, sdf in enumerate(fields):
        piece = build('', sdf, (-.48,.82,-.70), (.50,1.62,.27), step, write=False)
        offset = len(result['vertices'])//3
        count = len(piece['vertices'])//3
        result['vertices'].extend(piece['vertices'])
        result['normals'].extend(piece['normals'])
        result['indices'].extend(i+offset for i in piece['indices'])
        result['parts'].extend([part]*count)
    save(name, result)


if __name__ == '__main__':
    build_jacket('uniform_jacket_painted_lod',.046)
    build('uniform_trousers_painted_lod',trousers,(-.37,.10,-.28),(.37,1.12,.33),step=.048)
    build_jacket('uniform_jacket_painted',.023)
    build('uniform_trousers_painted',trousers,(-.37,.10,-.28),(.37,1.12,.33),step=.026)
