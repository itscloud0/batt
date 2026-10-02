#import "native_internal.h"
#import <IOKit/IOKitLib.h>
#import <sys/mount.h>
#import <math.h>

double BattCounterRate(uint64_t previous, uint64_t current, double elapsed) {
    if (!isfinite(elapsed) || elapsed <= 0 || current < previous) return -1;
    return (current - previous) / elapsed;
}

void BattUpdateStorage(BattMenuController *controller) {
    NSMutableDictionary *counters = [NSMutableDictionary dictionary];
    io_iterator_t iterator = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(kIOMainPortDefault,
            IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS) {
        io_service_t service;
        while ((service = IOIteratorNext(iterator))) {
            // Only the built-in drive; external/hot-plugged volumes are not SSD load.
            CFTypeRef protocol = IORegistryEntrySearchCFProperty(service, kIOServicePlane,
                CFSTR("Protocol Characteristics"), kCFAllocatorDefault,
                kIORegistryIterateRecursively | kIORegistryIterateParents);
            BOOL internal = [(NSDictionary *)protocol isKindOfClass:NSDictionary.class] &&
                [[(NSDictionary *)protocol objectForKey:@"Physical Interconnect Location"]
                    isEqual:@"Internal"];
            if (protocol) CFRelease(protocol);
            CFTypeRef statistics = IORegistryEntryCreateCFProperty(service,
                CFSTR("Statistics"), kCFAllocatorDefault, 0);
            uint64_t identity = 0;
            if (internal && [(id)statistics isKindOfClass:NSDictionary.class] &&
                IORegistryEntryGetRegistryEntryID(service, &identity) == KERN_SUCCESS) {
                NSDictionary *stats = (NSDictionary *)statistics;
                if ([stats[@"Bytes (Read)"] isKindOfClass:NSNumber.class] &&
                    [stats[@"Bytes (Write)"] isKindOfClass:NSNumber.class])
                    counters[@(identity)] = @[stats[@"Bytes (Read)"], stats[@"Bytes (Write)"]];
            }
            if (statistics) CFRelease(statistics);
            IOObjectRelease(service);
        }
        IOObjectRelease(iterator);
    }
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    double elapsed = now - controller.previousDiskSampleTime;
    double read = 0, write = 0;
    // Key order is irrelevant when there is more than one internal drive.
    BOOL valid = counters.count > 0 && [NSSet setWithArray:counters.allKeys].count ==
        controller.previousDiskCounters.count &&
        [[NSSet setWithArray:counters.allKeys]
            isEqualToSet:[NSSet setWithArray:controller.previousDiskCounters.allKeys ?: @[]]];
    for (NSNumber *key in counters) {
        NSArray *previous = controller.previousDiskCounters[key];
        NSArray *current = counters[key];
        if (!previous) { valid = NO; continue; }
        double r = BattCounterRate([previous[0] unsignedLongLongValue],
            [current[0] unsignedLongLongValue], elapsed);
        double w = BattCounterRate([previous[1] unsignedLongLongValue],
            [current[1] unsignedLongLongValue], elapsed);
        if (r < 0 || w < 0) valid = NO;
        read += r; write += w;
    }
    controller.diskReadRate = valid ? read : -1;
    controller.diskWriteRate = valid ? write : -1;
    controller.previousDiskCounters = counters;
    controller.previousDiskSampleTime = now;
    struct statfs volume;
    controller.diskTotalBytes = controller.diskFreeBytes = 0;
    controller.diskSpacePercent = -1;
    if (statfs("/System/Volumes/Data", &volume) == 0 && volume.f_blocks > 0) {
        controller.diskTotalBytes = volume.f_blocks * (uint64_t)volume.f_bsize;
        controller.diskFreeBytes = volume.f_bavail * (uint64_t)volume.f_bsize;
        controller.diskSpacePercent = 100.0 * (1 -
            volume.f_bavail / (double)volume.f_blocks);
    }
}
