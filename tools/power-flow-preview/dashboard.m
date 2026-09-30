#import "../../pkg/gui/native_internal.h"
#include <assert.h>
#include <math.h>
#import <QuartzCore/QuartzCore.h>

// Isolated native render + behavior checks. No daemon callbacks or process quits.
void battMenuWillOpen(uintptr_t handle) { (void)handle; }
void battMenuTimerFired(uintptr_t handle) { (void)handle; }
void battMenuAction(uintptr_t handle, int item, bool checked) { (void)handle; (void)item; (void)checked; }
static int requestedLimit = -1;
bool battMenuSetLimit(uintptr_t handle, int limit) { (void)handle; requestedLimit = limit; return true; }

static NSButton *FindButton(NSView *view, NSString *title) {
    for (NSView *child in view.subviews) {
        if ([child isKindOfClass:NSButton.class] && [((NSButton *)child).title isEqual:title])
            return (NSButton *)child;
        NSButton *found = FindButton(child,title);
        if (found) return found;
    }
    return nil;
}
static void Capture(NSView *view, NSString *directory, NSString *name) {
    [view displayIfNeeded];
    NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
    [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
        writeToFile:[directory stringByAppendingPathComponent:[name stringByAppendingString:@".png"]]
        atomically:YES];
}
int main(int argc, const char *argv[]) {
    if (argc != 2) return 2;
    @autoreleasepool {
        assert(BattCounterRate(100,300,2) == 100);
        assert(BattCounterRate(300,100,2) == -1);
        assert(BattCounterRate(100,100,2) == 0);
        assert(BattCounterRate(0,100,0) == -1);
        assert(BattCounterRate(0,100,NAN) == -1);
        [NSApplication sharedApplication];
        NSString *directory = [NSString stringWithUTF8String:argv[1]];
        [[NSFileManager defaultManager] createDirectoryAtPath:directory
            withIntermediateDirectories:YES attributes:nil error:nil];
        BattMenuController *c = [[BattMenuController alloc] init];
        c.items = [NSMutableDictionary dictionary];
        c.powerFlowView = [[[BattPowerFlowView alloc] initWithFrame:NSMakeRect(0,0,360,220)] autorelease];
        c.diskReadRate = 12400000; c.diskWriteRate = 2100000;
        c.diskSpacePercent = 73; c.diskTotalBytes = 500000000000; c.diskFreeBytes = 135000000000;
        c.appStats = @[
            @{@"pid":@123, @"name":@"ChatGPT", @"path":@"/Applications/ChatGPT.app", @"cpu":@9, @"memory":@780000000},
            @{@"pid":@124, @"name":@"Warp", @"path":@"/Applications/Warp.app", @"cpu":@6, @"memory":@1370000000},
            @{@"pid":@125, @"name":@"Safari", @"path":@"/System/Applications/Safari.app", @"cpu":@4, @"memory":@500000000},
            @{@"pid":@126, @"name":@"Finder", @"path":@"/System/Library/CoreServices/Finder.app", @"cpu":@1, @"memory":@180000000},
            @{@"pid":@127, @"name":@"An application with a very long name", @"path":@"/Applications/Utilities/Terminal.app", @"cpu":@0, @"memory":@180000000}];
        BattBuildPopover(c);
        NSView *view = c.popover.contentViewController.view;
        NSWindow *window = [[NSWindow alloc] initWithContentRect:view.bounds
            styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        [window.contentView addSubview:view];
        NSArray *states = @[
            @{@"name":@"battery", @"charge":@48, @"plug":@NO, @"adapter":@0, @"battery":@-9.4, @"system":@9.4, @"heat":@NO},
            @{@"name":@"charging", @"charge":@57, @"plug":@YES, @"adapter":@36, @"battery":@15.8, @"system":@20.2, @"heat":@NO},
            @{@"name":@"limit-held", @"charge":@80, @"plug":@YES, @"adapter":@21, @"battery":@0, @"system":@21, @"heat":@NO},
            @{@"name":@"heat-held", @"charge":@64, @"plug":@YES, @"adapter":@18.9, @"battery":@0, @"system":@18.9, @"heat":@YES},
            @{@"name":@"hybrid", @"charge":@70, @"plug":@YES, @"adapter":@11.1, @"battery":@-5.5, @"system":@16.6, @"heat":@NO},
            @{@"name":@"unavailable", @"charge":@70, @"plug":@NO, @"adapter":@0, @"battery":@0, @"system":@0, @"heat":@NO},
            @{@"name":@"inconsistent", @"charge":@57, @"plug":@YES, @"adapter":@14, @"battery":@14.3, @"system":@0, @"heat":@NO}];
        for (NSDictionary *state in states) {
            BattPowerFlowView *power = c.powerFlowView;
            power.chargePercent = [state[@"charge"] integerValue]; power.limitPercent = 80;
            power.pluggedIn = [state[@"plug"] boolValue]; power.adapterWatts = [state[@"adapter"] doubleValue];
            power.batteryWatts = [state[@"battery"] doubleValue]; power.systemWatts = [state[@"system"] doubleValue];
            power.heatPaused = [state[@"heat"] boolValue]; power.temperatureCelsius = 36.5;
            power.hasTelemetry = ![state[@"name"] isEqual:@"unavailable"];
            BattRefreshPopover(c,63,81);
            Capture(view,directory,state[@"name"]);
        }
        NSButton *system = FindButton(view,@"System"); assert(system);
        c.powerFlowView.limitEditable = YES;
        [c.powerFlowView keyDown:[NSEvent keyEventWithType:NSEventTypeKeyDown
            location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil
            characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:124]];
        assert(requestedLimit == 85);
        assert(c.powerFlowView.displayedLimitPercent == 85);
        c.powerFlowView.limitPercent = 80;
        BattRefreshPopover(c,63,81);
        [system performClick:nil]; assert(c.powerFlowView.hiddenOrHasHiddenAncestor);
        Capture(view,directory,@"system-cpu");
        [FindButton(view,@"Memory") performClick:nil];
        Capture(view,directory,@"system-memory");
        [FindButton(view,@"Battery") performClick:nil]; assert(!c.powerFlowView.hiddenOrHasHiddenAncestor);
        c.appStats = @[]; c.diskReadRate = -1; c.diskWriteRate = -1;
        BattRefreshPopover(c,-1,-1);
        [system performClick:nil]; Capture(view,directory,@"system-empty");
        BattUpdateStorage(c); assert(c.diskReadRate == -1);
        c.previousDiskSampleTime -= 1;
        BattUpdateStorage(c);
        assert(c.previousDiskCounters.count == 0 || (c.diskReadRate >= 0 && c.diskWriteRate >= 0));
        [FindButton(view,@"Battery") performClick:nil];
        c.powerFlowView.hasTelemetry = YES;
        c.powerFlowView.pluggedIn = YES;
        c.powerFlowView.adapterWatts = 18.9;
        c.powerFlowView.batteryWatts = 0;
        c.powerFlowView.systemWatts = 18.9;
        [window orderFront:nil];
        c.powerFlowView.flowAnimationEnabled = YES;
        [c.powerFlowView display];
        [CATransaction flush];
        BOOL animated = NO;
        for (CALayer *layer in c.powerFlowView.layer.sublayers)
            animated |= [layer animationForKey:@"flow"] != nil;
        assert(animated == !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion);
        c.powerFlowView.flowAnimationEnabled = NO;
        for (CALayer *layer in c.powerFlowView.layer.sublayers)
            assert([layer animationForKey:@"flow"] == nil);
        [window orderOut:nil];
        NSLog(@"Native checks passed; internal disks: %lu, read %.1f B/s, write %.1f B/s",
            (unsigned long)c.previousDiskCounters.count,c.diskReadRate,c.diskWriteRate);
        [window release]; [c release];
    }
    return 0;
}
