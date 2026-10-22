// Horizontal edge lighting for App Library and Dock, separate from lock screen.
#ifndef GF_HORIZONTAL_GLASS_RIM_H
#define GF_HORIZONTAL_GLASS_RIM_H

#import "GFGlassRim.h"
#import <math.h>

static CGFloat GFHorizontalRimCoverage(BOOL shoulder, CGFloat t) {
    // No flat white core: start feathering immediately. A restrained wider
    // shoulder supplies depth without turning the whole edge into a rail.
    return (shoulder ? 0.36 : 1.0) * (1.0 - GFLockRimSmoothstep(t));
}

static CAGradientLayer *GFHorizontalRimBand(CGFloat peak, BOOL shade) {
    NSMutableArray *colors = [NSMutableArray arrayWithCapacity:18];
    // Sample one smooth light falloff around each cap. Nonzero side light
    // keeps the contour connected without a bright, uniform perimeter.
    NSArray *steps = @[@0.0, @0.08, @0.20, @0.35, @0.50,
                       @0.65, @0.80, @0.92, @1.0];
    for (NSUInteger index = 0; index < steps.count * 2; index++) {
        BOOL bottom = index >= steps.count;
        NSUInteger sample = bottom ? steps.count * 2 - 1 - index : index;
        CGFloat weight = 0.10 + (bottom ? 0.72 : 0.90) *
            (1.0 - GFLockRimSmoothstep([steps[sample] doubleValue]));
        [colors addObject:(id)[UIColor colorWithWhite:shade ? 0.0 : 1.0
            alpha:peak * weight].CGColor];
    }
    CAGradientLayer *band = GFLockRimBand(colors);
    // The shared factory has eight stops; this renderer sets eighteen after
    // learning the native radius. Keep the initial gradient evenly spaced.
    band.locations = nil;
    return band;
}

@interface GFHorizontalGlassRimView : UIView
@property (nonatomic, strong) CAGradientLayer *gfReflection;
@property (nonatomic, strong) CAGradientLayer *gfShoulder;
@property (nonatomic, strong) CAGradientLayer *gfInnerShade;
@property (nonatomic, strong) CAGradientLayer *gfLightEnvelope;
@property (nonatomic, assign) CGFloat gfRadius;
@property (nonatomic, assign) BOOL gfSearchVariant;
@property (nonatomic, assign) BOOL gfDockVariant;
@end

@implementation GFHorizontalGlassRimView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = UIColor.clearColor;
        self.layer.zPosition = 21.0;
        // Locations are set from the actual radius during layout. This
        // concentrates lighting on the horizontal edges, eases around the
        // curved caps and leaves the straight side middles nearly unlit.
        self.gfReflection = GFHorizontalRimBand(0.34, NO);
        self.gfShoulder = GFHorizontalRimBand(0.11, NO);
        self.gfInnerShade = GFHorizontalRimBand(0.06, YES);
        [self.layer addSublayer:self.gfInnerShade];
        [self.layer addSublayer:self.gfShoulder];
        [self.layer addSublayer:self.gfReflection];
        // Light varies across the long edges too. Attenuating the cap ends
        // removes the evenly lit white rail seen in lock13 device captures.
        _gfLightEnvelope = [CAGradientLayer layer];
        _gfLightEnvelope.startPoint = CGPointMake(0.0, 0.5);
        _gfLightEnvelope.endPoint = CGPointMake(1.0, 0.5);
        NSMutableArray *light = [NSMutableArray arrayWithCapacity:17];
        for (NSUInteger index = 0; index <= 16; index++) {
            CGFloat wave = sin(M_PI * index / 16.0);
            [light addObject:(id)[UIColor colorWithWhite:1.0
                alpha:0.35 + 0.65 * wave * wave].CGColor];
        }
        _gfLightEnvelope.colors = light;
        self.layer.mask = _gfLightEnvelope;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat height = CGRectGetHeight(self.bounds);
    CGFloat width = CGRectGetWidth(self.bounds);
    if (width <= 0.0 || height <= 0.0) return;
    CGFloat radius = MIN(MAX(0.0, self.gfRadius), MIN(width, height) * 0.5);
    CGFloat cap = MAX(0.01, MIN(0.5, radius / height));
    // At a capsule radius cap=0.5, the two cap tails meet at one quiet stop.
    NSArray *steps = @[@0.0, @0.08, @0.20, @0.35, @0.50,
                       @0.65, @0.80, @0.92, @1.0];
    NSMutableArray *locations = [NSMutableArray arrayWithCapacity:18];
    for (NSNumber *step in steps) [locations addObject:@(cap * step.doubleValue)];
    for (NSNumber *step in steps.reverseObjectEnumerator)
        [locations addObject:@(1.0 - cap * step.doubleValue)];
    CGFloat scale = self.window.screen.scale ?: UIScreen.mainScreen.scale;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.gfLightEnvelope.frame = self.bounds;
    self.gfLightEnvelope.contentsScale = scale;
    for (CAGradientLayer *band in @[self.gfInnerShade, self.gfShoulder, self.gfReflection]) {
        BOOL shade = band == self.gfInnerShade;
        BOOL shoulder = band == self.gfShoulder;
        // Search pills are shallow, so their bevel is narrower than a pod's.
        CGFloat reach = shade ? (self.gfSearchVariant ? 1.0 : 1.4) :
            (shoulder ? (self.gfSearchVariant ? 1.8 : (self.gfDockVariant ? 2.3 : 2.4)) :
                        (self.gfSearchVariant ? 1.0 : (self.gfDockVariant ? 1.4 : 1.35)));
        NSUInteger count = MAX((NSUInteger)1, (NSUInteger)ceil(reach * scale));
        reach = count / scale;
        band.frame = self.bounds;
        band.startPoint = CGPointMake(0.5, 0.0);
        band.endPoint = CGPointMake(0.5, 1.0);
        band.locations = locations;
        band.opacity = 1.0;
        band.contentsScale = scale;
        band.mask.frame = self.bounds;
        band.mask.contentsScale = scale;
        while (band.mask.sublayers.count > count)
            [band.mask.sublayers.lastObject removeFromSuperlayer];
        while (band.mask.sublayers.count < count) {
            CALayer *ring = [CALayer layer];
            ring.borderColor = UIColor.whiteColor.CGColor;
            ring.allowsEdgeAntialiasing = YES;
            [band.mask addSublayer:ring];
        }
        NSUInteger index = 0;
        for (CALayer *ring in band.mask.sublayers) {
            // Bright bands use overlapping cumulative borders with exactly
            // one native outer curve, preserving lock11's seam-free corners.
            CGFloat inset = shade ? reach * index / count : 0.0;
            CGRect rect = CGRectInset(self.bounds, inset, inset);
            rect.size.width = MAX(0.0, rect.size.width);
            rect.size.height = MAX(0.0, rect.size.height);
            ring.frame = rect;
            ring.borderWidth = shade ? reach / count : reach * (index + 1) / count;
            if (shade) {
                ring.opacity = GFLockRimCoverage(GFLockRimProfileShade, (index + 0.5) / count);
            } else {
                CGFloat target = GFHorizontalRimCoverage(shoulder, (index + 0.5) / count);
                CGFloat underneath = index + 1 < count ?
                    GFHorizontalRimCoverage(shoulder, (index + 1.5) / count) : 0.0;
                ring.opacity = MAX(0.0, MIN(1.0,
                    (target - underneath) / MAX(0.0001, 1.0 - underneath)));
            }
            ring.contentsScale = scale;
            ring.cornerRadius = MAX(0.0, radius - inset);
            ring.cornerCurve = kCACornerCurveContinuous;
            index++;
        }
    }
    [CATransaction commit];
}
@end

#endif
