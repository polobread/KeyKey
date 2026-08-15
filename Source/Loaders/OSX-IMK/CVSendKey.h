// [AUTO_HEADER]

#import <Cocoa/Cocoa.h>

@interface CVSendKey : NSObject {

}
+ (CVSendKey*)sharedSendKey;
- (void)typeString:(NSString *)string;
@end
