// src/PlaceholderPage.qml
//
// Generic "coming soon" page used by every sidebar section that
// doesn't have a real implementation yet. The macOS app has eight
// sections beyond Overview + Connections (Files, Sessions, Workflows,
// CronJobs, Kanban, Usage, Skills, Terminal) — each will replace this
// placeholder one by one.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.ScrollablePage {
    id: page

    property string sectionId: ""
    property string sectionTitle: ""
    property string sectionIcon: "view-list-symbolic"
    property string sectionDescription: ""

    title: page.sectionTitle

    Kirigami.PlaceholderMessage {
        anchors.centerIn: parent
        width: parent.width - (Kirigami.Units.largeSpacing * 4)
        icon.name: page.sectionIcon
        text: i18n("%1 — coming soon", page.sectionTitle)
        explanation: page.sectionDescription.length > 0
            ? page.sectionDescription
            : i18n(
                "This section is on the Linux port roadmap. It already " +
                "works in the macOS build; the Linux UI hasn't been " +
                "written yet.")
    }
}
