# cmake/SwiftCore.cmake
#
# Locates libHermesCore.a (built by `swift build` from Sources/HermesDesktop)
# and the Swift toolchain runtime libraries the binary needs at link + run
# time. Fails loudly if either is missing so the build error is actionable.
#
# Outputs (cache variables, also globally available):
#   HERMES_CORE_INCLUDE_DIR     — path to include/ holding HermesCore.h
#   HERMES_CORE_STATIC_LIBRARY  — absolute path to libHermesCore.a
#   HERMES_CORE_RUNTIME_DIR     — Swift runtime .so directory (rpath target)
#   HERMES_CORE_RUNTIME_LIBS    — list of Swift stdlib library names to link

set(HERMES_CORE_INCLUDE_DIR "${CMAKE_SOURCE_DIR}/include"
    CACHE PATH "Directory containing HermesCore.h")

# SwiftPM debug build output. Production AppImage CI will switch to release.
set(_swift_build_dir "${CMAKE_SOURCE_DIR}/.build/x86_64-unknown-linux-gnu/debug")
set(HERMES_CORE_STATIC_LIBRARY "${_swift_build_dir}/libHermesCore.a"
    CACHE FILEPATH "Absolute path to libHermesCore.a")

if(NOT EXISTS "${HERMES_CORE_STATIC_LIBRARY}")
    message(FATAL_ERROR
        "\n"
        "  libHermesCore.a not found at:\n"
        "    ${HERMES_CORE_STATIC_LIBRARY}\n"
        "\n"
        "  Run from the repo root, inside the hermes-build Distrobox:\n"
        "    source ~/.bashrc.d/swift.sh\n"
        "    swift build\n"
        "\n"
        "  Then re-run cmake.\n"
    )
endif()

# Swift toolchain root. Default matches the dev-env install at
# ~/.local/swift-6.3 (see spike/dev-environment.md). Override with
# -DSWIFT_HOME=/some/other/path on the cmake command line.
set(SWIFT_HOME "$ENV{HOME}/.local/swift-6.3"
    CACHE PATH "Swift toolchain root containing usr/lib/swift/linux")

set(HERMES_CORE_RUNTIME_DIR "${SWIFT_HOME}/usr/lib/swift/linux"
    CACHE PATH "Swift runtime library directory")

if(NOT EXISTS "${HERMES_CORE_RUNTIME_DIR}/libswiftCore.so")
    message(FATAL_ERROR
        "\n"
        "  Swift runtime libs not found at:\n"
        "    ${HERMES_CORE_RUNTIME_DIR}\n"
        "\n"
        "  Either install Swift 6.3 to ~/.local/swift-6.3 (see\n"
        "  spike/dev-environment.md) or pass -DSWIFT_HOME=/path to cmake.\n"
    )
endif()

# Stdlibs the executable explicitly depends on. swiftc usually figures
# these out at link time; we enumerate them since we're linking via
# the C++ compiler driver.
set(HERMES_CORE_RUNTIME_LIBS
    swiftCore
    swiftSwiftOnoneSupport
    swift_Concurrency
    swift_StringProcessing
    swift_RegexParser
    swiftDispatch
    swiftGlibc
    swiftSynchronization
    Foundation
    FoundationNetworking
    FoundationEssentials
    FoundationInternationalization
    BlocksRuntime
    dispatch
    CACHE STRING "Swift runtime libraries to link"
)

message(STATUS "HermesCore static:  ${HERMES_CORE_STATIC_LIBRARY}")
message(STATUS "HermesCore runtime: ${HERMES_CORE_RUNTIME_DIR}")
