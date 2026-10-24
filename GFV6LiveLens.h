#ifndef GF_V6_LIVE_LENS_H
#define GF_V6_LIVE_LENS_H

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreImage/CoreImage.h>
#import <objc/message.h>
#import <math.h>
#include <stdint.h>

/*
 * GlassFolders V6: visible, one-card, snapshot-based refraction prototype.
 * It DOES sample real on-screen SpringBoard content, but not continuously.
 * Images live in memory, never on disk or network. Fail closed.
 * No private filter assignment and no recurring display link/timer.
 */
static BOOL GFV6RefractionEnabled = NO;
static BOOL GFV6CaptureInProgress = NO;

@interface GFV6LensImageView : UIImageView
@end
@implementation GFV6LensImageView
@end

static inline CGFloat GFV6Clamp(CGFloat v, CGFloat lo, CGFloat hi) {
    return fmin(hi, fmax(lo, v));
}

static void GFV6CollectGlassViews(UIView *view, NSMutableArray<UIView *> *candidates,
                                 NSUInteger *visits) {
    if (!view || *visits >= 2500 || candidates.count >= 48) return;
    (*visits)++;
    Class cls = NSClassFromString(@"GFAppLibraryGlassView");
    if (cls && [view isKindOfClass:cls]) {
        CGSize s = view.bounds.size;
        if (s.width > 110 && s.height > 100 && s.height < 520 && view.window && !view.hidden) {
            [candidates addObject:view];
        }
        return; // Do not traverse inside glass itself.
    }
    for (UIView *child in [view.subviews copy]) {
        GFV6CollectGlassViews(child, candidates, visits);
        if (*visits >= 2500 || candidates.count >= 48) return;
    }
}

static void GFV6ClearLensOverlays(UIView *root) {
    if (!root) return;
    NSMutableArray<UIView *> *candidates = [NSMutableArray array];
    NSUInteger visits = 0;
    GFV6CollectGlassViews(root, candidates, &visits);
    for (UIView *glass in candidates) {
        for (UIView *child in [glass.subviews copy]) {
            if ([child isKindOfClass:GFV6LensImageView.class]) [child removeFromSuperview];
        }
    }
}

static UIImage *GFV6SnapshotUnderGlass(UIView *glass, CGRect *outSample) {
    UIWindow *window = glass.window;
    if (!window || !outSample || GFV6CaptureInProgress) return nil;
    CGRect card = [glass convertRect:glass.bounds toView:window];
    if (!isfinite(card.origin.x) || !isfinite(card.origin.y) ||
        card.size.width < 110 || card.size.height < 100 ||
        card.size.width > 540 || card.size.height > 520) return nil;
    CGFloat pad = 28.0;
    CGRect sample = CGRectInset(card, -pad, -pad);
    if (sample.size.width * sample.size.height > 320000) return nil;

    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1.0; // intentionally low-res, only a narrow boundary ring
    format.opaque = YES;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc]
        initWithSize:sample.size format:format];
    __block BOOL success = NO;
    __block UIImage *image = nil;
    GFV6CaptureInProgress = YES;
    @try {
        // Hide just this card's native glass so the warp samples the scene
        // rather than recursively sampling our effect. Existing app icons
        // outside the glass view are not modified.
        BOOL oldHidden = glass.hidden;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        glass.hidden = YES;
        @try {
            image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
                (void)ctx;
                success = [window drawViewHierarchyInRect:
                    CGRectMake(-sample.origin.x, -sample.origin.y,
                               window.bounds.size.width, window.bounds.size.height)
                    afterScreenUpdates:NO];
            }];
        } @finally {
            glass.hidden = oldHidden;
            [CATransaction commit];
        }
    } @catch (__unused NSException *error) {
        image = nil;
    } @finally {
        GFV6CaptureInProgress = NO;
    }
    if (!success || !image.CGImage) return nil;
    *outSample = sample;
    return image;
}

static UIImage *GFV6MakeRefractedRing(UIImage *source, CGRect cardInSample,
                                     CGFloat radius) {
    if (!source.CGImage) return nil;
    const size_t w = CGImageGetWidth(source.CGImage);
    const size_t h = CGImageGetHeight(source.CGImage);
    if (w < 100 || h < 100 || w*h > 320000) return nil;
    const size_t rowBytes = w*4;
    NSMutableData *map = [NSMutableData dataWithLength:rowBytes*h];
    uint8_t *m = (uint8_t *)map.mutableBytes;
    CGFloat centerX = CGRectGetMidX(cardInSample);
    CGFloat centerY = CGRectGetMidY(cardInSample);
    CGFloat halfW = cardInSample.size.width / 2.0;
    CGFloat halfH = cardInSample.size.height / 2.0;
    CGFloat r = GFV6Clamp(radius, 8.0, fmin(halfW,halfH));
    // Signed distance from a rounded rectangle; negative inside glass.
    for (size_t y = 0; y < h; ++y) {
        for (size_t x = 0; x < w; ++x) {
            CGFloat dx = (CGFloat)x + 0.5 - centerX;
            CGFloat dy = (CGFloat)y + 0.5 - centerY;
            CGFloat ax = fabs(dx) - (halfW-r), ay = fabs(dy) - (halfH-r);
            CGFloat outside = hypot(fmax(ax,0),fmax(ay,0));
            CGFloat sdf = outside + fmin(fmax(ax,ay),0) - r;
            CGFloat distInside = -sdf;
            // Distort within the first ~20 px inside the perimeter.
            CGFloat weight = GFV6Clamp((22.0-distInside)/22.0,0,1);
            weight *= weight;
            CGFloat normalX = (dx >= 0 ? 1 : -1) *
                (ax >= ay ? 1.0 : 0.40);
            CGFloat normalY = (dy >= 0 ? 1 : -1) *
                (ay > ax ? 1.0 : 0.40);
            size_t i = (y*w+x)*4;
            m[i]   = (uint8_t)lrint(GFV6Clamp(128 + normalX*116*weight,0,255));
            m[i+1] = (uint8_t)lrint(GFV6Clamp(128 + normalY*116*weight,0,255));
            m[i+2] = 128; m[i+3] = 255;
        }
    }
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    if (!cs) return nil;
    CIImage *image = [CIImage imageWithCGImage:source.CGImage];
    CIImage *mapImage = [[CIImage alloc] initWithBitmapData:map
         bytesPerRow:rowBytes size:CGSizeMake(w,h) format:kCIFormatRGBA8 colorSpace:cs];
    CIFilter *warp = [CIFilter filterWithName:@"CIDisplacementDistortion"];
    if (!warp || !mapImage) { CGColorSpaceRelease(cs); return nil; }
    [warp setValue:image forKey:kCIInputImageKey];
    [warp setValue:mapImage forKey:@"inputDisplacementImage"];
    [warp setValue:@19.0 forKey:kCIInputScaleKey];
    CIImage *output = warp.outputImage;
    if (!output) { CGColorSpaceRelease(cs); return nil; }
    // A normal Core Image render: no unsupported CALayer.filters on iOS.
    static CIContext *context = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        context = [CIContext contextWithOptions:@{
            kCIContextUseSoftwareRenderer: @NO,
            kCIContextCacheIntermediates: @NO
        }];
    });
    if (!context) { CGColorSpaceRelease(cs); return nil; }
    NSMutableData *rgba = [NSMutableData dataWithLength:rowBytes*h];
    @try {
        [context render:output toBitmap:rgba.mutableBytes rowBytes:rowBytes
                  bounds:CGRectMake(0,0,w,h) format:kCIFormatRGBA8 colorSpace:cs];
    } @catch (__unused NSException *exception) {
        CGColorSpaceRelease(cs); return nil;
    }
    CGColorSpaceRelease(cs);
    // Feather the warped snapshot into a rounded 19 pt interior ring.
    // This prevents duplicated icons in the central part of a category pod.
    uint8_t *pixel = (uint8_t *)rgba.mutableBytes;
    for (size_t y = 0; y < h; ++y) {
        for (size_t x = 0; x < w; ++x) {
            CGFloat dx = (CGFloat)x + 0.5 - centerX;
            CGFloat dy = (CGFloat)y + 0.5 - centerY;
            CGFloat ax = fabs(dx)-(halfW-r), ay=fabs(dy)-(halfH-r);
            CGFloat sdf = hypot(fmax(ax,0),fmax(ay,0)) + fmin(fmax(ax,ay),0) - r;
            CGFloat d = -sdf;
            CGFloat outer = GFV6Clamp(d/1.5,0,1);
            CGFloat inner = GFV6Clamp((21.0-d)/17.0,0,1);
            CGFloat opacity = 0.88*outer*inner;
            pixel[(y*w+x)*4+3] = (uint8_t)lrint(opacity*255);
        }
    }
    // Explicit bitmap lifetime: copy pixel bytes into the CGImage provider.
    CFDataRef bytes = CFDataCreate(kCFAllocatorDefault, (const UInt8 *)rgba.bytes, (CFIndex)rgba.length);
    if (!bytes) return nil;
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(bytes);
    CFRelease(bytes);
    if (!provider) return nil;
    CGColorSpaceRef outputCS = CGColorSpaceCreateDeviceRGB();
    CGImageRef cg = CGImageCreate(w,h,8,32,rowBytes,outputCS,
        kCGBitmapByteOrderDefault | kCGImageAlphaLast,
        provider,NULL,false,kCGRenderingIntentDefault);
    CGColorSpaceRelease(outputCS);
    CGDataProviderRelease(provider);
    if (!cg) return nil;
    UIImage *lens = [UIImage imageWithCGImage:cg scale:1.0 orientation:UIImageOrientationUp];
    CGImageRelease(cg);
    return lens;
}

static void GFV6UpdateVisibleCard(UIView *root, BOOL enabled) {
    if (![NSThread isMainThread] || !root.window || GFV6CaptureInProgress) return;
    GFV6ClearLensOverlays(root);
    if (!enabled) return;
    NSMutableArray<UIView *> *candidates = [NSMutableArray array];
    NSUInteger visited = 0;
    GFV6CollectGlassViews(root,candidates,&visited);
    if (!candidates.count) return;
    // Only the first, upper-left category card, never every card or search.
    [candidates sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        CGRect ra=[a convertRect:a.bounds toView:a.window];
        CGRect rb=[b convertRect:b.bounds toView:b.window];
        if (fabs(ra.origin.y-rb.origin.y)>20.0)
            return ra.origin.y<rb.origin.y ? NSOrderedAscending:NSOrderedDescending;
        return ra.origin.x<rb.origin.x ? NSOrderedAscending:NSOrderedDescending;
    }];
    UIView *glass = candidates.firstObject;
    CGRect captured = CGRectZero;
    UIImage *raw = GFV6SnapshotUnderGlass(glass,&captured);
    if (!raw) return;
    CGRect frame = [glass convertRect:glass.bounds toView:glass.window];
    CGRect cardInSample=CGRectOffset(frame,-captured.origin.x,-captured.origin.y);
    CGFloat radius = glass.layer.cornerRadius;
    if (radius < 5.0) radius = fmin(22.0,glass.bounds.size.height*0.14);
    UIImage *refracted = GFV6MakeRefractedRing(raw,cardInSample,radius);
    if (!refracted) return;
    GFV6LensImageView *overlay = [[GFV6LensImageView alloc] initWithImage:refracted];
    overlay.userInteractionEnabled=NO;
    overlay.contentMode=UIViewContentModeScaleToFill;
    overlay.frame=CGRectMake(captured.origin.x-frame.origin.x,
                             captured.origin.y-frame.origin.y,
                             captured.size.width,captured.size.height);
    overlay.accessibilityElementsHidden=YES;
    // Keep the ring inside the card's rounded bounds; never intercept touches.
    glass.clipsToBounds=YES;
    [glass addSubview:overlay];
}
#endif
