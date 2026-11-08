// Actual production library renderer with view/filter doubles and QuartzCore.
// This verifies recipe/cache/scope behavior, not SpringBoard compositing.
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <math.h>

@interface UITraitCollection : NSObject
@end
@implementation UITraitCollection
@end
@interface UIColor : NSObject
@property (strong) NSColor *color;
+ (instancetype)colorWithWhite:(CGFloat)white alpha:(CGFloat)alpha;
+ (instancetype)whiteColor;
+ (instancetype)clearColor;
- (CGColorRef)CGColor;
- (UIColor *)resolvedColorWithTraitCollection:(UITraitCollection *)traits;
- (BOOL)getRed:(CGFloat *)r green:(CGFloat *)g blue:(CGFloat *)b alpha:(CGFloat *)a;
- (BOOL)getWhite:(CGFloat *)w alpha:(CGFloat *)a;
@end
@implementation UIColor
+ (instancetype)colorWithWhite:(CGFloat)white alpha:(CGFloat)alpha {
    UIColor *value = [self new];
    value.color = [NSColor colorWithSRGBRed:white green:white blue:white alpha:alpha];
    return value;
}
+ (instancetype)whiteColor { return [self colorWithWhite:1 alpha:1]; }
+ (instancetype)clearColor { return [self colorWithWhite:0 alpha:0]; }
- (CGColorRef)CGColor { return self.color.CGColor; }
- (UIColor *)resolvedColorWithTraitCollection:(UITraitCollection *)traits { return self; }
- (BOOL)getRed:(CGFloat *)r green:(CGFloat *)g blue:(CGFloat *)b alpha:(CGFloat *)a {
    [self.color getRed:r green:g blue:b alpha:a]; return YES;
}
- (BOOL)getWhite:(CGFloat *)w alpha:(CGFloat *)a {
    *w = self.color.redComponent; *a = self.color.alphaComponent; return YES;
}
@end

@interface UIScreen : NSObject
@property CGFloat scale;
+ (instancetype)mainScreen;
@end
@implementation UIScreen
+ (instancetype)mainScreen {
    static UIScreen *screen;
    if (!screen) { screen = [self new]; screen.scale = 3; }
    return screen;
}
@end
@interface TestWindow : NSObject
@property (strong) UIScreen *screen;
@end
@implementation TestWindow
@end

@interface TestBackdropLayer : CALayer
@property (copy) NSArray *testFilters;
@property NSUInteger assignments;
@property (copy) NSString *groupName;
@property BOOL allowsInPlaceFiltering;
@end
@implementation TestBackdropLayer
- (void)setValue:(id)value forKey:(NSString *)key {
    if ([key isEqualToString:@"filters"]) {
        self.testFilters = value; self.assignments++;
    } else [super setValue:value forKey:key];
}
@end

@interface UIView : NSObject
@property CGRect frame;
@property CGRect bounds;
@property BOOL hidden;
@property BOOL userInteractionEnabled;
@property BOOL clipsToBounds;
@property CGFloat alpha;
@property (strong) UIColor *backgroundColor;
@property (strong) CALayer *layer;
@property (strong) TestWindow *window;
@property (strong) UITraitCollection *traitCollection;
+ (Class)layerClass;
- (instancetype)initWithFrame:(CGRect)frame;
- (void)addSubview:(UIView *)view;
- (void)insertSubview:(UIView *)view aboveSubview:(UIView *)other;
- (void)setNeedsLayout;
- (void)layoutSubviews;
- (void)didMoveToWindow;
- (void)traitCollectionDidChange:(UITraitCollection *)previous;
@end
@implementation UIView
+ (Class)layerClass { return TestBackdropLayer.class; }
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super init];
    if (self) {
        _frame = frame; _bounds = (CGRect){CGPointZero, frame.size};
        _layer = [[[self.class layerClass] alloc] init];
        _traitCollection = [UITraitCollection new];
    }
    return self;
}
- (void)addSubview:(UIView *)view { [self.layer addSublayer:view.layer]; }
- (void)insertSubview:(UIView *)view aboveSubview:(UIView *)other { [self addSubview:view]; }
- (void)setNeedsLayout {}
- (void)layoutSubviews {}
- (void)didMoveToWindow {}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {}
@end

typedef NS_ENUM(NSInteger, UIBlurEffectStyle) {
    UIBlurEffectStyleSystemUltraThinMaterial,
    UIBlurEffectStyleSystemThinMaterial,
};
@interface UIBlurEffect : NSObject
+ (instancetype)effectWithStyle:(UIBlurEffectStyle)style;
@end
@implementation UIBlurEffect
+ (instancetype)effectWithStyle:(UIBlurEffectStyle)style { return [self new]; }
@end
@interface UIVisualEffectView : UIView
@property (strong) UIBlurEffect *effect;
- (instancetype)initWithEffect:(UIBlurEffect *)effect;
@end
@implementation UIVisualEffectView
- (instancetype)initWithEffect:(UIBlurEffect *)effect {
    self = [super initWithFrame:CGRectZero]; if (self) self.effect = effect; return self;
}
@end

@interface SBWallpaperController : NSObject
@property (strong) UIColor *homeColor;
@property NSUInteger reads;
+ (instancetype)sharedInstance;
- (id)averageColorForVariant:(NSInteger)variant;
@end
@implementation SBWallpaperController
+ (instancetype)sharedInstance {
    static SBWallpaperController *controller;
    if (!controller) controller = [self new];
    return controller;
}
- (id)averageColorForVariant:(NSInteger)variant {
    NSCAssert(variant == 1, @"Home variant required");
    self.reads++; return self.homeColor;
}
@end

@interface TestFilter : NSObject
@property (copy) NSString *name;
@property (strong) NSNumber *inputAmount;
@property (strong) NSNumber *inputRadius;
@property (strong) NSNumber *inputNormalizeEdges;
@end
@implementation TestFilter
@end
static id GFCreateCAFilter(NSString *name) {
    TestFilter *filter = [TestFilter new]; filter.name = name; return filter;
}
static BOOL TestDarkAppearance = YES;
static BOOL TestReduceTransparency = NO;
static BOOL GFUsesDarkAppearance(UIView *view) { return TestDarkAppearance; }
static BOOL UIAccessibilityIsReduceTransparencyEnabled(void) { return TestReduceTransparency; }
static BOOL UIAccessibilityDarkerSystemColorsEnabled(void) { return NO; }
static CGFloat GFClamp01(CGFloat value) { return MAX(0, MIN(1, value)); }
static NSInteger TestStyle = 1;
static NSInteger GFResolvedAppLibraryStyle(void) { return TestStyle; }
typedef struct { CGFloat blur, saturation, veilStrength; } GFAppLibraryMaterialRecipe;
static GFAppLibraryMaterialRecipe GFAppLibraryRecipe(BOOL search, BOOL dark) {
    return (GFAppLibraryMaterialRecipe){TestStyle == 1 ? 8.0 : 10.0, 1.04, 1.0};
}

#import "../GFAppLibraryGlass.h"

static CGFloat BlurRadius(GFAppLibraryGlassView *view) {
    TestBackdropLayer *layer = (TestBackdropLayer *)view.gfBackdropSampleView.layer;
    for (TestFilter *filter in layer.testFilters)
        if ([filter.name isEqualToString:@"gaussianBlur"]) return filter.inputRadius.doubleValue;
    return -1;
}
static Class TestBackdropClass(id object, SEL selector) { return TestBackdropLayer.class; }
#define CHECK(x) do { if (!(x)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #x); return 1; \
} } while (0)

int main(void) {
    @autoreleasepool {
        // Replace only the platform-specific layer factory with a recorder.
        Method factory = class_getClassMethod(GFAppLibraryBackdropView.class, @selector(layerClass));
        method_setImplementation(factory, (IMP)TestBackdropClass);
        SBWallpaperController *provider = [SBWallpaperController sharedInstance];
        provider.homeColor = UIColor.whiteColor;
        GFHomeInvalidateWallpaper();
        GFAppLibraryGlassView *pod = [[GFAppLibraryGlassView alloc] initWithStrength:1];
        CHECK(pod.gfMaterialAdaptiveLight);
        CHECK(BlurRadius(pod) == 3);
        CHECK(pod.gfCardRim.hidden && !pod.gfAdaptiveRim.hidden);
        pod.bounds = CGRectMake(0, 0, 160, 180);
        [pod setPreferredRadius:28];
        [pod layoutSubviews];
        CHECK(pod.gfAdaptiveRim.gfRadius == 28);
        CHECK(CGRectEqualToRect(pod.gfAdaptiveRim.frame, pod.bounds));
        TestBackdropLayer *layer = (TestBackdropLayer *)pod.gfBackdropSampleView.layer;
        NSArray *filters = layer.testFilters;
        NSUInteger writes = layer.assignments;
        for (NSUInteger i = 0; i < 100; i++) [pod layoutSubviews];
        CHECK(layer.testFilters == filters && layer.assignments == writes);
        CHECK(provider.reads == 1);
        pod.gfSearchVariant = YES;
        [pod gfRefreshMaterial];
        CHECK(pod.gfMaterialAdaptiveLight && BlurRadius(pod) == 3);
        TestStyle = 0;
        [pod gfRefreshMaterial];
        CHECK(BlurRadius(pod) == 4);
        provider.homeColor = [UIColor colorWithWhite:0 alpha:1];
        GFHomeInvalidateWallpaper();
        [pod gfRefreshMaterial];
        CHECK(!pod.gfMaterialAdaptiveLight && BlurRadius(pod) == 10);
        CHECK(!pod.gfCardRim.hidden && pod.gfAdaptiveRim.hidden);
        provider.homeColor = UIColor.whiteColor;
        GFHomeInvalidateWallpaper();
        [pod gfRefreshMaterial];
        CHECK(pod.gfMaterialAdaptiveLight);
        TestReduceTransparency = YES;
        [pod gfRefreshMaterial];
        CHECK(!pod.gfMaterialAdaptiveLight);
        TestReduceTransparency = NO;
        [pod gfRefreshMaterial];
        CHECK(pod.gfMaterialAdaptiveLight);
        pod.gfDockVariant = YES;
        [pod gfRefreshMaterial];
        CHECK(!pod.gfMaterialAdaptiveLight && BlurRadius(pod) == 10);
        CHECK(pod.gfAdaptiveRim.hidden);
        CHECK([layer.groupName isEqualToString:@"com.kulinich.glassfolders.dock.glass"]);
        puts("Production library renderer: light wallpaper in dark UI, pod/search, "
             "100 stable layouts, style changes, wallpaper invalidation, "
             "accessibility and Dock scope PASS");
    }
    return 0;
}
