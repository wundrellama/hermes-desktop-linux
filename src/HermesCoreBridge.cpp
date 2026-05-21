#include "HermesCoreBridge.h"

namespace {
/// Take ownership of a char* returned from a hermes_* function: copy
/// into a QString and free the Swift-side allocation. NULL inputs yield
/// an empty QString.
QString takeOwnedString(char *ptr) {
    if (ptr == nullptr) {
        return {};
    }
    QString result = QString::fromUtf8(ptr);
    hermes_free_string(ptr);
    return result;
}
}  // namespace

HermesCoreBridge::HermesCoreBridge(QObject *parent)
    : QObject(parent) {
    m_version = takeOwnedString(hermes_core_version());

    // NULL/NULL → read XDG paths from the process environment, matching
    // what the macOS path does and what the FFI smoke validated.
    m_handle = hermes_apppaths_init(nullptr, nullptr);
    if (m_handle != 0) {
        m_configDir =
            takeOwnedString(hermes_apppaths_application_support_dir(m_handle));
        m_controlSocketDir =
            takeOwnedString(hermes_apppaths_control_socket_dir(m_handle));
    }
}

HermesCoreBridge::~HermesCoreBridge() {
    if (m_handle != 0) {
        hermes_apppaths_release(m_handle);
        m_handle = 0;
    }
}
