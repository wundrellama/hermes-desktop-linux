#!/usr/bin/env bash
# scripts/run-debug.sh — launch the C++ binary inside hermes-build with
# maximal Qt/Kirigami logging and tee everything to /tmp/hermes.log.
#
# Use when the UI is misbehaving and we need stderr to diagnose:
#
#   ./scripts/run-debug.sh
#
# Then click around (Overview → Connections → Connections again →
# global drawer → close) for ~10s and ^C.
#
# Share /tmp/hermes.log afterwards.

set -u

LOG=/tmp/hermes.log
: > "$LOG"

echo "Logging to: $LOG"
echo "----------- begin -----------" | tee -a "$LOG"

# Enable everything we might possibly want:
#   default.debug=true     — QML console.log + qDebug() output
#   qt.qml.binding.removal.info=true — binding failures
#   qt.qml.connections.warning=true  — bad signal/slot
#   qt.quick.diagnostic.qmlerror=true — visible QML errors
#   kf.kirigami*=true                 — Kirigami's own warnings
QT_LOGGING_RULES="default.debug=true;\
qt.qml.*=true;\
qt.quick.diagnostic.qmlerror=true;\
kf.kirigami*=true" \
QML_IMPORT_TRACE=0 \
QT_MESSAGE_PATTERN='[%{category}] %{type}: %{message}' \
exec build/src/hermes-desktop 2>&1 | tee -a "$LOG"
