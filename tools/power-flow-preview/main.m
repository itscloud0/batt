#import "../../pkg/gui/native_internal.h"

// Render fake power states without touching the daemon or the actual charge limit.
int main(int argc, const char *argv[]) {
    if (argc != 2) return 2;
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *directory = [NSString stringWithUTF8String:argv[1]];
        [[NSFileManager defaultManager] createDirectoryAtPath:directory
                                  withIntermediateDirectories:YES attributes:nil error:nil];
        NSArray<NSDictionary *> *states = @[
            @{ @"name": @"battery", @"charge": @48, @"plug": @NO,
               @"adapter": @0, @"battery": @-9.4, @"system": @9.4, @"heat": @NO },
            @{ @"name": @"charging", @"charge": @57, @"plug": @YES,
               @"adapter": @36, @"battery": @15.8, @"system": @20.2, @"heat": @NO },
            @{ @"name": @"limit-held", @"charge": @80, @"plug": @YES,
               @"adapter": @21, @"battery": @0, @"system": @21, @"heat": @NO },
            @{ @"name": @"heat-held", @"charge": @48, @"plug": @YES,
               @"adapter": @13, @"battery": @0, @"system": @13, @"heat": @YES },
            @{ @"name": @"hybrid", @"charge": @70, @"plug": @YES,
               @"adapter": @11.1, @"battery": @-5.5, @"system": @16.6, @"heat": @NO },
            @{ @"name": @"unavailable", @"charge": @70, @"plug": @NO,
               @"adapter": @0, @"battery": @0, @"system": @0, @"heat": @NO },
        ];
        for (NSDictionary *state in states) {
            NSWindow *window = [[NSWindow alloc]
                initWithContentRect:NSMakeRect(0, 0, 340, 188)
                          styleMask:NSWindowStyleMaskBorderless
                            backing:NSBackingStoreBuffered defer:NO];
            window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
            BattPowerFlowView *view = [[BattPowerFlowView alloc]
                initWithFrame:NSMakeRect(0, 0, 340, 188)];
            view.chargePercent = [state[@"charge"] integerValue];
            view.limitPercent = 80;
            view.pluggedIn = [state[@"plug"] boolValue];
            view.adapterWatts = [state[@"adapter"] doubleValue];
            view.batteryWatts = [state[@"battery"] doubleValue];
            view.systemWatts = [state[@"system"] doubleValue];
            view.heatPaused = [state[@"heat"] boolValue];
            view.temperatureCelsius = 32.4;
            view.hasTelemetry = ![state[@"name"] isEqualToString:@"unavailable"];
            [window.contentView addSubview:view];
            [view displayIfNeeded];
            NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
            [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
            NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            NSString *path = [directory stringByAppendingPathComponent:
                [state[@"name"] stringByAppendingString:@".png"]];
            [png writeToFile:path atomically:YES];
            [view release];
            [window release];
        }
    }
    return 0;
}
