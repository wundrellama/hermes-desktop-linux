// src/main.cpp — Linux skeleton entry point.
//
// Bootstraps a Kirigami ApplicationWindow that displays the HermesCore
// version + resolved XDG paths pulled live from libHermesCore.a. The
// first end-to-end proof that the Swift core, the C ABI, and the
// Qt6/Kirigami stack actually compose.

#include "AppController.h"
#include "ConnectionsModel.h"
#include "HermesCoreBridge.h"

#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QUrl>

#include <KAboutData>
#include <KCrash>
#include <KLocalizedContext>
#include <KLocalizedString>

int main(int argc, char *argv[]) {
    QApplication app(argc, argv);
    QApplication::setApplicationName(QStringLiteral("hermes-desktop"));
    QApplication::setOrganizationName(QStringLiteral("dodo-reach"));
    QApplication::setOrganizationDomain(QStringLiteral("hermesdesktop.com"));

    KAboutData about(
        QStringLiteral("hermes-desktop"),
        QStringLiteral("Hermes Desktop"),
        QStringLiteral("0.1.0-linux-port"),
        QStringLiteral(
            "Linux port of hermes-desktop — Swift core + Qt6/Kirigami UI."),
        KAboutLicense::MIT);
    KAboutData::setApplicationData(about);
    KCrash::initialize();

    // Required for the QML `i18n()` / `i18nc()` / `i18np()` helpers and
    // the underlying KLocalizedString lookup. Without this, every `text:
    // i18n("...")` in QML evaluates to undefined, and Kirigami hides
    // toolbar actions / sidebar entries whose text is empty.
    KLocalizedString::setApplicationDomain("hermes-desktop");

    // Bridge owns the AppPaths handle for the process lifetime.
    HermesCoreBridge bridge;

    // The model reuses the bridge's handle for every CRUD call.
    ConnectionsModel connectionsModel(&bridge);

    // Application-wide commands (quit, about) + their KDE-canonical
    // key sequences.
    AppController appController;

    QQmlApplicationEngine engine;
    // Install KLocalizedContext as the engine-wide context object so QML
    // can call i18n() everywhere without per-file imports.
    engine.rootContext()->setContextObject(new KLocalizedContext(&engine));
    engine.rootContext()->setContextProperty(QStringLiteral("hermesCore"),
                                             &bridge);
    engine.rootContext()->setContextProperty(QStringLiteral("connectionsModel"),
                                             &connectionsModel);
    engine.rootContext()->setContextProperty(QStringLiteral("appController"),
                                             &appController);
    engine.load(QUrl(QStringLiteral("qrc:/qt/qml/HermesDesktop/Main.qml")));

    if (engine.rootObjects().isEmpty()) {
        return -1;
    }

    return app.exec();
}
