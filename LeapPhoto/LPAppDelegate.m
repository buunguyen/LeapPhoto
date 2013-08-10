#import <objc/runtime.h>
#import <float.h>
#import "LPAppDelegate.h"

static const int kMinX = -100;
static const int kMaxX = 100;
static const int kMinY = 100;
static const int kMaxY = 200;
static CGEventSourceRef kEventSource;
static NSSize kScreenSize;

@implementation LPAppDelegate {
    NSStatusItem *_statusBar;
    LeapController *_leapController;
    int _currentFingerId;
    long _lastFrameTimestamp;
    NSMutableArray *_pastPositions;
}

+ (void) initialize {
    kEventSource = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    NSScreen *screen = [NSScreen screens][0];
    kScreenSize = [screen visibleFrame].size;
}

- (void) awakeFromNib {
    _statusBar = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    _statusBar.title = @"LeapPhoto";
    _statusBar.menu = self.statusMenu;
    _statusBar.highlightMode = YES;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [[NSWorkspace sharedWorkspace] launchApplication: @"iPhoto"];
    
    _lastFrameTimestamp = _currentFingerId = -1;
    
    _leapController = [[LeapController alloc] init];
    [_leapController addListener:self];
    [_leapController setPolicyFlags:LEAP_POLICY_BACKGROUND_FRAMES];
    if([_leapController.config setFloat:@"Gesture.Swipe.MinLength" value:10] &&
       [_leapController.config setFloat:@"Gesture.Swipe.MinVelocity" value:50])
        [_leapController.config save];
    _pastPositions = [[NSMutableArray alloc] init];
}


#pragma mark - LeapListener

- (void)onInit:(NSNotification *)notification {
    NSLog(@"Initialized");
}

- (void)onConnect:(NSNotification *)notification {
    NSLog(@"Connected");
    LeapController *lc = (LeapController *)[notification object];
    [lc enableGesture:LEAP_GESTURE_TYPE_CIRCLE enable:YES];
    [lc enableGesture:LEAP_GESTURE_TYPE_KEY_TAP enable:YES];
    [lc enableGesture:LEAP_GESTURE_TYPE_SCREEN_TAP enable:YES];
    [lc enableGesture:LEAP_GESTURE_TYPE_SWIPE enable:YES];
}

- (void)onDisconnect:(NSNotification *)notification {
    NSLog(@"Disconnected");
}

- (void)onExit:(NSNotification *)notification {
    NSLog(@"Exited");
}

- (void)onFrame:(NSNotification *)notification {
    LeapController *lc = (LeapController *)[notification object];
    LeapFrame *frame = [lc frame:0];    
    LeapFinger *finger = [frame finger:_currentFingerId];
    if (![finger isValid]) {
        if ([frame hands].count == 0 || [[frame hands][0] fingers].count == 0)
            return;
        finger = [[frame hands][0] fingers][0];
    }
    _currentFingerId = finger.id;
    [self move:finger.tipPosition];

    // Cancel click if there's any gap in focus
    if (_lastFrameTimestamp != -1 && frame.timestamp - _lastFrameTimestamp > 50000) {
        [_pastPositions removeAllObjects];
    }
    _lastFrameTimestamp = frame.timestamp;
    
    // Perform clicks if focusing for 60 contiguous frames
    [_pastPositions addObject:finger.tipPosition];
    if (_pastPositions.count > 60) {
        [_pastPositions removeObjectAtIndex:0];
        bool shouldClick = true;
        float top = FLT_MAX, bottom = FLT_MAX, left = FLT_MAX, right = FLT_MAX;
        for (id obj in _pastPositions) {
            LeapVector *position = (LeapVector *) obj;
            if (top == FLT_MAX || top < position.y) top = position.y;
            if (bottom == FLT_MAX || bottom > position.y) bottom = position.y;
            if (left == FLT_MAX || left > position.x) left = position.x;
            if (right == FLT_MAX || right < position.x) right = position.x;
            if (top - bottom > 20 || right - left > 20) {
                shouldClick = false;
                break;
            }
        };
        if (shouldClick) {
            [_pastPositions removeAllObjects];
            [self click:[[LeapVector alloc] initWithX:(right+left)/2 y:(top+bottom)/2 z:0]];
            return;
        }
    }
    
    NSArray *gestures = [frame gestures:nil];
    for (int i = 0; i < gestures.count; i++) {
        LeapGesture *gesture = gestures[i];
        switch (gesture.type) {
            case LEAP_GESTURE_TYPE_SWIPE: {
                LeapSwipeGesture *g = (LeapSwipeGesture *)gesture;
                if (g.state == LEAP_GESTURE_STATE_STOP) {
                    [self press: g.direction.x > 0 ? 124 : 123];
                    [self press: g.direction.y > 0 ? 126 : 125];
                }
                break;
            }
            case LEAP_GESTURE_TYPE_CIRCLE: {
                LeapCircleGesture *g = (LeapCircleGesture *)gesture;
                if (g.state == LEAP_GESTURE_STATE_STOP)
                    [self dblClick:g.pointable.tipPosition];
                break;
            }
            case LEAP_GESTURE_TYPE_SCREEN_TAP: {
                break;
            }
            case LEAP_GESTURE_TYPE_KEY_TAP: {
                break;
            }
            default:
                NSLog(@"Unknown gesture type");
                break;
        }
    }
}

- (void)onFocusGained:(NSNotification *)notification {
    NSLog(@"Focus Gained");
}

- (void)onFocusLost:(NSNotification *)notification {
    NSLog(@"Focus Lost");
}


#pragma mark - Utilities

- (CGPoint) toScreen:(LeapVector *) position {
    float x = MAX(MIN(position.x, kMaxX), kMinX);
    float y = MAX(MIN(position.y, kMaxY), kMinY);
    float projectedX = (x - kMinX) * kScreenSize.width / (kMaxX - kMinX);
    float projectedY = kScreenSize.height - (y - kMinY) * kScreenSize.height / (kMaxY - kMinY);
    return CGPointMake(projectedX, projectedY);
}

- (void)move:(LeapVector *)vector {
    CGPoint point = [self toScreen:vector];
    CGDisplayMoveCursorToPoint(kCGDirectMainDisplay, point);
}

- (void)click:(LeapVector *)vector {
    CGPoint point = [self toScreen:vector];

    CGEventRef mouseEvent = CGEventCreateMouseEvent(kEventSource, kCGEventLeftMouseDown, point, kCGMouseButtonLeft);
    CGEventPost(kCGHIDEventTap, mouseEvent);
    CGEventSetType(mouseEvent, kCGEventLeftMouseUp);
    CGEventPost(kCGHIDEventTap, mouseEvent);
    
    CFRelease(mouseEvent);
}

- (void)dblClick:(LeapVector *)vector {
    CGPoint point = [self toScreen:vector];
    
    CGEventRef mouseEvent = CGEventCreateMouseEvent(kEventSource, kCGEventLeftMouseDown, point, kCGMouseButtonLeft);
    CGEventPost(kCGHIDEventTap, mouseEvent);
    CGEventSetType(mouseEvent, kCGEventLeftMouseUp);
    CGEventPost(kCGHIDEventTap, mouseEvent);
    CGEventSetIntegerValueField(mouseEvent, kCGMouseEventClickState, 2);
    CGEventSetType(mouseEvent, kCGEventLeftMouseDown);
    CGEventPost(kCGHIDEventTap, mouseEvent);
    CGEventSetType(mouseEvent, kCGEventLeftMouseUp);
    CGEventPost(kCGHIDEventTap, mouseEvent);
    
    CFRelease(mouseEvent);
}

- (void)press:(CGKeyCode)code {
    CGEventRef keydown = CGEventCreateKeyboardEvent(kEventSource, code, true);
    CGEventRef keyup = CGEventCreateKeyboardEvent(kEventSource, code, false);
    
    CGEventPost(kCGHIDEventTap, keydown);
    CGEventPost(kCGHIDEventTap, keyup);
    
    CFRelease(keydown);
    CFRelease(keyup);
}

@end
