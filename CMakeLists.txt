cmake_minimum_required(VERSION 3.27)
project(HermesDesktopLinux
    VERSION 0.1.0
    DESCRIPTION "Hermes Desktop — Linux skeleton"
    LANGUAGES CXX
)

# ---------- C++ standard ----------
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# ---------- compile_commands.json for IDEs / clangd ----------
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# ---------- Hardened compile flags (subset of the plan) ----------
# Production AppImage builds will add the full set; for the dev skeleton
# we cover the cheap ones so we catch any regressions early.
add_compile_options(
    -Wall -Wextra -Wpedantic
    -fstack-protector-strong
    -fPIE
)
add_link_options(
    -Wl,-z,relro
    -Wl,-z,now
    -Wl,-z,noexecstack
)

# ---------- Qt6 + KDE Frameworks 6 ----------
find_package(Qt6 6.7 REQUIRED COMPONENTS
    Core
    Gui
    Widgets
    Qml
    Quick
    QuickControls2
)

# KF6 doesn't ship a single aggregator config on Fedora — each
# component has its own package. List them explicitly.
find_package(KF6CoreAddons 6.0 REQUIRED)
find_package(KF6Crash       6.0 REQUIRED)
find_package(KF6Config      6.0 REQUIRED)
find_package(KF6Kirigami    6.0 REQUIRED)
# KF6I18n provides KLocalizedString + KLocalizedContext (the QML
# `i18n()` function lives there). Without it `i18n("…")` returns
# undefined and Kirigami hides actions whose text is empty, which
# manifests as a blank-looking sidebar + missing toolbar buttons.
find_package(KF6I18n        6.0 REQUIRED)

qt_standard_project_setup(REQUIRES 6.7)

# ---------- Swift core static library ----------
include(cmake/SwiftCore.cmake)

# ---------- C++ subdir ----------
add_subdirectory(src)
