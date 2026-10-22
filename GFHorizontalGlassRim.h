// Horizontal edge lighting for App Library and Dock, separate from lock screen.
#ifndef GF_HORIZONTAL_GLASS_RIM_H
#define GF_HORIZONTAL_GLASS_RIM_H

#import "GFGlassRim.h"

static CGFloat GFHorizontalRimCoverage(BOOL shoulder, CGFloat t) {
    // A compact bright core followed by a smooth inward tail. The wider,
    // lower-peak shoulder gives the edge depth without a second white line.
    if (shoulder) return 0.48 * (1.0 - GFLockRimSmoothstep(t));
    return 1.0 - GFLockRimSmoothstep((t - 0.16) / 0.84);
}

static CAGradientLayer *GFHorizontalRimBand(CGFloat peak, BOOL shade) {
    NSMutableArray *colors = [NSMutableArray arrayWithCapacity:8];
    // Slightly different top/bottom strengths avoid a stamped outline.
    for (NSNumber *weight in @[@1.0, @0.92, @0.48, @0.035,
                                @0.035, @0.44, @0.86, @0.94]) {
        [colors addObject:(id)[UIColor colorWithWhite:shade ? 0.0 : 1.0
            alpha:peak * weight.doubleValue].CGColor];
    }
    return GFLockRimBand(colors);
}

@interface GFHorizontalGlassRimView : UIView
@property (nonatomic, strong) CAGradientLayer *gfReflection;
@property (nonatomic, strong) CAGradientLayer *gfShoulder;
@property (nonatomic, strong) CAGradientLayer *gfInnerShade;
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
        self.gfReflection = GFHorizontalRimBand(0.52, NO);
        self.gfShoulder = GFHorizontalRimBand(0.22, NO);
        self.gfInnerShade = GFHorizontalRimBand(0.14, YES);
        [self.layer addSublayer:self.gfInnerShade];
        [self.layer addSublayer:self.gfShoulder];
        [self.layer addSublayer:self.gfReflection];
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
    NSArray *locations = @[@0.0, @(cap * 0.18), @(cap * 0.56), @(cap),
                           @(1.0 - cap), @(1.0 - cap * 0.56),
                           @(1.0 - cap * 0.18), @1.0];
    CGFloat scale = self.window.screen.scale ?: UIScreen.mainScreen.scale;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (CAGradientLayer *band in @[self.gfInnerShade, self.gfShoulder, self.gfReflection]) {
        BOOL shade = band == self.gfInnerShade;
        BOOL shoulder = band == self.gfShoulder;
        // Search pills are shallow, so their bevel is narrower than a pod's.
        CGFloat reach = shade ? (self.gfSearchVariant ? 1.8 : 2.4) :
            (shoulder ? (self.gfSearchVariant ? 2.6 : (self.gfDockVariant ? 3.2 : 3.6)) :
                        (self.gfSearchVariant ? 1.8 : (self.gfDockVariant ? 2.2 : 2.4)));
        NSUInteger count = MAX((NSUInteger)1, (NSUInteger)ceil(reach * scale));
        reach = count / scale;
        band.frame = self.bounds;
        band.startPoint = CGPointMake(0.5, 0.0);
        band.endPoint = CGPointMake(0.5, 1.0);
        band.locations = locations;
        band.opacity = self.gfDockVariant && !shade ? 0.90 : 1.0;
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
