#include "AppController.h"

#include <QCoreApplication>
#include <QKeySequence>
#include <QList>

#include <KStandardShortcut>

namespace {
/// Returns the first portable-text rendering of the first key sequence
/// in `list`, or `fallback` if the list is empty.
QString firstSequenceText(const QList<QKeySequence> &list,
                          const QString &fallback) {
    if (list.isEmpty()) {
        return fallback;
    }
    return list.first().toString(QKeySequence::PortableText);
}
}  // namespace

AppController::AppController(QObject *parent)
    : QObject(parent),
      m_quitShortcut(firstSequenceText(
          KStandardShortcut::shortcut(KStandardShortcut::Quit),
          QStringLiteral("Ctrl+Q"))),
      // No KStandardShortcut for "About"; "Ctrl+Shift+A" is a common
      // KDE convention (matches Discover, Konsole's About flow, etc.).
      m_aboutShortcut(QStringLiteral("Ctrl+Shift+A")) {
}

void AppController::quit() {
    QCoreApplication::quit();
}
