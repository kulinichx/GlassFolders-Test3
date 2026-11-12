// Executes extracted production methods with translation-only view doubles.
// Does not emulate UISlider drawing or the device's private compositor.
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#include <math.h>

@interface UIView : NSObject
@property (nonatomic) CGRect frame;
@property CGRect bounds;
@property (weak) UIView *superview;
@property (strong) CALayer *layer;
@property BOOL clipsToBounds;
@property BOOL hidden;
@property CGAffineTransform transform;
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view;
- (void)layoutSubviews;
@end
@implementation UIView
- (instancetype)init {
    self = [super init];
    if (self) _layer = [CALayer layer];
    return self;
}
- (void)setFrame:(CGRect)frame {
    _frame = frame;
    _bounds.size = frame.size;
}
- (CGPoint)worldOffset {
    CGPoint result = CGPointZero;
    for (UIView *view = self; view; view = view.superview) {
        result.x += view.frame.origin.x - view.bounds.origin.x;
        result.y += view.frame.origin.y - view.bounds.origin.y;
    }
    return result;
}
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view {
    CGPoint from = [self worldOffset], to = [view worldOffset];
    return CGRectOffset(rect, from.x - to.x, from.y - to.y);
}
- (void)layoutSubviews {}
@end

@interface UISlider : UIView
@end
@implementation UISlider
@end
@interface UILabel : UIView
@end
@implementation UILabel
@end
@interface TestNotification : UIView
@property BOOL isNotificationContentViewHidden;
@end
@implementation TestNotification
@end
static BOOL GFLockBool(id object, NSString *name, BOOL fallback) {
    SEL selector = NSSelectorFromString(name);
    return [object respondsToSelector:selector] ?
        ((BOOL (*)(id, SEL))objc_msgSend)(object, selector) : fallback;
}
/* PRODUCTION_STACK_QUERY */

@interface PSSliderTableCell : UIView
@end
@implementation PSSliderTableCell
@end
@interface GFPercentSliderCell : PSSliderTableCell
@property (strong) UIView *contentView;
@property (strong) UILabel *gfPercentLabel;
@property (strong) UISlider *slider;
@property NSUInteger updates;
@end
@implementation GFPercentSliderCell
- (void)gfEnsurePercentLabel {}
- (void)gfBindSliderIfNeeded {}
- (UISlider *)gfSlider { return self.slider; }
- (void)gfUpdatePercentLabel { self.updates++; }
/* PRODUCTION_SLIDER_LAYOUT */
@end

#define CHECK(x) do { if (!(x)) { fprintf(stderr, "FAIL %d: %s\n", __LINE__, #x); return 1; } } while (0)
int main(void) {
    @autoreleasepool {
        TestNotification *host = [TestNotification new];
        UIView *wrapper = [UIView new];
        host.superview = wrapper;
        for (NSUInteger i = 0; i < 400; i++) {
            CGFloat scale = 0.70 + (i % 36) * 0.01;
            host.transform = CGAffineTransformMakeScale(scale, scale);
            wrapper.transform = CGAffineTransformMakeRotation(i * 0.01);
            host.isNotificationContentViewHidden = NO;
            CHECK(!GFLockNotificationIsStacked(host));
            host.isNotificationContentViewHidden = YES;
            CHECK(GFLockNotificationIsStacked(host));
        }
        CHECK(!GFLockNotificationIsStacked([UIView new]));

        const CGFloat widths[] = {280, 320, 375, 390, 430, 768};
        const CGFloat offsets[] = {-40, 0, 65};
        const CGFloat values[] = {0, 0.05, 0.15, 0.50, 1};
        for (NSUInteger w = 0; w < sizeof(widths)/sizeof(widths[0]); w++) {
            for (NSUInteger o = 0; o < sizeof(offsets)/sizeof(offsets[0]); o++) {
                GFPercentSliderCell *cell = [GFPercentSliderCell new];
                cell.contentView = [UIView new];
                cell.contentView.frame = CGRectMake(7, 3, widths[w], 44);
                cell.gfPercentLabel = [UILabel new];
                cell.gfPercentLabel.superview = cell.contentView;
                UIView *parent = [UIView new];
                parent.frame = CGRectMake(offsets[o], 2, widths[w], 44);
                parent.bounds = CGRectMake(12, 1, widths[w], 44);
                parent.superview = cell.contentView;
                cell.slider = [UISlider new];
                cell.slider.superview = parent;
                cell.slider.frame = CGRectMake(0, 0, widths[w], 31);
                cell.slider.clipsToBounds = YES;
                cell.slider.layer.masksToBounds = YES;
                for (NSUInteger pass = 0; pass < 20; pass++) {
                    [cell layoutSubviews];
                    CGRect slider = [cell.slider convertRect:cell.slider.bounds toView:cell.contentView];
                    CHECK(fabs(slider.origin.x - 96) < 0.001);
                    CHECK(fabs(CGRectGetMaxX(slider) - (widths[w] - 18)) < 0.001);
                    CHECK(CGRectGetMinY(slider) >= 0 && CGRectGetMaxY(slider) <= 44);
                    CHECK(!cell.slider.clipsToBounds && !cell.slider.layer.masksToBounds);
                    // A conventional 28pt thumb footprint, not a UIKit render.
                    for (NSUInteger v = 0; v < sizeof(values)/sizeof(values[0]); v++) {
                        CGFloat left = slider.origin.x + values[v] * (slider.size.width - 28);
                        CHECK(left >= CGRectGetMaxX(cell.gfPercentLabel.frame) + 18);
                        CHECK(left + 28 <= widths[w] - 18 + 0.001);
                    }
                }
                CHECK(cell.updates == 20);
                cell.slider = nil;
                [cell layoutSubviews];
                CHECK(cell.gfPercentLabel.hidden);
            }
        }
        puts("Production motion state and slider coordinates: scale/rotation, rear state, unknown host, wrapped control, endpoints and repeated layout PASS");
    }
    return 0;
}
