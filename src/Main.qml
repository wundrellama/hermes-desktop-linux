// src/Main.qml — entry point QML, loaded by main.cpp.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.ApplicationWindow {
    id: root

    title: i18n("Hermes Desktop (Linux)")
    width: 960
    height: 640
    minimumWidth: 720
    minimumHeight: 480

    pageStack.initialPage: ConnectionsPage {}

    globalDrawer: Kirigami.GlobalDrawer {
        isMenu: true
        actions: [
            Kirigami.Action {
                text: i18n("About Hermes Desktop")
                icon.name: "help-about"
                onTriggered: aboutSheet.open()
            }
        ]
    }

    Kirigami.OverlaySheet {
        id: aboutSheet
        title: i18n("About")

        ColumnLayout {
            implicitWidth: Kirigami.Units.gridUnit * 24
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Heading {
                text: i18n("Hermes Desktop")
                level: 2
                Layout.alignment: Qt.AlignHCenter
            }
            Kirigami.Heading {
                text: i18n("Linux port — early skeleton")
                level: 4
                opacity: 0.7
                Layout.alignment: Qt.AlignHCenter
            }

            Kirigami.Separator { Layout.fillWidth: true }

            Kirigami.FormLayout {
                Layout.fillWidth: true

                Label {
                    text: hermesCore.version
                    Kirigami.FormData.label: i18n("HermesCore version:")
                    font.family: "monospace"
                }
                Label {
                    text: hermesCore.configDir
                    Kirigami.FormData.label: i18n("Config dir:")
                    font.family: "monospace"
                    wrapMode: Text.WrapAnywhere
                    Layout.maximumWidth: Kirigami.Units.gridUnit * 18
                }
                Label {
                    text: hermesCore.controlSocketDir
                    Kirigami.FormData.label: i18n("Control sockets:")
                    font.family: "monospace"
                    wrapMode: Text.WrapAnywhere
                    Layout.maximumWidth: Kirigami.Units.gridUnit * 18
                }
            }
        }
    }
}
