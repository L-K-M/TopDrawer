/// The one version string both Linux executables report (`--version`) and that
/// `topdrawerd` embeds in its `Ping` reply.
///
/// Development builds carry the `0.0.0-dev` placeholder. The Debian packaging script
/// (`linux/packaging/build-deb.sh`) stamps the release version — taken from the git
/// tag — into the line below before building, so the tag stays the single source of
/// truth, the same rule the macOS release workflow applies to `MARKETING_VERSION`.
public enum TopDrawerVersion {
    /// Stamped by `build-deb.sh` with a one-line substitution: keep the literal on this
    /// line, and keep this the only `static let current` in the file.
    public static let current = "0.0.0-dev"
}
