//  OpenVanillaController.h

#import <Cocoa/Cocoa.h>
#if (MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_5)
    #import <InputMethodKit/InputMethodKit.h>
#else
    #import "InputMethodKitTiger.h"
#endif

#import "OpenVanillaConfig.h"
#import "OpenVanillaLoader.h"
#import "IMKShiftTapProbe.h"

using namespace OpenVanilla;

@interface OpenVanillaController : IMKInputController {
    // Enabled only in a marked local experiment bundle; no model/engine state.
    IMKShiftTapProbe _shiftProbe;
    BOOL _shiftProbeEnabled;
    PVLoaderContext* _context;
    NSMutableString *_composingBuffer;
    BOOL _commitFromOurselves;

    // Key codes whose key-down we consumed. IMK also hands us the key-up, and
    // a key-up we leave unhandled reaches the client on its own--enough for a
    // web-based client to act on Esc after we already cancelled the reading.
    NSMutableIndexSet *_handledKeyCodes;
	
    // application-specific fixes
    BOOL _doNotClearContextStateEvenWithForcedCommit;
    BOOL _updateCommitStringBeforeCommit;
}
+ (void)setActiveContext:(OpenVanillaController*)context sender:(id)sender;
+ (BOOL)hasPendingComposition;
#pragma mark Send string to client.
+ (void)sendComposedStringToCurrentlyActiveContext:(NSString*)text;
- (void)sendComposedStringToClient:(NSString*)text sender:(id)sender;

- (void)_resetUI;

@end
