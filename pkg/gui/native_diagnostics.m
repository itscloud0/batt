#import "native_internal.h"
#import <libproc.h>
#import <unistd.h>

static NSString *MemoryLabel(double bytes) {
    if (bytes >= 1024.0 * 1024.0 * 1024.0)
        return [NSString stringWithFormat:@"%.1f GB", bytes / (1024.0 * 1024.0 * 1024.0)];
    return [NSString stringWithFormat:@"%.0f MB", bytes / (1024.0 * 1024.0)];
}

@implementation BattMenuController (Diagnostics)

- (void)updateAppStats {
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    NSTimeInterval elapsed = now - _previousProcessSampleTime;
    NSMutableDictionary<NSNumber *, NSNumber *> *nextCPU = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSNumber *, NSMutableDictionary *> *roots = [NSMutableDictionary dictionary];
    for (NSRunningApplication *app in NSWorkspace.sharedWorkspace.runningApplications) {
        pid_t pid = app.processIdentifier;
        NSString *bundleID = app.bundleIdentifier;
        NSString *path = app.bundleURL.path;
        if (pid <= 0 || pid == getpid() || app.isTerminated ||
            app.activationPolicy != NSApplicationActivationPolicyRegular ||
            bundleID.length == 0 || path.length == 0 ||
            [path hasPrefix:@"/System/"]) continue;
        roots[@(pid)] = [[@{
            @"pid": @(pid),
            @"bundle": bundleID,
            @"name": app.localizedName ?: bundleID,
            @"path": path,
            @"cpu": @0,
            @"memory": @0,
        } mutableCopy] autorelease];
    }

    int requiredBytes = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (requiredBytes <= 0) return;
    NSMutableData *pidData = [NSMutableData dataWithLength:requiredBytes + 4096];
    int countBytes = proc_listpids(PROC_ALL_PIDS, 0, pidData.mutableBytes, (int)pidData.length);
    if (countBytes <= 0) return;
    NSMutableDictionary<NSNumber *, NSDictionary *> *processes = [NSMutableDictionary dictionary];
    pid_t *pids = pidData.mutableBytes;
    for (NSInteger i = 0; i < countBytes / sizeof(pid_t); i++) {
        pid_t pid = pids[i];
        if (pid <= 0 || pid == getpid()) continue;
        struct proc_bsdinfo bsd = {0};
        struct proc_taskinfo task = {0};
        if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, sizeof(bsd)) != sizeof(bsd) ||
            bsd.pbi_uid != getuid() ||
            proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, sizeof(task)) != sizeof(task))
            continue;
        NSNumber *key = @(pid);
        uint64_t totalCPU = task.pti_total_user + task.pti_total_system;
        nextCPU[key] = @(totalCPU);
        NSNumber *previous = self.previousProcessCPU[key];
        double cpu = previous != nil && elapsed > 0 && totalCPU >= previous.unsignedLongLongValue
            ? (totalCPU - previous.unsignedLongLongValue) / (elapsed * 10000000.0) : 0;
        processes[key] = @{
            @"parent": @(bsd.pbi_ppid),
            @"cpu": @(cpu),
            @"memory": @(task.pti_resident_size),
        };
    }
    for (NSNumber *pid in processes) {
        NSDictionary *process = processes[pid];
        NSMutableDictionary *root = roots[pid];
        NSNumber *ancestor = process[@"parent"];
        for (NSInteger depth = 0; root == nil && depth < 20 && ancestor != nil; depth++) {
            root = roots[ancestor];
            ancestor = processes[ancestor][@"parent"];
        }
        if (root == nil) {
            char pathBuffer[PROC_PIDPATHINFO_MAXSIZE] = {0};
            if (proc_pidpath(pid.intValue, pathBuffer, sizeof(pathBuffer)) > 0) {
                NSString *processPath = [NSString stringWithUTF8String:pathBuffer];
                for (NSMutableDictionary *candidate in roots.allValues) {
                    NSString *prefix = [candidate[@"path"] stringByAppendingString:@"/Contents/"];
                    if ([processPath hasPrefix:prefix]) {
                        root = candidate;
                        break;
                    }
                }
            }
        }
        if (root == nil) continue;
        root[@"cpu"] = @([root[@"cpu"] doubleValue] + [process[@"cpu"] doubleValue]);
        root[@"memory"] = @([root[@"memory"] doubleValue] + [process[@"memory"] doubleValue]);
    }
    self.previousProcessCPU = nextCPU;
    self.appStats = roots.allValues;
    _previousProcessSampleTime = now;
}

- (void)populateDiagnosticMenu:(NSMenu *)menu byCPU:(BOOL)byCPU {
    [menu removeAllItems];
    NSString *sortKey = byCPU ? @"cpu" : @"memory";
    NSArray<NSDictionary *> *sorted = [self.appStats sortedArrayUsingComparator:
        ^NSComparisonResult(NSDictionary *first, NSDictionary *second) {
            return [second[sortKey] compare:first[sortKey]];
        }];
    if (sorted.count == 0) {
        NSMenuItem *empty = [[[NSMenuItem alloc] initWithTitle:@"No app data"
                                                       action:nil keyEquivalent:@""] autorelease];
        empty.enabled = NO;
        [menu addItem:empty];
        return;
    }
    for (NSDictionary *sample in [sorted subarrayWithRange:NSMakeRange(0, MIN(5, sorted.count))]) {
        NSString *amount = byCPU
            ? [NSString stringWithFormat:@"%.0f%%", [sample[@"cpu"] doubleValue]]
            : MemoryLabel([sample[@"memory"] doubleValue]);
        NSString *title = [NSString stringWithFormat:@"%@  ·  %@", sample[@"name"], amount];
        NSMenuItem *row = [[[NSMenuItem alloc] initWithTitle:title
                                                    action:@selector(quitDiagnosedApp:)
                                               keyEquivalent:@""] autorelease];
        NSString *detail = [NSString stringWithFormat:@"CPU %.0f%%  ·  RAM %@",
            [sample[@"cpu"] doubleValue], MemoryLabel([sample[@"memory"] doubleValue])];
        row.target = self;
        row.toolTip = [detail stringByAppendingString:@"  ·  Click to request Quit"];
        row.representedObject = sample;
        [menu addItem:row];
    }
}

- (void)updateDiagnosticMenus {
    [self populateDiagnosticMenu:self.cpuAppsMenu byCPU:YES];
    [self populateDiagnosticMenu:self.memoryAppsMenu byCPU:NO];
}

- (void)quitDiagnosedApp:(NSMenuItem *)sender {
    NSDictionary *sample = sender.representedObject;
    pid_t pid = [sample[@"pid"] intValue];
    NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    if (app == nil || app.isTerminated ||
        ![app.bundleIdentifier isEqualToString:sample[@"bundle"]] ||
        pid == getpid() || [app.bundleURL.path hasPrefix:@"/System/"]) return;

    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    alert.messageText = [NSString stringWithFormat:@"Quit %@?", sample[@"name"]];
    alert.informativeText = @"This sends a normal Quit request. The app may ask you to save unsaved work.";
    [alert addButtonWithTitle:@"Quit App"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    if (![app terminate]) {
        NSAlert *error = [[[NSAlert alloc] init] autorelease];
        error.messageText = @"Could not quit the app";
        error.informativeText = @"It may already have exited. No force quit was attempted.";
        [error runModal];
    }
}

@end
