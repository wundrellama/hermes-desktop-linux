#pragma once

#include "HermesCore.h"

#include <QObject>
#include <QString>

/// QObject wrapper around the HermesCore C ABI. Owns one AppPaths handle
/// for the process lifetime. Exposes read-only Q_PROPERTY values usable
/// from QML.
///
/// Thread affinity: the bridge MUST live on Qt's main thread. The
/// underlying C ABI is itself thread-safe (NSLock-protected), but the
/// Q_PROPERTY mechanism is not designed for off-thread mutation.
class HermesCoreBridge : public QObject {
    Q_OBJECT

    /// HermesCore library version (e.g. "0.1.0-linux-port").
    Q_PROPERTY(QString version READ version CONSTANT)

    /// Resolved $XDG_CONFIG_HOME/HermesDesktop directory.
    Q_PROPERTY(QString configDir READ configDir CONSTANT)

    /// Resolved $XDG_RUNTIME_DIR/hermes-desktop/cs directory.
    Q_PROPERTY(QString controlSocketDir READ controlSocketDir CONSTANT)

public:
    explicit HermesCoreBridge(QObject *parent = nullptr);
    ~HermesCoreBridge() override;

    QString version() const { return m_version; }
    QString configDir() const { return m_configDir; }
    QString controlSocketDir() const { return m_controlSocketDir; }

    /// Exposed for later screens that need the AppPaths handle directly.
    /// Returns 0 if initialization failed.
    hermes_handle_t pathsHandle() const { return m_handle; }

private:
    hermes_handle_t m_handle = 0;
    QString m_version;
    QString m_configDir;
    QString m_controlSocketDir;
};
