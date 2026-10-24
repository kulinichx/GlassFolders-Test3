// Included after GFAppLibraryRecipe and the appearance/filter helpers.
#ifndef GF_APP_LIBRARY_GLASS_H
#define GF_APP_LIBRARY_GLASS_H

#import "GFHorizontalGlassRim.h"

@interface GFAppLibraryBackdropView : UIView
@end
@implementation GFAppLibraryBackdropView
+ (Class)layerClass {
    Class backdrop = NSClassFromString(@"CABackdropLayer");
    return [backdrop isSubclassOfClass:CALayer.class] ? backdrop : CALayer.class;
}
@end

@interface GFAppLibraryGlassView : UIView
@property (nonatomic, strong) GFAppLibraryBackdropView *gfBackdropSampleView;
@property (nonatomic, strong) UIVisualEffectView *gfFallbackBlurView;
@property (nonatomic, strong) CAGradientLayer *gfBodyVeil;
// Broad, low-contrast perimeter density -- not a bright outline.
@property (nonatomic, strong) CAGradientLayer *gfVolumeFalloff;
@property (nonatomic, strong) GFHorizontalGlassRimView *gfCardRim;
@property (nonatomic, assign) CGFloat gfStrength;
@property (nonatomic, assign) CGFloat gfPreferredRadius;
@property (nonatomic, assign) BOOL gfSearchVariant;
@property (nonatomic, assign) BOOL gfDockVariant;
@property (nonatomic, assign) BOOL gfHasMaterial;
@property (nonatomic, assign) BOOL gfMaterialDark;
@property (nonatomic, assign) NSInteger gfMaterialStyle;
@property (nonatomic, assign) BOOL gfMaterialSearchVariant;
@property (nonatomic, assign) BOOL gfMaterialDockVariant;
@property (nonatomic, assign) BOOL gfMaterialAppleLiquid;
- (instancetype)initWithStrength:(CGFloat)strength;
- (void)setPreferredRadius:(CGFloat)radius;
- (void)gfRefreshMaterial;
@end

@implementation GFAppLibraryGlassView
- (instancetype)initWithStrength:(CGFloat)strength {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _gfStrength = GFClamp01(strength);
        self.userInteractionEnabled = NO;
        self.backgroundColor = UIColor.clearColor;
        self.clipsToBounds = YES;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.allowsEdgeAntialiasing = YES;

        // Filter a larger, unclipped sample and clip once at the card edge.
        // Clipping the backdrop itself can clamp blur at the curved corners.
        _gfBackdropSampleView = [[GFAppLibraryBackdropView alloc] initWithFrame:CGRectZero];
        _gfBackdropSampleView.userInteractionEnabled = NO;
        _gfBackdropSampleView.backgroundColor = UIColor.clearColor;
        _gfBackdropSampleView.clipsToBounds = NO;
        _gfBackdropSampleView.layer.masksToBounds = NO;
        [self addSubview:_gfBackdropSampleView];

        _gfBodyVeil = [CAGradientLayer layer];
        _gfBodyVeil.startPoint = CGPointMake(0.5, 0.0);
        _gfBodyVeil.endPoint = CGPointMake(0.5, 1.0);
        _gfBodyVeil.zPosition = 19.0;
        [self.layer addSublayer:_gfBodyVeil];

        _gfVolumeFalloff = [CAGradientLayer layer];
        _gfVolumeFalloff.type = kCAGradientLayerRadial;
        _gfVolumeFalloff.startPoint = CGPointMake(0.5, 0.5);
        _gfVolumeFalloff.endPoint = CGPointMake(1.0, 1.0);
        _gfVolumeFalloff.locations = @[@0.0, @0.58, @0.86, @1.0];
        _gfVolumeFalloff.zPosition = 20.0;
        _gfVolumeFalloff.hidden = YES;
        [self.layer addSublayer:_gfVolumeFalloff];

        // App Library gets a restrained horizontal bevel; the lock-screen rim
        // continues using its accepted lighting and widths unchanged.
        _gfCardRim = [[GFHorizontalGlassRimView alloc] initWithFrame:CGRectZero];
        [self addSubview:_gfCardRim];
        [self gfRefreshMaterial];
    }
    return self;
}

- (void)setPreferredRadius:(CGFloat)radius {
    CGFloat safe = MAX(0.0, radius);
    if (fabs(safe - _gfPreferredRadius) > 0.01) {
        _gfPreferredRadius = safe;
        [self setNeedsLayout];
    }
}

- (void)gfRefreshMaterial {
    BOOL dark = GFUsesDarkAppearance(self);
    NSInteger style = self.gfDockVariant ? 1 : GFResolvedAppLibraryStyle();
    BOOL appleLiquid = GFAppleLiquidMaterialEnabled;
    // Pod hooks run on layout. Reuse filters and layers until their material
    // changes, including updates while App Library is already on screen.
    if (self.gfHasMaterial && self.gfMaterialDark == dark && self.gfMaterialStyle == style &&
        self.gfMaterialSearchVariant == self.gfSearchVariant &&
        self.gfMaterialDockVariant == self.gfDockVariant &&
        self.gfMaterialAppleLiquid == appleLiquid) return;
    self.gfHasMaterial = YES;
    self.gfMaterialDark = dark;
    self.gfMaterialStyle = style;
    self.gfMaterialSearchVariant = self.gfSearchVariant;
    self.gfMaterialDockVariant = self.gfDockVariant;
    self.gfMaterialAppleLiquid = appleLiquid;
    GFAppLibraryMaterialRecipe recipe = self.gfDockVariant ?
        (GFAppLibraryMaterialRecipe){10.0, 1.04, 1.0} : GFAppLibraryRecipe(self.gfSearchVariant, dark);
    if (appleLiquid) {
        // iOS-27-inspired transmission: preserve wallpaper chroma and
        // visible content instead of adding an opaque tint or fine glint.
        // These are visual approximations, NOT Apple's refraction shader.
        recipe = self.gfSearchVariant ?
            (GFAppLibraryMaterialRecipe){8.5, 1.32, 1.0} :
            self.gfDockVariant ?
            (GFAppLibraryMaterialRecipe){12.0, 1.28, 1.0} :
            (GFAppLibraryMaterialRecipe){11.0, 1.30, 1.0};
    }
    CALayer *backdrop = self.gfBackdropSampleView.layer;
    BOOL hasBlur = NO;
    if ([NSStringFromClass(backdrop.class) containsString:@"Backdrop"]) {
        SEL group = NSSelectorFromString(@"setGroupName:");
        if ([backdrop respondsToSelector:group])
            ((void (*)(id, SEL, id))objc_msgSend)(backdrop, group,
                self.gfDockVariant ? @"com.kulinich.glassfolders.dock.glass" :
                style == 1 ? @"com.kulinich.glassfolders.applibrary.liquid" :
                             @"com.kulinich.glassfolders.applibrary.clear");
        SEL inPlace = NSSelectorFromString(@"setAllowsInPlaceFiltering:");
        if ([backdrop respondsToSelector:inPlace])
            ((void (*)(id, SEL, BOOL))objc_msgSend)(backdrop, inPlace, NO);
        NSMutableArray *filters = [NSMutableArray array];
        id saturation = GFCreateCAFilter(@"colorSaturate");
        if (saturation) {
            [saturation setValue:@(recipe.saturation) forKey:@"inputAmount"];
            [filters addObject:saturation];
        }
        id blur = GFCreateCAFilter(@"gaussianBlur");
        if (blur) {
            [blur setValue:@(recipe.blur) forKey:@"inputRadius"];
            [blur setValue:@YES forKey:@"inputNormalizeEdges"];
            [filters addObject:blur];
            hasBlur = YES;
        }
        // No additive brightness or hard-edge blur clamp.
        [backdrop setValue:filters forKey:@"filters"];
    }
    self.gfBackdropSampleView.hidden = !hasBlur;
    if (!hasBlur) {
        if (!self.gfFallbackBlurView) {
            self.gfFallbackBlurView = [[UIVisualEffectView alloc] initWithEffect:nil];
            self.gfFallbackBlurView.userInteractionEnabled = NO;
            [self insertSubview:self.gfFallbackBlurView aboveSubview:self.gfBackdropSampleView];
        }
        self.gfFallbackBlurView.effect = [UIBlurEffect effectWithStyle:
            style == 1 ? UIBlurEffectStyleSystemUltraThinMaterial : UIBlurEffectStyleSystemThinMaterial];
        self.gfFallbackBlurView.alpha = style == 1 ? 0.22 : 0.28;
    }
    self.gfFallbackBlurView.hidden = hasBlur;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CGFloat density = recipe.veilStrength * (self.gfSearchVariant ? 0.8 : 1.0);
    if (appleLiquid) {
        // The WHOLE capsule/pod is a lens-like volume. A diffuse top-to-bottom
        // luminosity shift and soft peripheral density replace extra borders.
        // Body colors remain grayscale so wallpaper color passes through.
        CGFloat weight = self.gfSearchVariant ? 0.75 : 1.0;
        self.gfBodyVeil.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:(dark ? 0.15 : 0.105) * weight].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:(dark ? 0.085 : 0.055) * weight].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.018 * weight].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.012 * weight].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:(dark ? 0.055 : 0.08) * weight].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.018 * weight].CGColor
        ];
        self.gfVolumeFalloff.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:0.015].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:(dark ? 0.028 : 0.038)].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:(dark ? 0.075 : 0.10)].CGColor
        ];
    } else {
        self.gfBodyVeil.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:0.012 * density].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.004 * density].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.004 * density].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.008 * density].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.003 * density].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.006 * density].CGColor
        ];
    }
    self.gfVolumeFalloff.hidden = !appleLiquid;
    // Keep the old rim quiet in the experimental look: no added bright rail.
    self.gfCardRim.alpha = appleLiquid ? 0.40 : 1.0;
    [CATransaction commit];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self gfRefreshMaterial];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CGRect sample = CGRectInset(self.bounds, -30.0, -30.0);
    self.gfBackdropSampleView.frame = sample;
    self.gfFallbackBlurView.frame = sample;
    CGFloat limit = MIN(self.bounds.size.width, self.bounds.size.height) * 0.5;
    CGFloat radius = self.gfPreferredRadius;
    if (radius <= 0.0) radius = self.gfSearchVariant ? limit : limit * 0.36;
    radius = MIN(radius, limit);
    self.layer.cornerRadius = radius;
    self.gfBodyVeil.frame = self.bounds;
    self.gfVolumeFalloff.frame = self.bounds;
    CGFloat height = MAX(1.0, CGRectGetHeight(self.bounds));
    CGFloat lip = MIN(0.16, (self.gfSearchVariant ? 8.0 : (self.gfDockVariant ? 12.0 : 18.0)) / height);
    self.gfBodyVeil.locations = @[@0.0, @(lip), @0.40, @0.65, @(1.0 - lip), @1.0];
    self.gfCardRim.frame = self.bounds;
    self.gfCardRim.gfRadius = radius;
    self.gfCardRim.gfSearchVariant = self.gfSearchVariant;
    self.gfCardRim.gfDockVariant = self.gfDockVariant;
    [self.gfCardRim setNeedsLayout];
    [CATransaction commit];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self gfRefreshMaterial];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self gfRefreshMaterial];
}
@end

#endif
