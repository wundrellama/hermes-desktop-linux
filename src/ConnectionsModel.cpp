#include "ConnectionsModel.h"

#include <QByteArray>
#include <QDateTime>
#include <QDebug>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QMetaObject>
#include <QMutexLocker>
#include <QUuid>

namespace {
/// Take ownership of a hermes_* char* return.
QString takeOwnedString(char *ptr) {
    if (ptr == nullptr) {
        return {};
    }
    QString result = QString::fromUtf8(ptr);
    hermes_free_string(ptr);
    return result;
}

QVariantMap jsonObjectToMap(const QJsonObject &obj) {
    QVariantMap map;
    for (auto it = obj.constBegin(); it != obj.constEnd(); ++it) {
        map.insert(it.key(), it.value().toVariant());
    }
    return map;
}
}  // namespace

ConnectionsModel::ConnectionsModel(HermesCoreBridge *bridge, QObject *parent)
    : QAbstractListModel(parent), m_bridge(bridge) {
    reload();
}

int ConnectionsModel::rowCount(const QModelIndex &parent) const {
    if (parent.isValid()) {
        return 0;
    }
    return m_rows.size();
}

QVariant ConnectionsModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_rows.size()) {
        return {};
    }
    const QVariantMap &row = m_rows.at(index.row());
    switch (role) {
        case IdRole:                    return row.value("id");
        case LabelRole:                 return row.value("label");
        case SSHAliasRole:              return row.value("sshAlias");
        case SSHHostRole:               return row.value("sshHost");
        case SSHPortRole:               return row.value("sshPort");
        case SSHUserRole:               return row.value("sshUser");
        case HermesProfileRole:         return row.value("hermesProfile");
        case CustomHermesHomePathRole:  return row.value("customHermesHomePath");
        case CreatedAtRole:             return row.value("createdAt");
        case UpdatedAtRole:             return row.value("updatedAt");
        case LastConnectedAtRole:       return row.value("lastConnectedAt");
        case DisplayTargetRole:         return computeDisplayTarget(row);
        case DisplaySubtitleRole:       return computeDisplaySubtitle(row);
        case ConnectionStatusRole: {
            const QString id = row.value("id").toString();
            switch (m_status.value(id, StatusIdle)) {
                case StatusIdle:    return QStringLiteral("idle");
                case StatusRunning: return QStringLiteral("running");
                case StatusSuccess: return QStringLiteral("success");
                case StatusFailed:  return QStringLiteral("failed");
            }
            return QStringLiteral("idle");
        }
        case ConnectionStatusMessageRole: {
            const QString id = row.value("id").toString();
            return m_statusMessage.value(id);
        }
        default:                        return {};
    }
}

QHash<int, QByteArray> ConnectionsModel::roleNames() const {
    return {
        {IdRole,                    "id"},
        {LabelRole,                 "label"},
        {SSHAliasRole,              "sshAlias"},
        {SSHHostRole,               "sshHost"},
        {SSHPortRole,               "sshPort"},
        {SSHUserRole,               "sshUser"},
        {HermesProfileRole,         "hermesProfile"},
        {CustomHermesHomePathRole,  "customHermesHomePath"},
        {CreatedAtRole,             "createdAt"},
        {UpdatedAtRole,             "updatedAt"},
        {LastConnectedAtRole,       "lastConnectedAt"},
        {DisplayTargetRole,         "displayTarget"},
        {DisplaySubtitleRole,       "displaySubtitle"},
        {ConnectionStatusRole,      "connectionStatus"},
        {ConnectionStatusMessageRole, "connectionStatusMessage"},
    };
}

void ConnectionsModel::reload() {
    const hermes_handle_t handle = m_bridge ? m_bridge->pathsHandle() : 0;
    if (handle == 0) {
        return;
    }

    const QString json = takeOwnedString(hermes_connection_list(handle));
    QJsonParseError parseError{};
    const QJsonDocument doc = QJsonDocument::fromJson(json.toUtf8(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !doc.isArray()) {
        qWarning() << "ConnectionsModel::reload: bad JSON from"
                   << "hermes_connection_list:" << parseError.errorString();
        return;
    }

    QList<QVariantMap> next;
    const QJsonArray arr = doc.array();
    next.reserve(arr.size());
    for (const QJsonValue &val : arr) {
        if (!val.isObject()) {
            continue;
        }
        next.append(jsonObjectToMap(val.toObject()));
    }

    beginResetModel();
    m_rows = std::move(next);
    endResetModel();
}

QVariantMap ConnectionsModel::profileAt(int row) const {
    if (row < 0 || row >= m_rows.size()) {
        return {};
    }
    return m_rows.at(row);
}

QVariantMap ConnectionsModel::newProfile() const {
    QVariantMap profile;
    profile.insert("id", QUuid::createUuid().toString(QUuid::WithoutBraces).toLower());
    profile.insert("label", QString());
    profile.insert("sshAlias", QString());
    profile.insert("sshHost", QString());
    profile.insert("sshUser", QString());
    profile.insert("hermesProfile", QVariant());
    profile.insert("customHermesHomePath", QVariant());
    profile.insert("sshPort", QVariant());

    // Swift's JSONDecoder .iso8601 strategy uses ISO8601DateFormatter with
    // its default options (no fractional seconds) — match that here.
    const QString nowIso =
        QDateTime::currentDateTimeUtc().toString(Qt::ISODate);
    profile.insert("createdAt", nowIso);
    profile.insert("updatedAt", nowIso);
    profile.insert("lastConnectedAt", QVariant());
    return profile;
}

bool ConnectionsModel::saveProfile(const QVariantMap &profile) {
    const hermes_handle_t handle = m_bridge ? m_bridge->pathsHandle() : 0;
    if (handle == 0) {
        return false;
    }
    const QString json = rowToJson(profile);
    const QByteArray utf8 = json.toUtf8();
    const int32_t status = hermes_connection_save(handle, utf8.constData());
    if (status != 0) {
        qWarning() << "hermes_connection_save returned" << status
                   << "for profile id" << profile.value("id");
        return false;
    }
    reload();
    return true;
}

bool ConnectionsModel::removeProfile(const QString &id) {
    const hermes_handle_t handle = m_bridge ? m_bridge->pathsHandle() : 0;
    if (handle == 0) {
        return false;
    }
    const QByteArray idUtf8 = id.toUtf8();
    const int32_t status = hermes_connection_delete(handle, idUtf8.constData());
    if (status != 0) {
        qWarning() << "hermes_connection_delete returned" << status
                   << "for id" << id;
        return false;
    }
    reload();
    return true;
}

QString ConnectionsModel::rowToJson(const QVariantMap &row) const {
    // Build a normalized object: ensure required fields exist; treat
    // empty strings as nulls for optional fields so the on-disk shape
    // matches what the macOS path writes (omits null/empty keys).
    QJsonObject obj;

    auto putString = [&](const QString &key, const QVariant &value, bool required) {
        const QString s = value.toString();
        if (required) {
            obj.insert(key, s);
        } else if (!s.isEmpty()) {
            obj.insert(key, s);
        } else {
            // Explicit null — the Swift JSONDecoder accepts both omitted
            // and null for optional Codable fields.
            obj.insert(key, QJsonValue::Null);
        }
    };

    putString("id", row.value("id"), true);
    putString("label", row.value("label"), true);
    putString("sshAlias", row.value("sshAlias"), true);
    putString("sshHost", row.value("sshHost"), true);
    putString("sshUser", row.value("sshUser"), true);

    {
        const QVariant port = row.value("sshPort");
        bool ok = false;
        const int p = port.toInt(&ok);
        if (ok && p > 0) {
            obj.insert("sshPort", p);
        } else {
            obj.insert("sshPort", QJsonValue::Null);
        }
    }

    putString("hermesProfile", row.value("hermesProfile"), false);
    putString("customHermesHomePath", row.value("customHermesHomePath"), false);

    // Always update the updatedAt stamp on save.
    const QString nowIso = QDateTime::currentDateTimeUtc().toString(Qt::ISODate);
    putString("createdAt",
              row.value("createdAt").toString().isEmpty()
                  ? nowIso
                  : row.value("createdAt").toString(),
              true);
    obj.insert("updatedAt", nowIso);
    putString("lastConnectedAt", row.value("lastConnectedAt"), false);

    return QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Compact));
}

QString ConnectionsModel::computeDisplayTarget(const QVariantMap &row) {
    const QString alias = row.value("sshAlias").toString().trimmed();
    if (!alias.isEmpty()) {
        return alias;
    }
    const QString user = row.value("sshUser").toString().trimmed();
    const QString host = row.value("sshHost").toString().trimmed();
    const bool hasPort = row.value("sshPort").isValid()
                         && row.value("sshPort").toInt() > 0;
    QString target;
    if (!user.isEmpty()) {
        target += user + QStringLiteral("@");
    }
    target += host;
    if (hasPort) {
        target += QStringLiteral(":") + QString::number(row.value("sshPort").toInt());
    }
    return target;
}

int ConnectionsModel::rowIndexForId(const QString &id) const {
    for (int i = 0; i < m_rows.size(); ++i) {
        if (m_rows.at(i).value("id").toString() == id) {
            return i;
        }
    }
    return -1;
}

void ConnectionsModel::setStatus(const QString &id,
                                 ConnectionStatus status,
                                 const QString &message) {
    if (status == StatusIdle) {
        m_status.remove(id);
        m_statusMessage.remove(id);
    } else {
        m_status[id] = status;
        m_statusMessage[id] = message;
    }
    const int row = rowIndexForId(id);
    if (row >= 0) {
        const QModelIndex idx = index(row);
        emit dataChanged(idx, idx,
                         {ConnectionStatusRole, ConnectionStatusMessageRole});
    }
}

void ConnectionsModel::testConnection(const QString &id) {
    const int row = rowIndexForId(id);
    if (row < 0) {
        qWarning() << "testConnection: unknown id" << id;
        return;
    }
    const QVariantMap profile = m_rows.at(row);

    const hermes_handle_t handle = m_bridge ? m_bridge->pathsHandle() : 0;
    if (handle == 0) {
        setStatus(id, StatusFailed, tr("No HermesCore handle."));
        return;
    }

    // The Swift JSONDecoder.iso8601 strategy needs the field shape exactly
    // as ConnectionPersistence writes it — round-trip through rowToJson
    // for consistency rather than handing the in-memory QVariantMap raw.
    const QString profileJson = rowToJson(profile);
    const QByteArray profileUtf8 = profileJson.toUtf8();

    const char *remoteCommand = "echo hermes-connectivity-check";

    setStatus(id, StatusRunning, QString());

    const int64_t req = hermes_ssh_execute(
        handle,
        profileUtf8.constData(),
        remoteCommand,
        0,         // no TTY
        nullptr,   // no stdin
        &ConnectionsModel::asyncCallback,
        this);

    if (req == 0) {
        setStatus(id, StatusFailed,
                  tr("Submission failed — check the connection fields."));
        return;
    }

    QMutexLocker lock(&m_inflightMutex);
    m_inflight.insert(req, id);
}

// static — fires on a Swift cooperative-pool worker thread.
void ConnectionsModel::asyncCallback(int64_t req,
                                     const char *resultJson,
                                     void *user) {
    auto *self = static_cast<ConnectionsModel *>(user);
    const QString payload = resultJson ? QString::fromUtf8(resultJson) : QString();
    if (resultJson) {
        // Per the HermesCore.h ownership contract.
        hermes_free_string(const_cast<char *>(resultJson));
    }

    QString id;
    {
        QMutexLocker lock(&self->m_inflightMutex);
        id = self->m_inflight.take(req);
    }
    if (id.isEmpty()) {
        // Spurious / late callback (handle reused after release, etc.).
        return;
    }

    // Marshal onto the QML/Qt main thread. handleTestResult is a
    // Q_INVOKABLE slot on self — the cross-thread invocation is safe.
    QMetaObject::invokeMethod(
        self,
        [self, id, payload]() { self->handleTestResult(id, payload); },
        Qt::QueuedConnection);
}

void ConnectionsModel::handleTestResult(const QString &id,
                                        const QString &resultJson) {
    QJsonParseError err{};
    const QJsonDocument doc =
        QJsonDocument::fromJson(resultJson.toUtf8(), &err);
    if (err.error != QJsonParseError::NoError || !doc.isObject()) {
        setStatus(id, StatusFailed,
                  tr("Invalid response from core: %1").arg(err.errorString()));
        return;
    }
    const QJsonObject obj = doc.object();
    const bool ok = obj.value(QStringLiteral("ok")).toBool(false);

    if (ok) {
        const QJsonObject data =
            obj.value(QStringLiteral("data")).toObject();
        const int exitCode =
            data.value(QStringLiteral("exitCode")).toInt(-1);
        if (exitCode == 0) {
            setStatus(id, StatusSuccess,
                      tr("Connected — echo round-trip succeeded."));
        } else {
            const QString stderr_ =
                data.value(QStringLiteral("stderr")).toString();
            setStatus(id, StatusFailed,
                      tr("Remote exited %1: %2")
                          .arg(exitCode)
                          .arg(stderr_.left(160)));
        }
        return;
    }

    const QJsonObject error =
        obj.value(QStringLiteral("error")).toObject();
    const QString code =
        error.value(QStringLiteral("code")).toString();
    const QString message =
        error.value(QStringLiteral("message")).toString();
    setStatus(id, StatusFailed,
              tr("%1: %2").arg(code, message));
}

QString ConnectionsModel::computeDisplaySubtitle(const QVariantMap &row) {
    QStringList parts;
    const QString alias = row.value("sshAlias").toString().trimmed();
    const QString host = row.value("sshHost").toString().trimmed();
    if (!alias.isEmpty() && !host.isEmpty()) {
        parts.append(QStringLiteral("host %1").arg(host));
    }
    const QString hermesProfile = row.value("hermesProfile").toString().trimmed();
    if (!hermesProfile.isEmpty()) {
        parts.append(QStringLiteral("profile %1").arg(hermesProfile));
    }
    return parts.join(QStringLiteral(" · "));
}
