# 03 — Swift on Linux: toolchain, Foundation, libraries, distribution

*Findings as of 2026-08-23. **[V]** = verified against a primary source, **[I]** =
inference, **[U]** = unverified.*

## Toolchain

- Current stable Swift: **6.3.3** ([swift.org/install/linux](https://www.swift.org/install/linux/)).
  Swift 6.3.0 shipped 2026-03-24 (`@c` attribute for C export, Swift Build in SwiftPM
  as preview); Swift 6.2 (Sept 2025) brought the approachable-concurrency work,
  `Subprocess`, typed `NotificationCenter` messages, and the `Observations` async
  sequence. **[V]**
- **Supported Ubuntu versions:** official toolchains for **22.04 and 24.04 LTS**
  (x86_64 + aarch64), full "deployment and development" tier
  ([platform support](https://www.swift.org/platform-support/)). **Ubuntu 26.04 LTS is
  not yet officially supported by swift.org** — `swiftly` fails there with
  "Unsupported Linux platform" ([swiftly#532](https://github.com/swiftlang/swiftly/issues/532),
  open since May 2026). Ubuntu itself packages a community `swiftlang` deb in
  *universe* (6.1.3 on 26.04) — notably behind upstream. Practical options on 26.04
  today: distro Swift 6.1.3, the 24.04 tarball (glibc forward-compat, unsupported),
  or Docker. **[V]**
- Install: **swiftly** (official version manager, 1.1.3 June 2026), tarballs, or the
  official `swift` Docker images (`latest` = 6.3.3 on Ubuntu 24.04). **[V]**
- The full Swift 6 language — strict concurrency, typed throws, `@Observable`
  (Observation), stdlib `Synchronization` (`Atomic`, `Mutex`), Swift Testing and
  XCTest — ships identically on Linux. **[V]**

## Foundation: what actually works

Since Swift 6 the Linux stack is **swift-foundation** (the same pure-Swift
`FoundationEssentials`/`FoundationInternationalization` Apple ships in its OSes)
underneath **swift-corelibs-foundation** (NS-compat layer + `FoundationXML` +
`FoundationNetworking`). The old "corelibs is a best-effort clone" caveat now applies
to a much thinner layer. **[V]**

| API | Status on Linux |
|---|---|
| FileManager, URL, JSONEncoder/Decoder, PropertyList, Calendar/Locale/TimeZone, formatters | ✅ pure-Swift rewrite, same code Apple ships **[V]** |
| **FileManager search paths → XDG** | ✅ `.applicationSupportDirectory` → `$XDG_DATA_HOME` (`~/.local/share`), `.cachesDirectory` → `~/.cache`, `.downloadsDirectory` etc. → `xdg-user-dirs` **[V]** (verified in `FileManager+XDGSearchPaths.swift`; it maps to the XDG root itself — the app appends its own subdirectory, which `TabStore` already does) — our `Application Support/MacDring/launcher.json` code lands at `~/.local/share/MacDring/` unchanged. Caveat: `.trashDirectory` resolves to `~/.Trash`, which is **not** the freedesktop trash location — don't use it on Linux |
| UserDefaults | ✅ persists per-domain plists under `$XDG_CONFIG_HOME` (`~/.config`) **[V]** |
| NotificationCenter, RunLoop/Timer (epoll CFRunLoop), Process, FileHandle, NSCache, ISO8601 | ✅ **[V]** |
| `Data.write(options: .atomic)` | ✅ verified in source, and stronger than hoped: `O_CREAT\|O_EXCL` temp file in the destination directory, `fsync` before `renameat(2)`, mode-preserving, with graceful non-atomic fallbacks only on DOS filesystems **[V — load-bearing for PictKit's multi-writer store, see 06]** |
| `FileManager.trashItem(at:)` | ❌ **does not exist on Linux** — not even a stub; calling it is a compile error. No XDG-trash implementation anywhere in Foundation. `FileMover`'s default argument needs an `#if os(macOS)` guard; Linux trash goes through `gio trash`/GIO ([05](05-topdrawer-port.md)) **[V]** |
| `Bundle` / `Bundle.module` resources | ✅ SwiftPM resource bundles work (`<pkg>_<target>.resources` next to the executable) **[V]** |
| **NSImage / CGImage / CoreGraphics / ImageIO** | ❌ do not exist. Image work needs Cairo/gdk-pixbuf/libpng or pure-Swift codecs ([04](04-ui-frameworks.md), [06](06-pict-port.md)) **[V]** |
| **NSMetadataQuery (Spotlight)** | ❌ absent entirely — no `NSMetadata*` source in corelibs. Linux equivalent: TinySPARQL/LocalSearch + `recently-used.xbel` ([02](02-desktop-constraints.md) §Recents) **[V]** |
| **DispatchSource.makeFileSystemObjectSource** | ❌ compiled out on Linux (`#if !os(Linux)…`) — the vnode source exists only in the kqueue backend. It is *not* inotify-backed; it simply doesn't exist. Use inotify via C interop (~300-line wrapper) or a package (e.g. `aus-der-Technik/FileMonitor`) **[V]** |
| KVO / `@objc` / `dynamic` / message dispatch | ❌ no ObjC runtime on Linux; `NSObject` exists as a Swift reimplementation without dispatch/KVO **[V]** |
| **Combine** | ❌ closed-source, no Linux port. OpenCombine is effectively in maintenance mode (last release 0.14.0, ~2023). The ecosystem answer is **Observation (`@Observable`) + AsyncSequence + swift-async-algorithms** — this is the migration to plan for our `ObservableObject`/`@Published` usage **[V]** |

### URLSession / FoundationNetworking specifics

All of the following was verified by reading corelibs-foundation `main` directly
(see the appendix in [07](07-roadmap.md#verification-appendix)):

- Separate module: `import FoundationNetworking`; libcurl-backed. **[V]**
- Async `data(for:)`/`data(from:)`, `upload`, and **`download(for:)`/`download(from:)`
  exist and are real implementations — but only since Swift 6.0** (PR
  [#4970](https://github.com/swiftlang/swift-corelibs-foundation/pull/4970), June
  2024); they don't exist on 5.x Linux toolchains. `download` does not auto-remove
  the temp file. **[V]**
- **`URLSession.bytes(for:)` / `AsyncBytes` has never existed on Linux** — not a
  stub, not `unavailable`: the symbol is simply absent, so code using it fails to
  compile ([#5401](https://github.com/swiftlang/swift-corelibs-foundation/issues/5401)).
  For byte-streaming with an as-you-go cap (Pict's `RemoteIconFetcher`), use a
  delegate-based data task or **AsyncHTTPClient**. **[V]**
- **`URLSessionConfiguration.background` is hard-unavailable** on Linux
  (`@available(*, unavailable)`), as are `waitsForConnectivity` and
  `multipathServiceType`. **[V]**
- **Custom `URLProtocol` stubbing works — but only via
  `configuration.protocolClasses`** (put the stub first). `URLProtocol.registerClass`
  alone never intercepts http(s): the default config hardcodes the built-in HTTP
  protocol first and it claims every request
  ([#4940](https://github.com/swiftlang/swift-corelibs-foundation/issues/4940)).
  Pict's two stubbing test files port with that one change ([06](06-pict-port.md)). **[V]**
- **WebSockets**: `URLSessionWebSocketTask` exists but requires libcurl ≥ 8.11 built
  with `ws` — stock Ubuntu 24.04 ships curl 8.5 without it, so it fails at runtime
  there. (We don't use WebSockets today; noted for completeness.) **[V]**
- Delegate coverage is incomplete (e.g. task metrics never delivered —
  [corelibs#4988](https://github.com/swiftlang/swift-corelibs-foundation/issues/4988)). **[V]**
- For anything delegate-heavy or streaming, the server-side-Swift norm is
  **AsyncHTTPClient** instead of URLSession. **[I]**

## Libraries we'd lean on

| Need (today on macOS) | Linux answer |
|---|---|
| CryptoKit `SHA256` (`DrawerItem.stableID`, Pict's render cache) | **swift-crypto** (`import Crypto`) — API-compatible, actively maintained (4.5.0, Apr 2026) **[V]** |
| Combine `ObservableObject`/`@Published` (stores, models) | **Observation** (`@Observable`, works on Linux since 5.9) + `Observations` async sequence (6.2) **[V]** |
| `DispatchSourceFileSystemObject`, FSEvents | inotify via C interop **[V]** |
| `NSLog` | works; or **swift-log** **[V]** |
| Subprocess spawning (Pict's `tar`) | Foundation `Process` works; new **swift-subprocess** is the async-native option **[V]** |

## Interop

- **C interop via SwiftPM `systemLibrary` targets + pkg-config: mature.** This is how
  every GTK/X11/wlroots/WebKitGTK binding works, and how our platform kit would be
  built. Watch for varargs macros (`g_signal_connect`) needing a tiny C shim. **[V]**
- **ObjC interop: absent** (see above). Keep `@objc`/KVO out of shared code; gate
  with `#if canImport(ObjectiveC)`. **[V]**
- C++ interop: officially supported and evolving; fine behind a boundary, not a
  foundation to build a GUI stack on. **[V/I]**

## Distribution of Swift binaries on Linux

- **Static Linux SDK (musl)**: official; fully static executables with zero deps;
  ~5 MB stripped hello-world. **Not usable for GUI apps** — it forbids dynamic
  linking entirely (`dlopen` included) and GTK/Wayland/X11 client libraries are
  glibc-dynamic system libraries. Excellent for CLI helpers (a `pict` CLI, a
  headless daemon *if* we accept bundling no GUI libs). Known issue: URLSession
  currently breaks under the static SDK
  ([corelibs#5092](https://github.com/swiftlang/swift-corelibs-foundation/issues/5092)). **[V]**
- GUI apps therefore ship **glibc-dynamic + packaging**: `.deb` (primary — see
  [07](07-roadmap.md)), AppImage (type2-runtime is now statically linked, no libfuse2
  needed **[V]**), Flatpak (first-class for the *Adwaita* ecosystem; wrong shape for a
  launcher needing host access), tarball + our existing GitHub-release updater.
- The Swift runtime libraries can be bundled alongside the binary (`-Xlinker -rpath`
  / `$ORIGIN`) or the deb can depend on a packaged runtime; both are routine. **[I]**
- Cross-compiling from macOS: SE-0387 Swift SDKs + `swift-sdk-generator` work but are
  the less-trodden path; building in Docker/CI is the norm. Real-world precedent for
  shipping Swift Linux binaries in 2026: Tuist's CLI. **[V]**

## Developer experience

- **VS Code Swift extension** (official, Swift.org publisher; 2.16.7 Aug 2026) with
  SourceKit-LSP and lldb-dap debugging — all first-class on Linux. Also on Open VSX. **[V]**
- CI: GitHub Actions `ubuntu-24.04` runners + `swift-actions/setup-swift`, or jobs in
  the official `swift:6.3` containers. This repo's CI can gain a Linux job that runs
  the portable test subset (see [05](05-topdrawer-port.md) §Tests) long before any UI
  work exists. **[V/I]**

## Bottom line

The language/toolchain pillar is production-grade; the fragile pillar is the *desktop
app layer* (see [04](04-ui-frameworks.md)): no first-party GUI framework, a handful of
community GTK-centric frameworks, and a short-but-real list of shipped Swift desktop
apps on Linux (Memorize on Flathub; silveran-reader; dexbar; Video Village's
commercial tooling). Shareable with confidence: models, stores, listers' logic, JSON,
crypto, networking-with-caveats. Owned risk: the UI layer and the platform services
behind seams.
