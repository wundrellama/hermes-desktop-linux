// src/Main.qml — entry point QML, loaded by main.cpp.
//
// Persistent Kirigami.GlobalDrawer sidebar listing all 10 sections from
// the macOS AppSection enum. Selecting a section swaps the currently-
// displayed page via a Loader on root.pageStack.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.ApplicationWindow {
    id: root

    title: i18n("Hermes Desktop (Linux)")
    width: 1080
    height: 720
    minimumWidth: 840
    minimumHeight: 560

    /// Selected sidebar section identifier; matches macOS AppSection rawValues.
    property string currentSection: "overview"

    // ----- Application-wide shortcuts -----
    // Quit via KStandardShortcut-derived sequence (defaults Ctrl+Q on KDE).
    Shortcut {
        sequences: [appController.quitShortcut, StandardKey.Quit]
        onActivated: appController.quit()
    }
    // About → navigate to Overview, which is where version + paths live.
    Shortcut {
        sequence: appController.aboutShortcut
        onActivated: root.currentSection = "overview"
    }
    Connections {
        target: appController
        function onAboutRequested() {
            root.currentSection = "overview"
        }
    }

    // Section navigation shortcuts (Ctrl+1..0). Matches the macOS app's
    // HermesDesktopCommands keyboard map: 1=Connections (was), 2=Overview,
    // ... we keep the same ordering Linux-side for muscle memory.
    Shortcut { sequence: "Ctrl+1"; onActivated: root.currentSection = "connections" }
    Shortcut { sequence: "Ctrl+2"; onActivated: root.currentSection = "overview" }
    Shortcut { sequence: "Ctrl+3"; onActivated: root.currentSection = "sessions" }
    Shortcut { sequence: "Ctrl+4"; onActivated: root.currentSection = "workflows" }
    Shortcut { sequence: "Ctrl+5"; onActivated: root.currentSection = "cronjobs" }
    Shortcut { sequence: "Ctrl+6"; onActivated: root.currentSection = "kanban" }
    Shortcut { sequence: "Ctrl+7"; onActivated: root.currentSection = "files" }
    Shortcut { sequence: "Ctrl+8"; onActivated: root.currentSection = "usage" }
    Shortcut { sequence: "Ctrl+9"; onActivated: root.currentSection = "skills" }
    Shortcut { sequence: "Ctrl+0"; onActivated: root.currentSection = "terminal" }

    pageStack.initialPage: Loader {
        id: sectionLoader
        active: true
        sourceComponent: {
            switch (root.currentSection) {
                case "overview":    return overviewComponent
                case "connections": return connectionsComponent
                default:            return placeholderComponent
            }
        }
    }

    // ----- Real pages -----
    Component { id: overviewComponent;    OverviewPage {} }
    Component { id: connectionsComponent; ConnectionsPage {} }

    // ----- Placeholders for sections that aren't ported yet -----
    Component {
        id: placeholderComponent
        PlaceholderPage {
            sectionId: root.currentSection
            sectionTitle: {
                switch (root.currentSection) {
                    case "files":     return i18n("Files")
                    case "sessions":  return i18n("Sessions")
                    case "workflows": return i18n("Workflows")
                    case "cronjobs":  return i18n("Cron Jobs")
                    case "kanban":    return i18n("Kanban")
                    case "usage":     return i18n("Usage")
                    case "skills":    return i18n("Skills")
                    case "terminal":  return i18n("Terminal")
                    default:          return i18n("Unknown section")
                }
            }
            sectionIcon: {
                switch (root.currentSection) {
                    case "files":     return "document-multiple"
                    case "sessions":  return "view-conversation-balloon"
                    case "workflows": return "bookmarks"
                    case "cronjobs":  return "view-calendar-tasks"
                    case "kanban":    return "view-task"
                    case "usage":     return "view-statistics"
                    case "skills":    return "office-book"
                    case "terminal":  return "utilities-terminal"
                    default:          return "view-list-symbolic"
                }
            }
            sectionDescription: {
                switch (root.currentSection) {
                    case "files":
                        return i18n("Remote file editor for files up to 10 MB. " +
                                    "Conflict-detection on save matches the " +
                                    "macOS workflow.")
                    case "sessions":
                        return i18n("Browse the remote Hermes session store. " +
                                    "Transcripts, search, pin, continue chat, " +
                                    "resume in terminal.")
                    case "workflows":
                        return i18n("Reusable prompt presets scoped to a host " +
                                    "and Hermes profile.")
                    case "cronjobs":
                        return i18n("Manage the remote scheduler — create, " +
                                    "edit, pause, resume, run-now, delete.")
                    case "kanban":
                        return i18n("Upstream Hermes Kanban boards: tasks, " +
                                    "dependencies, comments, run history.")
                    case "usage":
                        return i18n("Token totals, top sessions, top models, " +
                                    "profile breakdowns. Will use Qt Charts.")
                    case "skills":
                        return i18n("Discover and edit remote SKILL.md files " +
                                    "anchored to the Hermes skills store.")
                    case "terminal":
                        return i18n("Embedded SSH terminal with tabs and " +
                                    "themes. Will use QTermWidget.")
                    default:
                        return ""
                }
            }
        }
    }

    // ----- Sidebar -----
    globalDrawer: Kirigami.GlobalDrawer {
        modal: false
        drawerOpen: true
        width: Kirigami.Units.gridUnit * 11
        handleVisible: false
        title: i18n("Hermes Desktop")
        titleIcon: "preferences-system-network"

        actions: [
            Kirigami.Action {
                text: i18n("Overview")
                icon.name: "applications-system"
                checked: root.currentSection === "overview"
                onTriggered: root.currentSection = "overview"
            },
            Kirigami.Action {
                text: i18n("Connections")
                icon.name: "network-server"
                checked: root.currentSection === "connections"
                onTriggered: root.currentSection = "connections"
            },
            Kirigami.Action { separator: true },
            Kirigami.Action {
                text: i18n("Sessions")
                icon.name: "view-conversation-balloon"
                checked: root.currentSection === "sessions"
                onTriggered: root.currentSection = "sessions"
            },
            Kirigami.Action {
                text: i18n("Files")
                icon.name: "document-multiple"
                checked: root.currentSection === "files"
                onTriggered: root.currentSection = "files"
            },
            Kirigami.Action {
                text: i18n("Workflows")
                icon.name: "bookmarks"
                checked: root.currentSection === "workflows"
                onTriggered: root.currentSection = "workflows"
            },
            Kirigami.Action {
                text: i18n("Cron Jobs")
                icon.name: "view-calendar-tasks"
                checked: root.currentSection === "cronjobs"
                onTriggered: root.currentSection = "cronjobs"
            },
            Kirigami.Action {
                text: i18n("Kanban")
                icon.name: "view-task"
                checked: root.currentSection === "kanban"
                onTriggered: root.currentSection = "kanban"
            },
            Kirigami.Action {
                text: i18n("Usage")
                icon.name: "view-statistics"
                checked: root.currentSection === "usage"
                onTriggered: root.currentSection = "usage"
            },
            Kirigami.Action {
                text: i18n("Skills")
                icon.name: "office-book"
                checked: root.currentSection === "skills"
                onTriggered: root.currentSection = "skills"
            },
            Kirigami.Action { separator: true },
            Kirigami.Action {
                text: i18n("Terminal")
                icon.name: "utilities-terminal"
                checked: root.currentSection === "terminal"
                onTriggered: root.currentSection = "terminal"
            }
        ]
    }
}
