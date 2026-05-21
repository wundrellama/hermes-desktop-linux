#pragma once

#include "HermesCore.h"
#include "HermesCoreBridge.h"

#include <QAbstractListModel>
#include <QHash>
#include <QList>
#include <QMutex>
#include <QString>
#include <QVariantMap>

/// QAbstractListModel-based bridge to the Swift connection store. Each
/// row corresponds to a ConnectionProfile JSON object returned by
/// hermes_connection_list. CRUD operations call back into the C ABI.
///
/// Thread affinity: lives on Qt's main thread. The C ABI is itself
/// thread-safe (NSLock-protected) but row-change signals must be
/// emitted on the QML thread.
class ConnectionsModel : public QAbstractListModel {
    Q_OBJECT

public:
    enum Roles {
        IdRole = Qt::UserRole + 1,
        LabelRole,
        SSHAliasRole,
        SSHHostRole,
        SSHPortRole,
        SSHUserRole,
        HermesProfileRole,
        CustomHermesHomePathRole,
        CreatedAtRole,
        UpdatedAtRole,
        LastConnectedAtRole,
        DisplayTargetRole,         // computed: "user@host[:port]" or alias
        DisplaySubtitleRole,       // computed: "alias · hermesProfile" or similar
        ConnectionStatusRole,      // "idle" | "running" | "success" | "failed"
        ConnectionStatusMessageRole, // human-readable result on success/failed
    };

    enum ConnectionStatus {
        StatusIdle = 0,
        StatusRunning,
        StatusSuccess,
        StatusFailed,
    };

    explicit ConnectionsModel(HermesCoreBridge *bridge, QObject *parent = nullptr);

    // QAbstractListModel
    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    /// Pull the latest array from disk via hermes_connection_list.
    Q_INVOKABLE void reload();

    /// Returns the row as a JS-friendly QVariantMap. Used by QML to seed
    /// the editor sheet. Out-of-range row returns an empty map.
    Q_INVOKABLE QVariantMap profileAt(int row) const;

    /// Returns a fresh, empty profile with a new UUID and current
    /// timestamps. The editor uses this to seed the "Add" form.
    Q_INVOKABLE QVariantMap newProfile() const;

    /// Persists the profile via hermes_connection_save. Returns true on
    /// success (status 0); reload() is invoked on success.
    Q_INVOKABLE bool saveProfile(const QVariantMap &profile);

    /// Removes the profile by UUID string via hermes_connection_delete.
    /// Returns true on success.
    Q_INVOKABLE bool removeProfile(const QString &id);

    /// Kick off an SSH connectivity test against the given connection id.
    /// Runs `echo hermes-connectivity-check` over the profile and updates
    /// the row's connectionStatus / connectionStatusMessage on completion.
    /// Returns immediately; the result lands asynchronously.
    Q_INVOKABLE void testConnection(const QString &id);

private:
    HermesCoreBridge *m_bridge;
    QList<QVariantMap> m_rows;

    // Per-id status state, keyed by ConnectionProfile.id (UUID string).
    // Reads happen on the QML thread inside data(); writes happen on the
    // QML thread inside testConnection() (kick-off) and inside the
    // queued slot that fires after the async callback marshals back.
    QHash<QString, ConnectionStatus> m_status;
    QHash<QString, QString> m_statusMessage;

    // In-flight async requests. Touched from BOTH the QML thread
    // (insert at submit; lookup at result) AND the Swift callback
    // thread (take at result, before queuing to QML thread). Guarded
    // by m_inflightMutex.
    QHash<qint64, QString> m_inflight;
    QMutex m_inflightMutex;

    // Helper: convert a QVariantMap row to the JSON the FFI expects.
    QString rowToJson(const QVariantMap &row) const;
    // Helper: build the row's display target string (alias or user@host).
    static QString computeDisplayTarget(const QVariantMap &row);
    static QString computeDisplaySubtitle(const QVariantMap &row);
    // Look up a row by its UUID. Returns -1 if not present.
    int rowIndexForId(const QString &id) const;

    // Static C callback hooked into hermes_ssh_execute. Fires on a
    // Swift cooperative-pool worker — marshals back to the QML thread.
    static void asyncCallback(int64_t req, const char *resultJson, void *user);

    // QML-thread slot that interprets the result JSON and updates state.
    Q_INVOKABLE void handleTestResult(const QString &id, const QString &resultJson);

    // Persist the new status + emit dataChanged for the matching row.
    void setStatus(const QString &id, ConnectionStatus status, const QString &message);
};
