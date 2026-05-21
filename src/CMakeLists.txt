# src/CMakeLists.txt — the C++ executable.

qt_add_executable(hermes-desktop
    main.cpp
    HermesCoreBridge.cpp
    HermesCoreBridge.h
    ConnectionsModel.cpp
    ConnectionsModel.h
)

# Modern Qt6 QML packaging. Generates qmldir + ahead-of-time-compiles
# each listed QML file. Files in the same module reference each other
# by type name (e.g. Main.qml does `ConnectionsPage {}`).
qt_add_qml_module(hermes-desktop
    URI HermesDesktop
    VERSION 1.0
    QML_FILES
        Main.qml
        OverviewPage.qml
        ConnectionsPage.qml
        PlaceholderPage.qml
)

target_include_directories(hermes-desktop PRIVATE
    "${HERMES_CORE_INCLUDE_DIR}"
)

# Qt6 + KDE Frameworks 6.
target_link_libraries(hermes-desktop PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Widgets
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    KF6::CoreAddons
    KF6::Crash
    KF6::Kirigami
    KF6::I18n
)

# Swift core static library + the runtime libs swiftc would otherwise
# auto-supply at link time. -lstdc++ is needed because swift-crypto's
# bundled BoringSSL has C++ std::terminate references.
target_link_libraries(hermes-desktop PRIVATE
    "${HERMES_CORE_STATIC_LIBRARY}"
    stdc++
)

target_link_directories(hermes-desktop PRIVATE
    "${HERMES_CORE_RUNTIME_DIR}"
)
target_link_libraries(hermes-desktop PRIVATE
    ${HERMES_CORE_RUNTIME_LIBS}
)

# Embed the Swift runtime lib path into the binary's RPATH so we don't
# need LD_LIBRARY_PATH wrangling at run-time. Production AppImage will
# rewrite this to $ORIGIN/../lib/swift/linux via patchelf.
set_target_properties(hermes-desktop PROPERTIES
    BUILD_RPATH   "${HERMES_CORE_RUNTIME_DIR}"
    INSTALL_RPATH "${HERMES_CORE_RUNTIME_DIR}"
    POSITION_INDEPENDENT_CODE ON
)
