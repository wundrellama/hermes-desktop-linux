// src/Main.qml — entry point QML, loaded by main.cpp.
//
// Renders a Kirigami.ApplicationWindow with one Page that displays the
// HermesCore version + resolved XDG paths via the `hermesCore` context
// property set up by main.cpp.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.ApplicationWindow {
    id: root

    title: i18n("Hermes Desktop (Linux skeleton)")
    width: 720
    height: 480
    minimumWidth: 480
    minimumHeight: 320

    pageStack.initialPage: Kirigami.Page {
        title: i18n("About")

        ColumnLayout {
            anchors.centerIn: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing
            width: Math.min(parent.width - Kirigami.Units.gridUnit * 4,
                            Kirigami.Units.gridUnit * 32)

            Kirigami.Heading {
                text: i18n("Hermes Desktop")
                level: 1
                Layout.alignment: Qt.AlignHCenter
            }

            Kirigami.Heading {
                text: i18n("Linux port — skeleton")
                level: 3
                opacity: 0.7
                Layout.alignment: Qt.AlignHCenter
            }

            Kirigami.Separator {
                Layout.fillWidth: true
            }

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
                    Layout.maximumWidth: root.width * 0.6
                }

                Label {
                    text: hermesCore.controlSocketDir
                    Kirigami.FormData.label: i18n("Control sockets:")
                    font.family: "monospace"
                    wrapMode: Text.WrapAnywhere
                    Layout.maximumWidth: root.width * 0.6
                }
            }
        }
    }
}
