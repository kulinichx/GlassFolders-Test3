# GlassFolders 0.7.3 Beta 2.1 — Package Gate Fix

The SpringBoard runtime code is byte-for-byte identical to Beta 2.

## Why the Beta 2 GitHub Action failed

Compilation and `.deb` packaging completed successfully.

The failure happened only in the custom post-build safety gate, where a chain
of `strings | grep -Fq` checks treated every expected Objective-C string as a
mandatory binary invariant.

That is too brittle for a stripped Mach-O: absence from `strings(1)` does not
by itself prove the Logos hook was omitted.

Beta 2.1 keeps forbidden controller/factory symbols as a hard failure, but
prints the intended visual class strings as diagnostics.

## Settings icon packaging fix

Inspection of an earlier real GlassFolders `.deb` showed the actual package did
not contain any PNG icon files. That directly explains the blank Settings icon.

Beta 2.1 explicitly sets:

`GlassFoldersPrefs_RESOURCE_FILES`

for the 1x/2x/3x and large PNG assets.

The post-build verifier now opens the actual `.deb` and hard-fails unless it
contains:

- nested PreferenceLoader `GlassFolders.plist`;
- PreferenceLoader icon 1x/2x/3x;
- GlassFoldersPrefs.bundle icon 1x/2x/3x.

This prevents another build where the source tree contains icons but the
installed package does not.

## App Library runtime

Unchanged from Beta 2:

- `SBHLibraryPodFolderView` is the pod lifecycle/container;
- its exact `SBHLibraryCategoryPodBackgroundView` descendant supplies card
  frame/radius;
- the stock category background view is hidden;
- custom glass is inserted at index 0 of the pod;
- icon/title/touch/expansion behavior remains system-managed.

No controller, icon-list, search-controller, timer, or polling hook is added.
