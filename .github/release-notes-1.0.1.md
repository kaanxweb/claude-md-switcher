# ClaudeMDSwitcher 1.0.1

This release hardens distribution and profile-data preservation without adding application features.

- Release artifacts require Developer ID Application signing.
- The app is submitted to Apple for notarization and has its notarization ticket stapled before packaging.
- The release tooling fails closed when signing or notarization prerequisites are missing; it does not produce an ad-hoc-signed production artifact.
- Release artifacts must be built from a clean checkout at the exact signed, annotated version tag and pass bundle-metadata, arm64 architecture, and checksum verification before publication.
- If `CLAUDE.default.md` already exists, a later regular `CLAUDE.md` is preserved as a uniquely named recovery profile instead of being lost during a switch.

v1.0.1 uses build number 2 and is the first release prepared through this hardened distribution process.
