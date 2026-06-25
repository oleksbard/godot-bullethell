#!/usr/bin/env bash
# Print a GLB's mesh/texture stats (tri counts, texture dimensions + byte sizes).
# Use before optimizing to pick a preset, and after to confirm the cut landed.
#
#   tools/inspect_model.sh <model.glb>
set -euo pipefail

model=${1:?usage: inspect_model.sh <model.glb>}
npx --yes @gltf-transform/cli inspect "$model"
