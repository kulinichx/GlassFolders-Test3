// Stable App Library and Dock glass used by the release build.
#ifndef GF_APP_LIBRARY_GLASS_H
#define GF_APP_LIBRARY_GLASS_H

#import "GFHorizontalGlassRim.h"

@interface GFAppLibraryBackdropView : UIView
@end

@implementation GFAppLibraryBackdropView
+ (Class)layerClass {
    Class backdrop = NSClassFromString(@"CABackdropLayer");
    return [backdrop isSubclassOfClass:CALayer.class]
        ? backdrop : CALayer.class;
}
@end

@interface GFAppLibraryGlassView : UIView
@property (nonatomic, strong) GFAppLibraryBackdropView *gfBackdropSampleView;
@property (nonatomic, strong) UIVisualEffectView *gfFallbackBlurView;
@property (nonatomic, strong) CAGradientLayer *gfBodyVeil;
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

        _gfBackdropSampleView =
            [[GFAppLibraryBackdropView alloc] initWithFrame:CGRectZero];
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

        _gfCardRim =
            [[GFHorizontalGlassRimView alloc] initWithFrame:CGRectZero];
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

    if (self.gfHasMaterial &&
        self.gfMaterialDark == dark &&
        self.gfMaterialStyle == style &&
        self.gfMaterialSearchVariant == self.gfSearchVariant &&
        self.gfMaterialDockVariant == self.gfDockVariant) {
        return;
    }

    self.gfHasMaterial = YES;
    self.gfMaterialDark = dark;
    self.gfMaterialStyle = style;
    self.gfMaterialSearchVariant = self.gfSearchVariant;
    self.gfMaterialDockVariant = self.gfDockVariant;

    GFAppLibraryMaterialRecipe recipe = self.gfDockVariant
        ? (GFAppLibraryMaterialRecipe){10.0, 1.04, 1.0}
        : GFAppLibraryRecipe(self.gfSearchVariant, dark);

    CALayer *backdrop = self.gfBackdropSampleView.layer;
    BOOL hasBlur = NO;
    if ([NSStringFromClass(backdrop.class) containsString:@"Backdrop"]) {
        SEL group = NSSelectorFromString(@"setGroupName:");
        if ([backdrop respondsToSelector:group]) {
            ((void (*)(id, SEL, id))objc_msgSend)(
                backdrop, group, self.gfDockVariant
                    ? @"com.kulinich.glassfolders.dock.glass"
                    : (style == 1
                        ? @"com.kulinich.glassfolders.applibrary.liquid"
                        : @"com.kulinich.glassfolders.applibrary.clear")
            );
        }

        SEL inPlace = NSSelectorFromString(@"setAllowsInPlaceFiltering:");
        if ([backdrop respondsToSelector:inPlace]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(backdrop, inPlace, NO);
        }

        NSMutableArray *filters = [NSMutableArray array];
        id saturation = GFCreateCAFilter(@"colorSaturate");
        if (saturation) {
            [saturation setValue:@(recipe.saturation) forKey:@"inputAmount"];
            [filters addObject:saturation];
        }

        id blur = GFCreateCAFilter(@"gaussianBlur");
        if (blur && recipe.blur > 0.001) {
            [blur setValue:@(recipe.blur) forKey:@"inputRadius"];
            [blur setValue:@YES forKey:@"inputNormalizeEdges"];
            [filters addObject:blur];
            hasBlur = YES;
        }
        [backdrop setValue:filters forKey:@"filters"];
    }

    self.gfBackdropSampleView.hidden = !hasBlur;
    if (!hasBlur) {
        if (!self.gfFallbackBlurView) {
            self.gfFallbackBlurView =
                [[UIVisualEffectView alloc] initWithEffect:nil];
            self.gfFallbackBlurView.userInteractionEnabled = NO;
            [self insertSubview:self.gfFallbackBlurView
                   aboveSubview:self.gfBackdropSampleView];
        }
        self.gfFallbackBlurView.effect = [UIBlurEffect effectWithStyle:
            style == 1
                ? UIBlurEffectStyleSystemUltraThinMaterial
                : UIBlurEffectStyleSystemThinMaterial];
        self.gfFallbackBlurView.alpha =
            self.gfDockVariant ? 0.22 : (style == 1 ? 0.22 : 0.28);
    }
    self.gfFallbackBlurView.hidden = hasBlur;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CGFloat density = recipe.veilStrength *
        (self.gfSearchVariant ? 0.8 : 1.0);
    self.gfBodyVeil.colors = @[
        (id)[UIColor colorWithWhite:1.0 alpha:0.012 * density].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.004 * density].CGColor,
        (id)[UIColor colorWithWhite:0.0 alpha:0.004 * density].CGColor,
        (id)[UIColor colorWithWhite:0.0 alpha:0.008 * density].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.003 * density].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.006 * density].CGColor
    ];
    self.gfCardRim.alpha = 1.0;
    [CATransaction commit];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self gfRefreshMaterial];

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CGRect sample = CGRectInset(self.bounds, -30.0, -30.0);
    if (!CGRectEqualToRect(self.gfBackdropSampleView.frame, sample)) {
        self.gfBackdropSampleView.frame = sample;
    }
    if (!CGRectEqualToRect(self.gfFallbackBlurView.frame, sample)) {
        self.gfFallbackBlurView.frame = sample;
    }

    CGFloat limit =
        MIN(self.bounds.size.width, self.bounds.size.height) * 0.5;
    CGFloat radius = self.gfPreferredRadius;
    if (radius <= 0.0) {
        radius = self.gfSearchVariant ? limit : limit * 0.36;
    }
    radius = MIN(radius, limit);
    if (fabs(self.layer.cornerRadius - radius) > 0.01) {
        self.layer.cornerRadius = radius;
    }

    if (!CGRectEqualToRect(self.gfBodyVeil.frame, self.bounds)) {
        self.gfBodyVeil.frame = self.bounds;
    }
    CGFloat height = MAX(1.0, CGRectGetHeight(self.bounds));
    CGFloat lip = MIN(0.16,
        (self.gfSearchVariant ? 8.0
            : (self.gfDockVariant ? 12.0 : 18.0)) / height);
    self.gfBodyVeil.locations =
        @[@0.0, @(lip), @0.40, @0.65, @(1.0 - lip), @1.0];

    BOOL rimGeometryChanged =
        !CGRectEqualToRect(self.gfCardRim.frame, self.bounds) ||
        fabs(self.gfCardRim.gfRadius - radius) > 0.01 ||
        self.gfCardRim.gfSearchVariant != self.gfSearchVariant ||
        self.gfCardRim.gfDockVariant != self.gfDockVariant;
    if (rimGeometryChanged) {
        self.gfCardRim.frame = self.bounds;
        self.gfCardRim.gfRadius = radius;
        self.gfCardRim.gfSearchVariant = self.gfSearchVariant;
        self.gfCardRim.gfDockVariant = self.gfDockVariant;
        [self.gfCardRim setNeedsLayout];
    }
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
