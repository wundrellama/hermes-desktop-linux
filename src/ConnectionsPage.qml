// src/ConnectionsPage.qml
//
// First real screen: a Kirigami.ScrollablePage listing the saved SSH
// hosts, with toolbar Add + Refresh actions and an inline overlay
// sheet editor. Backed by ConnectionsModel (C++) which talks to the
// Swift core via libHermesCore.a.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.ScrollablePage {
    id: page

    title: i18n("Connections")

    // NOTE: Kirigami.ScrollablePage.actions: [...] did not surface as
    // toolbar buttons on Plasma 6.4 / Kirigami 6.18 (Fedora 41). The
    // page-action pipeline expects the host shell to pull actions and
    // render them in a global toolbar — and our `Kirigami.GlobalDrawer
    // { modal: false }` setup doesn't seem to do that. Using an inline
    // Kirigami.ActionToolBar as the page header is the documented
    // alternative and renders reliably.
    header: Kirigami.ActionToolBar {
        flat: false
        actions: [
            Kirigami.Action {
                icon.name: "list-add"
                text: i18n("Add connection")
                displayHint: Kirigami.DisplayHint.KeepVisible
                onTriggered: editor.openWith(connectionsModel.newProfile())
            },
            Kirigami.Action {
                icon.name: "view-refresh"
                text: i18n("Refresh")
                displayHint: Kirigami.DisplayHint.KeepVisible
                onTriggered: connectionsModel.reload()
            }
        ]
    }

    Kirigami.PlaceholderMessage {
        anchors.centerIn: parent
        width: parent.width - (Kirigami.Units.largeSpacing * 4)
        visible: connectionsList.count === 0
        icon.name: "network-server"
        text: i18n("No connections yet")
        explanation: i18n(
            "Add a saved SSH host to manage Hermes agents from this Linux build.\n" +
            "Connections are stored at:\n" +
            hermesCore.configDir + "/connections.json")
    }

    ListView {
        id: connectionsList
        model: connectionsModel
        spacing: Kirigami.Units.smallSpacing
        currentIndex: -1

        delegate: ItemDelegate {
            id: delegate
            width: connectionsList.width
            highlighted: ListView.isCurrentItem

            contentItem: RowLayout {
                spacing: Kirigami.Units.largeSpacing

                Kirigami.Icon {
                    source: "network-server"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Label {
                        text: model.label && model.label.length > 0
                            ? model.label
                            : i18n("(unnamed)")
                        font.bold: true
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    Label {
                        text: model.displayTarget
                        font.family: "monospace"
                        opacity: 0.85
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    Label {
                        text: model.displaySubtitle
                        opacity: 0.65
                        visible: text.length > 0
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }

                // Status indicator: idle (nothing) / running (spinner) /
                // success (green check) / failed (red X with tooltip).
                Item {
                    id: statusIndicator
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                    visible: model.connectionStatus !== "idle"

                    BusyIndicator {
                        anchors.fill: parent
                        visible: model.connectionStatus === "running"
                        running: visible
                    }
                    Kirigami.Icon {
                        anchors.fill: parent
                        visible: model.connectionStatus === "success"
                        source: "emblem-success"

                        MouseArea {
                            id: successHover
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.NoButton
                        }
                        ToolTip.visible: successHover.containsMouse
                        ToolTip.text: model.connectionStatusMessage
                    }
                    Kirigami.Icon {
                        anchors.fill: parent
                        visible: model.connectionStatus === "failed"
                        source: "emblem-error"

                        MouseArea {
                            id: failedHover
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.NoButton
                        }
                        ToolTip.visible: failedHover.containsMouse
                        ToolTip.text: model.connectionStatusMessage
                    }
                }

                Button {
                    icon.name: "network-connect"
                    flat: true
                    enabled: model.connectionStatus !== "running"
                    ToolTip.visible: hovered
                    ToolTip.text: i18n("Test connection (echo round-trip)")
                    onClicked: connectionsModel.testConnection(model.id)
                }
                Button {
                    icon.name: "document-edit"
                    flat: true
                    ToolTip.visible: hovered
                    ToolTip.text: i18n("Edit")
                    onClicked: editor.openWith(connectionsModel.profileAt(index))
                }
                Button {
                    icon.name: "edit-delete"
                    flat: true
                    ToolTip.visible: hovered
                    ToolTip.text: i18n("Delete")
                    onClicked: {
                        confirmDelete.targetId = model.id
                        confirmDelete.targetLabel = model.label
                        confirmDelete.open()
                    }
                }
            }

            onClicked: editor.openWith(connectionsModel.profileAt(index))
        }
    }

    // ----- Editor sheet -----
    Kirigami.OverlaySheet {
        id: editor

        property var profile: ({})

        function openWith(p) {
            editor.profile = JSON.parse(JSON.stringify(p))  // deep copy
            labelField.text = editor.profile.label || ""
            aliasField.text = editor.profile.sshAlias || ""
            hostField.text  = editor.profile.sshHost || ""
            portField.text  = editor.profile.sshPort
                ? String(editor.profile.sshPort) : ""
            userField.text  = editor.profile.sshUser || ""
            hermesProfileField.text =
                editor.profile.hermesProfile || ""
            open()
        }

        title: editor.profile && editor.profile.label
            ? i18n("Edit '%1'", editor.profile.label)
            : i18n("Add connection")

        ColumnLayout {
            implicitWidth: Math.min(Kirigami.Units.gridUnit * 28,
                                     page.width - Kirigami.Units.gridUnit * 4)
            spacing: Kirigami.Units.largeSpacing

            Kirigami.FormLayout {
                Layout.fillWidth: true

                TextField {
                    id: labelField
                    Kirigami.FormData.label: i18n("Label:")
                    placeholderText: i18n("e.g. prod-east")
                    Layout.fillWidth: true
                }
                TextField {
                    id: aliasField
                    Kirigami.FormData.label: i18n("SSH alias:")
                    placeholderText: i18n("matches a Host entry in ~/.ssh/config")
                    Layout.fillWidth: true
                }
                TextField {
                    id: hostField
                    Kirigami.FormData.label: i18n("Host:")
                    placeholderText: i18n("hostname or IP (used when no alias)")
                    Layout.fillWidth: true
                }
                TextField {
                    id: portField
                    Kirigami.FormData.label: i18n("Port:")
                    placeholderText: i18n("22 (default)")
                    inputMethodHints: Qt.ImhDigitsOnly
                    validator: IntValidator { bottom: 1; top: 65535 }
                    Layout.fillWidth: true
                }
                TextField {
                    id: userField
                    Kirigami.FormData.label: i18n("User:")
                    placeholderText: i18n("ssh login name")
                    Layout.fillWidth: true
                }
                TextField {
                    id: hermesProfileField
                    Kirigami.FormData.label: i18n("Hermes profile:")
                    placeholderText: i18n("optional")
                    Layout.fillWidth: true
                }
            }

            Kirigami.InlineMessage {
                id: editorError
                Layout.fillWidth: true
                type: Kirigami.MessageType.Error
                showCloseButton: true
            }

            RowLayout {
                Layout.alignment: Qt.AlignRight
                Layout.topMargin: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.largeSpacing

                Button {
                    text: i18n("Cancel")
                    onClicked: editor.close()
                }
                Button {
                    text: i18n("Save")
                    enabled: labelField.text.length > 0
                          && (aliasField.text.length > 0
                              || hostField.text.length > 0)
                    onClicked: {
                        const p = editor.profile
                        p.label = labelField.text
                        p.sshAlias = aliasField.text
                        p.sshHost = hostField.text
                        p.sshPort = portField.text.length > 0
                            ? parseInt(portField.text) : null
                        p.sshUser = userField.text
                        p.hermesProfile = hermesProfileField.text.length > 0
                            ? hermesProfileField.text : null
                        if (connectionsModel.saveProfile(p)) {
                            editor.close()
                        } else {
                            editorError.text =
                                i18n("Save failed. See terminal log for details.")
                            editorError.visible = true
                        }
                    }
                }
            }
        }
    }

    // ----- Delete confirmation -----
    Dialog {
        id: confirmDelete
        property string targetId: ""
        property string targetLabel: ""
        title: i18n("Delete connection?")
        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.Cancel | Dialog.Yes
        contentItem: Label {
            text: i18n(
                "Permanently remove '%1' from this Linux app's saved hosts? " +
                "(This does not touch your ~/.ssh/config.)",
                confirmDelete.targetLabel.length > 0
                    ? confirmDelete.targetLabel : i18n("(unnamed)"))
            wrapMode: Text.WordWrap
        }
        onAccepted: connectionsModel.removeProfile(confirmDelete.targetId)
    }
}
