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
        assert([WattCPUUsageLabel(234,10) isEqual:@"23.4% CPU"]);
        assert([WattCPUUsageLabel(234,8) isEqual:@"29.2% CPU"]);
        assert([WattCPUUsageLabel(100,1) isEqual:@"100.0% CPU"]);
        assert([WattCPUUsageLabel(0,8) isEqual:@"0.0% CPU"]);
        assert([WattCPUUsageLabel(234,0) isEqual:@"—"]);
        assert([WattCPUUsageLabel(NAN,8) isEqual:@"—"]);
        assert(fabs(BattProcessCPUPercent(0,24000000,1,125,3)-100)<0.001);
        assert(fabs(BattProcessCPUPercent(0,1000000000,1,1,1)-100)<0.001);
        assert(BattProcessCPUPercent(200,100,1,125,3) == 0);
        assert(BattProcessCPUPercent(0,100,0,125,3) == 0);
        assert([WattCompactBytes(-1,YES) isEqual:@"—"]);
        assert([WattCompactBytes(NAN,YES) isEqual:@"—"]);
        assert([WattCompactBytes(0,YES) isEqual:@"0 B"]);
        assert([WattCompactBytes(1024,YES) isEqual:@"1 KB"]);
        assert([WattCompactBytes(1500000,NO) isEqual:@"1.5 MB"]);
        assert([WattCompactBytes(3.0*1024*1024*1024*1024,YES) isEqual:@"3 TB"]);
        assert([WattCompactBytes(999999999,NO) isEqual:@"1 GB"]);
        assert(BattCounterRate(100,300,2) == 100);
        assert(BattCounterRate(300,100,2) == -1);
        assert(BattCounterRate(100,100,2) == 0);
        assert(BattCounterRate(0,100,0) == -1);
        assert(BattCounterRate(0,100,NAN) == -1);
        [NSApplication sharedApplication];
        // This executable has no app bundle: preferences are isolated from WattNook.
        assert(NSBundle.mainBundle.bundleIdentifier == nil);
        for (NSString *key in @[@"WattNookPalette",@"WattNookMenuMetrics",@"WattNookMenuBatteryIcon",@"WattNookCPUUnits",@"WattNookMemoryUnits",@"WattNookDiskUnits"])
            [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
        NSString *directory = [NSString stringWithUTF8String:argv[1]];
        [[NSFileManager defaultManager] createDirectoryAtPath:directory
            withIntermediateDirectories:YES attributes:nil error:nil];
        BattMenuController *c = [[BattMenuController alloc] init];
        c.items = [NSMutableDictionary dictionary];
        c.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
        c.powerFlowView = [[[BattPowerFlowView alloc] initWithFrame:NSMakeRect(0,0,360,220)] autorelease];
        c.diskReadRate = 12400000; c.diskWriteRate = 2100000;
        c.diskSpacePercent = 73; c.diskTotalBytes = 500000000000; c.diskFreeBytes = 135000000000;
        c.swapUsedBytes = 1.5*1024*1024*1024;
        c.appStats = @[
            @{@"pid":@123, @"name":@"ChatGPT", @"path":@"/Applications/ChatGPT.app", @"cpu":@9, @"memory":@780000000},
            @{@"pid":@124, @"name":@"Warp", @"path":@"/Applications/Warp.app", @"cpu":@6, @"memory":@1370000000},
            @{@"pid":@125, @"name":@"Safari", @"path":@"/Applications/Safari.app", @"cpu":@4, @"memory":@500000000},
            @{@"pid":@126, @"name":@"Finder", @"path":@"/System/Library/CoreServices/Finder.app", @"cpu":@1, @"memory":@180000000},
            @{@"pid":@127, @"name":@"An application with a very long name", @"path":@"/System/Applications/Utilities/Terminal.app", @"cpu":@0, @"memory":@180000000},
            @{@"pid":@128, @"name":@"WattNook", @"path":@"", @"cpu":@0.2, @"memory":@42000000, @"canQuit":@NO}];
        NSMutableDictionary *previewProcesses = [NSMutableDictionary dictionary];
        for (NSDictionary *app in c.appStats) previewProcesses[app[@"pid"]] = @[@0,@0];
        c.previousProcessCPU = previewProcesses;
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
        c.powerFlowView.limitPercent = 20;
        assert([view hitTest:NSMakePoint(84,308)] == c.powerFlowView);
        c.powerFlowView.limitPercent = 80;
        assert([view hitTest:NSMakePoint(276,308)] == c.powerFlowView);
        [c refreshStatusImage];
        assert([c.statusItem.button.accessibilityLabel containsString:@"SSD space used 73%"]);
        CGFloat withoutPercent = c.statusItem.button.image.size.width;
        [NSUserDefaults.standardUserDefaults setBool:NO forKey:@"WattNookMenuBatteryIcon"];
        [c refreshStatusImage];
        assert(withoutPercent-c.statusItem.button.image.size.width >= 34);
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"WattNookMenuBatteryIcon"];
        [NSUserDefaults.standardUserDefaults setObject:@[@"CPU",@"RAM",@"SSD",@"Battery"] forKey:@"WattNookMenuMetrics"];
        [c refreshStatusImage];
        assert(c.statusItem.button.image.size.width-withoutPercent >= 14);
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"WattNookMenuMetrics"];
        BattRefreshPopover(c,63,81);
        [system performClick:nil]; assert(c.powerFlowView.hiddenOrHasHiddenAncestor);
        NSArray *consumerRows = [view valueForKey:@"_rows"];
        assert(consumerRows.count == 6);
        assert(((NSTextField *)[view valueForKey:@"_swap"]).font.pointSize == 12);
        assert([((NSTextField *)[view valueForKey:@"_swap"]).stringValue isEqual:@"Swap 1.5 GB"]);
        assert(((NSView *)[view valueForKey:@"_processCount"]).frame.origin.x == 24);
        assert(((NSView *)[view valueForKey:@"_swap"]).frame.origin.x == 134);
        assert(((NSView *)[view valueForKey:@"_availableSpace"]).frame.origin.x == 244);
        assert([((NSTextField *)[view valueForKey:@"_availableSpace"]).stringValue isEqual:@"Free 135 GB"]);
        // Regress the actual NSRangeException: CPU's default NSButton tag was -1.
        [FindButton(view,@"Memory") performClick:nil];
        [FindButton(view,@"CPU") performClick:nil];
        assert([[view valueForKey:@"_sortMetric"] integerValue] == 0);
        for (NSInteger i=0; i<100; i++) {
            [FindButton(view,@"Memory") performClick:nil];
            [FindButton(view,@"Disk") performClick:nil];
            [FindButton(view,@"CPU") performClick:nil];
        }
        NSButton *invalidSort = [[[NSButton alloc] init] autorelease]; invalidSort.tag = -1;
        [view performSelector:@selector(sort:) withObject:invalidSort];
        assert([[view valueForKey:@"_sortMetric"] integerValue] == 0);
        [view setValue:@-1 forKey:@"_sortMetric"];
        BattRefreshPopover(c,63,81);
        assert([[view valueForKey:@"_sortMetric"] integerValue] == 0);
        Capture(view,directory,@"system-cpu");
        NSArray *cpuApps = c.appStats;
        NSMutableDictionary *busyApp = [[cpuApps[0] mutableCopy] autorelease]; busyApp[@"cpu"] = @234;
        c.appStats = @[busyApp]; BattRefreshPopover(c,35,81);
        NSView *busyRow = consumerRows[0];
        assert([((NSTextField *)[busyRow valueForKey:@"_amount"]).stringValue isEqual:
            WattCPUUsageLabel(234,NSProcessInfo.processInfo.processorCount)]);
        assert(([((NSTextField *)[busyRow valueForKey:@"_relative"]).stringValue isEqual:
            [NSString stringWithFormat:@"2.34 / %lu cores",(unsigned long)NSProcessInfo.processInfo.processorCount]]));
        c.appStats = cpuApps; BattRefreshPopover(c,63,81);
        [FindButton(view,@"Memory") performClick:nil];
        Capture(view,directory,@"system-memory");
        NSArray *details = [view valueForKey:@"_details"];
        [(NSButton *)details[1] performClick:nil];
        assert([NSUserDefaults.standardUserDefaults integerForKey:@"WattNookMemoryUnits"] == 1);
        assert([((NSButton *)details[1]).title containsString:@"GB"]);
        assert([((NSButton *)details[0]).title containsString:@"%"]);
        [(NSButton *)details[0] performClick:nil];
        assert(![((NSButton *)details[0]).title containsString:@"%"]);
        [(NSButton *)details[2] performClick:nil];
        assert([((NSButton *)details[2]).title isEqual:@"73%"]);
        [(NSButton *)details[2] performClick:nil];
        assert([((NSButton *)details[2]).title isEqual:@"365 GB"]);
        Capture(view,directory,@"system-absolute");
        c.diskTotalBytes = 4000000000000; c.diskFreeBytes = 1000000000000;
        c.diskSpacePercent = 75;
        BattRefreshPopover(c,100,100);
        assert([((NSButton *)details[2]).title isEqual:@"3 TB"]);
        assert([((NSTextField *)[view valueForKey:@"_availableSpace"]).stringValue isEqual:@"Free 1 TB"]);
        Capture(view,directory,@"system-terabytes");
        NSArray *originalApps = c.appStats;
        NSMutableDictionary *largeApp = [[c.appStats[0] mutableCopy] autorelease];
        largeApp[@"memory"] = @(3.0*1024*1024*1024*1024);
        c.appStats = @[largeApp];
        BattRefreshPopover(c,100,100);
        NSArray *rows = [view valueForKey:@"_rows"];
        assert([((NSTextField *)[rows[0] valueForKey:@"_amount"]).stringValue isEqual:@"3 TB"]);
        for (NSString *key in @[@"_amount",@"_relative"]) {
            NSTextField *field = [rows[0] valueForKey:key];
            assert([field.stringValue sizeWithAttributes:@{NSFontAttributeName:field.font}].width <= field.frame.size.width);
        }
        Capture(view,directory,@"app-terabytes");
        c.appStats = originalApps;
        for (NSButton *detail in details)
            assert([detail.title sizeWithAttributes:@{NSFontAttributeName:detail.font}].width <= detail.frame.size.width-6);
        [(NSButton *)details[0] performClick:nil]; [(NSButton *)details[1] performClick:nil];
        [(NSButton *)details[2] performClick:nil];
        c.diskTotalBytes = 500000000000; c.diskFreeBytes = 135000000000;
        c.diskSpacePercent = 73;
        BattRefreshPopover(c,63,81);
        NSMutableArray *diskApps = [NSMutableArray array];
        for (NSDictionary *app in c.appStats) {
            NSMutableDictionary *sample = [[app mutableCopy] autorelease];
            sample[@"disk"] = @([sample[@"cpu"] doubleValue]*1000000);
            sample[@"diskRead"] = sample[@"disk"]; sample[@"diskWrite"] = @0;
            [diskApps addObject:sample];
        }
        c.appStats = diskApps;
        [FindButton(view,@"Disk") performClick:nil]; Capture(view,directory,@"system-disk");
        NSButton *gear = FindButton(view,@""); assert(gear);
        [gear performClick:nil]; assert(FindButton(view,@"SSD used")); Capture(view,directory,@"settings");
        [FindButton(view,@"Mint") performClick:nil];
        assert([[NSUserDefaults.standardUserDefaults stringForKey:@"WattNookPalette"] isEqual:@"Mint"]);
        [FindButton(view,@"Memory used") performClick:nil];
        [FindButton(view,@"SSD used") performClick:nil];
        [FindButton(view,@"Battery icon") performClick:nil];
        assert([WattMenuMetrics() isEqual:@[@"CPU"]] && !WattMenuBatteryIcon());
        [FindButton(view,@"CPU load") performClick:nil];
        assert(WattMenuMetrics().count == 0 && WattMenuBatteryIcon());
        [FindButton(view,@"Battery percentage") performClick:nil];
        [FindButton(view,@"Battery icon") performClick:nil];
        assert([WattMenuMetrics() isEqual:@[@"Battery"]] && !WattMenuBatteryIcon());
        [FindButton(view,@"Battery") performClick:nil];
        Capture(view,directory,@"palette-mint");
        [gear performClick:nil]; [FindButton(view,@"Blue") performClick:nil];
        [FindButton(view,@"Battery") performClick:nil];
        c.powerFlowView.pluggedIn = YES; c.powerFlowView.adapterWatts = 18.9;
        c.powerFlowView.batteryWatts = 0; c.powerFlowView.systemWatts = 18.9;
        c.powerFlowView.heatPaused = YES; c.powerFlowView.hasTelemetry = YES;
        [gear performClick:nil]; [FindButton(view,@"Mint") performClick:nil];
        [FindButton(view,@"Battery") performClick:nil]; Capture(view,directory,@"palette-mint");
        [gear performClick:nil]; [FindButton(view,@"Violet") performClick:nil];
        [FindButton(view,@"Battery") performClick:nil]; Capture(view,directory,@"palette-violet");
        [gear performClick:nil]; [FindButton(view,@"Amber") performClick:nil];
        [FindButton(view,@"Battery") performClick:nil]; Capture(view,directory,@"palette-amber");
        [gear performClick:nil]; [FindButton(view,@"Blue") performClick:nil];
        [FindButton(view,@"Battery") performClick:nil];
        BattApplyBatterySnapshot(c,@{@"ExternalConnected":@NO,@"InstantAmperage":@-900,
            @"Voltage":@12000,@"CurrentCapacity":@64,@"AppleRawMaxCapacity":@4003,@"DesignCapacity":@4629,
            @"CycleCount":@330,@"PowerTelemetryData":@{@"SystemPowerIn":@22000}});
        assert(!c.powerFlowView.pluggedIn && c.powerFlowView.adapterWatts == 0);
        assert(fabs(c.powerFlowView.batteryWatts+10.8)<0.0001);
        assert(fabs(c.powerFlowView.systemWatts-10.8)<0.0001);
        Capture(view,directory,@"unplug-transition");
        BattApplyBatterySnapshot(c,@{@"ExternalConnected":@NO,@"InstantAmperage":@0,
            @"Voltage":@12000,@"CurrentCapacity":@64});
        Capture(view,directory,@"transition-waiting");
        [FindButton(view,@"Battery") performClick:nil]; assert(!c.powerFlowView.hiddenOrHasHiddenAncestor);
        c.appStats = @[]; c.diskReadRate = -1; c.diskWriteRate = -1; c.swapUsedBytes = -1;
        BattRefreshPopover(c,-1,-1);
        [system performClick:nil]; Capture(view,directory,@"system-empty");
        BattUpdateStorage(c); assert(c.diskReadRate == -1);
        c.previousDiskSampleTime -= 1;
        BattUpdateStorage(c);
        assert(c.previousDiskCounters.count == 0 || (c.diskReadRate >= 0 && c.diskWriteRate >= 0));
        [c updateAppStats];
        CFAbsoluteTime busyUntil = CFAbsoluteTimeGetCurrent()+0.25;
        while (CFAbsoluteTimeGetCurrent() < busyUntil) { }
        [c updateAppStats];
        NSDictionary *selfSample = nil;
        for (NSDictionary *app in c.appStats)
            if ([app[@"pid"] intValue] == getpid()) selfSample = app;
        assert(selfSample != nil && ![selfSample[@"canQuit"] boolValue]);
        assert([selfSample[@"cpu"] doubleValue] > 50 && [selfSample[@"cpu"] doubleValue] < 250);
        NSLog(@"Live CPU sanity: one busy thread = %.1f%%; %lu readable processes",[selfSample[@"cpu"] doubleValue],(unsigned long)c.previousProcessCPU.count);
        [c updateSystemStats:nil]; assert(c.swapUsedBytes >= 0);
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
        for (NSString *key in @[@"WattNookPalette",@"WattNookMenuMetrics",@"WattNookMenuBatteryIcon",@"WattNookCPUUnits",@"WattNookMemoryUnits",@"WattNookDiskUnits"])
            [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
    }
    return 0;
}
