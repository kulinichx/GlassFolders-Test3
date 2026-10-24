#ifndef GF_V5_REFRACTION_PROBE_H
#define GF_V5_REFRACTION_PROBE_H

#import <Foundation/Foundation.h>
#import <CoreImage/CoreImage.h>
#import <Metal/Metal.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dispatch/dispatch.h>
#include <stdlib.h>
#include <stdint.h>

/*
 * GlassFolders V5 - synthetic displacement validation, not a UI renderer.
 * Runs once, only from the opt-in V4 App Library diagnostics path.
 * Works solely with generated 64x64 pixel buffers. No wallpaper sampling,
 * screenshots, user data, private CAFilter instantiation or UI mutation.
 */
static void GFV5RunSyntheticRefractionProbeOnce(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        @autoreleasepool {
            NSMutableArray<NSString *> *report = [NSMutableArray array];
            [report addObject:@"GlassFolders V5: generated-image refraction capability probe"];
            [report addObject:@"NOT a live SpringBoard backdrop refraction test"];
            [report addObject:[NSString stringWithFormat:@"timestamp=%@", [NSDate date]]];

            Class caFilter = NSClassFromString(@"CAFilter");
            Class backdrop = NSClassFromString(@"CABackdropLayer");
            BOOL caFilterFactory = caFilter && [caFilter respondsToSelector:NSSelectorFromString(@"filterWithType:")];
            [report addObject:[NSString stringWithFormat:@"privateCAFilterFactoryPresent=%d", caFilterFactory]];
            [report addObject:[NSString stringWithFormat:@"privateCABackdropClassPresent=%d", backdrop != Nil]];
            // Never call unknown private filter types in SpringBoard.

            id<MTLDevice> device = MTLCreateSystemDefaultDevice();
            [report addObject:[NSString stringWithFormat:@"metalDeviceAvailable=%d", device != nil]];
            BOOL gpuRendered = NO;
            NSUInteger pixelsChanged = 0;
            BOOL filterAvailable = NO;
            NSString *errorSummary = @"none";
            CFAbsoluteTime started = CFAbsoluteTimeGetCurrent();

            @try {
                CIFilter *warp = [CIFilter filterWithName:@"CIDisplacementDistortion"];
                filterAvailable = warp != nil;
                if (warp && device) {
                    enum { W = 64, H = 64, BPP = 4 };
                    NSMutableData *source = [NSMutableData dataWithLength:W * H * BPP];
                    NSMutableData *map = [NSMutableData dataWithLength:W * H * BPP];
                    uint8_t *s = (uint8_t *)source.mutableBytes;
                    uint8_t *m = (uint8_t *)map.mutableBytes;
                    for (NSUInteger y = 0; y < H; ++y) {
                        for (NSUInteger x = 0; x < W; ++x) {
                            const NSUInteger i = (y * W + x) * BPP;
                            const uint8_t stripe = ((x / 4) & 1) ? 240 : 12;
                            s[i] = stripe; s[i + 1] = stripe;
                            s[i + 2] = stripe; s[i + 3] = 255;
                            // Red channel offsets sampling in X; green is
                            // neutral Y. Compare against the undisplaced source.
                            m[i] = 210; m[i + 1] = 128;
                            m[i + 2] = 128; m[i + 3] = 255;
                        }
                    }
                    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
                    CIImage *sourceImage = [[CIImage alloc] initWithBitmapData:source
                        bytesPerRow:W * BPP size:CGSizeMake(W, H)
                        format:kCIFormatRGBA8 colorSpace:cs];
                    CIImage *mapImage = [[CIImage alloc] initWithBitmapData:map
                        bytesPerRow:W * BPP size:CGSizeMake(W, H)
                        format:kCIFormatRGBA8 colorSpace:cs];
                    [warp setValue:sourceImage forKey:kCIInputImageKey];
                    [warp setValue:mapImage forKey:@"inputDisplacementImage"];
                    [warp setValue:@20.0 forKey:kCIInputScaleKey];
                    CIImage *output = warp.outputImage;
                    if (output) {
                        CIContext *context = [CIContext contextWithMTLDevice:device
                            options:@{kCIContextCacheIntermediates: @NO}];
                        if (context) {
                            NSMutableData *result = [NSMutableData dataWithLength:W * H * BPP];
                            [context render:output toBitmap:result.mutableBytes
                                rowBytes:W * BPP bounds:CGRectMake(0, 0, W, H)
                                format:kCIFormatRGBA8 colorSpace:cs];
                            gpuRendered = YES;
                            const uint8_t *a = (const uint8_t *)result.bytes;
                            // Ignore sampling boundaries; only assert interior
                            // output differs, which blur-only visuals cannot do.
                            for (NSUInteger y = 12; y < 52; ++y) {
                                for (NSUInteger x = 12; x < 52; ++x) {
                                    NSUInteger i = (y * W + x) * BPP;
                                    if (abs((int)a[i] - (int)s[i]) > 80) {
                                        ++pixelsChanged;
                                    }
                                }
                            }
                        }
                    }
                    CGColorSpaceRelease(cs);
                }
            } @catch (NSException *exception) {
                // Keep exceptions local, do not allow test failures to bring
                // down SpringBoard. Never log sensitive exception userInfo.
                errorSummary = exception.name ?: @"unknown-ObjC-exception";
            }
            [report addObject:[NSString stringWithFormat:@"coreImageDisplacementAvailable=%d", filterAvailable]];
            [report addObject:[NSString stringWithFormat:@"syntheticGPUOutputRendered=%d", gpuRendered]];
            [report addObject:[NSString stringWithFormat:@"changedInteriorPixels=%lu", (unsigned long)pixelsChanged]];
            [report addObject:[NSString stringWithFormat:@"syntheticWarpWorks=%d", (gpuRendered && pixelsChanged > 100)]];
            [report addObject:[NSString stringWithFormat:@"renderDurationMs=%.1f", (CFAbsoluteTimeGetCurrent() - started) * 1000.0]];
            [report addObject:[NSString stringWithFormat:@"error=%@", errorSummary]];
            [report addObject:@"liveBackdropAcquisitionVerified=0"];
            [report addObject:@"note=Output proves only tiny synthetic image displacement, not Apple native Liquid Glass."];

            NSString *folder = @"/var/mobile/Library/Caches/GlassFolders";
            NSError *mkdirError = nil;
            [[NSFileManager defaultManager] createDirectoryAtPath:folder
                withIntermediateDirectories:YES attributes:nil error:&mkdirError];
            NSString *reportPath = [folder stringByAppendingPathComponent:@"LibraryRefraction-v5.txt"];
            NSError *writeError = nil;
            BOOL written = [[report componentsJoinedByString:@"\n"]
                writeToFile:reportPath atomically:YES
                encoding:NSUTF8StringEncoding error:&writeError];
            NSLog(@"[GlassFolders V5] synthetic probe complete: gpu=%d changed=%lu saved=%d error=%@",
                gpuRendered, (unsigned long)pixelsChanged, written,
                writeError ? writeError.domain : @"none");
        }
    });
}

#endif  // GF_V5_REFRACTION_PROBE_H
