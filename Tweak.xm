#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>

static CFStringRef const kB3MPrefsDomain = CFSTR("com.kulinichx.better3dmenus16rh");
static CFStringRef const kB3MNotification = CFSTR("com.kulinichx.better3dmenus16rh/preferences.changed");

static BOOL gB3MHideSeparators = YES;
static BOOL gB3MReduceBlur = YES;
static BOOL gB3MHideShareApp = YES;
static BOOL gB3MHideRemoveApp = YES;
static BOOL gB3MHideSectionGap = NO;
static BOOL gB3MGlassMenuTint = NO;
static BOOL gB3MGlassTextTint = NO;
static CGFloat gB3MBlurFactor = 0.55;
static UIColor *gB3MActiveIconColor = nil;

static char kB3MSeparatorCapturedKey;
static char kB3MSeparatorHiddenKey;
static char kB3MSeparatorAlphaKey;
static char kB3MBlurCapturedKey;
static char kB3MBlurAlphaKey;
static char kB3MTintCapturedKey;
static char kB3MTintColorKey;
static char kB3MTextCapturedKey;
static char kB3MTextColorKey;
static char kB3MGlassOverlayKey;

static BOOL B3MReadBool(CFStringRef key, BOOL fallback)
{
    CFPropertyListRef value = CFPreferencesCopyAppValue(key, kB3MPrefsDomain);
    if (!value) return fallback;

    BOOL result = fallback;
    CFTypeID type = CFGetTypeID(value);

    if (type == CFBooleanGetTypeID()) {
        result = CFBooleanGetValue((CFBooleanRef)value);
    } else if (type == CFNumberGetTypeID()) {
        int number = fallback ? 1 : 0;
        if (CFNumberGetValue((CFNumberRef)value, kCFNumberIntType, &number)) {
            result = (number != 0);
        }
    }

    CFRelease(value);
    return result;
}

static double B3MReadDouble(CFStringRef key, double fallback, double minimum, double maximum)
{
    CFPropertyListRef value = CFPreferencesCopyAppValue(key, kB3MPrefsDomain);
    if (!value) return fallback;

    double result = fallback;
    if (CFGetTypeID(value) == CFNumberGetTypeID()) {
        double number = fallback;
        if (CFNumberGetValue((CFNumberRef)value, kCFNumberDoubleType, &number)) {
            if (number < minimum) number = minimum;
            if (number > maximum) number = maximum;
            result = number;
        }
    }

    CFRelease(value);
    return result;
}

static void B3MLoadPreferences(void)
{
    CFPreferencesAppSynchronize(kB3MPrefsDomain);

    gB3MHideSeparators = B3MReadBool(CFSTR("HideSeparators"), YES);
    gB3MReduceBlur = B3MReadBool(CFSTR("ReduceBlur"), YES);
    gB3MHideShareApp = B3MReadBool(CFSTR("HideShareApp"), YES);
    gB3MHideRemoveApp = B3MReadBool(CFSTR("HideRemoveApp"), YES);
    gB3MHideSectionGap = B3MReadBool(CFSTR("HideSectionGap"), NO);
    gB3MGlassMenuTint = B3MReadBool(CFSTR("GlassMenuTint"), NO);
    gB3MGlassTextTint = B3MReadBool(CFSTR("GlassTextTint"), NO);
    gB3MBlurFactor = (CGFloat)B3MReadDouble(CFSTR("BlurFactor"), 0.55, 0.20, 1.00);
}

static void B3MPreferencesChanged(CFNotificationCenterRef center,
                                  void *observer,
                                  CFStringRef name,
                                  const void *object,
                                  CFDictionaryRef userInfo)
{
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;

    B3MLoadPreferences();
}

static void B3MApplySeparatorState(UIView *view)
{
    if (!view) return;

    NSNumber *captured = objc_getAssociatedObject(view, &kB3MSeparatorCapturedKey);

    if (gB3MHideSeparators) {
        if (![captured boolValue]) {
            objc_setAssociatedObject(view, &kB3MSeparatorHiddenKey, @(view.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(view, &kB3MSeparatorAlphaKey, @(view.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(view, &kB3MSeparatorCapturedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }

        if (!view.hidden) view.hidden = YES;
        if (view.alpha != 0.0) view.alpha = 0.0;
    } else if ([captured boolValue]) {
        NSNumber *oldHidden = objc_getAssociatedObject(view, &kB3MSeparatorHiddenKey);
        NSNumber *oldAlpha = objc_getAssociatedObject(view, &kB3MSeparatorAlphaKey);

        if (oldHidden) view.hidden = oldHidden.boolValue;
        if (oldAlpha) view.alpha = oldAlpha.doubleValue;

        objc_setAssociatedObject(view, &kB3MSeparatorCapturedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, &kB3MSeparatorHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, &kB3MSeparatorAlphaKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static BOOL B3MClassNameLooksLikeBackground(UIView *view)
{
    NSString *name = NSStringFromClass(view.class);
    return [name rangeOfString:@"Background" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static void B3MApplyBlurRecursively(UIView *view, BOOL backgroundAncestor)
{
    if (!view) return;

    BOOL isBackgroundBranch = backgroundAncestor || B3MClassNameLooksLikeBackground(view);

    if ([view isKindOfClass:UIVisualEffectView.class] && isBackgroundBranch) {
        NSNumber *captured = objc_getAssociatedObject(view, &kB3MBlurCapturedKey);

        if (gB3MReduceBlur) {
            if (![captured boolValue]) {
                objc_setAssociatedObject(view, &kB3MBlurAlphaKey, @(view.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(view, &kB3MBlurCapturedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }

            NSNumber *original = objc_getAssociatedObject(view, &kB3MBlurAlphaKey);
            CGFloat originalAlpha = original ? original.doubleValue : 1.0;
            CGFloat wanted = originalAlpha * gB3MBlurFactor;

            if (fabs(view.alpha - wanted) > 0.001) {
                view.alpha = wanted;
            }
        } else if ([captured boolValue]) {
            NSNumber *original = objc_getAssociatedObject(view, &kB3MBlurAlphaKey);
            if (original) view.alpha = original.doubleValue;

            objc_setAssociatedObject(view, &kB3MBlurCapturedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(view, &kB3MBlurAlphaKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }

    for (UIView *subview in view.subviews) {
        B3MApplyBlurRecursively(subview, isBackgroundBranch);
    }
}


static inline CGFloat B3MClamp01(CGFloat value)
{
    return MIN(1.0, MAX(0.0, value));
}

/*
 * GlassFolders-inspired response curves.
 * Tint intentionally rises slower than material/edge response so Light Mode
 * does not become a milky white card.
 */
static inline CGFloat B3MMaterialResponse(CGFloat strength)
{
    return pow(B3MClamp01(strength), 1.10);
}

static inline CGFloat B3MTintResponse(CGFloat strength)
{
    return pow(B3MClamp01(strength), 1.35);
}

static inline CGFloat B3MEdgeResponse(CGFloat strength)
{
    CGFloat s = B3MClamp01(strength);
    return 0.12 * s + 0.88 * pow(s, 1.80);
}

static BOOL B3MUsesDarkAppearance(UIView *view)
{
    if (!view) return NO;

    if (@available(iOS 12.0, *)) {
        return view.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    }

    return NO;
}

static UIColor *B3MFallbackIconColor(void)
{
    return [UIColor colorWithHue:0.58 saturation:0.58 brightness:0.78 alpha:1.0];
}

static UIImage *B3MImageSnapshotFromIconView(UIView *view)
{
    if (!view) return nil;

    BOOL active = NO;

    SEL showingSEL = NSSelectorFromString(@"isShowingContextMenu");
    if ([view respondsToSelector:showingSEL]) {
        BOOL (*msgBool)(id, SEL) = (BOOL (*)(id, SEL))objc_msgSend;
        active = msgBool(view, showingSEL);
    }

    if (!active) {
        SEL activeSEL =
            NSSelectorFromString(@"isContextMenuInteractionActiveOrPending");

        if ([view respondsToSelector:activeSEL]) {
            BOOL (*msgBool)(id, SEL) = (BOOL (*)(id, SEL))objc_msgSend;
            active = msgBool(view, activeSEL);
        }
    }

    if (!active) return nil;

    SEL snapshotSEL = NSSelectorFromString(@"iconImageSnapshot");
    if (![view respondsToSelector:snapshotSEL]) return nil;

    id (*msgObject)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
    id snapshot = msgObject(view, snapshotSEL);

    return [snapshot isKindOfClass:UIImage.class] ? (UIImage *)snapshot : nil;
}

static UIImage *B3MFindActiveIconSnapshotInView(UIView *view)
{
    if (!view) return nil;

    Class iconViewClass = NSClassFromString(@"SBIconView");

    if (iconViewClass && [view isKindOfClass:iconViewClass]) {
        UIImage *snapshot = B3MImageSnapshotFromIconView(view);
        if (snapshot) return snapshot;
    }

    for (UIView *subview in view.subviews) {
        UIImage *snapshot = B3MFindActiveIconSnapshotInView(subview);
        if (snapshot) return snapshot;
    }

    return nil;
}

static UIImage *B3MFindActiveIconSnapshot(void)
{
    UIApplication *application = UIApplication.sharedApplication;
    NSArray<UIWindow *> *windows = application.windows;

    for (UIWindow *window in windows.reverseObjectEnumerator) {
        UIImage *snapshot = B3MFindActiveIconSnapshotInView(window);
        if (snapshot) return snapshot;
    }

    return nil;
}

static UIColor *B3MDominantColorFromImage(UIImage *image)
{
    CGImageRef cgImage = image.CGImage;
    if (!cgImage) return B3MFallbackIconColor();

    const size_t width = 24;
    const size_t height = 24;
    const size_t bytesPerPixel = 4;
    const size_t bytesPerRow = width * bytesPerPixel;

    unsigned char pixels[width * height * bytesPerPixel];
    memset(pixels, 0, sizeof(pixels));

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(
        pixels,
        width,
        height,
        8,
        bytesPerRow,
        colorSpace,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big
    );
    CGColorSpaceRelease(colorSpace);

    if (!context) return B3MFallbackIconColor();

    CGContextSetInterpolationQuality(context, kCGInterpolationMedium);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), cgImage);
    CGContextRelease(context);

    enum { kHueBins = 24 };

    CGFloat weights[kHueBins] = {0};
    CGFloat redSums[kHueBins] = {0};
    CGFloat greenSums[kHueBins] = {0};
    CGFloat blueSums[kHueBins] = {0};

    for (size_t i = 0; i < width * height; i++) {
        unsigned char *p = pixels + i * 4;

        CGFloat r = p[0] / 255.0;
        CGFloat g = p[1] / 255.0;
        CGFloat b = p[2] / 255.0;
        CGFloat a = p[3] / 255.0;

        if (a < 0.18) continue;

        CGFloat maxC = MAX(r, MAX(g, b));
        CGFloat minC = MIN(r, MIN(g, b));
        CGFloat delta = maxC - minC;
        CGFloat brightness = maxC;
        CGFloat saturation = maxC > 0.001 ? delta / maxC : 0.0;

        // Ignore near-neutral and extreme pixels so white icon backgrounds
        // do not wash the extracted app hue toward gray.
        if (saturation < 0.16 || brightness < 0.12 || brightness > 0.97) {
            continue;
        }

        CGFloat hue = 0.0;

        if (delta > 0.0001) {
            if (maxC == r) {
                hue = fmod((g - b) / delta, 6.0);
            } else if (maxC == g) {
                hue = ((b - r) / delta) + 2.0;
            } else {
                hue = ((r - g) / delta) + 4.0;
            }

            hue /= 6.0;
            if (hue < 0.0) hue += 1.0;
        }

        NSInteger bin = (NSInteger)floor(hue * kHueBins) % kHueBins;

        CGFloat middlePreference =
            1.0 - MIN(1.0, fabs(brightness - 0.58) / 0.58);

        CGFloat weight =
            a *
            (0.28 + 0.72 * saturation) *
            (0.72 + 0.28 * middlePreference);

        weights[bin] += weight;
        redSums[bin] += r * weight;
        greenSums[bin] += g * weight;
        blueSums[bin] += b * weight;
    }

    NSInteger bestBin = -1;
    CGFloat bestWeight = 0.0;

    for (NSInteger i = 0; i < kHueBins; i++) {
        if (weights[i] > bestWeight) {
            bestWeight = weights[i];
            bestBin = i;
        }
    }

    if (bestBin < 0 || bestWeight < 0.35) {
        return B3MFallbackIconColor();
    }

    CGFloat r = redSums[bestBin] / bestWeight;
    CGFloat g = greenSums[bestBin] / bestWeight;
    CGFloat b = blueSums[bestBin] / bestWeight;

    UIColor *raw = [UIColor colorWithRed:r green:g blue:b alpha:1.0];

    CGFloat h = 0.0, s = 0.0, v = 0.0, alpha = 0.0;

    if (![raw getHue:&h saturation:&s brightness:&v alpha:&alpha]) {
        return raw;
    }

    s = MIN(0.90, MAX(0.42, s));
    v = MIN(0.88, MAX(0.52, v));

    return [UIColor colorWithHue:h saturation:s brightness:v alpha:1.0];
}

static void B3MRefreshActiveIconColor(void)
{
    UIImage *snapshot = B3MFindActiveIconSnapshot();

    gB3MActiveIconColor = snapshot
        ? B3MDominantColorFromImage(snapshot)
        : B3MFallbackIconColor();
}

static UIColor *B3MResolvedBaseIconColor(void)
{
    return gB3MActiveIconColor ?: B3MFallbackIconColor();
}

static UIColor *B3MGlassBackgroundColorForView(UIView *view)
{
    UIColor *base = B3MResolvedBaseIconColor();

    CGFloat h = 0.58, s = 0.58, v = 0.78, alpha = 1.0;
    [base getHue:&h saturation:&s brightness:&v alpha:&alpha];

    BOOL dark = B3MUsesDarkAppearance(view);
    CGFloat strength = dark ? 0.72 : 0.55;
    CGFloat tintDrive = B3MTintResponse(strength);

    if (dark) {
        s = MIN(0.88, MAX(0.42, s * 0.92));
        v = MIN(0.82, MAX(0.52, v * 0.88));
        alpha = 0.11 + 0.14 * tintDrive;
    } else {
        // Light recipe is intentionally restrained.
        s = MIN(0.62, MAX(0.24, s * 0.68));
        v = MIN(0.72, MAX(0.48, v * 0.78));
        alpha = 0.045 + 0.085 * tintDrive;
    }

    return [UIColor colorWithHue:h saturation:s brightness:v alpha:alpha];
}

static UIColor *B3MGlassEdgeColorForView(UIView *view)
{
    UIColor *base = B3MResolvedBaseIconColor();

    CGFloat h = 0.58, s = 0.58, v = 0.78, alpha = 1.0;
    [base getHue:&h saturation:&s brightness:&v alpha:&alpha];

    BOOL dark = B3MUsesDarkAppearance(view);
    CGFloat edgeDrive = B3MEdgeResponse(dark ? 0.72 : 0.55);

    if (dark) {
        s = MIN(0.82, MAX(0.35, s * 0.82));
        v = 1.0;
        alpha = 0.14 + 0.24 * edgeDrive;
    } else {
        s = MIN(0.62, MAX(0.28, s * 0.70));
        v = MIN(0.58, MAX(0.34, v * 0.58));
        alpha = 0.10 + 0.16 * edgeDrive;
    }

    return [UIColor colorWithHue:h saturation:s brightness:v alpha:alpha];
}

static UIColor *B3MGlassTextColorForView(UIView *view)
{
    UIColor *base = B3MResolvedBaseIconColor();

    CGFloat h = 0.58, s = 0.58, v = 0.78, alpha = 1.0;
    [base getHue:&h saturation:&s brightness:&v alpha:&alpha];

    if (B3MUsesDarkAppearance(view)) {
        // Pale same-hue text, intentionally not the same RGB as background.
        s = MIN(0.42, MAX(0.12, s * 0.42));
        v = 0.98;
    } else {
        // Light mode uses a dark same-hue text for readable contrast.
        s = MIN(0.72, MAX(0.30, s * 0.78));
        v = 0.32;
    }

    return [UIColor colorWithHue:h saturation:s brightness:v alpha:1.0];
}

static BOOL B3MColorLooksDestructive(UIColor *color, UITraitCollection *traits)
{
    if (!color) return NO;

    UIColor *resolved = color;

    if ([color respondsToSelector:@selector(resolvedColorWithTraitCollection:)]) {
        resolved = [color resolvedColorWithTraitCollection:traits];
    }

    CGFloat r = 0.0, g = 0.0, b = 0.0, alpha = 0.0;

    if (![resolved getRed:&r green:&g blue:&b alpha:&alpha]) {
        return NO;
    }

    return (r > 0.65 && r > (g * 1.45) && r > (b * 1.25));
}

static UIView *B3MGlassOverlayForBackgroundView(UIView *backgroundView, BOOL create)
{
    if (!backgroundView) return nil;

    UIView *overlay =
        objc_getAssociatedObject(backgroundView, &kB3MGlassOverlayKey);

    if (!overlay && create) {
        overlay = [[UIView alloc] initWithFrame:backgroundView.bounds];
        overlay.userInteractionEnabled = NO;
        overlay.autoresizingMask =
            UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

        [backgroundView addSubview:overlay];

        objc_setAssociatedObject(
            backgroundView,
            &kB3MGlassOverlayKey,
            overlay,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    }

    return overlay;
}

static void B3MApplyGlassBackground(UIView *backgroundView)
{
    if (!backgroundView) return;

    UIView *overlay =
        B3MGlassOverlayForBackgroundView(backgroundView, gB3MGlassMenuTint);

    if (!gB3MGlassMenuTint) {
        if (overlay) {
            [overlay removeFromSuperview];

            objc_setAssociatedObject(
                backgroundView,
                &kB3MGlassOverlayKey,
                nil,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC
            );
        }

        return;
    }

    overlay.frame = backgroundView.bounds;
    overlay.layer.cornerRadius = backgroundView.layer.cornerRadius;
    overlay.layer.masksToBounds = YES;
    overlay.backgroundColor = B3MGlassBackgroundColorForView(backgroundView);

    UIColor *edge = B3MGlassEdgeColorForView(backgroundView);
    overlay.layer.borderColor = edge.CGColor;
    overlay.layer.borderWidth = 0.65;
}

static void B3MApplyGlassTextRecursively(UIView *view)
{
    if (!view) return;

    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;

        NSNumber *captured =
            objc_getAssociatedObject(label, &kB3MTextCapturedKey);

        id oldStored =
            objc_getAssociatedObject(label, &kB3MTextColorKey);

        UIColor *originalColor = nil;

        if ([captured boolValue]) {
            originalColor =
                (oldStored == [NSNull null]) ? nil : (UIColor *)oldStored;
        } else {
            originalColor = label.textColor;
        }

        if (gB3MGlassTextTint) {
            if (B3MColorLooksDestructive(originalColor, label.traitCollection)) {
                if ([captured boolValue]) {
                    label.textColor = originalColor;

                    objc_setAssociatedObject(
                        label,
                        &kB3MTextCapturedKey,
                        nil,
                        OBJC_ASSOCIATION_RETAIN_NONATOMIC
                    );

                    objc_setAssociatedObject(
                        label,
                        &kB3MTextColorKey,
                        nil,
                        OBJC_ASSOCIATION_RETAIN_NONATOMIC
                    );
                }
            } else {
                if (![captured boolValue]) {
                    objc_setAssociatedObject(
                        label,
                        &kB3MTextColorKey,
                        originalColor ?: (id)[NSNull null],
                        OBJC_ASSOCIATION_RETAIN_NONATOMIC
                    );

                    objc_setAssociatedObject(
                        label,
                        &kB3MTextCapturedKey,
                        @YES,
                        OBJC_ASSOCIATION_RETAIN_NONATOMIC
                    );
                }

                label.textColor = B3MGlassTextColorForView(label);
            }
        } else if ([captured boolValue]) {
            label.textColor = originalColor;

            objc_setAssociatedObject(
                label,
                &kB3MTextCapturedKey,
                nil,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC
            );

            objc_setAssociatedObject(
                label,
                &kB3MTextColorKey,
                nil,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC
            );
        }
    }

    for (UIView *subview in view.subviews) {
        B3MApplyGlassTextRecursively(subview);
    }
}

static BOOL B3MActionIdentifierLooksLikeShareApp(NSString *identifier)
{
    if (identifier.length == 0) return NO;

    NSString *lower = identifier.lowercaseString;

    if ([lower isEqualToString:@"com.apple.springboard.application-shortcut-item.share"] ||
        [lower isEqualToString:@"com.apple.springboardhome.application-shortcut-item.share"]) {
        return YES;
    }

    BOOL springBoardOwned = ([lower rangeOfString:@"springboard"].location != NSNotFound);
    BOOL shortcutItem = ([lower rangeOfString:@"application-shortcut-item"].location != NSNotFound);
    BOOL share = ([lower hasSuffix:@".share"] ||
                  [lower rangeOfString:@".share-"].location != NSNotFound);

    return springBoardOwned && shortcutItem && share;
}

static NSString *B3MNormalizeMenuTitle(NSString *title)
{
    if (title.length == 0) return @"";

    NSString *normalized = [title lowercaseString];
    normalized = [normalized stringByReplacingOccurrencesOfString:@" " withString:@""];
    normalized = [normalized stringByReplacingOccurrencesOfString:@"\u00a0" withString:@""];
    normalized = [normalized stringByReplacingOccurrencesOfString:@"\t" withString:@""];
    normalized = [normalized stringByReplacingOccurrencesOfString:@"\n" withString:@""];

    return normalized;
}

static BOOL B3MTitleLooksLikeShareApp(NSString *title)
{
    NSString *normalized = B3MNormalizeMenuTitle(title);
    if (normalized.length == 0) return NO;

    static NSSet<NSString *> *knownTitles;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        knownTitles = [NSSet setWithArray:@[
            @"shareapp",
            @"分享app",
            @"共享app",
            @"分享应用",
            @"共享应用"
        ]];
    });

    return [knownTitles containsObject:normalized];
}

static BOOL B3MIsShareAppElement(UIMenuElement *element)
{
    if (!gB3MHideShareApp || !element) {
        return NO;
    }

    NSString *identifier = nil;
    NSString *title = nil;
    id candidate = (id)element;

    if ([candidate respondsToSelector:@selector(identifier)]) {
        identifier = [candidate identifier];
    }

    if ([candidate respondsToSelector:@selector(title)]) {
        title = [candidate title];
    }

    if (B3MActionIdentifierLooksLikeShareApp(identifier)) {
        return YES;
    }

    return B3MTitleLooksLikeShareApp(title);
}


static BOOL B3MActionIdentifierLooksLikeRemoveApp(NSString *identifier)
{
    if (identifier.length == 0) return NO;

    NSString *lower = identifier.lowercaseString;

    static NSSet<NSString *> *knownIdentifiers;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        knownIdentifiers = [NSSet setWithArray:@[
            @"com.apple.springboard.application-shortcut-item.remove",
            @"com.apple.springboard.application-shortcut-item.remove-app",
            @"com.apple.springboard.application-shortcut-item.delete",
            @"com.apple.springboard.application-shortcut-item.delete-app",
            @"com.apple.springboardhome.application-shortcut-item.remove",
            @"com.apple.springboardhome.application-shortcut-item.remove-app",
            @"com.apple.springboardhome.application-shortcut-item.delete",
            @"com.apple.springboardhome.application-shortcut-item.delete-app"
        ]];
    });

    if ([knownIdentifiers containsObject:lower]) {
        return YES;
    }

    BOOL springBoardOwned =
        ([lower rangeOfString:@"springboard"].location != NSNotFound);
    BOOL shortcutItem =
        ([lower rangeOfString:@"application-shortcut-item"].location != NSNotFound);
    BOOL removeOrDelete =
        ([lower hasSuffix:@".remove"] ||
         [lower hasSuffix:@".remove-app"] ||
         [lower hasSuffix:@".delete"] ||
         [lower hasSuffix:@".delete-app"]);

    return springBoardOwned && shortcutItem && removeOrDelete;
}

static BOOL B3MTitleLooksLikeRemoveApp(NSString *title)
{
    NSString *normalized = B3MNormalizeMenuTitle(title);
    if (normalized.length == 0) return NO;

    static NSSet<NSString *> *knownTitles;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        knownTitles = [NSSet setWithArray:@[
            @"removeapp",
            @"移除app"
        ]];
    });

    return [knownTitles containsObject:normalized];
}

static BOOL B3MIsRemoveAppElement(UIMenuElement *element)
{
    if (!gB3MHideRemoveApp || !element) {
        return NO;
    }

    NSString *identifier = nil;
    NSString *title = nil;
    id candidate = (id)element;

    if ([candidate respondsToSelector:@selector(identifier)]) {
        identifier = [candidate identifier];
    }

    if ([candidate respondsToSelector:@selector(title)]) {
        title = [candidate title];
    }

    if (B3MActionIdentifierLooksLikeRemoveApp(identifier)) {
        return YES;
    }

    return B3MTitleLooksLikeRemoveApp(title);
}

static __thread BOOL gB3MInsideMenuRewrite = NO;

static NSArray<UIMenuElement *> *B3MFilterMenuElements(NSArray<UIMenuElement *> *children)
{
    if ((!gB3MHideShareApp && !gB3MHideRemoveApp && !gB3MHideSectionGap) || children.count == 0) {
        return children;
    }

    NSMutableArray<UIMenuElement *> *result =
        [NSMutableArray arrayWithCapacity:children.count];

    BOOL changed = NO;

    for (UIMenuElement *element in children) {
        if (B3MIsShareAppElement(element) ||
            B3MIsRemoveAppElement(element)) {
            changed = YES;
            continue;
        }

        if ([element isKindOfClass:UIMenu.class]) {
            UIMenu *menu = (UIMenu *)element;
            NSArray<UIMenuElement *> *originalChildren = menu.children;
            NSArray<UIMenuElement *> *filteredChildren =
                B3MFilterMenuElements(originalChildren);

            /*
             * iOS 16 experimental section-gap removal.
             *
             * Untitled UIMenuOptionsDisplayInline menus are commonly used as
             * visual groups. Flatten only these groups so UIKit no longer
             * creates the large inter-section gap.
             *
             * We deliberately do not touch gesture recognizers, frames,
             * constraints, or global UIKit views here.
             */
            if (gB3MHideSectionGap &&
                menu.title.length == 0 &&
                (menu.options & UIMenuOptionsDisplayInline) &&
                !(menu.options & UIMenuOptionsDestructive)) {

                [result addObjectsFromArray:filteredChildren];
                changed = YES;
                continue;
            }

            if (filteredChildren != originalChildren) {
                BOOL oldGuard = gB3MInsideMenuRewrite;
                gB3MInsideMenuRewrite = YES;

                UIMenu *replacement =
                    [menu menuByReplacingChildren:filteredChildren];

                gB3MInsideMenuRewrite = oldGuard;

                [result addObject:replacement ?: menu];
                changed = YES;
                continue;
            }
        }

        [result addObject:element];
    }

    return changed ? result.copy : children;
}

%hook _UIContextMenuActionsListSeparatorView

- (void)didMoveToWindow
{
    %orig;
    B3MApplySeparatorState((UIView *)self);
}

- (void)layoutSubviews
{
    %orig;
    B3MApplySeparatorState((UIView *)self);
}

%end

%hook _UIContextMenuReusableSeparatorView

- (void)didMoveToWindow
{
    %orig;
    B3MApplySeparatorState((UIView *)self);
}

- (void)layoutSubviews
{
    %orig;
    B3MApplySeparatorState((UIView *)self);
}

%end

%hook _UIContextMenuSeparatorView

- (void)didMoveToWindow
{
    %orig;
    B3MApplySeparatorState((UIView *)self);
}

- (void)layoutSubviews
{
    %orig;
    B3MApplySeparatorState((UIView *)self);
}

%end

%hook _UIInterfaceActionBlankSeparatorView

- (void)didMoveToWindow
{
    %orig;
    B3MApplySeparatorState((UIView *)self);
}

- (void)layoutSubviews
{
    %orig;
    B3MApplySeparatorState((UIView *)self);
}

%end

%hook _UIInterfaceActionVibrantSeparatorView

- (void)didMoveToWindow
{
    %orig;
    B3MApplySeparatorState((UIView *)self);
}

- (void)layoutSubviews
{
    %orig;
    B3MApplySeparatorState((UIView *)self);
}

%end

%hook _UIElasticContextMenuBackgroundView

- (void)didMoveToWindow
{
    %orig;
    B3MApplyBlurRecursively((UIView *)self, YES);
    B3MApplyGlassBackground((UIView *)self);
}

- (void)layoutSubviews
{
    %orig;
    B3MApplyBlurRecursively((UIView *)self, YES);
    B3MApplyGlassBackground((UIView *)self);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
    %orig(previousTraitCollection);
    B3MApplyGlassBackground((UIView *)self);
}

%end

%hook _UIContextMenuView

- (void)didMoveToWindow
{
    %orig;

    if (((UIView *)self).window) {
        B3MRefreshActiveIconColor();
    }

    B3MApplyBlurRecursively((UIView *)self, NO);
    B3MApplyGlassTextRecursively((UIView *)self);
}

- (void)layoutSubviews
{
    %orig;
    B3MApplyBlurRecursively((UIView *)self, NO);
    B3MApplyGlassTextRecursively((UIView *)self);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
    %orig(previousTraitCollection);
    B3MApplyGlassTextRecursively((UIView *)self);
}

%end

%hook UIMenu

+ (instancetype)menuWithChildren:(NSArray<UIMenuElement *> *)children
{
    if (gB3MInsideMenuRewrite ||
        (!gB3MHideShareApp && !gB3MHideRemoveApp && !gB3MHideSectionGap)) {
        return %orig;
    }

    NSArray<UIMenuElement *> *filtered =
        B3MFilterMenuElements(children);

    return %orig(filtered);
}

+ (instancetype)menuWithTitle:(NSString *)title
                     children:(NSArray<UIMenuElement *> *)children
{
    if (gB3MInsideMenuRewrite ||
        (!gB3MHideShareApp && !gB3MHideRemoveApp && !gB3MHideSectionGap)) {
        return %orig;
    }

    NSArray<UIMenuElement *> *filtered =
        B3MFilterMenuElements(children);

    return %orig(title, filtered);
}

+ (instancetype)menuWithTitle:(NSString *)title
                        image:(UIImage *)image
                   identifier:(UIMenuIdentifier)identifier
                      options:(UIMenuOptions)options
                     children:(NSArray<UIMenuElement *> *)children
{
    if (gB3MInsideMenuRewrite ||
        (!gB3MHideShareApp && !gB3MHideRemoveApp && !gB3MHideSectionGap)) {
        return %orig;
    }

    NSArray<UIMenuElement *> *filtered =
        B3MFilterMenuElements(children);

    return %orig(title, image, identifier, options, filtered);
}

- (instancetype)menuByReplacingChildren:(NSArray<UIMenuElement *> *)children
{
    if (gB3MInsideMenuRewrite ||
        (!gB3MHideShareApp && !gB3MHideRemoveApp && !gB3MHideSectionGap)) {
        return %orig;
    }

    NSArray<UIMenuElement *> *filtered =
        B3MFilterMenuElements(children);

    return %orig(filtered);
}

%end

%ctor
{
    @autoreleasepool {
        if (![[NSBundle mainBundle].bundleIdentifier
              isEqualToString:@"com.apple.springboard"]) {
            return;
        }

        B3MLoadPreferences();

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            B3MPreferencesChanged,
            kB3MNotification,
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );

        %init;
    }
}
