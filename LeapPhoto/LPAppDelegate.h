#import <Cocoa/Cocoa.h>
#import "LeapObjectiveC.h"

@interface LPAppDelegate : NSObject <NSApplicationDelegate, LeapListener>

@property (weak) IBOutlet NSMenu *statusMenu;

@end
