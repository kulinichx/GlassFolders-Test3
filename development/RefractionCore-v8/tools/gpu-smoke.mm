// Standalone GPU output test with synthetic textures; NO system backdrop access.
// Can be compiled on Mac or separately in a test-only Theos tool on a device.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "../src/GFRefractionRenderer.h"
#import <vector>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    (void)argc; (void)argv;
    @autoreleasepool {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) { fprintf(stderr, "SKIP: Metal GPU unavailable.\n"); return 77; }
        const NSUInteger bgW = 400, bgH = 300, cardW = 128, cardH = 96;
        MTLTextureDescriptor *bgDesc = [MTLTextureDescriptor
            texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
            width:bgW height:bgH mipmapped:NO];
        bgDesc.usage = MTLTextureUsageShaderRead;
        bgDesc.storageMode = MTLStorageModeShared;
        id<MTLTexture> bg = [device newTextureWithDescriptor:bgDesc];
        MTLTextureDescriptor *outDesc = [MTLTextureDescriptor
            texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
            width:cardW height:cardH mipmapped:NO];
        outDesc.usage = MTLTextureUsageShaderWrite;
        outDesc.storageMode = MTLStorageModeShared;
        id<MTLTexture> out = [device newTextureWithDescriptor:outDesc];
        id<MTLTexture> zeroBend = [device newTextureWithDescriptor:outDesc];
        if (!bg || !out || !zeroBend) { fprintf(stderr, "FAIL: texture allocation\n"); return 1; }
        std::vector<uint8_t> pixels(bgW * bgH * 4, 255);
        for (NSUInteger y = 0; y < bgH; ++y) {
            for (NSUInteger x = 0; x < bgW; ++x) {
                const size_t index = (y * bgW + x) * 4;
                pixels[index] = (uint8_t)(x * 7 % 256);
                pixels[index + 1] = (uint8_t)(y * 11 % 256);
                pixels[index + 2] = (uint8_t)((x + y) * 5 % 256);
            }
        }
        [bg replaceRegion:MTLRegionMake2D(0, 0, bgW, bgH)
              mipmapLevel:0 withBytes:pixels.data() bytesPerRow:bgW * 4];
        NSError *error = nil;
        GFRefractionRenderer *renderer = [[GFRefractionRenderer alloc]
                                              initWithDevice:device error:&error];
        if (!renderer) {
            fprintf(stderr, "FAIL: Metal runtime compilation: %s\n",
                    error.localizedDescription.UTF8String); return 2;
        }
        id<MTLCommandQueue> queue = [device newCommandQueue];
        id<MTLCommandBuffer> buffer = [queue commandBuffer];
        BOOL ok = [renderer encodeBackdrop:bg intoCard:out
                         cardRect:CGRectMake(80, 60, cardW, cardH)
                     cornerRadius:32.0f bevelWidth:17.0f
                 displacementPx:7.0f dispersionPx:0.35f
                  sheenStrength:0.10f opacity:0.78f
                    samplingAxes:simd_make_float4(1, 0, 0, 1)
             samplingTranslation:simd_make_float2(0, 0)
                    commandBuffer:buffer error:&error];
        if (ok) {
            ok = [renderer encodeBackdrop:bg intoCard:zeroBend
                          cardRect:CGRectMake(80, 60, cardW, cardH)
                      cornerRadius:32.0f bevelWidth:17.0f
                  displacementPx:0.0f dispersionPx:0.0f
                   sheenStrength:0.10f opacity:0.78f
                     samplingAxes:simd_make_float4(1, 0, 0, 1)
              samplingTranslation:simd_make_float2(0, 0)
                     commandBuffer:buffer error:&error];
        }
        if (!ok) {
            fprintf(stderr, "FAIL: Metal encode: %s\n", error.localizedDescription.UTF8String);
            return 3;
        }
        [buffer commit];
        [buffer waitUntilCompleted];
        if (buffer.status != MTLCommandBufferStatusCompleted) {
            fprintf(stderr, "FAIL: GPU command: %s\n", buffer.error.localizedDescription.UTF8String);
            return 4;
        }
        std::vector<uint8_t> dst(cardW * cardH * 4);
        std::vector<uint8_t> baseline(cardW * cardH * 4);
        [out getBytes:dst.data() bytesPerRow:cardW * 4
           fromRegion:MTLRegionMake2D(0, 0, cardW, cardH) mipmapLevel:0];
        [zeroBend getBytes:baseline.data() bytesPerRow:cardW * 4
             fromRegion:MTLRegionMake2D(0, 0, cardW, cardH) mipmapLevel:0];
        auto alphaAt = [&](NSUInteger x, NSUInteger y) { return dst[(y * cardW + x) * 4 + 3]; };
        if (alphaAt(0, 0) != 0 || alphaAt(cardW / 2, cardH / 2) != 0 ||
            alphaAt(cardW / 2, 1) < 10) {
            fprintf(stderr, "FAIL: alpha corner=%u center=%u rim=%u\n",
                    alphaAt(0, 0), alphaAt(cardW / 2, cardH / 2), alphaAt(cardW / 2, 1));
            return 5;
        }
        size_t changed = 0;
        for (size_t i = 0; i < dst.size(); i += 4) {
            // Both are premultiplied-alpha buffers with identical alpha geometry.
            if (dst[i + 3] != baseline[i + 3]) {
                fprintf(stderr, "FAIL: different alpha for same geometry\n"); return 6;
            }
            for (int c = 0; c < 3; ++c) {
                if (dst[i + c] > dst[i + 3] + 1) {
                    fprintf(stderr, "FAIL: nonpremultiplied color\n"); return 6;
                }
            }
            if (dst[i + 3] > 10 &&
                (abs((int)dst[i] - (int)baseline[i]) > 3 ||
                 abs((int)dst[i + 1] - (int)baseline[i + 1]) > 3 ||
                 abs((int)dst[i + 2] - (int)baseline[i + 2]) > 3)) ++changed;
        }
        if (changed < 100) { fprintf(stderr, "FAIL: GPU displacement made too little difference\n"); return 6; }
        printf("PASS: real GPU synthetic backdrop refracted; changed_pixels=%zu; no compositor.\n", changed);
        return 0;
    }
}
