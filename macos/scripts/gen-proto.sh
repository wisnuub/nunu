#!/bin/bash
# Regenerates Sources/EmulatorAPI from proto/emulator_controller.proto.
# Refresh the proto from an installed engine first if Google changed it:
#   cp ~/.nunu/sdk/emulator/lib/emulator_controller.proto proto/
# Needs: brew install protobuf swift-protobuf protoc-gen-grpc-swift
set -euo pipefail

cd "$(dirname "$0")/.."
protoc -I proto -I "$(brew --prefix)/include" \
  --swift_out=Sources/EmulatorAPI --swift_opt=Visibility=Public \
  --grpc-swift-2_out=Sources/EmulatorAPI --grpc-swift-2_opt=Visibility=Public,Server=false \
  proto/emulator_controller.proto
echo "regenerated Sources/EmulatorAPI"
