"""Guardrails: Lab04 is a shader + offscreen renderer, not a SpringBoard hook."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
makefile=(root/'Makefile').read_text()
assert 'GlassFolders_FILES = Tweak.xm' in makefile
assert 'GFStandaloneRefractionRenderer' not in makefile
assert 'GFRefraction.metal' not in makefile
assert 'GFRefractionMath.c' not in makefile
shader=(root/'Experiments/GFRefraction.metal').read_text()
for token in ('gfRefractionVertex', 'gfRefractionFragment',
              'capture.sample(', 's.originPx', 'float2 grad', 'base+split',
              'base-split', 'coverage'):
    assert token in shader, token
host=(root/'Experiments/GFStandaloneRefractionRenderer.mm').read_text()
for token in ('encodeCapture:', 'commandBuffer:', 'setFragmentTexture:capture',
              'setFragmentBytes:', 'drawPrimitives:'):
    assert token in host, token
assert 'backboardd' not in (host + shader)
print('Optics Lab 04 isolation and explicit texture input: PASS')
