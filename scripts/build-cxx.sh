#!/usr/bin/env bash
# scripts/build-cxx.sh — convenience wrapper for the C++/Qt/Kirigami skeleton.
#
# Builds libHermesCore.a via swift build, configures the CMake project if
# needed, then runs ninja. Designed to run inside the hermes-build
# Distrobox (see spike/dev-environment.md).

set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v swiftc >/dev/null; then
    echo "swiftc not on PATH. From inside the container:" >&2
    echo "    source ~/.bashrc.d/swift.sh" >&2
    exit 2
fi
if ! command -v cmake >/dev/null; then
    echo "cmake not installed." >&2
    exit 2
fi

echo "==> swift build"
swift build

if [[ ! -f build/build.ninja ]]; then
    echo "==> cmake configure (first time)"
    cmake -B build -G Ninja
fi

echo "==> ninja"
ninja -C build

echo ""
echo "Built: $(realpath build/src/hermes-desktop)"
echo ""
echo "Run with:"
echo "    distrobox enter hermes-build -- ./build/src/hermes-desktop"
echo ""
echo "(Launching from outside the container won't find the Swift runtime"
echo "libs unless LD_LIBRARY_PATH points at ~/.local/swift-6.3/usr/lib/swift/linux.)"
