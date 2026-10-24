import json
import re
from pathlib import Path
import unittest
import tempfile
import sys
import hashlib
sys.path.insert(0,str(Path(__file__).resolve().parent))
from cpu_reference import make_backdrop, render_ring, create_demo

BASE=Path(__file__).resolve().parents[1]

class RefractionContractTests(unittest.TestCase):
    def test_embedded_shader_identical(self):
        source=(BASE/'src/GFRefraction.metal').read_text(encoding='utf8')
        embedded=(BASE/'src/GFRefractionShaderEmbedded.h').read_text(encoding='utf8')
        import ast
        strings=re.findall(r'^\s+("(?:[^"\\]|\\.)*")$',embedded,re.M)
        self.assertEqual(''.join(ast.literal_eval(x) for x in strings), source)
        self.assertIn(hashlib.sha256(source.encode('utf8')).hexdigest(),embedded)
    def test_shader_has_required_uniforms(self):
        shader=(BASE/'src/GFRefraction.metal').read_text()
        host=(BASE/'src/GFRefractionRenderer.mm').read_text()
        for name in ('cardRect','sourceShape','optics','affineAxes','affineOffset'):
            self.assertRegex(shader,r'float4\s+'+name+r'\s*;')
            self.assertRegex(host,r'simd_float4\s+'+name+r'\s*;')
        self.assertIn('static_assert(sizeof(GFUniforms) == 80',host)
    def test_center_and_outside_corner_transparent(self):
        img=render_ring(make_backdrop())
        self.assertEqual(img[95,134,3],0)
        self.assertEqual(img[0,0,3],0)
        self.assertGreater(img[1,134,3],.05)
    def test_overlay_always_premultiplied(self):
        rgba=render_ring(make_backdrop())
        self.assertTrue(((rgba[...,:3]-rgba[...,3:]) <= 1e-6).all())
    def test_zero_opacity_produces_no_overlay(self):
        rgba=render_ring(make_backdrop(),opacity=0)
        self.assertEqual(float(rgba.sum()),0)
    def test_rotation_mapping_alters_sample(self):
        scene=make_backdrop()
        identity=render_ring(scene)
        rotated=render_ring(scene,axes=(0,1,-1,0),translation=(370,0))
        self.assertGreater(float(abs(identity-rotated).sum()),50)
        self.assertEqual(identity[95,134,3], rotated[95,134,3])
    def test_demo_has_measurable_difference(self):
        with tempfile.TemporaryDirectory() as temp:
            result=create_demo(temp)
            self.assertGreater(result['changed_rgb_pixels_gt4'],1000)
            for file in ('before.png','after.png','difference_x3.png','metrics.json'):
                self.assertTrue((Path(temp)/file).exists())

if __name__=='__main__':
    unittest.main()

class BuildAndSafetyContractTests(unittest.TestCase):
    def test_theos_ci_installs_signer_before_build(self):
        workflow=(BASE/'ci/gf-refractioncore-v8.yml').read_text()
        self.assertIn('brew install ldid', workflow)
        self.assertIn('command -v ldid', workflow)
        self.assertLess(workflow.index('brew install ldid'),
                        workflow.index('make -C development/RefractionCore-v8'))

    def test_cpp17_does_not_use_cxx20_designated_initializers(self):
        renderer=(BASE/'src/GFRefractionRenderer.mm').read_text()
        self.assertIn('GFUniforms u = {};', renderer)
        self.assertNotRegex(renderer, r'(?m)^\s*\.cardRect\s*=')
        self.assertIn('static_assert(sizeof(GFUniforms) == 80', renderer)

    def test_frame_sequence_and_physical_display_scale_required(self):
        bridge=(BASE/'src/GFBackboardLiveFrameBridge.mm').read_text()
        header=(BASE/'src/GFBackboardLiveFrameBridge.h').read_text()
        self.assertIn('frame.liveFrameSequence <= _lastAcceptedFrameSequence', bridge)
        self.assertIn('@synchronized (self)', bridge)
        self.assertIn('screenPixelsPerPoint', header)
        self.assertIn('!isfinite(frame.screenPixelsPerPoint)', bridge)
        self.assertIn('cornerRadius:16.0f * scale', bridge)
        self.assertIn('bevelWidth:8.5f * scale', bridge)
        self.assertIn('if (encoded) _lastAcceptedFrameSequence', bridge)

    def test_commands_and_memoryless_texture_refused(self):
        src=(BASE/'src/GFRefractionRenderer.mm').read_text()
        self.assertIn('buffer.device != _device', src)
        self.assertIn('buffer.status >= MTLCommandBufferStatusCommitted', src)
        self.assertIn('backdrop.storageMode == MTLStorageModeMemoryless', src)
        self.assertIn('output.storageMode == MTLStorageModeMemoryless', src)
        self.assertIn('backdrop.usage & MTLTextureUsageShaderRead', src)
        self.assertIn('output.usage & MTLTextureUsageShaderWrite', src)

    def test_build_gates_include_both_native_languages(self):
        build=(BASE/'tools/verify-apple-build.sh').read_text()
        self.assertIn('--sdk iphoneos metal -c', build)
        self.assertIn('metal -o', build)
        self.assertIn('-std=c++17', build)
        self.assertIn('compile_ios arm64', build)
        self.assertIn('-dynamiclib', build)
        self.assertIn('GF_VERIFY_ARM64E', build)

    def test_ci_does_not_publish_or_inject(self):
        workflow=(BASE/'ci/gf-refractioncore-v8.yml').read_text()
        self.assertIn('runs-on: macos-15', workflow)
        self.assertIn('workflow_dispatch:', workflow)
        self.assertIn('verify-apple-build.sh', workflow)
        for forbidden in ('backboardd', 'deploy-pages', 'git push', 'make package install'):
            self.assertNotIn(forbidden, workflow)

    def test_gpu_smoke_compares_displacement_with_no_displacement(self):
        smoke=(BASE/'tools/gpu-smoke.mm').read_text()
        self.assertIn('displacementPx:7.0f', smoke)
        self.assertIn('displacementPx:0.0f', smoke)
        self.assertIn('MTLCommandBufferStatusCompleted', smoke)
        self.assertIn('GPU displacement made too little difference', smoke)

    def test_device_gpu_smoke_build_and_artifact(self):
        script=(BASE/'tools/verify-ios-smoke-build.sh').read_text()
        workflow=(BASE/'ci/gf-refractioncore-v8.yml').read_text()
        self.assertIn('GFRefractionRenderer.mm', script)
        self.assertIn('tools/gpu-smoke.mm', script)
        self.assertIn('-arch arm64', script)
        self.assertIn('ldid -S', script)
        self.assertIn('GFMetalSmoke-ios-arm64.zip', script)
        self.assertIn('actions/upload-artifact@v4', workflow)
        self.assertIn('verify-ios-smoke-build.sh', workflow)
        self.assertNotIn('make package install', script)

    def test_no_screenshot_capture_or_private_hook(self):
        src='\n'.join(p.read_text(encoding='utf-8') for p in (BASE/'src').glob('*')
            if p.suffix in ('.h','.mm','.metal'))
        for forbidden in ('drawViewHierarchyInRect', 'renderInContext:', 'CARenderServerRenderLayer',
                          'MSHookFunction', 'com.apple.backboardd'):
            self.assertNotIn(forbidden, src)
