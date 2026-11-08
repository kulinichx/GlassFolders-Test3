// Render the actual edge layers on macOS. This checks contours only; it does
// not reproduce SpringBoard backdrop sampling, text, or animation.
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#include <math.h>

#define UIColor NSColor
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
@interface UIView : NSObject
@property CGRect frame;
@property CGRect bounds;
@property BOOL userInteractionEnabled;
@property (strong) NSColor *backgroundColor;
@property (strong) CALayer *layer;
@property (strong) TestWindow *window;
- (instancetype)initWithFrame:(CGRect)frame;
- (void)layoutSubviews;
@end
@implementation UIView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super init];
    if (self) {
        _frame = frame;
        _bounds = (CGRect){CGPointZero, frame.size};
        _layer = [CALayer layer];
        _layer.frame = frame;
    }
    return self;
}
- (void)layoutSubviews {}
@end

#import "../GFGlassRim.h"
#import "../GFNotificationPalette.h"

static void AddCard(CALayer *root, CGRect frame, BOOL light, BOOL subdued) {
    CALayer *body = [CALayer layer];
    body.frame = frame;
    body.cornerCurve = kCACornerCurveContinuous;
    body.cornerRadius = 26;
    GFNotificationPalette palette = GFNotificationPaletteForWallpaper(1, 1, 1, 1, false, false);
    body.backgroundColor = [NSColor colorWithWhite:light ? palette.bodyWhite : 1
                                           alpha:palette.bodyOpacity].CGColor;
    [root addSublayer:body];
    GFLockRimView *rim = [[GFLockRimView alloc] initWithFrame:frame];
    rim.gfRadius = 26;
    rim.gfLightSurface = YES;
    rim.gfSubdued = subdued;
    [rim layoutSubviews];
    // The previous candidate had the same reduced white reflection but
    // no absorbing contour.
    rim.gfLightContour.hidden = !light;
    [root addSublayer:rim.layer];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) return 2;
        const size_t scale = 3, width = 860, height = 540;
        const size_t pixelsWide = width * scale, pixelsHigh = height * scale;
        unsigned char *pixels = calloc(pixelsWide * pixelsHigh, 4);
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = CGBitmapContextCreate(pixels, pixelsWide, pixelsHigh,
            8, pixelsWide * 4, space,
            kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
        CGContextScaleCTM(context, scale, scale);
        CALayer *root = [CALayer layer];
        root.frame = CGRectMake(0, 0, width, height);
        root.backgroundColor = NSColor.whiteColor.CGColor;
        // Left: previous light surface. Right: adaptive contour/body.
        AddCard(root, CGRectMake(20, 20, 390, 140), NO, NO);
        AddCard(root, CGRectMake(450, 20, 390, 140), YES, NO);
        AddCard(root, CGRectMake(20, 205, 390, 140), NO, YES);
        AddCard(root, CGRectMake(450, 205, 390, 140), YES, YES);
        // Wallpaper detail behind a third pair: edge test only, no blur.
        for (NSUInteger i = 0; i < 22; i++) {
            CALayer *mark = [CALayer layer];
            mark.frame = CGRectMake(10 + i * 40, 400 + (i % 3) * 25, 16, 16);
            mark.cornerRadius = 8;
            mark.backgroundColor = [NSColor colorWithWhite:.75 alpha:1].CGColor;
            [root addSublayer:mark];
        }
        AddCard(root, CGRectMake(20, 380, 390, 140), NO, NO);
        AddCard(root, CGRectMake(450, 380, 390, 140), YES, NO);
        [root renderInContext:context];
        // Straight top edge, safely clear of corners and wallpaper marks.
        unsigned char darkest = 255;
        for (size_t y = 20 * scale; y < 23 * scale; y++)
            for (size_t x = 580 * scale; x < 700 * scale; x++)
                darkest = MIN(darkest, pixels[(y * pixelsWide + x) * 4]);
        size_t center = ((90 * scale) * pixelsWide + 645 * scale) * 4;
        unsigned char bodyWhite = pixels[center];
        if (darkest >= 245 || bodyWhite < 240 || bodyWhite > 251) {
            fprintf(stderr, "Contour/body check failed: edge=%u body=%u\n", darkest, bodyWhite);
            return 1;
        }
        CGImageRef image = CGBitmapContextCreateImage(context);
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:image];
        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        BOOL saved = [png writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES];
        printf("Production rim render: pure-white edge=%u body=%u, PNG=%s\n",
               darkest, bodyWhite, saved ? "saved" : "failed");
        CGImageRelease(image);
        CGContextRelease(context);
        CGColorSpaceRelease(space);
        free(pixels);
        return saved ? 0 : 1;
    }
}
