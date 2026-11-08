#ifndef GF_NOTIFICATION_FOREGROUND_H
#define GF_NOTIFICATION_FOREGROUND_H

#import "GFNotificationPalette.h"
#import "GFHomeScreenPalette.h"

static id GFLockObject(id object, NSString *name);
static id GFLockIvar(id object, const char *name);
static BOOL GFLockIsKind(id object, const char *name);
static UIResponder *GFLockCoverSheetOwner(UIView *host);

static NSUInteger GFNotificationWallpaperGeneration = 1;
static BOOL GFNotificationUpdatingForeground = NO;
static BOOL GFNotificationReportedUnavailable = NO;

static void GFNotificationInvalidateWallpaper(void) {
    GFNotificationWallpaperGeneration++;
}

static BOOL GFNotificationReadColor(id value, UITraitCollection *traits, double rgba[4]) {
    if (![value isKindOfClass:UIColor.class]) return NO;
    UIColor *color = [(UIColor *)value resolvedColorWithTraitCollection:traits];
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        if (![color getWhite:&r alpha:&a]) return NO;
        g = b = r;
    }
    rgba[0] = r; rgba[1] = g; rgba[2] = b; rgba[3] = a;
    return YES;
}

// Only known vibrancy attached to a managed text view is replaced.
// Other filters and ancestors (including icons and remote content) stay intact.
static BOOL GFNotificationIsVibrancy(id filter) {
    NSString *name = [filter isKindOfClass:NSString.class] ? filter :
                     GFLockObject(filter, @"name");
    return [name isKindOfClass:NSString.class] &&
        ([name isEqualToString:@"vibrantLight"] || [name isEqualToString:@"vibrantDark"]);
}

@interface GFNotificationTextState : NSObject
@property (nonatomic, weak) UIView *view;
@property (nonatomic, strong) UIColor *nativeColor;
@property (nonatomic, strong) UIColor *appliedColor;
@property (nonatomic, copy) NSAttributedString *nativeAttributedText;
@property (nonatomic, copy) NSAttributedString *appliedAttributedText;
@property (nonatomic, strong) id nativeCompositingFilter;
@property (nonatomic, copy) NSArray *nativeFilters;
@property (nonatomic, copy) NSArray *appliedFilters;
@property (nonatomic, assign) BOOL changedCompositing;
@property (nonatomic, assign) BOOL changedFilters;
- (void)applyColor:(UIColor *)color;
- (void)restore;
@end

@implementation GFNotificationTextState
- (void)applyColor:(UIColor *)color {
    id text = self.view;
    if (![text isKindOfClass:UILabel.class] && ![text isKindOfClass:UITextView.class]) return;
    UIColor *current = [text textColor];
    if (!self.appliedColor || ![current isEqual:self.appliedColor]) self.nativeColor = current;
    NSAttributedString *attributed = [text attributedText];
    if (!self.appliedAttributedText ||
        ![attributed isEqualToAttributedString:self.appliedAttributedText]) {
        self.nativeAttributedText = attributed;
    }
    if (self.nativeAttributedText.length) {
        NSMutableAttributedString *replacement = [self.nativeAttributedText mutableCopy];
        [replacement addAttribute:NSForegroundColorAttributeName value:color
                            range:NSMakeRange(0, replacement.length)];
        if (![attributed isEqualToAttributedString:replacement]) [text setAttributedText:replacement];
        self.appliedAttributedText = replacement;
    } else {
        self.appliedAttributedText = nil;
    }
    if (![[text textColor] isEqual:color]) [text setTextColor:color];
    self.appliedColor = color;
    CALayer *layer = self.view.layer;
    if (GFNotificationIsVibrancy(layer.compositingFilter)) {
        self.nativeCompositingFilter = layer.compositingFilter;
        self.changedCompositing = YES;
        layer.compositingFilter = nil;
    }
    if (layer.filters.count &&
        (!self.changedFilters || ![layer.filters isEqual:self.appliedFilters])) {
        NSMutableArray *remaining = [NSMutableArray array];
        BOOL changed = NO;
        for (id filter in layer.filters) {
            if (GFNotificationIsVibrancy(filter)) changed = YES;
            else [remaining addObject:filter];
        }
        if (changed) {
            self.nativeFilters = layer.filters;
            self.appliedFilters = remaining;
            self.changedFilters = YES;
            layer.filters = remaining;
        }
    }
}
- (void)restore {
    id text = self.view;
    if (!text) return;
    BOOL restoreColor = [[text textColor] isEqual:self.appliedColor];
    BOOL restoreAttributed = self.appliedAttributedText &&
        [[text attributedText] isEqualToAttributedString:self.appliedAttributedText];
    if (restoreColor && self.nativeColor)
        [text setTextColor:self.nativeColor];
    if (restoreAttributed) [text setAttributedText:self.nativeAttributedText];
    CALayer *layer = self.view.layer;
    if (self.changedCompositing && !layer.compositingFilter)
        layer.compositingFilter = self.nativeCompositingFilter;
    if (self.changedFilters && [layer.filters isEqual:self.appliedFilters])
        layer.filters = self.nativeFilters;
    self.appliedColor = nil;
    self.appliedAttributedText = nil;
    self.changedCompositing = NO;
    self.changedFilters = NO;
}
@end

@interface GFNotificationForegroundState : NSObject
@property (nonatomic, weak) UIView *host;
@property (nonatomic, weak) id wallpaperProvider;
@property (nonatomic, assign) NSUInteger generation;
@property (nonatomic, assign) GFNotificationPalette palette;
@property (nonatomic, strong) NSMutableDictionary<NSValue *, GFNotificationTextState *> *texts;
@property (nonatomic, assign) NSInteger loggedMode;
@property (nonatomic, assign) BOOL loggedTextCount;
@property (nonatomic, assign) NSUInteger previousTextCount;
- (GFNotificationPalette)paletteForHost:(UIView *)host;
- (GFNotificationPalette)paletteForHomeBannerHost:(UIView *)host;
- (NSUInteger)applyToHost:(UIView *)host content:(UIView *)content;
- (void)restore;
@end

@implementation GFNotificationForegroundState
- (instancetype)init {
    self = [super init];
    if (self) {
        _texts = [NSMutableDictionary dictionary];
        _loggedMode = -1;
    }
    return self;
}
- (GFNotificationPalette)paletteForHomeBannerHost:(UIView *)host {
    self.host = host;
    // A reused platter returning to lock screen must re-read its own provider.
    self.generation = 0;
    self.wallpaperProvider = nil;
    self.palette = GFHomeWallpaperPalette(host.traitCollection);
    return self.palette;
}
- (GFNotificationPalette)paletteForHost:(UIView *)host {
    id cover = GFLockCoverSheetOwner(host);
    id provider = GFLockObject(cover, @"wallpaperColorProvider");
    if (self.host == host && self.generation == GFNotificationWallpaperGeneration &&
        self.wallpaperProvider == provider && self.palette.valid) return self.palette;
    self.host = host;
    self.wallpaperProvider = provider;
    self.generation = GFNotificationWallpaperGeneration;
    id average = GFLockObject(provider, @"averageColorForCurrentWallpaper");
    if (![average isKindOfClass:UIColor.class])
        average = GFLockObject(cover, @"_averageLockScreenWallpaperColor");
    double rgba[4];
    GFNotificationPalette result = {0};
    NSString *input = @"unavailable";
    if (GFNotificationReadColor(average, host.traitCollection, rgba)) {
        result = GFNotificationPaletteForWallpaper(rgba[0], rgba[1], rgba[2], rgba[3],
                                                   self.palette.valid, self.palette.lightSurface);
        if (result.valid) input = @"wallpaper-average";
    }
    if (!result.valid) {
        id settings = GFLockObject(cover, @"legibilitySettings");
        if (!settings)
            settings = GFLockObject(GFLockObject(cover, @"legibilityProvider"),
                                    @"currentLegibilitySettings");
        if (GFNotificationReadColor(GFLockObject(settings, @"primaryColor"),
                                    host.traitCollection, rgba) && rgba[3] >= 0.95) {
            GFNotificationPalette foreground = GFNotificationPaletteForWallpaper(
                rgba[0], rgba[1], rgba[2], rgba[3], false, false);
            if (foreground.valid) {
                result = GFNotificationPaletteForAppearance(foreground.luminance < 0.18);
                input = @"system-legibility";
            }
        }
    }
    NSInteger mode = result.valid ? (result.lightSurface ? 1 : 0) : 2;
    if (self.loggedMode != mode && (mode != 2 || !GFNotificationReportedUnavailable)) {
        // No notification content, application identity, or sampled image is logged.
        NSLog(@"[GlassFolders WhiteBG3] input=%@ mode=%@", input,
              mode == 1 ? @"light" : (mode == 0 ? @"dark" : @"native"));
        self.loggedMode = mode;
        if (mode == 2) GFNotificationReportedUnavailable = YES;
    }
    self.palette = result;
    return result;
}
- (void)addText:(id)candidate secondary:(BOOL)secondary root:(UIView *)root
           seen:(NSMutableSet<NSValue *> *)seen {
    if (![candidate isKindOfClass:UILabel.class] &&
        ![candidate isKindOfClass:UITextView.class]) return;
    UIView *view = candidate;
    if (![view isDescendantOfView:root]) return;
    NSValue *key = [NSValue valueWithNonretainedObject:view];
    if ([seen containsObject:key]) return;
    [seen addObject:key];
    GFNotificationTextState *state = self.texts[key];
    if (state.view != view) {
        [state restore];
        state = [GFNotificationTextState new];
        state.view = view;
        self.texts[key] = state;
    }
    CGFloat white = secondary ? self.palette.secondaryWhite : self.palette.primaryWhite;
    [state applyColor:[UIColor colorWithWhite:white alpha:1.0]];
}
- (NSUInteger)applyToHost:(UIView *)host content:(UIView *)content {
    if (!self.palette.valid || GFNotificationUpdatingForeground) return 0;
    GFNotificationUpdatingForeground = YES;
    NSMutableSet<NSValue *> *seen = [NSMutableSet set];
    // These are the actual text slots in NCNotificationContentView and
    // NCNotificationSeamlessContentView, not a generic UILabel tree rewrite.
    for (NSString *name in @[@"_primaryLabel", @"_primarySubtitleLabel", @"_secondaryLabel",
                             @"_secondaryTextView", @"_summaryLabel", @"_primaryTextLabel",
                             @"_primarySubtitleTextLabel", @"_secondaryTextElement",
                             @"_summaryTextLabel", @"_importantTextLabel"]) {
        id text = GFLockIvar(content, name.UTF8String);
        [self addText:text secondary:NO root:host seen:seen];
    }
    for (NSString *name in @[@"_dateLabel", @"_footerTextLabel"]) {
        [self addText:GFLockIvar(content, name.UTF8String) secondary:YES root:host seen:seen];
    }
    id header = GFLockObject(host, @"_headerContentView");
    if (!header) header = GFLockIvar(host, "_headerContentView");
    if ([header isKindOfClass:UIView.class] &&
        [(UIView *)header isDescendantOfView:host]) {
        [self addText:GFLockIvar(header, "_titleLabel") secondary:NO root:host seen:seen];
        [self addText:GFLockIvar(header, "_dateLabel") secondary:YES root:host seen:seen];
    }
    for (NSValue *key in [self.texts.allKeys copy]) {
        if (![seen containsObject:key]) {
            [self.texts[key] restore];
            [self.texts removeObjectForKey:key];
        }
    }
    GFNotificationUpdatingForeground = NO;
    if (!self.loggedTextCount || self.previousTextCount != seen.count) {
        NSLog(@"[GlassFolders WhiteBG3] text-slots=%lu", (unsigned long)seen.count);
        self.previousTextCount = seen.count;
        self.loggedTextCount = YES;
    }
    return seen.count;
}
- (void)restore {
    BOOL previous = GFNotificationUpdatingForeground;
    GFNotificationUpdatingForeground = YES;
    for (GFNotificationTextState *state in self.texts.allValues) [state restore];
    [self.texts removeAllObjects];
    GFNotificationUpdatingForeground = previous;
}
- (void)dealloc { [self restore]; }
@end

static BOOL GFNotificationHasVoidMethod(Class cls, SEL selector, BOOL objectArgument) {
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    char result[8] = {0}, argument[8] = {0};
    if (!method || method_getNumberOfArguments(method) != (objectArgument ? 3u : 2u)) return NO;
    method_getReturnType(method, result, sizeof(result));
    if (objectArgument) method_getArgumentType(method, 2, argument, sizeof(argument));
    return result[0] == 'v' && (!objectArgument || argument[0] == '@');
}
#endif
