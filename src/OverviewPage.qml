// src/OverviewPage.qml
//
// Overview / About page. Surfaces the HermesCore version, the storage
// paths the Swift core resolved, and a quick count of saved
// connections. As more sections come online (sessions, kanban, cron,
// etc.) this is where their summary cards land.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.ScrollablePage {
    id: page

    title: i18n("Overview")

    ColumnLayout {
        width: Math.min(page.width - Kirigami.Units.largeSpacing * 4,
                         Kirigami.Units.gridUnit * 36)
        spacing: Kirigami.Units.largeSpacing

        // ----- Identity card -----
        Kirigami.Card {
            Layout.fillWidth: true

            header: Kirigami.Heading {
                text: i18n("Hermes Desktop")
                level: 2
                padding: Kirigami.Units.largeSpacing
            }

            ColumnLayout {
                spacing: Kirigami.Units.smallSpacing
                Layout.margins: Kirigami.Units.largeSpacing

                Label {
                    text: i18n(
                        "Linux build of the Hermes Desktop workbench. The " +
                        "Swift core (libHermesCore.a) is the same one that " +
                        "powers the macOS app — connections.json and " +
                        "preferences.json are read/written in the identical " +
                        "format on both platforms.")
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }
        }

        // ----- HermesCore card -----
        Kirigami.Card {
            Layout.fillWidth: true

            header: Kirigami.Heading {
                text: i18n("HermesCore")
                level: 3
                padding: Kirigami.Units.largeSpacing
            }

            Kirigami.FormLayout {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.largeSpacing

                Label {
                    text: hermesCore.version
                    Kirigami.FormData.label: i18n("Version:")
                    font.family: "monospace"
                }
                Label {
                    text: hermesCore.configDir
                    Kirigami.FormData.label: i18n("Config dir:")
                    font.family: "monospace"
                    wrapMode: Text.WrapAnywhere
                    Layout.maximumWidth: Kirigami.Units.gridUnit * 22
                }
                Label {
                    text: hermesCore.controlSocketDir
                    Kirigami.FormData.label: i18n("Control sockets:")
                    font.family: "monospace"
                    wrapMode: Text.WrapAnywhere
                    Layout.maximumWidth: Kirigami.Units.gridUnit * 22
                }
            }
        }

        // ----- Connection summary card -----
        Kirigami.Card {
            Layout.fillWidth: true

            header: Kirigami.Heading {
                text: i18n("Connections")
                level: 3
                padding: Kirigami.Units.largeSpacing
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.smallSpacing

                Label {
                    text: connectionsModel.rowCount() > 0
                        ? i18np(
                            "%1 saved host",
                            "%1 saved hosts",
                            connectionsModel.rowCount())
                        : i18n("No connections yet")
                    font.pointSize: 18
                    Layout.fillWidth: true
                }
                Label {
                    text: i18n(
                        "Manage them in the Connections section. The list " +
                        "lives at:")
                    wrapMode: Text.WordWrap
                    opacity: 0.75
                    Layout.fillWidth: true
                }
                Label {
                    text: hermesCore.configDir + "/connections.json"
                    font.family: "monospace"
                    opacity: 0.75
                    wrapMode: Text.WrapAnywhere
                    Layout.fillWidth: true
                }
            }
        }
    }
}
