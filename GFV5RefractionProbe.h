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
 * GlassFolders V5.2 - input-map and channel displacement controls (read-only).
 * No SpringBoard view mutation, wallpaper capture, screenshots or networking.
 * The V4 diagnostics entry point still calls this function once per process.
 */
static NSUInteger GFV51CountPixelDifferences(NSData *reference,
                                             NSData *candidate,
                                             NSUInteger *absoluteSum) {
    enum { W = 64, H = 64, BPP = 4 };
    const uint8_t *a = (const uint8_t *)reference.bytes;
    const uint8_t *b = (const uint8_t *)candidate.bytes;
    if (!a || !b || reference.length < W*H*BPP || candidate.length < W*H*BPP) {
        if (absoluteSum) *absoluteSum = 0;
        return 0;
    }
    NSUInteger changed = 0;
    NSUInteger total = 0;
    for (NSUInteger y = 10; y < 54; ++y) {
        for (NSUInteger x = 10; x < 54; ++x) {
            NSUInteger i = (y * W + x) * BPP;
            NSUInteger difference = (NSUInteger)abs((int)a[i] - (int)b[i]) +
                (NSUInteger)abs((int)a[i + 1] - (int)b[i + 1]) +
                (NSUInteger)abs((int)a[i + 2] - (int)b[i + 2]);
            total += difference;
            if (difference >= 75) ++changed;
        }
    }
    if (absoluteSum) *absoluteSum = total;
    return changed;
}

static void GFV5RunSyntheticRefractionProbeOnce(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        @autoreleasepool {
            NSMutableArray<NSString *> *report = [NSMutableArray array];
            [report addObject:@"GlassFolders V5.2: displacement channels and filter inputs"];
            [report addObject:@"NOT a live SpringBoard backdrop refraction test"];
            [report addObject:[NSString stringWithFormat:@"timestamp=%@", [NSDate date]]];

            Class caFilter = NSClassFromString(@"CAFilter");
            Class backdrop = NSClassFromString(@"CABackdropLayer");
            BOOL caFilterFactory = caFilter &&
                [caFilter respondsToSelector:NSSelectorFromString(@"filterWithType:")];
            [report addObject:[NSString stringWithFormat:@"privateCAFilterFactoryPresent=%d", caFilterFactory]];
            [report addObject:[NSString stringWithFormat:@"privateCABackdropClassPresent=%d", backdrop != Nil]];

            id<MTLDevice> device = MTLCreateSystemDefaultDevice();
            [report addObject:[NSString stringWithFormat:@"metalDeviceAvailable=%d", device != nil]];

            BOOL filterAvailable = NO;
            BOOL metalContextCreated = NO;
            BOOL allRenderCallsCompleted = NO;
            NSUInteger affineChanged = 0, neutralChanged = 0, warpChanged = 0;
            NSUInteger patternedChanged = 0, mapChanged = 0;
            NSUInteger affineSum = 0, neutralSum = 0, warpSum = 0;
            NSUInteger patternedSum = 0, mapSum = 0;
            BOOL displacementInputKeyPresent = NO;
            BOOL displacementInputAccepted = NO;
            BOOL outputImagesPresent = NO;
            NSString *errorSummary = @"none";
            CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
            CGColorSpaceRef colorSpace = NULL;

            @try {
                CIFilter *warp = [CIFilter filterWithName:@"CIDisplacementDistortion"];
                filterAvailable = (warp != nil);
                if (device && warp) {
                    enum { W = 64, H = 64, BPP = 4 };
                    NSMutableData *source = [NSMutableData dataWithLength:W * H * BPP];
                    NSMutableData *mapNeutral = [NSMutableData dataWithLength:W * H * BPP];
                    NSMutableData *mapShifted = [NSMutableData dataWithLength:W * H * BPP];
                    NSMutableData *mapPattern = [NSMutableData dataWithLength:W * H * BPP];
                    uint8_t *s = (uint8_t *)source.mutableBytes;
                    uint8_t *n = (uint8_t *)mapNeutral.mutableBytes;
                    uint8_t *d = (uint8_t *)mapShifted.mutableBytes;
                    uint8_t *p = (uint8_t *)mapPattern.mutableBytes;
                    for (NSUInteger y = 0; y < H; ++y) {
                        for (NSUInteger x = 0; x < W; ++x) {
                            NSUInteger i = (y * W + x) * BPP;
                            // Non-periodic RGB test image: unlike 4px stripes,
                            // 5px of displacement cannot alias back to itself.
                            s[i]     = (uint8_t)((x * 37 + y * 11 + (x ^ y) * 19) & 255);
                            s[i + 1] = (uint8_t)((x * 13 + y * 43 + (x * y) * 3) & 255);
                            s[i + 2] = (uint8_t)((x * 29 + y * 17 + (x ^ (y * 7))) & 255);
                            s[i + 3] = 255;
                            // 128/128 is the neutral red/green vector.
                            n[i] = 128; n[i + 1] = 128;
                            n[i + 2] = 128; n[i + 3] = 255;
                            // Strong and unequal R/G channels detect filters
                            // which interpret the two channels as a 2D vector.
                            d[i] = 240; d[i + 1] = 18;
                            d[i + 2] = 128; d[i + 3] = 255;
                            // Four quadrants: spatially varying displacement,
                            // rather than a flat color or repetitive stripes.
                            p[i] = (x < W / 2) ? 12 : 245;
                            p[i + 1] = (y < H / 2) ? 240 : 10;
                            p[i + 2] = 128; p[i + 3] = 255;
                        }
                    }
                    colorSpace = CGColorSpaceCreateDeviceRGB();
                    CIImage *sourceImage = [[CIImage alloc] initWithBitmapData:source
                        bytesPerRow:W * BPP size:CGSizeMake(W, H)
                        format:kCIFormatRGBA8 colorSpace:colorSpace];
                    CIImage *neutralImage = [[CIImage alloc] initWithBitmapData:mapNeutral
                        bytesPerRow:W * BPP size:CGSizeMake(W, H)
                        format:kCIFormatRGBA8 colorSpace:colorSpace];
                    CIImage *shiftedImage = [[CIImage alloc] initWithBitmapData:mapShifted
                        bytesPerRow:W * BPP size:CGSizeMake(W, H)
                        format:kCIFormatRGBA8 colorSpace:colorSpace];
                    CIImage *patternImage = [[CIImage alloc] initWithBitmapData:mapPattern
                        bytesPerRow:W * BPP size:CGSizeMake(W, H)
                        format:kCIFormatRGBA8 colorSpace:colorSpace];
                    CIContext *context = [CIContext contextWithMTLDevice:device
                        options:@{ kCIContextCacheIntermediates: @NO }];
                    metalContextCreated = (context != nil);
                    if (context && sourceImage && neutralImage && shiftedImage && patternImage) {
                        // Three separate filter objects eliminate any possible
                        // mutable CIFilter graph reuse between output images.
                        CIFilter *neutralWarp = [CIFilter filterWithName:@"CIDisplacementDistortion"];
                        CIFilter *channelWarp = [CIFilter filterWithName:@"CIDisplacementDistortion"];
                        CIFilter *patternWarp = [CIFilter filterWithName:@"CIDisplacementDistortion"];
                        displacementInputKeyPresent = [[warp inputKeys]
                            containsObject:@"inputDisplacementImage"];
                        for (CIFilter *f in @[neutralWarp, channelWarp, patternWarp]) {
                            [f setValue:sourceImage forKey:kCIInputImageKey];
                            [f setValue:@32.0 forKey:kCIInputScaleKey];
                        }
                        [neutralWarp setValue:neutralImage forKey:@"inputDisplacementImage"];
                        [channelWarp setValue:shiftedImage forKey:@"inputDisplacementImage"];
                        [patternWarp setValue:patternImage forKey:@"inputDisplacementImage"];
                        displacementInputAccepted =
                            [neutralWarp valueForKey:@"inputDisplacementImage"] != nil &&
                            [channelWarp valueForKey:@"inputDisplacementImage"] != nil &&
                            [patternWarp valueForKey:@"inputDisplacementImage"] != nil;
                        CIImage *neutralOutput = neutralWarp.outputImage;
                        CIImage *shiftedOutput = channelWarp.outputImage;
                        CIImage *patternOutput = patternWarp.outputImage;
                        // The affine control validates rendering and comparison.
                        CIImage *affineOutput = [sourceImage imageByApplyingTransform:
                            CGAffineTransformMakeTranslation(5.0, 0.0)];
                        outputImagesPresent = neutralOutput && shiftedOutput &&
                            patternOutput && affineOutput;
                        if (outputImagesPresent) {
                            NSMutableData *baseline = [NSMutableData dataWithLength:W*H*BPP];
                            NSMutableData *affine = [NSMutableData dataWithLength:W*H*BPP];
                            NSMutableData *neutral = [NSMutableData dataWithLength:W*H*BPP];
                            NSMutableData *shifted = [NSMutableData dataWithLength:W*H*BPP];
                            NSMutableData *patterned = [NSMutableData dataWithLength:W*H*BPP];
                            NSMutableData *neutralMapRendered = [NSMutableData dataWithLength:W*H*BPP];
                            NSMutableData *shiftedMapRendered = [NSMutableData dataWithLength:W*H*BPP];
                            CGRect bounds = CGRectMake(0, 0, W, H);
                            [context render:sourceImage toBitmap:baseline.mutableBytes
                                rowBytes:W*BPP bounds:bounds format:kCIFormatRGBA8
                                colorSpace:colorSpace];
                            [context render:affineOutput toBitmap:affine.mutableBytes
                                rowBytes:W*BPP bounds:bounds format:kCIFormatRGBA8
                                colorSpace:colorSpace];
                            [context render:neutralOutput toBitmap:neutral.mutableBytes
                                rowBytes:W*BPP bounds:bounds format:kCIFormatRGBA8
                                colorSpace:colorSpace];
                            [context render:shiftedOutput toBitmap:shifted.mutableBytes
                                rowBytes:W*BPP bounds:bounds format:kCIFormatRGBA8
                                colorSpace:colorSpace];
                            [context render:patternOutput toBitmap:patterned.mutableBytes
                                rowBytes:W*BPP bounds:bounds format:kCIFormatRGBA8
                                colorSpace:colorSpace];
                            [context render:neutralImage toBitmap:neutralMapRendered.mutableBytes
                                rowBytes:W*BPP bounds:bounds format:kCIFormatRGBA8
                                colorSpace:colorSpace];
                            [context render:shiftedImage toBitmap:shiftedMapRendered.mutableBytes
                                rowBytes:W*BPP bounds:bounds format:kCIFormatRGBA8
                                colorSpace:colorSpace];
                            allRenderCallsCompleted = YES;
                            affineChanged = GFV51CountPixelDifferences(baseline, affine, &affineSum);
                            neutralChanged = GFV51CountPixelDifferences(baseline, neutral, &neutralSum);
                            warpChanged = GFV51CountPixelDifferences(baseline, shifted, &warpSum);
                            patternedChanged = GFV51CountPixelDifferences(baseline, patterned, &patternedSum);
                            mapChanged = GFV51CountPixelDifferences(neutralMapRendered,
                                shiftedMapRendered, &mapSum);
                        }
                    }
                }
            } @catch (NSException *exception) {
                errorSummary = exception.name ?: @"unknown-ObjC-exception";
            } @finally {
                if (colorSpace) CGColorSpaceRelease(colorSpace);
            }

            BOOL affineControlWorks = allRenderCallsCompleted && affineChanged > 100;
            BOOL syntheticWarpWorks = affineControlWorks && mapChanged > 100 &&
                displacementInputKeyPresent && displacementInputAccepted &&
                ((warpChanged > neutralChanged + 100 && warpSum > neutralSum + 1000) ||
                 (patternedChanged > neutralChanged + 100 && patternedSum > neutralSum + 1000));
            [report addObject:[NSString stringWithFormat:@"coreImageDisplacementAvailable=%d", filterAvailable]];
            [report addObject:[NSString stringWithFormat:@"metalContextCreated=%d", metalContextCreated]];
            [report addObject:[NSString stringWithFormat:@"allRenderCallsCompleted=%d", allRenderCallsCompleted]];
            [report addObject:[NSString stringWithFormat:@"displacementInputKeyPresent=%d", displacementInputKeyPresent]];
            [report addObject:[NSString stringWithFormat:@"displacementInputAccepted=%d", displacementInputAccepted]];
            [report addObject:[NSString stringWithFormat:@"outputImagesPresent=%d", outputImagesPresent]];
            [report addObject:[NSString stringWithFormat:@"inputMapsChangedPixels=%lu", (unsigned long)mapChanged]];
            [report addObject:[NSString stringWithFormat:@"inputMapsAbsoluteDifference=%lu", (unsigned long)mapSum]];
            [report addObject:[NSString stringWithFormat:@"affineControlChangedPixels=%lu", (unsigned long)affineChanged]];
            [report addObject:[NSString stringWithFormat:@"neutralMapChangedPixels=%lu", (unsigned long)neutralChanged]];
            [report addObject:[NSString stringWithFormat:@"displacementMapChangedPixels=%lu", (unsigned long)warpChanged]];
            [report addObject:[NSString stringWithFormat:@"patternMapChangedPixels=%lu", (unsigned long)patternedChanged]];
            [report addObject:[NSString stringWithFormat:@"affineAbsoluteDifference=%lu", (unsigned long)affineSum]];
            [report addObject:[NSString stringWithFormat:@"neutralAbsoluteDifference=%lu", (unsigned long)neutralSum]];
            [report addObject:[NSString stringWithFormat:@"displacementAbsoluteDifference=%lu", (unsigned long)warpSum]];
            [report addObject:[NSString stringWithFormat:@"patternAbsoluteDifference=%lu", (unsigned long)patternedSum]];
            [report addObject:[NSString stringWithFormat:@"syntheticWarpWorks=%d", syntheticWarpWorks]];
            [report addObject:[NSString stringWithFormat:@"renderDurationMs=%.1f", (CFAbsoluteTimeGetCurrent() - start) * 1000.0]];
            [report addObject:[NSString stringWithFormat:@"error=%@", errorSummary]];
            [report addObject:@"liveBackdropAcquisitionVerified=0"];
            [report addObject:@"note=Separate filters, R/G vectors, spatial map and rendered map control; no live background captured."];

            NSString *folder = @"/var/mobile/Library/Caches/GlassFolders";
            NSError *mkdirError = nil;
            [[NSFileManager defaultManager] createDirectoryAtPath:folder
                withIntermediateDirectories:YES attributes:nil error:&mkdirError];
            NSString *reportPath = [folder stringByAppendingPathComponent:@"LibraryRefraction-v5.2.txt"];
            NSError *writeError = nil;
            BOOL written = [[report componentsJoinedByString:@"\n"]
                writeToFile:reportPath atomically:YES encoding:NSUTF8StringEncoding error:&writeError];
            NSLog(@"[GlassFolders V5.2] controls complete: affine=%lu neutral=%lu shifted=%lu saved=%d error=%@",
                (unsigned long)affineChanged, (unsigned long)neutralChanged,
                (unsigned long)warpChanged, written,
                writeError ? writeError.domain : @"none");
        }
    });
}

#endif // GF_V5_REFRACTION_PROBE_H
