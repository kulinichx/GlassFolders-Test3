// Runs the production foreground state against small Foundation test doubles.
// This verifies lifecycle behavior, not UIKit rendering or private API presence.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <math.h>

typedef double CGFloat;
NSString * const NSForegroundColorAttributeName = @"ForegroundColor";

@interface UITraitCollection : NSObject
@end
@implementation UITraitCollection
@end

@interface UIColor : NSObject
@property double white;
@property double alpha;
+ (instancetype)colorWithWhite:(CGFloat)white alpha:(CGFloat)alpha;
- (UIColor *)resolvedColorWithTraitCollection:(UITraitCollection *)traits;
- (BOOL)getRed:(CGFloat *)r green:(CGFloat *)g blue:(CGFloat *)b alpha:(CGFloat *)a;
- (BOOL)getWhite:(CGFloat *)w alpha:(CGFloat *)a;
@end
@implementation UIColor
+ (instancetype)colorWithWhite:(CGFloat)white alpha:(CGFloat)alpha {
    UIColor *color = [self new]; color.white = white; color.alpha = alpha; return color;
}
- (UIColor *)resolvedColorWithTraitCollection:(UITraitCollection *)traits { return self; }
- (BOOL)getRed:(CGFloat *)r green:(CGFloat *)g blue:(CGFloat *)b alpha:(CGFloat *)a {
    *r = *g = *b = self.white; *a = self.alpha; return YES;
}
- (BOOL)getWhite:(CGFloat *)w alpha:(CGFloat *)a { *w = self.white; *a = self.alpha; return YES; }
- (BOOL)isEqual:(id)other {
    return [other isKindOfClass:UIColor.class] &&
        self.white == [(UIColor *)other white] && self.alpha == [(UIColor *)other alpha];
}
@end

@interface CALayer : NSObject
@property (strong) id compositingFilter;
@property (copy) NSArray *filters;
@end
@implementation CALayer
@end

@interface UIView : NSObject
@property (strong) CALayer *layer;
@property (weak) UIView *superview;
@property (strong) UITraitCollection *traitCollection;
- (BOOL)isDescendantOfView:(UIView *)view;
@end
@implementation UIView
- (instancetype)init {
    self = [super init];
    if (self) { _layer = [CALayer new]; _traitCollection = [UITraitCollection new]; }
    return self;
}
- (BOOL)isDescendantOfView:(UIView *)view {
    for (UIView *node = self; node; node = node.superview) if (node == view) return YES;
    return NO;
}
@end
typedef UIView UIResponder;

@interface UILabel : UIView
@property (strong) UIColor *textColor;
@property (copy) NSAttributedString *attributedText;
@end
@implementation UILabel
@end
@interface UITextView : UILabel
@end
@implementation UITextView
@end

@interface TestContent : UIView {
@public
    UILabel *_primaryTextLabel;
    UILabel *_dateLabel;
    UILabel *_secondaryTextElement;
}
@end
@implementation TestContent
@end

@interface TestHeader : UIView {
@public
    UILabel *_titleLabel;
    UILabel *_dateLabel;
}
@end
@implementation TestHeader
@end
@interface TestHost : UIView {
@public
    TestHeader *_headerContentView;
}
@end
@implementation TestHost
@end

@interface TestProvider : NSObject
@property (strong) UIColor *color;
@property NSUInteger reads;
- (UIColor *)averageColorForCurrentWallpaper;
@end
@implementation TestProvider
- (UIColor *)averageColorForCurrentWallpaper { self.reads++; return self.color; }
@end

@interface TestCover : UIView
@property (strong) TestProvider *wallpaperColorProvider;
@end
@implementation TestCover
@end

@interface UIApplication : NSObject
+ (instancetype)sharedApplication;
@property BOOL showingHome;
- (BOOL)isShowingHomescreen;
@end
@implementation UIApplication
+ (instancetype)sharedApplication {
    static UIApplication *application;
    if (!application) application = [self new];
    return application;
}
- (BOOL)isShowingHomescreen { return self.showingHome; }
@end

@interface TestLegibility : NSObject
@property (strong) UIColor *primaryColor;
@end
@implementation TestLegibility
@end
@interface SBWallpaperController : NSObject
+ (instancetype)sharedInstance;
@property (strong) UIColor *homeColor;
@property (strong) TestLegibility *settings;
@property NSUInteger homeReads;
@property NSInteger lastVariant;
- (UIColor *)averageColorForVariant:(NSInteger)variant;
- (TestLegibility *)legibilitySettingsForVariant:(NSInteger)variant;
@end
@implementation SBWallpaperController
+ (instancetype)sharedInstance {
    static SBWallpaperController *controller;
    if (!controller) controller = [self new];
    return controller;
}
- (UIColor *)averageColorForVariant:(NSInteger)variant {
    self.homeReads++;
    self.lastVariant = variant;
    return self.homeColor;
}
- (TestLegibility *)legibilitySettingsForVariant:(NSInteger)variant {
    self.lastVariant = variant;
    return self.settings;
}
@end

@interface WrongVariantProvider : NSObject
- (UIColor *)averageColorForVariant:(id)variant;
@end
@implementation WrongVariantProvider
- (UIColor *)averageColorForVariant:(id)variant {
    @throw [NSException exceptionWithName:@"MustNotCall" reason:@"Wrong ABI" userInfo:nil];
}
@end

#import "../GFNotificationForeground.h"

@interface BSUIDefaultDateLabel : UILabel
@end
@implementation BSUIDefaultDateLabel
- (void)setTextColor:(UIColor *)color {
    GFNotificationTextState *state = objc_getAssociatedObject(self, &kGFNotificationManagedTextKey);
    UIColor *resolved = GFNotificationManagedDateColor(self, color);
    BOOL applying = state.applyingColor;
    state.applyingColor = YES;
    [super setTextColor:resolved];
    state.applyingColor = applying;
}
- (void)setAttributedText:(NSAttributedString *)text {
    GFNotificationTextState *state = objc_getAssociatedObject(self, &kGFNotificationManagedTextKey);
    NSAttributedString *resolved = GFNotificationManagedDateText(self, text);
    BOOL applying = state.applyingColor;
    state.applyingColor = YES;
    [super setAttributedText:resolved];
    state.applyingColor = applying;
}
@end

static id GFLockObject(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    Method method = object ? class_getInstanceMethod(object_getClass(object), selector) : NULL;
    char type[8] = {0};
    if (method) method_getReturnType(method, type, sizeof(type));
    if (!method || method_getNumberOfArguments(method) != 2 || type[0] != '@') return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}
static id GFLockIvar(id object, const char *name) {
    Ivar ivar = object ? class_getInstanceVariable(object_getClass(object), name) : NULL;
    return ivar && ivar_getTypeEncoding(ivar)[0] == '@' ? object_getIvar(object, ivar) : nil;
}
static BOOL GFLockIsKind(id object, const char *name) {
    Class cls = objc_getClass(name); return cls && [object isKindOfClass:cls];
}
static UIResponder *GFLockCoverSheetOwner(UIView *host) {
    for (UIView *node = host; node; node = node.superview)
        if ([node isKindOfClass:TestCover.class]) return node;
    return nil;
}

#define CHECK(x) do { if (!(x)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #x); return 1; \
} } while (0)

int main(void) {
    @autoreleasepool {
        UIColor *white = [UIColor colorWithWhite:1 alpha:1];
        UIColor *black = [UIColor colorWithWhite:0 alpha:1];
        UIColor *native = [UIColor colorWithWhite:.8 alpha:.9];
        UILabel *label = [UILabel new];
        label.textColor = native;
        label.attributedText = [[NSAttributedString alloc] initWithString:@"Title"
            attributes:@{NSForegroundColorAttributeName: native, @"Font": @"original"}];
        label.layer.compositingFilter = @"vibrantLight";
        label.layer.filters = @[@"vibrantDark", @"keep-this-filter"];
        NSAttributedString *original = label.attributedText;
        GFNotificationTextState *state = [GFNotificationTextState new];
        state.view = label;
        [state applyColor:black];
        CHECK([label.textColor isEqual:black]);
        CHECK(!label.layer.compositingFilter);
        CHECK([label.layer.filters isEqual:@[@"keep-this-filter"]]);
        CHECK([[label.attributedText attribute:@"Font" atIndex:0 effectiveRange:NULL] isEqual:@"original"]);
        [state applyColor:black];
        [state applyColor:white];
        [state restore];
        CHECK([label.textColor isEqual:native]);
        CHECK([label.attributedText isEqualToAttributedString:original]);
        CHECK([label.layer.compositingFilter isEqual:@"vibrantLight"]);
        CHECK([label.layer.filters isEqual:(@[@"vibrantDark", @"keep-this-filter"])]);

        [state applyColor:black];
        UIColor *newNative = [UIColor colorWithWhite:.6 alpha:1];
        label.textColor = newNative;
        label.attributedText = [[NSAttributedString alloc] initWithString:@"New content"
            attributes:@{NSForegroundColorAttributeName: newNative}];
        [state applyColor:white];
        [state restore];
        CHECK([label.textColor isEqual:newNative]);
        CHECK([label.attributedText.string isEqual:@"New content"]);
        CHECK([[label.attributedText attribute:NSForegroundColorAttributeName
            atIndex:0 effectiveRange:NULL] isEqual:newNative]);
        [state applyColor:black];
        label.textColor = newNative;
        label.attributedText = [[NSAttributedString alloc] initWithString:@"Native after disable"];
        [state restore];
        CHECK([label.textColor isEqual:newNative]);
        CHECK([label.attributedText.string isEqual:@"Native after disable"]);

        TestCover *cover = [TestCover new];
        TestProvider *provider = [TestProvider new];
        cover.wallpaperColorProvider = provider;
        provider.color = white;
        TestHost *host = [TestHost new]; host.superview = cover;
        TestContent *content = [TestContent new]; content.superview = host;
        content->_primaryTextLabel = [UILabel new];
        content->_primaryTextLabel.superview = content;
        content->_primaryTextLabel.textColor = white;
        content->_dateLabel = [BSUIDefaultDateLabel new];
        content->_dateLabel.superview = content;
        content->_dateLabel.textColor = native;
        UILabel *unmanaged = [UILabel new]; unmanaged.superview = content;
        unmanaged.textColor = white;
        GFNotificationForegroundState *foreground = [GFNotificationForegroundState new];
        CHECK([foreground paletteForHost:host].lightSurface);
        CHECK([foreground applyToHost:host content:content] == 2);
        CHECK(content->_primaryTextLabel.textColor.white < .1);
        CHECK(content->_dateLabel.textColor.white == content->_primaryTextLabel.textColor.white);
        for (NSUInteger i = 0; i < 100; i++) {
            content->_dateLabel.textColor = white;
            content->_dateLabel.attributedText = [[NSAttributedString alloc]
                initWithString:[NSString stringWithFormat:@"%lum ago", (unsigned long)i]
                attributes:@{NSForegroundColorAttributeName:white, @"Font":@"native-date-font"}];
            CHECK(content->_dateLabel.textColor.white == content->_primaryTextLabel.textColor.white);
            CHECK([[content->_dateLabel.attributedText attribute:NSForegroundColorAttributeName
                atIndex:0 effectiveRange:NULL] white] == content->_primaryTextLabel.textColor.white);
            CHECK([[content->_dateLabel.attributedText attribute:@"Font"
                atIndex:0 effectiveRange:NULL] isEqual:@"native-date-font"]);
        }
        CHECK([unmanaged.textColor isEqual:white]);
        for (NSUInteger i = 0; i < 100; i++) [foreground paletteForHost:host];
        CHECK(provider.reads == 1);
        provider.color = black;
        GFNotificationInvalidateWallpaper();
        CHECK(![foreground paletteForHost:host].lightSurface);
        CHECK(provider.reads == 2);
        [foreground applyToHost:host content:content];
        CHECK(content->_primaryTextLabel.textColor.white > .95);
        [foreground restore];
        CHECK([content->_primaryTextLabel.textColor isEqual:white]);
        CHECK([content->_dateLabel.textColor isEqual:white]);
        content->_dateLabel.textColor = native;
        // Header dates and seamless dates can be restyled without host layout.
        provider.color = white;
        GFNotificationInvalidateWallpaper();
        [foreground paletteForHost:host];
        host->_headerContentView = [TestHeader new];
        host->_headerContentView.superview = host;
        UILabel *headerDate = [UILabel new];
        headerDate.superview = host->_headerContentView;
        headerDate.textColor = white;
        host->_headerContentView->_dateLabel = headerDate;
        CHECK([foreground applyToHost:host content:content] == 3);
        CHECK(headerDate.textColor.white < .4);
        headerDate.textColor = white;
        headerDate.attributedText = [[NSAttributedString alloc] initWithString:@"2m ago"
            attributes:@{NSForegroundColorAttributeName:white, @"Font":@"date-font"}];
        headerDate.layer.compositingFilter = @"vibrantLight";
        [foreground applyToHost:host content:content];
        CHECK(headerDate.textColor.white < .4);
        CHECK([[headerDate.attributedText attribute:NSForegroundColorAttributeName
            atIndex:0 effectiveRange:NULL] white] < .4);
        CHECK([[headerDate.attributedText attribute:@"Font"
            atIndex:0 effectiveRange:NULL] isEqual:@"date-font"]);
        CHECK(!headerDate.layer.compositingFilter);
        UILabel *replacementDate = [UILabel new];
        replacementDate.superview = host->_headerContentView;
        replacementDate.textColor = native;
        host->_headerContentView->_dateLabel = replacementDate;
        CHECK([foreground applyToHost:host content:content] == 3);
        CHECK([headerDate.textColor isEqual:white]);
        CHECK([headerDate.layer.compositingFilter isEqual:@"vibrantLight"]);
        CHECK(replacementDate.textColor.white < .4);
        [foreground restore];
        CHECK([replacementDate.textColor isEqual:native]);
        provider.color = nil;
        GFNotificationInvalidateWallpaper();
        CHECK(![foreground paletteForHost:host].valid);
        // Home and lock wallpapers differ; banners must never use lock input.
        SBWallpaperController *home = [SBWallpaperController sharedInstance];
        home.homeColor = black;
        provider.color = white;
        GFHomeInvalidateWallpaper();
        GFNotificationInvalidateWallpaper();
        CHECK([foreground paletteForHost:host].lightSurface);
        CHECK(![foreground paletteForHomeBannerHost:host].lightSurface);
        CHECK(home.lastVariant == 1 && home.homeReads == 1);
        for (NSUInteger i = 0; i < 100; i++)
            [foreground paletteForHomeBannerHost:host];
        CHECK(home.homeReads == 1);
        CHECK([foreground paletteForHost:host].lightSurface);
        home.homeColor = white;
        GFHomeInvalidateWallpaper();
        CHECK([foreground paletteForHomeBannerHost:host].lightSurface);
        CHECK(home.homeReads == 2);
        CHECK(!GFHomeScreenVisible());
        [UIApplication sharedApplication].showingHome = YES;
        CHECK(GFHomeScreenVisible());
        [UIApplication sharedApplication].showingHome = NO;
        CHECK(!GFHomeScreenVisible());
        CHECK(!GFHomeVariantObject([WrongVariantProvider new], @"averageColorForVariant:"));
        home.homeColor = nil;
        home.settings = [TestLegibility new];
        home.settings.primaryColor = black;
        GFHomeInvalidateWallpaper();
        CHECK([foreground paletteForHomeBannerHost:host].lightSurface);
        home.settings.primaryColor = white;
        GFHomeInvalidateWallpaper();
        CHECK(![foreground paletteForHomeBannerHost:host].lightSurface);
        home.settings = nil;
        GFHomeInvalidateWallpaper();
        CHECK(![foreground paletteForHomeBannerHost:host].valid);
        NSUInteger missingReads = home.homeReads;
        for (NSUInteger i = 0; i < 100; i++)
            CHECK(![foreground paletteForHomeBannerHost:host].valid);
        CHECK(home.homeReads == missingReads);
        CHECK(GFNotificationHasVoidMethod(UIView.class, @selector(setLayer:), YES));
        CHECK(!GFNotificationHasVoidMethod(UIView.class, @selector(layer), NO));
        puts("Production foreground state: recolor, attributed runs, filter restoration, "
             "native updates, scoped slots, cache and wallpaper invalidation PASS");
        puts("Production Home Screen input: separate wallpaper variant, cache, visibility, "
             "legibility fallback, invalid input and ABI guard PASS");
    }
    return 0;
}
