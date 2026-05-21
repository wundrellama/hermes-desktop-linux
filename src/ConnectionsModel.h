#pragma once

#include "HermesCore.h"
#include "HermesCoreBridge.h"

#include <QAbstractListModel>
#include <QList>
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
        DisplayTargetRole,   // computed: "user@host[:port]" or alias
        DisplaySubtitleRole, // computed: "alias · hermesProfile" or similar
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

private:
    HermesCoreBridge *m_bridge;
    QList<QVariantMap> m_rows;

    // Helper: convert a QVariantMap row to the JSON the FFI expects.
    QString rowToJson(const QVariantMap &row) const;
    // Helper: build the row's display target string (alias or user@host).
    static QString computeDisplayTarget(const QVariantMap &row);
    static QString computeDisplaySubtitle(const QVariantMap &row);
};
