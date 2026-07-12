"""Bake a T-pose model's outstretched arms DOWN to the sides (one-time, geometry-informed).

The enemy vertex shader has no skeleton, so it can't pose arms; and the generated revenant is
a T-pose (armspan ~= height). We read the mesh, find the arm verts (upper body + far out along
X), and rotate them down about an estimated per-side shoulder pivot in the X-Y plane. Normals are
rotated too so shading stays right. Overwrites the output glb in place.

Usage: repose_arms.py <in.glb> <out.glb> [theta_degrees]
"""
import sys, math, numpy as np
from pygltflib import GLTF2

IN, OUT = sys.argv[1], sys.argv[2]
THETA = math.radians(float(sys.argv[3]) if len(sys.argv) > 3 else 82.0)

# tunables (normalized: h = height fraction 0..1; x is mesh-local, torso near 0)
ARM_X_INNER, ARM_X_OUTER = 0.30, 0.52   # |x| ramp: 0 at torso -> 1 on the arm
ARM_H_LO,   ARM_H_HI    = 0.52, 0.64   # height gate: exclude legs/feet/hips
SHOULDER_X = 0.26                        # per-side shoulder pivot x
SHOULDER_H = 0.72                        # shoulder pivot height (normalized)

def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)

g = GLTF2().load(IN)
blob = bytearray(g.binary_blob())

def view(acc_idx):
    acc = g.accessors[acc_idx]
    bv = g.bufferViews[acc.bufferView]
    stride = bv.byteStride or 12
    base = (bv.byteOffset or 0) + (acc.byteOffset or 0)
    return acc, base, stride

def read(acc_idx):
    acc, base, stride = view(acc_idx)
    out = np.empty((acc.count, 3), np.float32)
    for i in range(acc.count):
        out[i] = np.frombuffer(blob, np.float32, 3, base + i * stride)
    return out

def write(acc_idx, arr):
    acc, base, stride = view(acc_idx)
    for i in range(acc.count):
        blob[base + i * stride : base + i * stride + 12] = arr[i].astype('<f4').tobytes()

# global bounds across all primitives for a consistent h
allP = np.concatenate([read(p.attributes.POSITION) for m in g.meshes for p in m.primitives])
lo_y, hi_y = float(allP[:,1].min()), float(allP[:,1].max())
H = hi_y - lo_y
sy = lo_y + SHOULDER_H * H
print("height %.3f  shoulder_y %.3f  theta %.0f deg" % (H, sy, math.degrees(THETA)))
print("before: x[%.3f,%.3f]" % (allP[:,0].min(), allP[:,0].max()))

for m in g.meshes:
    for p in m.primitives:
        P = read(p.attributes.POSITION)
        x, y = P[:,0], P[:,1]
        h = (y - lo_y) / H
        w = smoothstep(ARM_X_INNER, ARM_X_OUTER, np.abs(x)) * smoothstep(ARM_H_LO, ARM_H_HI, h)
        a = -np.sign(x) * THETA * w                      # per-vertex rotation about Z
        ca, sa = np.cos(a), np.sin(a)
        sx = np.sign(x) * SHOULDER_X
        vx, vy = x - sx, y - sy
        P[:,0] = sx + vx * ca - vy * sa
        P[:,1] = sy + vx * sa + vy * ca
        write(p.attributes.POSITION, P)
        # update POSITION accessor bounds
        acc = g.accessors[p.attributes.POSITION]
        acc.min = [float(P[:,0].min()), float(P[:,1].min()), float(P[:,2].min())]
        acc.max = [float(P[:,0].max()), float(P[:,1].max()), float(P[:,2].max())]
        # rotate normals by the same per-vertex angle (pure rotation, no pivot)
        if p.attributes.NORMAL is not None:
            N = read(p.attributes.NORMAL)
            nx, ny = N[:,0].copy(), N[:,1].copy()
            N[:,0] = nx * ca - ny * sa
            N[:,1] = nx * sa + ny * ca
            n = np.linalg.norm(N, axis=1, keepdims=True); n[n == 0] = 1
            write(p.attributes.NORMAL, N / n)

chk = np.concatenate([read(p.attributes.POSITION) for m in g.meshes for p in m.primitives])
print("after:  x[%.3f,%.3f]  (arms pulled in => T-pose gone)" % (chk[:,0].min(), chk[:,0].max()))
g.set_binary_blob(bytes(blob))
g.save(OUT)
