// Actual production slider + UIKit. Only the Preferences cell/specifier are stubs.
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Preferences/PSSpecifier.h>
#import "../prefs/GFPercentSliderCell.h"

@implementation PSSpecifier
- (id)propertyForKey:(NSString *)key { return self.properties[key]; }
@end
@implementation PSTableCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style
             reuseIdentifier:(NSString *)identifier specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:identifier];
    if (self) { self.specifier = specifier; self.cellEnabled = YES; }
    return self;
}
- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier { self.specifier = specifier; }
- (UILabel *)titleLabel { return self.textLabel; }
@end

static PSSpecifier *Specifier(NSString *key) {
    PSSpecifier *s = [PSSpecifier new];
    s.name = @"";
    s.properties = @{@"key":key, @"defaults":@"com.kulinich.glassfolders", @"default":@55};
    return s;
}
static void Store(double value, NSString *key) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFNumberRef)@(value),
                             CFSTR("com.kulinich.glassfolders"));
    CFPreferencesAppSynchronize(CFSTR("com.kulinich.glassfolders"));
}
static double Read(NSString *key) {
    NSNumber *value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                              CFSTR("com.kulinich.glassfolders")));
    return value.doubleValue;
}
static NSString *Documents(void) {
    return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
}

@interface SliderController : UITableViewController
@end
@implementation SliderController
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 5; }
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)path { return 44; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    const double values[] = {0,15,35,85,100};
    Store(values[path.row], @"ClearStrength");
    GFPercentSliderCell *cell = [[GFPercentSliderCell alloc] initWithStyle:UITableViewCellStyleDefault
        reuseIdentifier:nil specifier:Specifier(@"ClearStrength")];
    return cell;
}
@end

@interface SliderApp : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation SliderApp
- (void)writeResult:(NSDictionary *)result {
    NSData *data = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];
    [data writeToFile:[Documents() stringByAppendingPathComponent:@"result.json"] atomically:YES];
}
- (void)checkCell:(GFPercentSliderCell *)cell {
    [cell layoutIfNeeded];
    UISlider *slider = [cell valueForKey:@"gfOwnedSlider"];
    UILabel *label = [cell valueForKey:@"gfPercentLabel"];
    CGRect track = [slider trackRectForBounds:slider.bounds];
    CGRect thumb = [slider thumbRectForBounds:slider.bounds trackRect:track value:slider.value];
    thumb = [slider convertRect:thumb toView:cell.contentView];
    track = [slider convertRect:track toView:cell.contentView];
    NSCAssert(CGRectGetMinX(track) >= CGRectGetMaxX(label.frame) + 8, @"Track crosses number: %@", NSStringFromCGRect(track));
    NSCAssert(CGRectGetMinX(thumb) >= CGRectGetMaxX(label.frame) + 6, @"Thumb crosses number");
    NSCAssert(CGRectGetMinX(thumb) >= 0 && CGRectGetMaxX(thumb) <= CGRectGetWidth(cell.contentView.bounds), @"Thumb clipped horizontally");
    NSCAssert(CGRectGetMinY(thumb) >= 0 && CGRectGetMaxY(thumb) <= CGRectGetHeight(cell.contentView.bounds), @"Thumb clipped vertically");
    NSCAssert(!slider.hasAmbiguousLayout && !label.hasAmbiguousLayout, @"Ambiguous slider constraints");
}
- (void)checks {
    @try {
        const CGFloat widths[] = {280,320,375,390,430,768};
        const double values[] = {0,5,15,35,85,100};
        for (NSUInteger w = 0; w < 6; w++) {
            for (NSUInteger v = 0; v < 6; v++) {
                Store(values[v], @"ClearStrength");
                GFPercentSliderCell *cell = [[GFPercentSliderCell alloc] initWithStyle:UITableViewCellStyleDefault
                    reuseIdentifier:nil specifier:Specifier(@"ClearStrength")];
                cell.frame = CGRectMake(0, 0, widths[w], 44);
                for (NSUInteger pass = 0; pass < 10; pass++) {
                    [cell setNeedsLayout];
                    [self checkCell:cell];
                }
                Store(15, @"LiquidGlassStrength");
                [cell refreshCellContentsWithSpecifier:Specifier(@"LiquidGlassStrength")];
                [self checkCell:cell];
                UISlider *slider = [cell valueForKey:@"gfOwnedSlider"];
                NSCAssert(slider.value == 15, @"Reused cell has wrong key");
                slider.value = 21;
                [slider sendActionsForControlEvents:UIControlEventValueChanged];
                NSCAssert(Read(@"LiquidGlassStrength") == 21, @"Continuous preference write failed");
                [slider sendActionsForControlEvents:UIControlEventTouchUpInside];
                NSCAssert(Read(@"LiquidGlassStrength") == 20, @"Release detent write failed");
                NSCAssert(Read(@"ClearStrength") == values[v], @"Wrong preference key changed");
            }
        }
        self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        [self.window layoutIfNeeded];
        [self capture:@"slider-dark.png"];
        self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{
            @try {
                [self.window layoutIfNeeded];
                [self capture:@"slider-light.png"];
                [self writeResult:@{@"status":@"pass", @"widths":@6, @"values":@6,
                    @"checks":@"Actual UIKit track/thumb bounds, repeated layout, reuse, continuous writes, independent keys, release detents"}];
            } @catch (NSException *exception) {
                [self writeResult:@{@"status":@"fail", @"reason":exception.reason ?: @"unknown"}];
            }
        });
    } @catch (NSException *exception) {
        [self writeResult:@{@"status":@"fail", @"reason":exception.reason ?: @"unknown"}];
    }
}
- (void)capture:(NSString *)name {
    UITableViewController *controller = (UITableViewController *)self.window.rootViewController;
    for (GFPercentSliderCell *cell in controller.tableView.visibleCells) [self checkCell:cell];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:self.window.bounds];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [self.window drawViewHierarchyInRect:self.window.bounds afterScreenUpdates:YES];
    }];
    [UIImagePNGRepresentation(image) writeToFile:[Documents() stringByAppendingPathComponent:name] atomically:YES];
}
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.window.rootViewController = [[SliderController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    [self.window makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [self checks]; });
    return YES;
}
@end

int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(SliderApp.class)); }
}
