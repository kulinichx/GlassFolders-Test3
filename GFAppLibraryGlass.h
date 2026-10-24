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
// Dock-only secondary live sample, clipped to a soft optical boundary band.
// Unlike a painted border, it retains the real wallpaper hue at the perimeter.
@property (nonatomic, strong) UIView *gfDockLensEdgeHost;
@property (nonatomic, strong) GFAppLibraryBackdropView *gfDockLensEdgeBackdrop;
@property (nonatomic, strong) CAShapeLayer *gfDockLensEdgeMask;
@property (nonatomic, strong) UIVisualEffectView *gfFallbackBlurView;
@property (nonatomic, strong) CAGradientLayer *gfBodyVeil;
// Broad, low-contrast perimeter density -- not a bright outline.
@property (nonatomic, strong) CAGradientLayer *gfVolumeFalloff;
// A broad, low-energy reflected glow, not another hairline highlight.
@property (nonatomic, strong) CAGradientLayer *gfDockLensSheen;
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
@property (nonatomic, assign) BOOL gfMaterialDockLens;
@property (nonatomic, assign) BOOL gfMaterialLibraryLens;
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

        _gfDockLensSheen = [CAGradientLayer layer];
        _gfDockLensSheen.startPoint = CGPointMake(0.5, 0.0);
        _gfDockLensSheen.endPoint = CGPointMake(0.5, 1.0);
        _gfDockLensSheen.locations = @[@0.0, @0.11, @0.35, @0.70, @1.0];
        _gfDockLensSheen.zPosition = 20.5;
        _gfDockLensSheen.hidden = YES;
        [self.layer addSublayer:_gfDockLensSheen];

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
    BOOL dockLens = self.gfDockVariant && GFDockLensMaterialEnabled;
    // App Library has its own high-transmission recipe. It takes precedence
    // over the old volume experiment ONLY for pods and the search capsule.
    BOOL libraryLens = !self.gfDockVariant && GFAppLibraryLensMaterialEnabled;
    BOOL appleLiquid = GFAppleLiquidMaterialEnabled && !dockLens && !libraryLens;
    // Pod hooks run on layout. Reuse filters and layers until their material
    // changes, including updates while App Library is already on screen.
    if (self.gfHasMaterial && self.gfMaterialDark == dark && self.gfMaterialStyle == style &&
        self.gfMaterialSearchVariant == self.gfSearchVariant &&
        self.gfMaterialDockVariant == self.gfDockVariant &&
        self.gfMaterialAppleLiquid == appleLiquid &&
        self.gfMaterialDockLens == dockLens &&
        self.gfMaterialLibraryLens == libraryLens) return;
    self.gfHasMaterial = YES;
    self.gfMaterialDark = dark;
    self.gfMaterialStyle = style;
    self.gfMaterialSearchVariant = self.gfSearchVariant;
    self.gfMaterialDockVariant = self.gfDockVariant;
    self.gfMaterialAppleLiquid = appleLiquid;
    self.gfMaterialDockLens = dockLens;
    self.gfMaterialLibraryLens = libraryLens;
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
    if (libraryLens) {
        // Pods are already seen through SpringBoard's blurred library page;
        // additional 11pt blur and high-opacity veils make a muddy card.
        // Use one existing live sample per surface, with no second edge layer.
        recipe = self.gfSearchVariant ?
            (GFAppLibraryMaterialRecipe){2.0, 1.10, 1.0} :
            (GFAppLibraryMaterialRecipe){3.0, 1.12, 1.0};
    }
    if (dockLens) {
        // 12pt blur in the earlier prototype obscured the wallpaper. A small
        // live blur preserves texture and chroma; the boundary has its own
        // clearer sample. This is optical approximation, not pixel warping.
        recipe = (GFAppLibraryMaterialRecipe){4.0, 1.13, 1.0};
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
    // A second CABackdrop sample only for the Dock perimeter. Separate groups
    // avoid reusing the body filter across two different blur radii.
    BOOL edgeActive = NO;
    if (dockLens && !self.gfDockLensEdgeHost) {
        // Allocate the second backdrop ONLY for an enabled Dock experiment,
        // never for each App Library category or the regular Dock.
        UIView *host = [[UIView alloc] initWithFrame:self.bounds];
        host.userInteractionEnabled = NO;
        host.backgroundColor = UIColor.clearColor;
        // Blend the clearer perimeter sample gently into the main material;
        // full-opacity sampling would expose a sharp inner ring boundary.
        host.alpha = 0.52;
        GFAppLibraryBackdropView *edge = [[GFAppLibraryBackdropView alloc]
            initWithFrame:CGRectZero];
        edge.userInteractionEnabled = NO;
        edge.backgroundColor = UIColor.clearColor;
        [host addSubview:edge];
        CAShapeLayer *mask = [CAShapeLayer layer];
        mask.fillColor = UIColor.whiteColor.CGColor;
        mask.fillRule = kCAFillRuleEvenOdd;
        host.layer.mask = mask;
        self.gfDockLensEdgeHost = host;
        self.gfDockLensEdgeBackdrop = edge;
        self.gfDockLensEdgeMask = mask;
        // Backdrop must remain under all tint, sheen, and icon content.
        [self insertSubview:host aboveSubview:self.gfBackdropSampleView];
        [self setNeedsLayout];
    }
    CALayer *edgeLayer = self.gfDockLensEdgeBackdrop.layer;
    if (dockLens && hasBlur &&
        [NSStringFromClass(edgeLayer.class) containsString:@"Backdrop"]) {
        SEL group = NSSelectorFromString(@"setGroupName:");
        if ([edgeLayer respondsToSelector:group])
            ((void (*)(id, SEL, id))objc_msgSend)(edgeLayer, group,
                @"com.kulinich.glassfolders.dock.lens.edge");
        SEL inPlace = NSSelectorFromString(@"setAllowsInPlaceFiltering:");
        if ([edgeLayer respondsToSelector:inPlace])
            ((void (*)(id, SEL, BOOL))objc_msgSend)(edgeLayer, inPlace, NO);
        NSMutableArray *edgeFilters = [NSMutableArray array];
        id saturate = GFCreateCAFilter(@"colorSaturate");
        if (saturate) {
            [saturate setValue:@1.12 forKey:@"inputAmount"];
            [edgeFilters addObject:saturate];
        }
        id edgeBlur = GFCreateCAFilter(@"gaussianBlur");
        if (edgeBlur) {
            [edgeBlur setValue:@1.15 forKey:@"inputRadius"];
            [edgeBlur setValue:@YES forKey:@"inputNormalizeEdges"];
            [edgeFilters addObject:edgeBlur];
            edgeActive = YES;
        }
        if (edgeActive) [edgeLayer setValue:edgeFilters forKey:@"filters"];
    }
    self.gfDockLensEdgeHost.hidden = !edgeActive;
    if (!hasBlur) {
        if (!self.gfFallbackBlurView) {
            self.gfFallbackBlurView = [[UIVisualEffectView alloc] initWithEffect:nil];
            self.gfFallbackBlurView.userInteractionEnabled = NO;
            [self insertSubview:self.gfFallbackBlurView aboveSubview:self.gfBackdropSampleView];
        }
        self.gfFallbackBlurView.effect = [UIBlurEffect effectWithStyle:
            style == 1 ? UIBlurEffectStyleSystemUltraThinMaterial : UIBlurEffectStyleSystemThinMaterial];
        self.gfFallbackBlurView.alpha = (dockLens || libraryLens) ? 0.12 :
            (style == 1 ? 0.22 : 0.28);
    }
    self.gfFallbackBlurView.hidden = hasBlur;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CGFloat density = recipe.veilStrength * (self.gfSearchVariant ? 0.8 : 1.0);
    if (libraryLens) {
        // Unlike the old iOS 27 volume test, this does not add a dense gray
        // layer. Color and existing wallpaper detail should stay visible.
        // The broad, quiet top reflection comes from the material volume,
        // not from an extra hard highlight line.
        self.gfBodyVeil.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:0.035].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.014].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.002].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.002].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.018].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.008].CGColor
        ];
        self.gfVolumeFalloff.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:0.003].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.000].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.008].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.023].CGColor
        ];
        self.gfDockLensSheen.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:0.055].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.024].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.004].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor
        ];
    } else if (dockLens) {
        // High transmission is the base. Keep the center close to untouched
        // backdrop; a broad sheen follows the curvature without a white rail.
        self.gfBodyVeil.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:0.033].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.013].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.003].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.002].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.022].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.006].CGColor
        ];
        self.gfVolumeFalloff.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:0.005].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.000].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.010].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.030].CGColor
        ];
        self.gfDockLensSheen.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:0.080].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.037].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.008].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor
        ];
    } else if (appleLiquid) {
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
    self.gfVolumeFalloff.hidden = !(appleLiquid || dockLens || libraryLens);
    self.gfDockLensSheen.hidden = !(dockLens || libraryLens);
    // Quiet down the old bevel for pods/search without affecting the Dock.
    self.gfCardRim.alpha = libraryLens ? 0.28 :
        (dockLens ? 0.62 : (appleLiquid ? 0.40 : 1.0));
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
    self.gfDockLensEdgeHost.frame = self.bounds;
    self.gfDockLensEdgeBackdrop.frame = sample;
    CGFloat limit = MIN(self.bounds.size.width, self.bounds.size.height) * 0.5;
    CGFloat radius = self.gfPreferredRadius;
    if (radius <= 0.0) radius = self.gfSearchVariant ? limit : limit * 0.36;
    radius = MIN(radius, limit);
    self.layer.cornerRadius = radius;
    self.gfBodyVeil.frame = self.bounds;
    self.gfVolumeFalloff.frame = self.bounds;
    self.gfDockLensSheen.frame = self.bounds;
    // Even-odd cutout creates a translucent optical boundary, NOT an opaque
    // painted line. Small and bounded to avoid obscuring Dock icons.
    if (self.gfMaterialDockLens && self.bounds.size.width > 0.0 &&
        self.bounds.size.height > 0.0) {
        CGFloat band = MIN(4.5, self.bounds.size.height * 0.08);
        CGRect inset = CGRectInset(self.bounds, band, band);
        UIBezierPath *ring = [UIBezierPath bezierPathWithRoundedRect:self.bounds
            cornerRadius:radius];
        [ring appendPath:[UIBezierPath bezierPathWithRoundedRect:inset
            cornerRadius:MAX(0.0, radius - band)]];
        self.gfDockLensEdgeMask.frame = self.bounds;
        self.gfDockLensEdgeMask.path = ring.CGPath;
    }
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
