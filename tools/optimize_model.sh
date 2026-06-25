#!/usr/bin/env bash
# Shrink an AI-generated GLB for the swarm: decimate tris -> resize texture -> webp + draco.
# Wraps the glTF-Transform CLI via npx (needs Node; first run downloads the CLI, then it's cached).
#
#   tools/optimize_model.sh <input.glb> <output.glb> [fodder|elite|boss]
#
# Never touches the input. Pick the preset by how close the camera gets:
#   fodder  swarm blobs, seen tiny top-down   -> brutal cut
#   elite   distinct enemies, mid-range
#   boss    seen up close                     -> light cut
# Tune by hand: run tools/inspect_model.sh on the input first to see its tri/texture sizes,
# and on the output after to confirm. Bump --ratio toward 1.0 if the silhouette breaks.
set -euo pipefail

in=${1:?usage: optimize_model.sh <input.glb> <output.glb> [fodder|elite|boss]}
out=${2:?usage: optimize_model.sh <input.glb> <output.glb> [fodder|elite|boss]}
preset=${3:-fodder}

case "$preset" in
  fodder) ratio=0.10 error=0.01  tex=512  ;;
  elite)  ratio=0.35 error=0.005 tex=1024 ;;
  boss)   ratio=0.60 error=0.003 tex=2048 ;;
  *) echo "unknown preset '$preset' (use fodder|elite|boss)" >&2; exit 2 ;;
esac

gt() { npx --yes @gltf-transform/cli "$@"; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "=> $preset: keep ${ratio} of tris (err ${error}), texture ${tex}px, webp"
gt simplify "$in"        "$tmp/1.glb" --ratio "$ratio" --error "$error"   # auto-welds first
gt resize   "$tmp/1.glb" "$tmp/2.glb" --width "$tex" --height "$tex"
# webp textures only — NO draco/meshopt geometry compression: Godot 4.7 can't import
# KHR_draco_mesh_compression without a plugin. Geometry is tiny after simplify anyway.
gt webp     "$tmp/2.glb" "$out"   # ponytail: converts ALL textures; if a normal/roughness map looks blotchy, restrict with --slots '{baseColor,emissive}'

echo "=> wrote $out  (run tools/inspect_model.sh '$out' to check the result)"
