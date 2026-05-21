# SwiftCrossUI: tag pin + backend choice

**Status**: Decision proposed; awaits user confirmation. Material deviation from the original plan.

## Tag pinned

**`v0.6.0`** (released 2026-05-14, current `latest` as of 2026-05-20).

Source: https://github.com/moreSwift/swift-cross-ui (`stackotter/swift-cross-ui` is a redirect; ownership moved to the `moreSwift` org). License: MIT.

Release history shows ~6 weeks between recent minor releases (v0.4.0 → v0.5.0 → v0.5.1 → v0.6.0 over April–May 2026). v0.6.0 includes an `AppBackend` refactor, gradient support, and heavy AndroidBackend work — Linux desktop is shipped but not the headline focus of v0.6.0.

We **vendor** SwiftCrossUI under `Vendor/swift-cross-ui/` (mirroring the existing SwiftTerm vendoring pattern) rather than depending on the GitHub URL. Reasons:
- Pre-1.0 churn — upstream may break public API at any release.
- Build reproducibility — vendoring pins both source and SwiftPM resolution.
- Allow local patching of the GtkBackend (see below) without forking on GitHub.

## Backend choice: **GtkBackend (Gtk4)**, NOT QtBackend

The plan's recommendation of "SwiftCrossUI Qt6Backend + QTermWidget" was based on agent inference; the actual v0.6.0 reality is:

| Backend | State in v0.6.0 |
|---|---|
| `GtkBackend` | **First-class Linux backend.** Used by `DefaultBackend` on `.linux`. ~2.8k LOC, actively maintained, supports widgets, paths, gradients, alerts, sheets, popover menus, slider, picker, datePicker, scroll containers, split views. |
| `QtBackend` | **Disabled/unmaintained.** Single 198-LOC source file, both the `.library(name: "QtBackend"...)` product and `.target(name: "QtBackend"...)` declarations in `Package.swift` are commented out. Depends on `Qlift` (Qt5 Swift binding). Last touched only by global formatting passes — no functional work in 2026. |
| `Gtk3Backend` | Older, still present, lower priority. Stick with the Gtk4 `GtkBackend`. |
| `AndroidBackend` | Heavy 2026 development; irrelevant here. |
| `WinUIBackend` | Windows; irrelevant here. |
| `CursesBackend`, `LVGLBackend`, `DummyBackend` | Niche / inappropriate. |

**Decision**: Pin GtkBackend. Plan revisions required (see below).

## Consequent revisions to the plan

The plan assumes "Qt6Backend + QTermWidget" and a thin Swift–C++ interop to QTermWidget. With GtkBackend, the matched components change:

| Concern | Plan said (Qt6) | Actual (Gtk4) |
|---|---|---|
| GUI toolkit | Qt6 | **Gtk4** (libgtk-4-1, libadwaita-1) |
| Terminal widget | QTermWidget (LXQt, LGPL) | **VTE 0.74+** (`libvte-2.91-gtk4`), the GNOME Terminal / Tilix / Black Box engine. More CVE eyeballs and richer feature set than QTermWidget. |
| Charts library | Qt Charts 6 (LGPL) | Less obvious. Options: render Cairo paths via SwiftCrossUI `Path`, embed `gtk4-chart` (small project), or render to PNG via a sidecar process. Decision deferred to gap analysis. |
| File pickers | QFileDialog | GtkFileDialog (built into Gtk4); on Plasma 6, Plasma's portal honors `xdg-desktop-portal` so KDE's file picker can be used transparently. |
| Native KDE integration | Direct (Qt-on-Plasma) | Indirect (Gtk-on-Plasma via xdg-desktop-portal). Plasma 6 respects Gtk themes via `kde-gtk-config`. Acceptable. |
| Title bar / window chrome | QMainWindow native KDE | Gtk's CSD (client-side decorations) — Plasma users may notice the non-KDE look. **Acceptable tradeoff.** |

**Bridge complexity**: roughly equivalent. Gtk has cleaner C interop than Qt (no MOC, no `Q_OBJECT`, no signals/slots machinery to bridge). The C-ABI shim for VTE is simpler than the QTermWidget one would have been.

**KDE integration loss**: minor. KDE Plasma 6 hosts Gtk apps natively; users see CSD title bars but functionality is intact. We lose Konsole/KPart integration (which we never planned to use anyway) and Kirigami/Plasma-style chrome.

## Files to update outside this spike doc

When the user confirms this choice:
- `/home/mriettini/.claude/plans/hermes-desktop-https-github-com-dodo-re-dreamy-bachman.md` — change every "Qt6", "QTermWidget", "QtCharts", "qtcharts-devel", "qt6-qtbase-devel" reference to the Gtk4 equivalent.
- `Package.swift` — once Swift is installed, add `Vendor/swift-cross-ui` package and link `DefaultBackend`.
- Threat model T10 (clipboard) — Gtk4 uses Wayland data device with proper portal mediation, marginally better than Qt6's clipboard story.
- Build container deps (Containerfile.builder) — replace `qt6-qtbase-devel qt6-qtwayland-devel qt6-qtdeclarative-devel qt6-qtcharts-devel` with `gtk4-devel libadwaita-devel vte291-gtk4-devel cairo-devel pango-devel`.

## Risk note

GtkBackend in v0.6.0 is the most-developed Linux desktop backend in SwiftCrossUI, but the framework itself is pre-1.0. The 2-week spike must validate (in the gap analysis next) that the SwiftUI APIs hermes-desktop uses are actually expressible against the GtkBackend primitives. The Phase 0 GO/NO-GO triggers if too many are missing.

## Reproducing this analysis

```sh
git clone --depth 1 --branch v0.6.0 https://github.com/moreSwift/swift-cross-ui.git /tmp/swift-cross-ui
cd /tmp/swift-cross-ui
# Sanity check: is QtBackend in the products list?
grep -E '\.library\(name: "QtBackend"' Package.swift   # commented out
grep -E '\.target\(\s*name: "QtBackend"' Package.swift # commented out
# Sanity check: is GtkBackend the Linux default?
grep -E 'GtkBackend.*\.linux' Package.swift            # yes
# Inventory backend primitives:
grep -E '^\s+public func create' Sources/GtkBackend/GtkBackend.swift
```
