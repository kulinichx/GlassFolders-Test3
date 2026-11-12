# Mango Beta14-4: Blur And Live Refraction

Research date: 2026-11-13. Read-only inspection of the supplied package.
No package installation, dylib loading, license changes, copied shader files,
production rendering changes, build, or device validation was performed.

This records the initial inspection. The subsequent notification-only blur
source change and repeatable bridge verifier are described separately in
[the clear-blur candidate](notification-clear-blur-candidate.md); real live
refraction is still not enabled.

## Scope And Sample

The user wants less frosted notifications and actual edge refraction, while
preserving the existing rim, highlights, and backing. The newly supplied Mango
sample supersedes the older Beta8 sample as the primary local reference.

- Input: `G:/QQDownload/com.go.mango_1.0-Beta14-4_iphoneos-arm64e_roothide.deb`
- Package: `com.go.mango`, version `1.0-Beta14-4`, architecture `iphoneos-arm64e`.
- Package bytes: 21,187,076.
- Package SHA256: `314a7d2db9f7ac53f7f33f7f16da0efa4a97bc7eed566204b3782e058645e7b1`.
- Rendering module: `Library/MobileSubstrate/DynamicLibraries/MangoOSRendering.dylib`.
- Rendering module bytes: 141,824.
- Rendering module SHA256: `3a5ede25336b05e8c6007ebb0dcc3645ed2ccfaeb3446b166cdd7effed758749`.
- The injection plist targets the `com.apple.backboardd` bundle.
- Control metadata only depends on `mobilesubstrate`; it does not declare a
  firmware range. The absence of a firmware constraint is not a compatibility test.

The user reports Mango works on iOS 16. Independently, static inspection confirms
OS-version-dependent renderer setup, including a distinct iOS 16 case. The
previous LiquidGlass27 sample's iOS 17 package restriction must not be generalized
to all live refraction implementations or to Mango.

## Confirmed Rendering Separation

### Blur Is Not The Refraction Shader

The embedded Metal source has 551 lines and SHA256
`cca64e34dceb23fd72d1c2f9c4184e23d044c63fd15a952aad0815c3c5ddcb50`.
Its entry points are `mangoGlassVertex` and `mangoGlassFragment`.
The inspected fragment path displaces texture sampling coordinates; it does not
contain a Gaussian blur kernel. `MGLiveBackdropView` in `MangoHello.dylib` has a
separate native blur overlay method, called from `applyFilters`.

Static Objective-C call sites in that module:

- `-[MGLiveBackdropView updateNativeBlurOverlayWithRadius:filterClass:]` starts
  at `0xea1328`; it adds/removes sublayers and assigns layer filter values.
- `-[MGLiveBackdropView applyFilters]` starts at `0xeb89d0`.
- At `0xec4168`, `0xec4ca8`, `0xec6ac8`, and `0xec6b80`, that method calls the
  native blur overlay method.
- The same method calls `lgNativeBlurRadiusOverride` at `0xec672c` and `0xec68e4`.

This supports independent blur/refraction controls. It does not establish the
default notification blur, filter order in every branch, or physical radius
units. Host code is substantially obfuscated; numeric defaults must not be
guessed from nearby constants or UI multiplier values.

### Edge Distortion Is Actual Texture Displacement

The following line numbers refer to the embedded source at cstring address
`0xd218` in this exact rendering module, not to project source files:

- Lines 33-69 compute an edge profile, its slope, and a refracted-ray displacement.
- Lines 164-190 map displaced positions into source texture coordinates,
  accounting for origins, transforms, orientation, and backdrop zoom.
- Lines 326-405 derive panel geometry, edge distance, and displacement direction.
- Lines 409-417 taper the displacement band's width near corners.
- Lines 419-433 bypass displacement in the interior of ordinary non-capsule
  cards. The condition also depends on the corner radius; it is not an
  unconditional center fast path for every shape.
- Lines 435-458 limit refraction to the edge band and make the thin-glass mode
  disable displacement independently of tint and lighting.
- Lines 460-496 optionally sample red/green/blue at different displaced positions.
- Lines 499-520 apply tint and highlights after background sampling.

Thus, its distortion is not a brighter outline or a scaled copy of wallpaper.
For our requested scope, the useful division is independent background sampling
and edge displacement, with our existing rim left as a separate decoration.
No Mango source needs to be copied to adopt that division of responsibilities.

### There Is A Live Renderer Connection, Not Just A Standalone Shader

Static ARM64 evidence in `MangoOSRendering.dylib`:

- At `0x4370`, initialization requests `operatingSystemVersion`. The following
  block at `0x4388` through `0x43f0` branches on OS major versions including 16
  and stores different internal offsets. This is real version-dependent setup,
  not merely a low deployment-target declaration.
- The C render function beginning at `0x5b7c` reads a texture-like object from an
  incoming structure at `0x5cf8`, stores it at stack offset `0x48`, and queries its
  Metal device, width, and height.
- That stored object is passed to fragment texture slot 0 at `0x6890`. Slot 1
  receives the glyph mask at `0x68a0`. Uniform bytes and a fullscreen triangle
  draw follow at `0x68b4` and `0x68c8`.
- Shader compilation calls `newLibraryWithSource:options:error:` at `0x714c`.
- The module includes native filter registration markers `addFilter`,
  `filterTableSlot`, `gaussianCtxSlot`, and `go.mangoos.refraction`.
- A guarded indirect forwarding branch appears at `0x5c84` through `0x5cbc`;
  the module also contains native Gaussian forwarding diagnostics.

Together these establish a supplied-texture-to-Metal path within an injected
renderer. They do not establish a complete safe filter ABI for our target,
texture ownership, GPU synchronization, or that every fallback returns native
material correctly. No live invocation was observed.

### Output Texture And Command-Buffer Discovery

Further static inspection follows the output side of the same callback:

- Initialization calls `0xaf68` at `0x445c` and stores its result in the sample's
  global at `0x1c300`. This is separate from the OS-major setup globals ending
  at `0x1c2f8`.
- The helper references the string `Command buffer allocation failed!` at
  `0x137f5`, scans instruction words, extracts a candidate load displacement at
  `0xb110..0xb118`, and can return `-1`. The helper was inspected, not executed;
  no target-system offset was recovered. It is not a portable scanner we have
  validated or incorporated into our tweak.
- At `0x6590`, the callback reads a surface-like pointer using the previously
  identified auxiliary-surface offset. At `0x65a8`, it reads an output texture
  through that pointer using the auxiliary-texture offset. For the sample's
  iOS 16 setup these are `0x110` followed by `0x58`, not a command-buffer field.
- Output width/height comparisons occur at `0x65c4..0x661c`; device comparison
  follows at `0x6674..0x6690`. The usage result at `0x66a0` is tested for bit 2
  at `0x66b0`. These are actual checks, not proof of safe ownership, protected
  content handling, or exact one-to-one input/output dimensions.
- After an indirect callback at `0x6748`, the renderer loads a context field
  using the discovered offset at `0x6754..0x6758`. That object receives
  `renderCommandEncoderWithDescriptor:` at `0x6864`.
- The output texture is assigned to color attachment zero at `0x67c8`, with
  load/store values set at `0x6808` and `0x6848`. The input remains fragment
  texture zero. Drawing ends with `endEncoding` at `0x68d0`.

This strengthens the evidence for encoding into compositor-supplied rendering
resources. It does not establish the indirect callback's complete ABI, who
commits the command buffer, when textures may be released, or GPU completion.
Our integration must verify those contracts instead of adding a separate queue
or assuming `endEncoding` means GPU completion.

The verifier now checks 19 selector calls, the original 6 input-flow instructions,
25 additional compositor-flow instructions, and the scanner anchor. Its JSON
deliberately reports `target_field_offset: null` and `scanner_executed: false`.
The new synthetic tests reject altered/missing evidence; they do not run the
scanner, register a filter, or certify runtime compatibility.

## What Changed Since Beta8

The local Beta8 renderer is 124,752 bytes and embeds an 18,516-byte shader;
Beta14 embeds a 24,239-byte shader. Text comparison found 117 added and 25 removed
source lines, including comments. Additions include thin-glass handling, clock
color parameters, revised highlights, and corner treatment. These are sample
differences, not a claim that this is the latest Mango release or that all new
paths are active by default. Our user did not request adopting the new highlights.

## Implications For GlassFolders

The active project currently uses a native live backdrop with Gaussian blur and
separate local rim layers. Its notification path has no displacement stage.
Older `GlassFolders-Test3/Experiments` code already displaces an explicitly
supplied texture but is not connected to the production SpringBoard backdrop.

The remaining work is not simply writing another Metal fragment function:

1. Keep the existing rim, palette, foreground adaptation, and stack behavior.
2. Calibrate notification blur separately. A proposed dark radius of 4 instead
   of 8, with the light radius left at 3, is our own test candidate, not a Mango
   parameter extracted from this sample. No such production edit was made here.
3. Independently validate the target iOS 16 compositor's texture supply, filter
   registration, output surface, coordinate mapping, and command-buffer lifetime.
   Do not transplant Mango's OS-major offsets as a portable ABI.
4. Verify an opt-in identity pass before edge displacement: unchanged background,
   no self-sampling, and exact alignment during notification motion and rotation.
5. Apply only edge displacement; keep our existing highlight layer and begin
   with dispersion disabled. The renderer must fall back on unsupported inputs.
6. Verify static notifications, stack transitions, banners, background changes,
   protected content, lock/unlock, GPU completion, and idle behavior on device.

Do not attach an arbitrary Core Image displacement filter to a backdrop and call
that verified live refraction. Do not use a screenshot loop or a synthetic demo
as proof that actual SpringBoard backgrounds are supplied correctly.

## Reproduction

Existing read-only helpers are in the sibling `GlassFolders-Test3-audit/tools`
directory. From the workspace root, with Python and Capstone installed:

```powershell
python -B GlassFolders-Test3-audit/tools/inspect_rendering_package.py G:/QQDownload/com.go.mango_1.0-Beta14-4_iphoneos-arm64e_roothide.deb
python -B GlassFolders-Test3-audit/tools/inspect_mango_foreground.py G:/QQDownload/com.go.mango_1.0-Beta14-4_iphoneos-arm64e_roothide.deb --module MangoOSRendering.dylib --pattern 'setFragmentTexture|newLibrary|newFunction|renderCommandEncoder' --max-calls 10 --dump
```

The second helper was originally written for Mango and assumes zero-based ARM64
images smaller than 4 GiB. It indexed this renderer as 0 Objective-C methods and
74 selector stubs, then scanned all `0x7e6c` text bytes. Function and call-site
addresses above are image-relative virtual addresses tied to the recorded hash.
No third-party shader or dylib is extracted or incorporated in our package.
