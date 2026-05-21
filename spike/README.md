# Phase 0 spike — SwiftCrossUI + Gtk4 viability gate

> ⚠️ **Outcome 2026-05-20**: The spike triggered a **strategy pivot, not a continuation**. SwiftCrossUI+GtkBackend would have worked (~85% API coverage, three patchable gaps) but the user opted to **pivot to Hybrid: Swift core via FFI + C++/Qt6/Kirigami UI** for full KDE-native integration. See the parent plan (`~/.claude/plans/hermes-desktop-https-github-com-dodo-re-dreamy-bachman.md` — Strategy v2) for the new approach. The artifacts here remain useful as inputs (especially `inventory.md`, which lists every UI behavior the C++ screens must support).

This directory holds the artifacts for the **2-week Phase 0 spike** that gates the port of `hermes-desktop` to Linux. See the parent plan at
`/home/mriettini/.claude/plans/hermes-desktop-https-github-com-dodo-re-dreamy-bachman.md`.

## Status: analysis complete; build-validation deferred

|  | File | Status |
|---|---|---|
| Inventory of SwiftUI APIs used in `Views/` | [`inventory.sh`](inventory.sh) → [`inventory.md`](inventory.md) | ✅ Done |
| SwiftCrossUI tag pin + backend choice (GtkBackend) | [`swift-cross-ui-decision.md`](swift-cross-ui-decision.md) | ✅ Done |
| Cross-reference (used APIs vs SwiftCrossUI surface) | [`api-gap-analysis.md`](api-gap-analysis.md) | ✅ Done |
| **GO/NO-GO recommendation** | [`api-gap-analysis.md`](api-gap-analysis.md) | ✅ **PROCEED** (with three caveats, +1–4 weeks vs original budget) |
| Working slices of the 4 hardest screens | — | ⏳ Deferred: requires Swift 6.1 installed locally |

## Top-line finding

SwiftCrossUI v0.6.0's `GtkBackend` (Gtk4, not the planned Qt6) covers ~85% of hermes-desktop's SwiftUI footprint. The three remaining gaps are concentrated, with known mitigations:

1. **Apple Charts** (UsageView, 13 API uses) → custom DSL on top of SwiftCrossUI's `Path` widget (Cairo-backed). Already in plan scope.
2. **`@FocusState` + `ScrollViewReader`** (SessionDetailView, 8 use sites) → small SwiftCrossUI patch we vendor.
3. **`ViewThatFits` + custom `Layout` protocol** (UsageView, Workflows, HermesUI, 25 use sites) → either replace at call sites or vendor patch.

**The plan's #1 risk — Kanban SwiftUI drag-drop — evaporated.** Hermes Kanban uses no SwiftUI drag/drop APIs; column transitions are menu/button-driven and are structurally portable.

## Material deviation from the original plan

The plan recommended **SwiftCrossUI Qt6Backend + QTermWidget**. Phase 0 found that:

- SwiftCrossUI v0.6.0's `QtBackend` is **unmaintained**: 198 LOC, target and library declarations both commented out in `Package.swift`, depends on a Qt5 binding (Qlift). No 2026 activity beyond global formatting passes.
- `GtkBackend` is **first-class** in v0.6.0 (~2.8k LOC, used by `DefaultBackend` on Linux).
- Pairs naturally with **VTE 0.74+ (`libvte-2.91-gtk4`)** for the terminal (more active than QTermWidget, used by GNOME Terminal / Tilix / Black Box).

See [`swift-cross-ui-decision.md`](swift-cross-ui-decision.md) for the full backend rationale and the list of plan substitutions (`Qt6Backend` → `GtkBackend`, `QTermWidget` → `VTE`, `Qt Charts 6` → `Cairo`-based custom, etc.).

## Reproducing the analysis

```sh
# From repo root:
spike/inventory.sh > spike/inventory.md
```

Prerequisite: `ripgrep` (provided by `linuxbrew/ripgrep` or `dnf install ripgrep`).

## Installing Swift 6.1 on Aurora to run the remaining slice work

Swift is not currently installed locally on this Aurora box. Once installed, the remaining spike work is to build prototype slices for the four hardest screens and confirm the analysis empirically.

### Install Swift 6.1 toolchain

Swift.org publishes UBI 9 / Fedora 39 tarballs that work cleanly on Aurora (Silverblue 40-based, glibc 2.39). On an immutable Silverblue root, install into your home directory rather than `/opt`:

```sh
# Fetch (check https://www.swift.org/install/linux/ for the current 6.1 build URL)
SWIFT_VERSION=6.1.2
SWIFT_TARBALL="swift-${SWIFT_VERSION}-RELEASE-fedora39-x86_64.tar.gz"
curl -L -o "/tmp/${SWIFT_TARBALL}" \
  "https://download.swift.org/swift-${SWIFT_VERSION}-release/fedora39/swift-${SWIFT_VERSION}-RELEASE/${SWIFT_TARBALL}"
# Verify the signature (always — Swift publishes detached .sig + ALL_KEYS.asc)
gpg --keyserver hkp://keyserver.ubuntu.com --recv-keys A62AE125BBBFBB96A6E042EC925CC1CCED3D1561
curl -L -o "/tmp/${SWIFT_TARBALL}.sig" \
  "https://download.swift.org/swift-${SWIFT_VERSION}-release/fedora39/swift-${SWIFT_VERSION}-RELEASE/${SWIFT_TARBALL}.sig"
gpg --verify "/tmp/${SWIFT_TARBALL}.sig" "/tmp/${SWIFT_TARBALL}"
# Install into ~/.local/swift-6.1
mkdir -p ~/.local
tar -C ~/.local -xzf "/tmp/${SWIFT_TARBALL}"
mv ~/.local/swift-${SWIFT_VERSION}-RELEASE-fedora39-x86_64 ~/.local/swift-6.1
echo 'export PATH="$HOME/.local/swift-6.1/usr/bin:$PATH"' >> ~/.bashrc
exec bash
swift --version
```

### Install Gtk4 + VTE + Cairo dev libraries

Aurora (Silverblue) requires `rpm-ostree install` (layers into the immutable image; reboot needed), OR use Distrobox / toolbox to keep the build deps in a mutable container:

```sh
# Cleaner: distrobox.
distrobox create --image quay.io/fedora/fedora:41 --name hermes-build
distrobox enter hermes-build
# Inside the container:
sudo dnf install -y \
  gtk4-devel libadwaita-devel \
  vte291-gtk4-devel \
  cairo-devel pango-devel \
  glib2-devel \
  fontconfig-devel \
  libicu-devel \
  pkgconf-pkg-config
```

### Vendor SwiftCrossUI

```sh
# From repo root:
git submodule add -b v0.6.0 https://github.com/moreSwift/swift-cross-ui.git Vendor/swift-cross-ui
# Pin the submodule commit so future updates are deliberate.
```

### Add SwiftCrossUI to Package.swift

When Swift is available, add to `Package.swift`:

```swift
// dependencies:
.package(path: "Vendor/swift-cross-ui"),

// In the target's deps, gated to Linux:
.product(
    name: "SwiftCrossUI",
    package: "swift-cross-ui",
    condition: .when(platforms: [.linux])
),
.product(
    name: "DefaultBackend",
    package: "swift-cross-ui",
    condition: .when(platforms: [.linux])
),
```

### Build the spike slice targets

The four slices are not yet checked in (no Swift available to validate). Once Swift is installed, scaffold them at:

```
Sources/HermesSpike/
├── KanbanSlice.swift          # Confirms task movement (menu/button-driven; no SwiftUI drag-drop needed)
├── UsageChartsSlice.swift     # Renders one BarMark-equivalent via SwiftCrossUI Path
├── SessionScrollSlice.swift   # Confirms ScrollViewReader/@FocusState workaround
└── TerminalSlice.swift        # Embeds VTE via GtkWidgetRepresentable
```

Each slice is an SPM executable target so it can be built independently:

```swift
// In Package.swift, gated to Linux:
.executableTarget(
    name: "HermesSpikeKanban",
    dependencies: [.product(name: "DefaultBackend", package: "swift-cross-ui")],
    path: "Sources/HermesSpike",
    sources: ["KanbanSlice.swift"]
)
```

Build & run:

```sh
swift build --product HermesSpikeKanban
.build/debug/HermesSpikeKanban
```

If all four slices launch on Aurora's Wayland session and render their happy-path UI, the spike's empirical confirmation step is complete.

## Decision log (live)

| Date | Decision | Why |
|---|---|---|
| 2026-05-20 | Pin SwiftCrossUI **v0.6.0** | Current `latest`. Released 2026-05-14, 6 days old at decision time. |
| 2026-05-20 | Use **GtkBackend**, not QtBackend | QtBackend unmaintained in v0.6.0 (target commented out, depends on Qt5 binding). |
| 2026-05-20 | Use **VTE 0.74+** for terminal | Active maintenance, more CVE eyes than QTermWidget. Natural pairing with Gtk4. |
| 2026-05-20 | **PROCEED** with the Swift port | Gap analysis shows ~85% API coverage; three remaining gaps have known mitigations totaling +1–4 weeks. |

## Open questions for the user (next session)

1. **Backend pivot approval**: do you accept the Qt6 → Gtk4 substitution? If yes, the plan needs in-place edits (s/Qt6/Gtk4/, etc.).
2. **Swift install on Aurora**: which approach? (a) rpm-ostree layered install (system-wide, reboot), (b) Distrobox/Toolbox container (containerized, no reboot), (c) tarball into `~/.local`. The build pipeline assumes (b) for reproducibility.
3. **Scope of the empirical slices**: do all four slices need to build before we declare Phase 0 complete, or is the analysis-only gate enough to move into Phase 1?
