from pathlib import Path
import plistlib
r = Path(__file__).resolve().parents[1]
app = r / 'Experiments/OpticsLab05Probe'
make = (r / 'Makefile').read_text()
assert 'GlassFolders_FILES = Tweak.xm' in make
assert 'OpticsLab05Probe' not in make
assert (r / 'Experiments/GFStandaloneRefractionRenderer.mm').exists()
a = (app / 'Makefile').read_text()
assert 'GFStandaloneRefractionRenderer.mm' in a
assert 'GFOpticsLab05.metallib' in a
assert 'GFOpticsProbe' in a
assert 'APPLICATION_NAME = GFOpticsProbe' in a
assert not any(word in a for word in ['Tweak.xm','backboardd','MangoOSRendering'])
main = (app / 'GFProbeViewController.mm').read_text()
assert 'encodeCapture:_capture output:_panelTexture' in main
assert '[cmd presentDrawable:drawable]' in main
assert 'gfProbeBackground' in main
assert 'MTKView' in main
assert not any(word in main for word in ['UIScreen.mainScreen snapshot','drawViewHierarchyInRect','IOSurfaceLookup','backboardd'])
shaders = (app / 'GFProbeShaders.metal').read_text()
for symbol in ['gfProbeBackground','gfProbePanel','gfProbeCopy','gfProbeVertex']:
    assert symbol in shaders
p = plistlib.loads((app / 'Resources/Info.plist').read_bytes())
assert p['CFBundleIdentifier'] == 'com.kulinich.glassfolders.opticsprobe'
assert p['MinimumOSVersion'] == '16.0'
print('Lab05 isolated synthetic Metal app structure: PASS')
