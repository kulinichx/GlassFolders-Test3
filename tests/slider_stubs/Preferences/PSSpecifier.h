#import <Foundation/Foundation.h>

@interface PSSpecifier : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSDictionary *properties;
- (id)propertyForKey:(NSString *)key;
@end
