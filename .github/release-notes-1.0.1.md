# ClaudeMDSwitcher 1.0.1

This is the first Developer ID-signed release and the Sparkle update trust root. v1.0.0 cannot self-update, so replace it manually with v1.0.1 once; profiles in `~/.claude/` are unaffected.

- The app automatically checks a signed update feed and exposes **Check for Updates…**. Downloads and installations remain user-approved; updates are not installed silently.
- Release artifacts require Developer ID Application signing.
- The app is submitted to Apple for notarization and has its notarization ticket stapled before packaging.
- The release tooling fails closed when signing or notarization prerequisites are missing; it does not produce an ad-hoc-signed production artifact.
- Release artifacts must be built from a clean checkout at the exact signed, annotated version tag and pass bundle-metadata, arm64 architecture, checksum, and signed-appcast verification before publication.
- If `CLAUDE.default.md` already exists, a later regular `CLAUDE.md` is preserved as a uniquely named recovery profile instead of being lost during a switch.

v1.0.1 uses build number 2 and is the first release prepared through this hardened distribution process.
