# GlassFolders 0.7.4 Beta 1.6.1 — Unused Variable Fix

This is a compile-only correction to Beta 1.6.

## GitHub Actions failure

Beta 1.6 replaced the previous independent edge/corner lighting model with the
new shared continuous specular rails, but eight old local declarations were
left behind.

Because the project compiles with warnings promoted to errors, Clang stopped on
`-Wunused-variable`.

Removed declarations:

Closed optical map:
- `horizontalEdge`
- `highlightShoulderGain`
- `highlightCoreGain`
- `highlightFilamentGain`

Opened optical map:
- `horizontalEdge`
- `shoulderGain`
- `coreGain`
- `filamentGain`

## Optical behavior

The Beta 1.6 formulas are otherwise unchanged:

- upper-left corner + top edge share `primaryRailMask`;
- bottom edge + lower-right corner share `secondaryRailMask`;
- both pieces inside each rail use the same luminance gains;
- straight left/right side middles remain strongly suppressed;
- opened and closed states use the same topology.

## Runtime / safety

Unchanged:
- RootHide arm64e;
- SpringBoard-only injection;
- `SBFolderIconImageView`;
- `SBFolderBackgroundView`;
- no App Library code;
- no daemon/timer/DisplayLink/gyro;
- rounded Settings icon;
- duplicate PreferenceLoader cleanup;
- `作者  kulinich`.
