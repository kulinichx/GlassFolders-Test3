#!/usr/bin/env python3
"""Static safety contract for the iOS 16 folder CAFilter bridge.

Not a SpringBoard integration test or proof of refraction.
"""
from pathlib import Path
import plistlib

p = plistlib.loads(Path('prefs/Resources/Root.plist').read_bytes())
items = [item for item in p['items'] if item.get('key') == 'FolderNativeRefractionEnabled']
assert len(items) == 1
entry = items[0]
assert entry['cell'] == 'PSSwitchCell'
assert entry['default'] is False
assert entry['gfStyle'] == 1 and entry['gfSection'] == 'home'
assert entry['defaults'] == 'com.kulinich.glassfolders'

src = Path('Tweak.xm').read_text()
bridge = Path('GFNativeLiveGlass.h').read_text()
assert src.count('GFFolderNativeLensInstall(self,') == 2
assert 'licensed &&\n        GFReadBool(CFSTR("FolderNativeRefractionEnabled"), NO)' in src
assert src.count('GFStyle == 1);') >= 2
assert 'if (!enabled || !host.window' in bridge
assert 'lens.hidden = YES;' in bridge
assert 'GFNativeLiveVendorAttached(provider)' in bridge
assert 'GFNativeAvailableFilterType()' in bridge
assert 'GFFolderLensRetryAfter = now + 8.0;' in bridge
assert 'takeScreenshot' not in bridge
assert 'CADisplayLink' not in bridge
assert 'MangoOSRendering' not in bridge

for lang in ('en.lproj', 'zh-Hans.lproj'):
    strings = Path(f'prefs/Resources/{lang}/Root.strings').read_text()
    assert '"Folder Live Refraction Bridge (Requires Engine)"' in strings

print('Optics Lab 03 folder bridge static safety checks: PASS')
