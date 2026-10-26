#!/usr/bin/env python3
"""Source-level guardrails for iOS16 App Library's stable material reuse."""
from pathlib import Path
import plistlib
root = Path(__file__).resolve().parents[1]
s = (root / 'Tweak.xm').read_text()
h = (root / 'GFAppLibraryGlass.h').read_text()
assert 'GFAppLibraryFollowedStrength(void)' in s
assert 'GFLiquidGlassStrength : GFClearStrength' in s
assert 'GFMaterialResponse(strength)' in s
assert 'GFClearBlurResponse(strength)' in s
assert 'blur *= 0.65;' in s, 'Only App Library should reduce the second blur pass'
assert 'fabs(self.gfMaterialStrength - materialStrength) < 0.0005' in h
assert 'self.gfMaterialStrength = materialStrength;' in h
assert 'id brighten = GFCreateCAFilter(@"colorBrightness");' in h
assert 'BOOL stableLibrary = !self.gfDockVariant && !libraryLens && !appleLiquid;' in h
assert 'self.gfVolumeFalloff.hidden = !(stableLibrary ||' in h
assert 'self.gfDockLensSheen.hidden = !(stableLibrary ||' in h
assert 'GFAppLibraryGlassEnabled' in s
prefs = plistlib.loads((root / 'prefs/Resources/Root.plist').read_bytes())['items']
keys = {x.get('key') for x in prefs}
assert {'AppLibraryGlassEnabled', 'AppLibraryStyleMode', 'DockMode', 'Enabled'} <= keys
assert 'AppLibraryLensMaterialEnabled' not in keys
print('App Library shared closed-folder material: PASS')
