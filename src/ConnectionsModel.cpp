#include "ConnectionsModel.h"

#include <QByteArray>
#include <QDateTime>
#include <QDebug>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
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
