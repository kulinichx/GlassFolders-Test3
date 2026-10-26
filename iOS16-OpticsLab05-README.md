# GlassFolders Optics Lab 05 — independent GPU display probe

## What is new

Lab 05 contains a **standalone iOS 16 test app** which draws a constantly changing **synthetic** grid entirely with Metal. The standalone app feeds the generated texture to the Lab 04 displacement renderer and presents the refraction within a rounded rectangle. A slider controls sampling displacement. This verifies an end-to-end texture pipeline **without** changing the existing SpringBoard tweak.

### Two different packages

- `com.kulinich.glassfolders` remains the existing `GlassFolders` tweak (`Makefile` at repository root). Lab 05 doesn't modify its build inputs or Settings.
- `com.kulinich.glassfolders.opticsprobe` is a **separate**, opt-in demonstration app. It does not Hook SpringBoard or `backboardd`. It does not read the wallpaper, screen pixels, or the actual compositor backdrop.

### Run on macOS / GitHub Actions (RootHide iOS 16)

With RootHide Theos / iOS SDK and Xcode Metal Toolchain installed:

```bash
cd Experiments/OpticsLab05Probe
THEOS=/path/to/theos-roothide ./build.sh
```

The generated `.deb` should be under `Experiments/OpticsLab05Probe/packages/`. Install it **separately** after the GitHub Actions GPU-build succeeds; it creates a home-screen app named **Optics Probe**. Remove it anytime without removing GlassFolders.

The app opens with a moving grid and a rounded glass panel. Use the slider to compare 0 px vs 8 px vs 16 px offset; lines should bend near the edges only. Label explicitly says `synthetic GPU refraction / No SpringBoard capture`.

### CI coverage

The separate `optics-lab05-gpu.yml` workflow compiles two `.metal` sources into a single `GFOpticsLab05.metallib`, compiles the Objective-C++ host with Theos on a macOS runner, and uploads the **separate probe `.deb`**. Its build result (especially Metal host compile) must be checked before installing on device. Linux-only tests cannot compile Apple Metal source and aren't represented as such.

### Mango insight and still-open obstacle

Static inspection of `MangoOSRendering.dylib` shows `MSHookFunction`, `addFilter`, `filterTableSlot`, `go.mangoos.refraction`, and shader entry points. This is evidence of a renderer registration path, but does **not** establish a safe or portable filter-registration ABI. A custom Metal library in an app cannot automatically receive SpringBoard's already-composited background. The next requirement is an independently verified, **supported by the target runtime** backdrop texture supply and CA compositor layer output; only then can Lab 04/05 be moved into the tweak without pretending a static or synthetic texture is 'live SpringBoard glass'.

### Safety and limitations

- Lab 05 does not modify `Tweak.xm`, existing prefs, RootHide filters, license files, or original package, and does not inject `backboardd`.
- Visual source is synthetic, not the user’s private pixels.
- Metal GPU compilation and runtime performance are *not verified in this Linux environment*. GitHub Actions and iOS 16-device validation remain necessary.
- Separate probe app is intended for testing only, not a consumer feature.
