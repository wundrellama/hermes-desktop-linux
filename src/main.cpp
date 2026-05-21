// src/main.cpp — Linux skeleton entry point.
//
// Bootstraps a Kirigami ApplicationWindow that displays the HermesCore
// version + resolved XDG paths pulled live from libHermesCore.a. The
// first end-to-end proof that the Swift core, the C ABI, and the
// Qt6/Kirigami stack actually compose.

#include "HermesCoreBridge.h"

#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QUrl>

#include <KAboutData>
#include <KCrash>

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

    // Bridge owns the AppPaths handle for the process lifetime.
    HermesCoreBridge bridge;

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("hermesCore"),
                                             &bridge);
    engine.load(QUrl(QStringLiteral("qrc:/qt/qml/HermesDesktop/Main.qml")));

    if (engine.rootObjects().isEmpty()) {
        return -1;
    }

    return app.exec();
}
