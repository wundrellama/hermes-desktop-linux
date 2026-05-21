# Development environment — Aurora 44 Kinoite + Distrobox

This is the actual, reproduced, working setup as of 2026-05-20. Replaces the speculative section in `spike/README.md`. Every command below was executed; package versions are what shipped.

## Host

| Item | Value |
|---|---|
| Distro | Aurora 44 Kinoite (Fedora Silverblue 44 derivative) |
| Kernel | 6.19.14-101.fc44.x86_64 |
| Desktop | KDE Plasma 6 on Wayland |
| Container runtime | podman 5.8.2 |
| Container manager | distrobox 1.8.2.4 |

The host stays clean — no compiler, no language runtime installed on it. All build work happens in the `hermes-build` Distrobox container below.

## Container: `hermes-build`

### Create

```sh
distrobox create --image quay.io/fedora/fedora:41 --name hermes-build --yes
```

Image pulled once; container creation is instant after that. Default Distrobox settings give us:
- Host home mounted at the same path (`/var/home/mriettini` → `/var/home/mriettini`)
- Wayland & X11 sockets passed through (UI smoke tests work without extra setup)
- DBus session passed through
- `sudo dnf` works passwordless inside the container

### Install build deps

```sh
distrobox enter hermes-build -- sudo dnf install -y \
  gcc-c++ make cmake ninja-build pkgconf-pkg-config ccache \
  glibc-devel libicu-devel openssl-devel zlib-devel \
  glib2-devel sqlite-devel libxml2-devel libcurl-devel \
  qt6-qtbase-devel qt6-qtwayland-devel qt6-qtdeclarative-devel \
  qt6-qtquickcontrols2-devel qt6-qtcharts-devel qt6-qtsvg-devel \
  qt6-qt5compat-devel \
  kf6-kcoreaddons-devel kf6-kcrash-devel kf6-kconfig-devel \
  kf6-kglobalaccel-devel kf6-kio-devel kf6-kirigami-devel \
  kf6-kirigami-addons-devel \
  qtermwidget-devel \
  clang-tools-extra valgrind \
  git
```

**Gotchas discovered in setup:**
- Fedora 41 ships the Qt6 build of QTermWidget under just `qtermwidget-devel` (no `qt6` suffix). Confirm: `dnf search qtermwidget`.
- The `kf6-kirigami-addons-devel` package does NOT pull in the base `kf6-kirigami` library; install both.
- `git` is not in the Fedora 41 container image by default. Without it, `swift build` fails on the first dependency clone.

### Versions confirmed installed

| Tool | Version |
|---|---|
| cmake | 3.30.8 |
| Qt6 | 6.8.3 (newer than the plan's 6.7 target — fine) |
| QTermWidget | 2.0.1 (Qt6) |
| Kirigami | 6.18.0 |
| Kirigami Addons | 1.9.0 |
| gcc-c++ | 14.x (Fedora 41 default) |

## Swift 6.3.2 toolchain

The plan originally targeted Swift 6.1. As of 2026-05-20 the swift.org Fedora 39 builds are retired (Fedora 39 EOL), and 6.1.x ones for Fedora are gone. The current stable is **6.3.2**. The UBI 9 build runs cleanly on Fedora 41 (glibc 2.34 binaries on glibc 2.40 host is a forward-compat win).

### Download (on host)

```sh
mkdir -p ~/.local/swift-downloads
SWIFT_VERSION=6.3.2
SWIFT_TARBALL=swift-${SWIFT_VERSION}-RELEASE-ubi9.tar.gz
SWIFT_BASEURL=https://download.swift.org/swift-${SWIFT_VERSION}-release/ubi9/swift-${SWIFT_VERSION}-RELEASE
curl -L --output-dir ~/.local/swift-downloads -O "$SWIFT_BASEURL/$SWIFT_TARBALL"
curl -L --output-dir ~/.local/swift-downloads -O "$SWIFT_BASEURL/${SWIFT_TARBALL}.sig"
```

Size: ~1.06 GB.

### Verify (on host)

The Swift signing key fingerprint changed from `925CC1CC...3D1561` (5.x release key) to `52BB7E3D...B47A981F` (**6.x release key**, key id `EF80A866B47A981F`). Don't try to fetch by fingerprint from keys.openpgp.org — it returns no data for the 6.x key. The reliable path is the published keyring:

```sh
curl -sL https://swift.org/keys/all-keys.asc | gpg --import
gpg --verify ~/.local/swift-downloads/swift-6.3.2-RELEASE-ubi9.tar.gz.sig \
            ~/.local/swift-downloads/swift-6.3.2-RELEASE-ubi9.tar.gz
# Expect: "Good signature from \"Swift 6.x Release Signing Key <swift-infrastructure@forums.swift.org>\""
```

### Extract & wire PATH (inside the container)

Extraction belongs **inside** the container — the UBI 9 binaries depend on container-side runtime libs and shouldn't be invoked from the host.

```sh
distrobox enter hermes-build -- bash -c '
  cd ~/.local
  tar -xzf ~/.local/swift-downloads/swift-6.3.2-RELEASE-ubi9.tar.gz
  mv swift-6.3.2-RELEASE-ubi9 swift-6.3
  swift-6.3/usr/bin/swift --version
  # Wire up PATH for future container shells:
  mkdir -p ~/.bashrc.d
  cat > ~/.bashrc.d/swift.sh <<EOF
export PATH=\$HOME/.local/swift-6.3/usr/bin:\$PATH
EOF
'
```

Confirmed in-container output:
```
Swift version 6.3.2 (swift-6.3.2-RELEASE)
Target: x86_64-unknown-linux-gnu
```

Distrobox sources `~/.bashrc.d/*.sh` from `.bashrc` automatically, so subsequent `distrobox enter` shells have `swift` on PATH.

## Repo build smoke

```sh
distrobox enter hermes-build -- bash -c '
  source ~/.bashrc.d/swift.sh
  cd /var/home/mriettini/git/hermes-desktop-agent
  swift package dump-package | jq .name    # confirms manifest parses
  swift build                              # fails — see below; expected
'
```

### Smoke-build outcome (2026-05-20)

**Manifest parses cleanly.** `swift-crypto` resolved and fetched. `SwiftTerm` correctly gated to macOS-only.

**Compile result**: 526 of 536 source files compiled successfully on Linux. The only blocker is **one file**:

| File | Failure | Why |
|---|---|---|
| `Sources/HermesDesktop/App/AppState.swift` (line 1) | `error: no such module 'Combine'` | Combine is Apple-only. AppState's reactive plumbing relies on `@Published` / Combine publishers. |

Every other compile error in the build log is a cascade from `AppState` failing — because every UI screen references the central `AppState` `EnvironmentObject` and Swift can't synthesize their types without it.

**What survived the smoke build**:
- All ~5,676 LOC of `Models/`
- All ~8,810 LOC of `Services/` (including `SSH/SSHTransport.swift` — the core ssh execution path)
- All `Utilities/` (Localization, DateFormatters, ShellCommandQuoting, RemotePythonScript, WorkflowLaunchDiagnostics)
- `Models/TerminalTheme.swift` with our Phase 1 `canImport(AppKit)` gating — confirmed working
- `Services/Storage/AppPaths.swift` with our XDG branch — compiled clean

**Strong validation of the Hybrid strategy**: the Swift core compiles on Linux ~as-is. The library split (Phase 1) needs only to:
1. Exclude `Sources/HermesDesktop/App/` and `Sources/HermesDesktop/Views/` from the Linux target.
2. Exclude `Sources/HermesDesktop/Services/Terminal/{TerminalViewHost.swift,SwiftTermTerminalView.swift}` (the AppKit-coupled terminal host).
3. Either decouple `AppState.swift` from the Linux build entirely (since it's UI orchestration state), or extract its non-UI parts to a separate file in `Services/`.

That's a much smaller surgical change than the original plan anticipated.

## CMake configs confirmed present

```
/usr/lib64/cmake/Qt6Charts/Qt6ChartsConfig.cmake
/usr/lib64/cmake/Qt6ChartsQml/Qt6ChartsQmlConfig.cmake
/usr/lib64/cmake/KF6Kirigami/KF6KirigamiConfig.cmake
/usr/lib64/cmake/KF6Kirigami2/KF6Kirigami2Config.cmake
/usr/lib64/cmake/KF6KirigamiPlatform/KF6KirigamiPlatformConfig.cmake
/usr/lib64/cmake/KF6KirigamiAddons/KF6KirigamiAddonsConfig.cmake
/usr/lib64/cmake/KF6KIO/KF6KIOConfig.cmake
/usr/lib64/cmake/qtermwidget6/qtermwidget6-config.cmake
```

So the Phase 4+ `CMakeLists.txt` will look roughly like:

```cmake
find_package(Qt6 6.7 REQUIRED COMPONENTS Core Gui Widgets Qml Quick QuickControls2 Charts Svg WaylandClient)
find_package(KF6 6.0 REQUIRED COMPONENTS CoreAddons Crash Config GlobalAccel KIO Kirigami)
find_package(qtermwidget6 REQUIRED)
```

## Re-entry

Future sessions just need:

```sh
distrobox enter hermes-build
# Swift is on PATH automatically via ~/.bashrc.d/swift.sh
cd /var/home/mriettini/git/hermes-desktop-agent
swift --version
cmake --version
pkg-config --modversion Qt6Charts
```

## Cleanup / rebuild

```sh
distrobox stop hermes-build
distrobox rm hermes-build      # then re-create from the top
```

The Swift toolchain in `~/.local/swift-6.3` survives container rebuilds (it lives in host home).

## Next session prerequisites

For the Phase 1 library split work, this environment is sufficient. For the C++ Qt UI work in later phases, also confirm:

```sh
distrobox enter hermes-build -- bash -c '
  find /usr/lib64/cmake -name "KF6KirigamiConfig.cmake"     # KF6 Kirigami
  find /usr/lib64/cmake -name "Qt6ChartsConfig.cmake"        # QtCharts
  find /usr/lib64/cmake -name "QTermWidgetConfig.cmake" -o -name "qtermwidget*Config.cmake"  # QTermWidget
'
```

All three must resolve before CMake build setup begins (Phase 4 onwards per plan).
