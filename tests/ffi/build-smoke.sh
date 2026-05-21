#!/usr/bin/env bash
# tests/ffi/build-smoke.sh — build + run the C smoke test against
# libHermesCore.a. Designed to run inside the hermes-build Distrobox; will
# bail loudly if swift, libHermesCore.a, or the runtime libs aren't found.

set -euo pipefail

cd "$(dirname "$0")/../.."

if ! command -v swiftc >/dev/null; then
  echo "swiftc not found on PATH. Source ~/.bashrc.d/swift.sh inside the container." >&2
  exit 2
fi

LIB=".build/x86_64-unknown-linux-gnu/debug/libHermesCore.a"
if [[ ! -f "$LIB" ]]; then
  echo "$LIB not found. Run \`swift build\` first." >&2
  exit 2
fi

# Compile the C file with clang (swiftc rejects raw .c sources at the
# top of the driver invocation). Then link with swiftc — that pulls in
# the Swift runtime + Foundation libs from $SWIFT_HOME automatically,
# saving us from a manual -L/-l dance.
clang -c -O0 -g -fPIC tests/ffi/smoke.c -I include -o tests/ffi/smoke.o
swiftc \
  -o tests/ffi/smoke \
  tests/ffi/smoke.o \
  "$LIB" \
  -Xlinker -lstdc++ \
  -Xlinker -lpthread   # smoke.c uses pthread_cond for async SSH coordination
rm -f tests/ffi/smoke.o

echo "Built tests/ffi/smoke"
echo "---running---"
./tests/ffi/smoke
