# License inputs for the .deb

`linux/packaging/build-deb.sh` generates the package's license notices from these
files, the resolved SwiftPM checkouts and the toolchain:

- `third-party-notices.json`: overrides for `scripts/swiftpm-notices.py`, which
  collects the LICENSE and NOTICE files of every pin in `linux/Package.resolved`.
- `components.json`: the spec for `scripts/deb-copyright.py`, which writes the DEP-5
  `copyright` file and `Third-Party-Notices.txt` (own code, Swift runtime, ICU, the
  SwiftPM set and the vendored gtk4-layer-shell).

The texts below are verbatim upstream files for code that the checkouts and the
toolchain do not carry a license file for. Replace them when the version changes.

| File | Upstream ref | SHA-256 |
| --- | --- | --- |
| `ICU-76.1-LICENSE.txt` | unicode-org/icu `LICENSE` at `release-76-1` (Swift 6.3's swift-foundation-icu is ICU 76.1) | `01edac20612b1e590c1c1cfb02b7218c6adc7b0a944eda7a1e03aeee10725aed` |
| `dbus-0.4.1-LICENSE` | wendylabsinc/dbus `LICENSE` at `5727296ecaef9655b781f82c7ebde5c9f0d45551`, the commit after the 0.4.1 tag | `498cc51b41cbc70ad3e48ac049c045f6c233b7ae77d52b3d3efa09c956f5d987` |
| `boringssl-0226f304-LICENSE` | google/boringssl `LICENSE` at `0226f30467f540a3f62ef48d453f93927da199b6` (vendored by swift-crypto 4.5.1) | `827c8d8fc207c2392794eef9e00fe246f9f61fdcc132556c275be3dd8c3cd97f` |
| `boringssl-0226f304-third_party-fiat-LICENSE` | google/boringssl `third_party/fiat/LICENSE` at the same revision | `9eacbcb81be660840c714a560a9d65ba07913db98dd4baf969f78dd499fdd60f` |
| `boringssl-0226f304-third_party-fiat-AUTHORS` | google/boringssl `third_party/fiat/AUTHORS` at the same revision | `ad74c036a6afaedc418fed65f171c877c2f74a4c70938a03930aa11c98a20508` |
| `ushet-c09e0aca-LICENSE` | 18sg/uSHET `LICENSE` at `c09e0acafd86720efe42dc15c63e0cc228244c32` (swift-nio's `cpp_magic.h`) | `62a279b6a64b37680b691436c3ac1c0f6e8eeb81d8ad0a05c1dfc68f2c9ca28a` |
