// Shared card-edge renderer. Keep the lock11 coverage and geometry identical
// for lock-screen cards, banners, and App Library surfaces.
#ifndef GF_GLASS_RIM_H
#define GF_GLASS_RIM_H

// The lock-screen rim is separate from the folder's wide optical texture.
// Each band uses the same Core Animation corner curve as the clipping layer:
// a narrow reflection, a faint inward shoulder, and a shallow inner shade.
// These are local source-over layers, not additive backdrop filters.
static CAGradientLayer *GFLockRimBand(NSArray *colors) {
    CAGradientLayer *band = [CAGradientLayer layer];
    band.startPoint = CGPointMake(0.12, 0.0);
    band.endPoint = CGPointMake(0.88, 1.0);
    // More stops ease the falloff into the quiet side and back into the
    // secondary reflection. There is no bright segment with a cut-off end.
    band.locations = @[@0.0, @0.12, @0.28, @0.46, @0.62, @0.78, @0.92, @1.0];
    band.colors = colors;
    band.contentsScale = UIScreen.mainScreen.scale;
    CALayer *mask = [CALayer layer];
    mask.backgroundColor = UIColor.clearColor.CGColor;
    mask.contentsScale = UIScreen.mainScreen.scale;
    // Fixed layers are reused on layout. Card reflections/shoulders overlap
    // on a shared outer curve; no bitmap generation or animation timer.
    for (NSNumber *opacity in @[@1.0, @0.80, @0.46, @0.18, @0.035]) {
        CALayer *ring = [CALayer layer];
        ring.borderColor = UIColor.whiteColor.CGColor;
        ring.opacity = opacity.floatValue;
        ring.contentsScale = UIScreen.mainScreen.scale;
        ring.allowsEdgeAntialiasing = YES;
        [mask addSublayer:ring];
    }
    band.mask = mask;
    return band;
}

typedef NS_ENUM(NSUInteger, GFLockRimProfile) {
    GFLockRimProfileLegacy,
    GFLockRimProfileShoulder,
    GFLockRimProfileShade,
};

static CGFloat GFLockRimSmoothstep(CGFloat t) {
    t = MAX(0.0, MIN(1.0, t));
    return t * t * (3.0 - 2.0 * t);
}

static CGFloat GFLockRimCoverage(GFLockRimProfile profile, CGFloat t) {
    if (profile == GFLockRimProfileShoulder)
        return 0.55 * (1.0 - GFLockRimSmoothstep(t));
    // The inner shade must start transparent too. A hard, fully opaque start
    // at an inset draws a second contour even when its inward tail is soft.
    CGFloat rise = GFLockRimSmoothstep(t / 0.30);
    CGFloat fall = 1.0 - GFLockRimSmoothstep((t - 0.30) / 0.70);
    return 0.14 * rise * fall;
}

static CGFloat GFLockRimSampleCoverage(GFLockRimProfile profile, NSUInteger index, NSUInteger count) {
    if (index >= count) return 0.0;
    if (profile == GFLockRimProfileLegacy) {
        const CGFloat coverage[] = {1.0, 0.80, 0.46, 0.18, 0.035};
        return coverage[MIN(index, (NSUInteger)4)];
    }
    return GFLockRimCoverage(profile, (index + 0.5) / count);
}

// For a decreasing profile, cumulative borders reconstruct the same coverage
// without abutting separately antialiased subpixel rings. Every border shares
// the native outer continuous curve; only its inward reach varies. Compensate
// source-over alpha so overlapping layers do not brighten the reflection.
static CGFloat GFLockRimCumulativeOpacity(GFLockRimProfile profile, NSUInteger index, NSUInteger count) {
    CGFloat target = GFLockRimSampleCoverage(profile, index, count);
    CGFloat underneath = GFLockRimSampleCoverage(profile, index + 1, count);
    return MAX(0.0, MIN(1.0, (target - underneath) / MAX(0.0001, 1.0 - underneath)));
}

@interface GFLockRimView : UIView
@property (nonatomic, strong) CAGradientLayer *gfReflection;
@property (nonatomic, strong) CAGradientLayer *gfShoulder;
@property (nonatomic, strong) CAGradientLayer *gfInnerShade;
@property (nonatomic, assign) CGFloat gfRadius;
@property (nonatomic, assign) BOOL gfCircular;
@property (nonatomic, assign) BOOL gfSubdued;
@end
@implementation GFLockRimView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = UIColor.clearColor;
        self.layer.zPosition = 21.0;
        self.gfShoulder = GFLockRimBand(@[
            (id)[UIColor colorWithWhite:1.0 alpha:0.16].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.15].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.085].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.024].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.008].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.04].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.092].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.10].CGColor
        ]);
        self.gfInnerShade = GFLockRimBand(@[
            (id)[UIColor colorWithWhite:0.0 alpha:0.025].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.022].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.014].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.012].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.032].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.075].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.112].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.12].CGColor
        ]);
        self.gfReflection = GFLockRimBand(@[
            (id)[UIColor colorWithWhite:1.0 alpha:0.42].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.39].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.24].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.065].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.015].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.10].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.29].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.32].CGColor
        ]);
        [self.layer addSublayer:self.gfInnerShade];
        [self.layer addSublayer:self.gfShoulder];
        [self.layer addSublayer:self.gfReflection];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    // Keep a substantial, compact reflection like the existing folder rim.
    // Thickness belongs at the edge, not in a broad inward gray/white halo.
    // Rear strips need an identifiable rim even after native stack fading.
    self.gfShoulder.opacity = self.gfSubdued ? 0.30 : 1.0;
    self.gfReflection.opacity = self.gfSubdued ? 0.78 : 1.0;
    self.gfInnerShade.opacity = self.gfSubdued ? 0.90 : 1.0;
    for (CAGradientLayer *band in @[self.gfInnerShade, self.gfShoulder, self.gfReflection]) {
        // A collapsed stack reveals mostly bottom strips. A diagonal light
        // leaves their middle almost invisible; distribute the restrained
        // reflection along the lower edge, without brightening the body.
        band.startPoint = self.gfSubdued ? CGPointMake(0.5, 0.0) : CGPointMake(0.12, 0.0);
        band.endPoint = self.gfSubdued ? CGPointMake(0.5, 1.0) : CGPointMake(0.88, 1.0);
        GFLockRimProfile profile = GFLockRimProfileLegacy;
        if (!self.gfCircular && band == self.gfShoulder) profile = GFLockRimProfileShoulder;
        if (!self.gfCircular && band == self.gfInnerShade) profile = GFLockRimProfileShade;
        CGFloat inset = (band == self.gfInnerShade) ? (self.gfCircular ? 1.2 : 0.25) : 0.0;
        // Widen the compact reflection only. Preserve lock9's clean inward
        // shoulder/shade; rear strips use a smaller increase to stay distinct.
        CGFloat reflectionWidth = self.gfCircular ? 0.8 : (self.gfSubdued ? 1.4 : 1.6);
        CGFloat width = band == self.gfShoulder ? (self.gfCircular ? 1.6 : 2.4) :
                        (band == self.gfReflection ? reflectionWidth :
                         (self.gfCircular ? 1.2 : 1.6));
        CGFloat scale = self.window.screen.scale ?: UIScreen.mainScreen.scale;
        NSUInteger count = 5;
        if (profile != GFLockRimProfileLegacy) {
            // Sample the smooth profile at display-pixel intervals, instead
            // of broad, visibly stepped bands. The reflection has a thicker
            // core with the existing soft tail; circular controls stay intact.
            count = MAX((NSUInteger)1, (NSUInteger)ceil(width * scale));
            width = count / scale;
            inset = round(inset * scale) / scale;
        }
        CGRect rect = CGRectInset(self.bounds, inset, inset);
        rect.size.width = MAX(0.0, rect.size.width);
        rect.size.height = MAX(0.0, rect.size.height);
        band.frame = rect;
        band.contentsScale = scale;
        band.mask.frame = (CGRect){CGPointZero, rect.size};
        band.mask.contentsScale = scale;
        while (band.mask.sublayers.count > count) [band.mask.sublayers.lastObject removeFromSuperlayer];
        while (band.mask.sublayers.count < count) {
            CALayer *ring = [CALayer layer];
            ring.borderColor = UIColor.whiteColor.CGColor;
            ring.allowsEdgeAntialiasing = YES;
            [band.mask addSublayer:ring];
        }
        // Keep circular controls and the very faint non-monotonic shade on
        // their existing recipe. The two bright card bands need no adjacent
        // contours: gaps between those contours were visible at the corners.
        BOOL cumulative = !self.gfCircular && band != self.gfInnerShade;
        NSUInteger index = 0;
        for (CALayer *ring in band.mask.sublayers) {
            CGFloat featherInset = cumulative ? 0.0 : width * index / count;
            CGRect ringRect = CGRectInset((CGRect){CGPointZero, rect.size}, featherInset, featherInset);
            ringRect.size.width = MAX(0.0, ringRect.size.width);
            ringRect.size.height = MAX(0.0, ringRect.size.height);
            ring.frame = ringRect;
            ring.contentsScale = scale;
            ring.opacity = cumulative ? GFLockRimCumulativeOpacity(profile, index, count) :
                GFLockRimSampleCoverage(profile, index, count);
            ring.borderWidth = cumulative ? width * (index + 1) / count : width / count;
            ring.cornerRadius = MAX(0.0, self.gfRadius - inset - featherInset);
            ring.cornerCurve = self.gfCircular ? kCACornerCurveCircular : kCACornerCurveContinuous;
            index++;
        }
    }
    [CATransaction commit];
}
@end

#endif
