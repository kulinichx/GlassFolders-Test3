// Execute the production stack subclass; no UIKit renderer is emulated here.
#import <Foundation/Foundation.h>

@interface TestRim : NSObject
@property BOOL gfSubdued;
@property NSUInteger layouts;
- (void)setNeedsLayout;
@end
@implementation TestRim
- (void)setNeedsLayout { self.layouts++; }
@end

@interface GFLockScreenGlassView : NSObject
@property (strong) TestRim *gfLockRim;
@property (strong) NSArray *filters;
@property (strong) NSObject *fallbackEffect;
@property NSUInteger materialRefreshes;
@property NSUInteger veilRefreshes;
- (void)gfRefreshMaterial;
- (void)gfRefreshBodyVeil;
@end
@implementation GFLockScreenGlassView
- (instancetype)init {
    self = [super init];
    if (self) { _gfLockRim = [TestRim new]; [self gfRefreshMaterial]; }
    return self;
}
- (void)gfRefreshMaterial {
    self.materialRefreshes++;
    self.filters = @[[NSObject new], [NSObject new]];
    self.fallbackEffect = [NSObject new];
}
- (void)gfRefreshBodyVeil { self.veilRefreshes++; }
@end

#import "../GFNotificationGlassView.h"

#define CHECK(x) do { if (!(x)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #x); return 1; \
} } while (0)

int main(void) {
    @autoreleasepool {
        GFNotificationGlassView *glass = [GFNotificationGlassView new];
        NSArray *filters = glass.filters;
        NSObject *effect = glass.fallbackEffect;
        NSUInteger refreshes = glass.materialRefreshes;
        NSUInteger veils = glass.veilRefreshes;
        for (NSUInteger i = 0; i < 200; i++) {
            glass.gfStacked = YES;
            CHECK(glass.gfLockRim.gfSubdued);
            glass.gfStacked = NO;
            CHECK(!glass.gfLockRim.gfSubdued);
            CHECK(glass.filters == filters);
            CHECK(glass.filters[0] == filters[0] && glass.filters[1] == filters[1]);
            CHECK(glass.fallbackEffect == effect);
            CHECK(glass.materialRefreshes == refreshes);
        }
        CHECK(glass.veilRefreshes == veils + 400);
        NSUInteger layouts = glass.gfLockRim.layouts;
        glass.gfStacked = NO;
        CHECK(glass.gfLockRim.layouts == layouts);
        glass.gfStacked = YES;
        [glass gfRefreshMaterial];
        CHECK(glass.filters != filters);
        CHECK(glass.fallbackEffect != effect);
        CHECK(glass.gfLockRim.gfSubdued);
        puts("Production stack subclass: 400 transitions retain filter/effect identity; "
             "explicit material refresh and duplicate stack state PASS");
    }
    return 0;
}
