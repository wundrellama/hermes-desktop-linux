#pragma once

#include <QObject>
#include <QString>

/// Thin command surface for application-wide actions. Exposed to QML
/// as `appController`. Holds no state of its own; navigation lives in
/// Main.qml's `currentSection` property and quit goes through
/// QCoreApplication::quit().
///
/// The shortcut Q_PROPERTYs are derived from KStandardShortcut so the
/// user's KDE Global Shortcuts settings are respected — overriding
/// Quit at the system level Just Works.
class AppController : public QObject {
    Q_OBJECT

    /// User's configured Quit key sequence (default "Ctrl+Q").
    Q_PROPERTY(QString quitShortcut READ quitShortcut CONSTANT)

    /// Reasonable default for "show About"; KDE doesn't define a
    /// standard system shortcut for it.
    Q_PROPERTY(QString aboutShortcut READ aboutShortcut CONSTANT)

public:
    explicit AppController(QObject *parent = nullptr);

    QString quitShortcut() const { return m_quitShortcut; }
    QString aboutShortcut() const { return m_aboutShortcut; }

    /// QCoreApplication::quit(). Triggers a clean shutdown.
    Q_INVOKABLE void quit();

signals:
    /// Emitted when the user invokes "About" via the keyboard shortcut.
    /// Main.qml binds onAboutRequested to navigate to the Overview
    /// section (which already shows the version + paths).
    void aboutRequested();

private:
    QString m_quitShortcut;
    QString m_aboutShortcut;
};
