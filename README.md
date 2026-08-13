# GlassFolders Test3 — RootHide

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
