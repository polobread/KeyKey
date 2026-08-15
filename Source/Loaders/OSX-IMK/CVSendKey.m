// [AUTO_HEADER]

#import "CVSendKey.h"

@implementation CVSendKey

static CVSendKey *_sharedSendKey = nil;

+ (CVSendKey *)sharedSendKey
{
	if (_sharedSendKey == nil)
		_sharedSendKey = [[CVSendKey alloc] init];
	return _sharedSendKey;
}

- (void)_typeString: (NSString *)string
{
	NSUInteger length = [string length];
	if (!length)
		return;

	UniChar *characters = (UniChar *)calloc(length, sizeof(UniChar));
	[string getCharacters:characters range:NSMakeRange(0, length)];

	NSUInteger i;
	for (i = 0; i < length; i++) {
		CGEventRef keyDown = CGEventCreateKeyboardEvent(NULL, 0, true);
		CGEventRef keyUp = CGEventCreateKeyboardEvent(NULL, 0, false);
		CGEventKeyboardSetUnicodeString(keyDown, 1, characters + i);
		CGEventKeyboardSetUnicodeString(keyUp, 1, characters + i);
		CGEventPost(kCGHIDEventTap, keyDown);
		CGEventPost(kCGHIDEventTap, keyUp);
		CFRelease(keyDown);
		CFRelease(keyUp);
	}

	free(characters);
}

- (void)typeString: (NSString *)string
{
	[self performSelector:@selector(_typeString:) withObject:string afterDelay:0.1];
}

@end
