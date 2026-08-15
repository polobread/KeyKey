// [AUTO_HEADER]

#import <Cocoa/Cocoa.h>

// The list of associated-phrase collections in the Phrases pane. Names and
// counts come from the cooked dictionary, so adding a collection is a matter of
// dropping a file into DataSource and rebuilding, with nothing to change here.
//
// No collection ticked is a valid state and means no associated phrases at all.
// It is written as an empty EnabledCollections string, which the module tells
// apart from an absent key -- absent is a first run and gets McBopomofo.

@interface TakaoPhraseCollections : NSObject
{
	IBOutlet NSTableView *_collectionTableView;

	NSArray *_collections;
	NSMutableArray *_enabled;
}

- (void)reload;
- (IBAction)toggleCollection:(id)sender;

@end
