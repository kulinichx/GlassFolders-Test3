// Included after GFAppLibraryRecipe and the appearance/filter helpers.
#ifndef GF_APP_LIBRARY_GLASS_H
#define GF_APP_LIBRARY_GLASS_H

#import "GFGlassRim.h"

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
@property (nonatomic, strong) GFLockRimView *gfCardRim;
@property (nonatomic, assign) CGFloat gfStrength;
@property (nonatomic, assign) CGFloat gfPreferredRadius;
@property (nonatomic, assign) BOOL gfSearchVariant;
@property (nonatomic, assign) BOOL gfHasMaterial;
@property (nonatomic, assign) BOOL gfMaterialDark;
@property (nonatomic, assign) NSInteger gfMaterialStyle;
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
        _gfBodyVeil.startPoint = CGPointMake(0.3, 0.0);
        _gfBodyVeil.endPoint = CGPointMake(0.7, 1.0);
        _gfBodyVeil.locations = @[@0.0, @0.36, @0.72, @1.0];
        _gfBodyVeil.zPosition = 19.0;
        [self.layer addSublayer:_gfBodyVeil];

        // Use the exact accepted lock11 contour and coverage. The legacy
        // class name is retained so existing lock-screen paths stay intact.
        _gfCardRim = [[GFLockRimView alloc] initWithFrame:CGRectZero];
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
    NSInteger style = GFResolvedAppLibraryStyle();
    // Pod hooks run on layout. Reuse filters and layers until their material
    // changes, including updates while App Library is already on screen.
    if (self.gfHasMaterial && self.gfMaterialDark == dark && self.gfMaterialStyle == style) return;
    self.gfHasMaterial = YES;
    self.gfMaterialDark = dark;
    self.gfMaterialStyle = style;
    GFAppLibraryMaterialRecipe recipe = GFAppLibraryRecipe(self.gfSearchVariant, dark);
    CALayer *backdrop = self.gfBackdropSampleView.layer;
    BOOL hasBlur = NO;
    if ([NSStringFromClass(backdrop.class) containsString:@"Backdrop"]) {
        SEL group = NSSelectorFromString(@"setGroupName:");
        if ([backdrop respondsToSelector:group])
            ((void (*)(id, SEL, id))objc_msgSend)(backdrop, group,
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
    CGFloat density = recipe.veilStrength;
    self.gfBodyVeil.colors = @[
        (id)[UIColor colorWithWhite:1.0 alpha:0.018 * density].CGColor,
        (id)[UIColor colorWithWhite:0.0 alpha:0.008 * density].CGColor,
        (id)[UIColor colorWithWhite:0.0 alpha:0.012 * density].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.006 * density].CGColor
    ];
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
    self.gfCardRim.frame = self.bounds;
    self.gfCardRim.gfRadius = radius;
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
