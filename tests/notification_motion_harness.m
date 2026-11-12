// Extracted production stack query. Slider drawing is tested in UIKit separately.
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>

@interface UIView : NSObject
@property (weak) UIView *superview;
@property CGAffineTransform transform;
@end
@implementation UIView
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
        puts("Production notification state: scale/rotation, rear state and unknown host PASS");
    }
    return 0;
}
