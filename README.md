# GlassFolders Test3.1 — RootHide

Minimal validation build for:
- iPhone 14 Pro / A16 / iPhone15,2
- iOS 16.6
- Dopamine 3.x RootHide-style environment

## Purpose

Test3 deliberately does only one thing:
hide the translucent plate behind the miniature app previews of a closed Home Screen folder icon.

It uses:
- RootHide Theos
- Logos
- substrate-compatible injection
- arm64e
- SpringBoard-only filter

Hooked selector:
`SBFolderIconImageView -setBackgroundView:`

It does NOT modify opened-folder visuals, wallpaper blur, layout, titles, gestures, Dock, launchd, or jailbreak filesystem paths.

There is no Settings bundle in Test3.

## Build on GitHub

1. Create a new GitHub repository.
2. Upload every file/folder from this project to the repository root.
3. Open Actions → Build RootHide Test3.
4. Click Run workflow.
5. Download the `GlassFolders-Test3-DEB` artifact.

The workflow fails automatically if the built dylib is not reported as arm64e.


## Test3.1 change

Test3 initially kept Apple's folder background view and changed its alpha to zero.
On iOS 16.6, Home Screen page scrolling can reuse/reconfigure `SBFolderIconImageView`,
which allows the original material background to become visible again.

Test3.1 keeps the same single `setBackgroundView:` hook but substitutes a fresh,
empty `UIView` instead. This mirrors the strategy used by Atria for its
"Hide folder icon blur" option and avoids relying on the system material view's
alpha remaining unchanged during reuse.

Expected result: folder icon plates stay transparent after repeatedly swiping
between Home Screen pages.
