#import <UIKit/UIKit.h>
@class PSSpecifier;

@interface PSTableCell : UITableViewCell
@property (nonatomic, strong) PSSpecifier *specifier;
@property (nonatomic) BOOL cellEnabled;
@property (nonatomic, readonly) UILabel *titleLabel;
- (instancetype)initWithStyle:(UITableViewCellStyle)style
             reuseIdentifier:(NSString *)identifier specifier:(PSSpecifier *)specifier;
- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier;
@end
