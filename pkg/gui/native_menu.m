#import "native_internal.h"
#import <mach/mach.h>
#import <sys/mount.h>
#import <sys/sysctl.h>

static const NSTimeInterval BattMenuUpdateInterval = 10.0;

static NSColor *WattBatteryColor(NSInteger charge, BOOL pluggedIn) {
    return !pluggedIn && charge <= 20 ? NSColor.systemRedColor
        : ([NSProcessInfo processInfo].lowPowerModeEnabled
            ? NSColor.systemYellowColor : NSColor.whiteColor);
}

// Tahoe-style glyph: the percentage sits inside the battery, knocked out of
// the fill and drawn solid over the empty part. Power state moves outside.
static NSImage *WattPercentBatteryGlyph(NSInteger charge, BOOL pluggedIn, BOOL charging) {
    charge = MAX(0, MIN(100, charge));
    NSBundle *controlCenter = [NSBundle bundleWithPath:@"/System/Library/CoreServices/ControlCenter.app"];
    NSImage *outline = [controlCenter imageForResource:@"battery-outline"];
    NSImage *cap = [controlCenter imageForResource:@"battery-cap"];
    NSImage *power = !pluggedIn ? nil :
        [NSImage imageWithSystemSymbolName:charging ? @"bolt.fill" : @"powerplug.fill"
                  accessibilityDescription:nil];
    NSImage *image = [[[NSImage alloc] initWithSize:NSMakeSize(power ? 34 : 25, 14)] autorelease];
    [image lockFocus];
    [NSColor.blackColor set];
    CGFloat fillEnd = 2 + 19.0 * charge / 100.0;
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(2, 3, fillEnd - 2, 8)
                                     xRadius:1.5 yRadius:1.5] fill];
    if (outline != nil && cap != nil) {
        [outline drawInRect:NSMakeRect(0, 1, 23, 12) fromRect:NSZeroRect
                 operation:NSCompositingOperationSourceOver fraction:1];
        [cap drawInRect:NSMakeRect(23, 1, 2, 12) fromRect:NSZeroRect
             operation:NSCompositingOperationSourceOver fraction:1];
    } else {
        NSBezierPath *body = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0.5, 1.5, 22, 11)
                                                             xRadius:3 yRadius:3];
        body.lineWidth = 1;
        [body stroke];
        NSRectFill(NSMakeRect(23, 5, 1.5, 4));
    }
    NSFont *font = [NSFont monospacedDigitSystemFontOfSize:charge == 100 ? 7 : 8.5
                                                    weight:NSFontWeightBold];
    NSString *text = [NSString stringWithFormat:@"%ld", (long)charge];
    NSDictionary *style = @{NSFontAttributeName:font,
                            NSForegroundColorAttributeName:NSColor.blackColor};
    NSSize size = [text sizeWithAttributes:style];
    NSPoint origin = NSMakePoint(2 + (19 - size.width) / 2,
                                 7 - font.capHeight / 2 + font.descender);
    NSGraphicsContext *context = NSGraphicsContext.currentContext;
    context.compositingOperation = NSCompositingOperationDestinationOut;
    [text drawAtPoint:origin withAttributes:style];
    context.compositingOperation = NSCompositingOperationSourceOver;
    [NSGraphicsContext saveGraphicsState];
    NSRectClip(NSMakeRect(fillEnd, 0, 23 - fillEnd, 14));
    [text drawAtPoint:origin withAttributes:style];
    [NSGraphicsContext restoreGraphicsState];
    if (power) [power drawInRect:NSMakeRect(27, 2.5, 7, 9) fromRect:NSZeroRect
                       operation:NSCompositingOperationSourceOver fraction:1];
    [WattBatteryColor(charge, pluggedIn) setFill];
    NSRectFillUsingOperation(NSMakeRect(0, 0, image.size.width, 14),
                             NSCompositingOperationSourceAtop);
    [image unlockFocus];
    return image;
}

static NSMenuItem *ActionItem(BattMenuController *controller,
                              NSString *title,
                              NSString *key,
                              BattMenuItem identifier) {
    NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:title
                                                  action:@selector(menuAction:)
                                           keyEquivalent:key] autorelease];
    item.target = controller;
    item.tag = identifier;
    [controller rememberItem:item as:identifier];
    return item;
}

static NSMenuItem *DisplayItem(BattMenuController *controller,
                               NSString *title,
                               BattMenuItem identifier,
                               BOOL enabled) {
    NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:title
                                                  action:@selector(noop:)
                                           keyEquivalent:@""] autorelease];
    item.target = controller;
    item.tag = identifier;
    item.enabled = enabled;
    [controller rememberItem:item as:identifier];
    return item;
}

static NSMenu *AddSubmenu(BattMenuController *controller,
                          NSMenu *parent,
                          NSString *title,
                          BattMenuItem identifier) {
    NSMenu *submenu = [[[NSMenu alloc] initWithTitle:title] autorelease];
    submenu.autoenablesItems = NO;
    NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:title
                                                  action:nil
                                           keyEquivalent:@""] autorelease];
    item.submenu = submenu;
    [controller rememberItem:item as:identifier];
    [parent addItem:item];
    return submenu;
}

@implementation BattMenuController

- (instancetype)initWithHandle:(uintptr_t)handle version:(NSString *)version {
    self = [super init];
    if (self) {
        _handle = handle;
        _items = [[NSMutableDictionary alloc] init];
        _menu = [[NSMenu alloc] initWithTitle:@"batt"];
        _menu.autoenablesItems = NO;
        _menu.delegate = self;
        _statusItem = [[[NSStatusBar systemStatusBar]
            statusItemWithLength:NSVariableStatusItemLength] retain];
        _statusItem.autosaveName = @"BattThermalCombinedStatus";
        _cpuPercent = -1;
        _memoryPercent = -1;
        _swapUsedBytes = -1;
        _diskPercent = -1;
        _diskReadRate = -1;
        _diskWriteRate = -1;
        _diskSpacePercent = -1;
        _powerFlowView = [[BattPowerFlowView alloc] initWithFrame:NSMakeRect(0, 0, 340, 220)];

        BattBuildMenu(self, version);
        BattApplyTooltips(self);
        [self buildPopover];
        _statusItem.button.target = self;
        _statusItem.button.action = @selector(togglePopover:);
        [_statusItem.button sendActionOn:NSEventMaskLeftMouseUp | NSEventMaskRightMouseUp];
        [self setStatusIconInstalled:NO capable:NO needsUpgrade:NO];
        _timer = [[NSTimer scheduledTimerWithTimeInterval:BattMenuUpdateInterval
                                                   target:self
                                                 selector:@selector(timerTick:)
                                                 userInfo:nil
                                                  repeats:YES] retain];
        _timer.tolerance = 1.0;
        [self applyMonitoringPreferences];
    }
    return self;
}

- (void)dealloc {
    [_timer invalidate];
    [_timer release];
    [_statsTimer invalidate];
    [_statsTimer release];
    _menu.delegate = nil;
    [[NSStatusBar systemStatusBar] removeStatusItem:_statusItem];
    [_statusItem release];
    [_batteryIcon release];
    [_powerFlowView release];
    [_popover release];
    [_chargeButton release];
    [_heatButton release];
    [_darkButton release];
    [_keepAwakeStatus release];
    [_lidGuard release];
    [_keepAwakeError release];
    [_lidGuardError release];
    [_metricHistory release];
    [_statsButton release];
    [_memoryButton release];
    [_diskButton release];
    [_cpuTopAppLabel release];
    [_memoryTopAppLabel release];
    [_cpuQuitButton release];
    [_memoryQuitButton release];
    [_cpuFeaturedApp release];
    [_memoryFeaturedApp release];
    [_cpuAppsMenu release];
    [_memoryAppsMenu release];
    [_appStats release];
    [_previousProcessCPU release];
    [_previousProcessDisk release];
    [_previousDiskCounters release];
    [_menu release];
    [_items release];
    [super dealloc];
}

- (NSMenuItem *)item:(BattMenuItem)item {
    return [_items objectForKey:[NSNumber numberWithInteger:item]];
}

- (void)rememberItem:(NSMenuItem *)item as:(BattMenuItem)identifier {
    [_items setObject:item forKey:[NSNumber numberWithInteger:identifier]];
}

- (void)menuAction:(NSMenuItem *)sender {
    BattMenuItem identifier = (BattMenuItem)sender.tag;
    switch (identifier) {
        case BattItemMagSafeEnabled:
        case BattItemMagSafeDisabled:
        case BattItemMagSafeAlwaysOff:
            [self item:BattItemMagSafeEnabled].state = identifier == BattItemMagSafeEnabled
                ? NSControlStateValueOn : NSControlStateValueOff;
            [self item:BattItemMagSafeDisabled].state = identifier == BattItemMagSafeDisabled
                ? NSControlStateValueOn : NSControlStateValueOff;
            [self item:BattItemMagSafeAlwaysOff].state = identifier == BattItemMagSafeAlwaysOff
                ? NSControlStateValueOn : NSControlStateValueOff;
            break;
        case BattItemHeatOff:
        case BattItemHeatStrict:
        case BattItemHeatBalanced:
        case BattItemHeatRelaxed:
            [self item:BattItemHeatOff].state = identifier == BattItemHeatOff
                ? NSControlStateValueOn : NSControlStateValueOff;
            [self item:BattItemHeatStrict].state = identifier == BattItemHeatStrict
                ? NSControlStateValueOn : NSControlStateValueOff;
            [self item:BattItemHeatBalanced].state = identifier == BattItemHeatBalanced
                ? NSControlStateValueOn : NSControlStateValueOff;
            [self item:BattItemHeatRelaxed].state = identifier == BattItemHeatRelaxed
                ? NSControlStateValueOn : NSControlStateValueOff;
            break;
        case BattItemKeepAwake:
            [self toggleKeepAwake];
            return;
        case BattItemHeatCustom:
            [self setCustomHeatProtection];
            return;
        case BattItemPreventIdleSleep:
        case BattItemDisableChargingPreSleep:
        case BattItemPreventSystemSleep:
            sender.state = sender.state == NSControlStateValueOff
                ? NSControlStateValueOn : NSControlStateValueOff;
            break;
        default:
            break;
    }
    battMenuAction(_handle, identifier, sender.state == NSControlStateValueOn);
}

- (void)noop:(NSMenuItem *)sender {
    (void)sender;
}

- (void)menuWillOpen:(NSMenu *)menu {
    if (menu == self.menu) [self updateDiagnosticMenus];
    battMenuWillOpen(_handle);
}

- (void)buildPopover {
    BattBuildPopover(self);
    [self refreshPopoverControls];
}


- (void)togglePopover:(id)sender {
    (void)sender;
    NSEvent *event = [NSApp currentEvent];
    if (event.type == NSEventTypeRightMouseUp) {
        [self.popover close];
        battMenuWillOpen(_handle);
        [self updateDiagnosticMenus];
        [self showMenu:self.menu fromButton:self.statusItem.button];
        return;
    }
    if (self.popover.isShown) {
        [self.popover close];
        return;
    }
    battMenuWillOpen(_handle);
    if (self.systemPageVisible) [self updateAppStats];
    [self refreshPopoverControls];
    [NSApp activateIgnoringOtherApps:YES];
    [self.popover showRelativeToRect:self.statusItem.button.bounds
                             ofView:self.statusItem.button
                      preferredEdge:NSRectEdgeMinY];
}

- (void)popoverDidShow:(NSNotification *)notification {
    (void)notification;
    self.powerFlowView.flowAnimationEnabled = !self.powerFlowView.hiddenOrHasHiddenAncestor;
}

- (void)popoverDidClose:(NSNotification *)notification {
    (void)notification;
    self.powerFlowView.flowAnimationEnabled = NO;
    self.previousProcessCPU = nil; self.previousProcessDisk = nil;
    _previousProcessSampleTime = 0;
}

- (void)showMenu:(NSMenu *)menu fromButton:(NSButton *)button {
    if (menu == nil) return;
    battMenuWillOpen(_handle);
    [menu popUpMenuPositioningItem:nil
                       atLocation:NSMakePoint(0, NSHeight(button.bounds))
                           inView:button];
    [self refreshPopoverControls];
}

- (void)showChargeLimits:(NSButton *)sender {
    [self showMenu:[self item:BattItemQuickLimits].submenu fromButton:sender];
}

- (void)showHeatOptions:(NSButton *)sender {
    [self showMenu:[self item:BattItemHeatProtection].submenu fromButton:sender];
}

- (void)showDiagnostics:(NSButton *)sender {
    [self updateDiagnosticMenus];
    NSMenu *diagnostics = [self.menu itemWithTitle:@"Diagnostics"].submenu;
    [self showMenu:diagnostics fromButton:sender];
}

- (void)showCPUApps:(NSButton *)sender {
    [self updateDiagnosticMenus];
    [self showMenu:self.cpuAppsMenu fromButton:sender];
}

- (void)showMemoryApps:(NSButton *)sender {
    [self updateDiagnosticMenus];
    [self showMenu:self.memoryAppsMenu fromButton:sender];
}

- (void)showMoreMenu:(NSButton *)sender {
    [self showMenu:self.menu fromButton:sender];
}

- (void)showKeepAwakeDiagnostics:(id)sender {
    (void)sender;
    [self isKeepAwakeActive];
    NSString *report = WattAwakeReport(self);
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    alert.messageText = @"Keep Awake diagnostics";
    alert.informativeText = @"Last 64 local events: sleep-setting changes and display-guard activity. No network or input data.";
    NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,480,280)] autorelease];
    scroll.hasVerticalScroller = YES;
    NSTextView *text = [[[NSTextView alloc] initWithFrame:scroll.bounds] autorelease];
    text.editable = NO; text.selectable = YES; text.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    text.string = report; text.verticallyResizable = YES;
    text.textContainer.widthTracksTextView = YES;
    scroll.documentView = text; alert.accessoryView = scroll;
    [alert addButtonWithTitle:@"Close"]; [alert addButtonWithTitle:@"Copy report"];
    if ([alert runModal] == NSAlertSecondButtonReturn) {
        [NSPasteboard.generalPasteboard clearContents];
        [NSPasteboard.generalPasteboard setString:report forType:NSPasteboardTypeString];
    }
}

- (void)toggleKeepAwakeFromPopover:(NSButton *)sender {
    (void)sender;
    [self toggleKeepAwake];
    [self refreshPopoverControls];
}

- (void)quitFeaturedApp:(NSButton *)sender {
    NSDictionary *sample = sender.tag == 0 ? self.cpuFeaturedApp : self.memoryFeaturedApp;
    if (sample == nil) return;
    NSMenuItem *request = [[[NSMenuItem alloc] initWithTitle:@"Quit"
                                                    action:nil keyEquivalent:@""] autorelease];
    request.representedObject = sample;
    [self quitDiagnosedApp:request];
    [self updateAppStats];
    [self refreshPopoverControls];
}

- (void)commitLimitFromRail:(BattPowerFlowView *)sender {
    NSInteger requested = sender.displayedLimitPercent;
    if (!battMenuSetLimit(_handle, (int)requested)) {
        sender.limitPercent = sender.limitPercent;
    }
    [self refreshPopoverControls];
}

- (void)refreshPopoverControls {
    BattRefreshPopover(self, _cpuPercent, _memoryPercent);
}


- (void)menuDidClose:(NSMenu *)menu {
    (void)menu;
}

- (void)timerTick:(NSTimer *)timer {
    (void)timer;
    battMenuTimerFired(_handle);
    if (!WattMonitoringEnabled()) BattUpdateBattery(self);
    [self isKeepAwakeActive];
}

- (void)applyMonitoringPreferences {
    if (WattMonitoringEnabled()) {
        if (!_statsTimer) {
            self.statsTimer = [NSTimer scheduledTimerWithTimeInterval:2 target:self
                selector:@selector(updateSystemStats:) userInfo:nil repeats:YES];
            self.statsTimer.tolerance = 0.25;
        }
        if (WattHistoryEnabled() && !self.metricHistory) self.metricHistory = [[[WattMetricHistory alloc] init] autorelease];
        if (!WattHistoryEnabled()) self.metricHistory = nil;
        [self updateSystemStats:nil];
    } else {
        [self.statsTimer invalidate]; self.statsTimer = nil;
        self.metricHistory = nil; self.appStats = nil;
        self.cpuFeaturedApp = nil; self.memoryFeaturedApp = nil;
        [self.cpuAppsMenu removeAllItems]; [self.memoryAppsMenu removeAllItems];
        self.previousProcessCPU = nil; self.previousProcessDisk = nil;
        self.previousDiskCounters = nil; self.previousDiskSampleTime = 0;
        _hasCPUSample = NO; _previousProcessSampleTime = 0;
        _cpuPercent = _memoryPercent = _diskPercent = -1;
        self.diskReadRate = self.diskWriteRate = self.diskSpacePercent = -1;
        self.diskTotalBytes = self.diskFreeBytes = 0;
        self.swapUsedBytes = -1; self.memoryPressure = 0; self.memoryPressureSince = 0;
    }
    [self refreshStatusImage]; [self refreshPopoverControls];
}

- (void)updateSystemStats:(NSTimer *)timer {
    (void)timer;
    if (!WattMonitoringEnabled()) return;
    _cpuPercent = _memoryPercent = -1;
    host_t host = mach_host_self();
    host_cpu_load_info_data_t cpu;
    mach_msg_type_number_t cpuCount = HOST_CPU_LOAD_INFO_COUNT;
    if (host_statistics(host, HOST_CPU_LOAD_INFO,
                        (host_info_t)&cpu, &cpuCount) == KERN_SUCCESS) {
        uint64_t totalDelta = 0;
        uint64_t busyDelta = 0;
        for (NSInteger i = 0; i < CPU_STATE_MAX; i++) {
            uint64_t tick = cpu.cpu_ticks[i];
            uint64_t delta = tick >= _previousCPUTicks[i] ? tick - _previousCPUTicks[i] : 0;
            totalDelta += delta;
            if (i != CPU_STATE_IDLE) busyDelta += delta;
            _previousCPUTicks[i] = tick;
        }
        if (_hasCPUSample && totalDelta > 0)
            _cpuPercent = 100.0 * busyDelta / totalDelta;
        _hasCPUSample = YES;
    } else _hasCPUSample = NO;

    vm_statistics64_data_t memory;
    mach_msg_type_number_t memoryCount = HOST_VM_INFO64_COUNT;
    if (host_statistics64(host, HOST_VM_INFO64,
                          (host_info64_t)&memory, &memoryCount) == KERN_SUCCESS) {
        uint64_t total = [NSProcessInfo processInfo].physicalMemory;
        uint64_t available = ((uint64_t)memory.free_count +
                              (uint64_t)memory.inactive_count +
                              (uint64_t)memory.speculative_count) * (uint64_t)vm_page_size;
        if (total > 0)
            _memoryPercent = 100.0 * (1.0 - MIN(available, total) / (double)total);
    }
    mach_port_deallocate(mach_task_self(),host);
    NSInteger pressure = WattMemoryPressureLevel();
    if (pressure != self.memoryPressure || !self.memoryPressureSince)
        self.memoryPressureSince = NSDate.timeIntervalSinceReferenceDate;
    self.memoryPressure = pressure;

    struct xsw_usage swap = {0};
    size_t swapSize = sizeof(swap);
    self.swapUsedBytes = sysctlbyname("vm.swapusage", &swap, &swapSize, NULL, 0) == 0 &&
        swapSize == sizeof(swap) ? (double)swap.xsu_used : -1;
    BattUpdateStorage(self);
    BattUpdateBattery(self);
    _diskPercent = self.diskSpacePercent;
    if (self.metricHistory) {
        double watts = self.powerFlowView.systemWatts;
        BOOL inconsistent = self.powerFlowView.batteryWatts > 0.25 &&
            (self.powerFlowView.adapterWatts < self.powerFlowView.batteryWatts+0.5 || watts < 0.5);
        if (!self.powerFlowView.hasTelemetry || inconsistent || watts <= 0.05) watts = NAN;
        double disk = self.diskReadRate < 0 || self.diskWriteRate < 0 ? NAN : (self.diskReadRate+self.diskWriteRate)/1000000;
        [self.metricHistory append:(WattMetricSample){NSDate.timeIntervalSinceReferenceDate,_cpuPercent,_memoryPercent,watts,disk}];
    }
    [self refreshStatusImage];
    // Per-process scans are only useful while the app list is visible.
    if (self.popover.isShown && self.systemPageVisible)
        [self updateAppStats];
    if (self.popover.isShown) [self refreshPopoverControls];
}

- (void)refreshStatusImage {
    NSArray *metrics = WattMenuMetrics();
    NSMutableArray *labels = [NSMutableArray array], *values = [NSMutableArray array];
    for (NSString *metric in @[@"CPU",@"RAM",@"SSD"]) {
        if (![metrics containsObject:metric]) continue;
        [labels addObject:metric];
        if ([metric isEqual:@"SSD"]) {
            [values addObject:self.diskSpacePercent < 0 ? @"—" :
                [NSString stringWithFormat:@"%.0f%%",self.diskSpacePercent]];
        } else {
            double value = [metric isEqual:@"CPU"] ? _cpuPercent : _memoryPercent;
            [values addObject:value < 0 ? @"—" : [NSString stringWithFormat:@"%.0f%%",value]];
        }
    }
    BOOL percent = [metrics containsObject:@"Battery"];
    BOOL icon = WattMenuBatteryIcon() || (labels.count == 0 && !percent);
    CGFloat fontSize = labels.count > 1 ? 8.5 : 11;
    NSDictionary *attributes = @{
        NSFontAttributeName:[NSFont monospacedDigitSystemFontOfSize:fontSize weight:NSFontWeightMedium],
        NSForegroundColorAttributeName:NSColor.whiteColor};
    CGFloat labelWidth = 0, valueWidth = 0;
    for (NSString *label in labels) labelWidth = MAX(labelWidth,[label sizeWithAttributes:attributes].width);
    for (NSString *value in values) valueWidth = MAX(valueWidth,[value sizeWithAttributes:attributes].width);
    CGFloat stackWidth = labels.count ? ceil(labelWidth+5+valueWidth)+3 : 0;
    NSString *charge = self.powerFlowView.chargePercent < 0 ? @"—%" :
        [NSString stringWithFormat:@"%ld%%",(long)self.powerFlowView.chargePercent];
    NSDictionary *chargeStyle = @{NSFontAttributeName:
        [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName:NSColor.whiteColor};
    // Icon + battery percentage: draw the number inside the battery, like macOS.
    BOOL inside = percent && icon && self.powerFlowView.chargePercent >= 0;
    BOOL percentText = percent && !inside;
    NSImage *glyph = inside ? WattPercentBatteryGlyph(self.powerFlowView.chargePercent,
        self.powerFlowView.pluggedIn, _statusCharging) : self.batteryIcon;
    CGFloat glyphWidth = glyph ? glyph.size.width : 25;
    CGFloat percentGap = percentText && labels.count ? 10 : 0;
    CGFloat percentWidth = percentText ? percentGap+ceil([charge sizeWithAttributes:chargeStyle].width)+4 : 0;
    CGFloat iconGap = icon && (labels.count || percentText) ? 8 : 0;
    NSImage *combined = [[[NSImage alloc] initWithSize:
        NSMakeSize(MAX(24,stackWidth+percentWidth+iconGap+(icon ? glyphWidth+1 : 0)),24)] autorelease];
    [combined lockFocus];
    CGFloat height = [@"100%" sizeWithAttributes:attributes].height;
    for (NSInteger i=0;i<labels.count;i++) {
        CGFloat y = (24-height)/2 + ((labels.count-1)/2.0-i)*8;
        [labels[i] drawAtPoint:NSMakePoint(1,y) withAttributes:attributes];
        [values[i] drawAtPoint:NSMakePoint(labelWidth+6,y) withAttributes:attributes];
    }
    if (percentText) [charge drawAtPoint:NSMakePoint(stackWidth+percentGap,
        (24-[charge sizeWithAttributes:chargeStyle].height)/2) withAttributes:chargeStyle];
    if (icon) [glyph drawInRect:NSMakeRect(stackWidth+percentWidth+iconGap,5,glyphWidth,14)
        fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
    [combined unlockFocus];
    self.statusItem.button.image = combined;
    self.statusItem.button.title = @"";
    NSMutableArray *descriptions = [NSMutableArray arrayWithObject:@"WattNook"];
    for (NSInteger i=0;i<labels.count;i++)
        [descriptions addObject:[NSString stringWithFormat:@"%@ %@",
            [labels[i] isEqual:@"SSD"] ? @"SSD space used" : labels[i],values[i]]];
    if (percent) [descriptions addObject:[@"Battery " stringByAppendingString:charge]];
    self.statusItem.button.accessibilityLabel = [descriptions componentsJoinedByString:@", "];
}

- (void)setStatusIconInstalled:(BOOL)installed
                       capable:(BOOL)capable
                  needsUpgrade:(BOOL)needsUpgrade {
    NSString *symbol = @"minus.plus.batteryblock";
    NSString *description = @"batt icon";
    if (!installed) {
        symbol = @"batteryblock.slash";
        description = @"batt daemon not installed";
    } else if (!capable) {
        symbol = @"minus.plus.batteryblock.exclamationmark";
        description = @"Your machine cannot run batt";
    } else if (needsUpgrade) {
        symbol = @"fluid.batteryblock";
        description = @"batt needs upgrade";
    }
    self.statusItem.button.image = [NSImage imageWithSystemSymbolName:symbol
                                            accessibilityDescription:description];
    self.statusItem.button.title = @"";
    self.statusItem.button.contentTintColor = nil;
}

- (void)setLiveStatusCharge:(NSInteger)charge
                   pluggedIn:(BOOL)pluggedIn
                    charging:(BOOL)charging
                 heatPaused:(BOOL)heatPaused {
    charge = MAX(0, MIN(100, charge));
    NSBundle *controlCenter = [NSBundle bundleWithPath:@"/System/Library/CoreServices/ControlCenter.app"];
    NSImage *outline = [controlCenter imageForResource:@"battery-outline"];
    NSImage *cap = [controlCenter imageForResource:@"battery-cap"];
    NSString *overlayName = !pluggedIn ? nil : (charging ? @"battery-bolt" : @"battery-plug");
    NSImage *overlay = overlayName == nil ? nil : [controlCenter imageForResource:overlayName];
    NSImage *mask = overlayName == nil ? nil :
        [controlCenter imageForResource:[overlayName stringByAppendingString:@"-mask"]];
    NSImage *image = nil;
    if (outline != nil && cap != nil) {
        image = [[[NSImage alloc] initWithSize:NSMakeSize(25, 14)] autorelease];
        [image lockFocus];
        [NSColor.blackColor setFill];
        NSRect fill = NSMakeRect(2, 3, 19.0 * charge / 100.0, 8);
        [NSBezierPath fillRect:fill];
        if (mask != nil) {
            [mask drawInRect:NSMakeRect(7, 0, 11, 14) fromRect:NSZeroRect
                  operation:NSCompositingOperationDestinationOut fraction:1];
        }
        [outline drawInRect:NSMakeRect(0, 1, 23, 12) fromRect:NSZeroRect
                 operation:NSCompositingOperationSourceOver fraction:1];
        [cap drawInRect:NSMakeRect(23, 1, 2, 12) fromRect:NSZeroRect
             operation:NSCompositingOperationSourceOver fraction:1];
        if (overlay != nil) {
            [overlay drawInRect:NSMakeRect(7, 0, 11, 14) fromRect:NSZeroRect
                     operation:NSCompositingOperationSourceOver fraction:1];
        }
        [image unlockFocus];
    } else {
        image = [NSImage imageWithSystemSymbolName:@"battery.100percent"
                         accessibilityDescription:@"Battery"];
    }
    // Keep Control Center's exact outlines, but render them as a fixed white
    // glyph: NSStatusBar does not reliably tint a composed template image.
    [image lockFocus];
    [WattBatteryColor(charge, pluggedIn) setFill];
    NSRectFillUsingOperation(NSMakeRect(0, 0, image.size.width, image.size.height),
                             NSCompositingOperationSourceAtop);
    [image unlockFocus];
    image.template = NO;
    self.batteryIcon = image;
    // The status image reads these, so set them before redrawing it.
    _statusCharging = charging;
    self.powerFlowView.chargePercent = charge;
    self.powerFlowView.pluggedIn = pluggedIn;
    [self refreshStatusImage];
    self.statusItem.button.contentTintColor = nil;
    NSString *state = heatPaused && pluggedIn ? @"heat protection paused charging" :
        (charging ? @"charging" : (pluggedIn ? @"plugged in, not charging" : @"on battery"));
    self.statusItem.button.toolTip = [NSString stringWithFormat:@"Battery %ld%%, %@", (long)charge, state];
    self.statusItem.button.accessibilityLabel = self.statusItem.button.toolTip;
    self.powerFlowView.heatPaused = heatPaused;
    [self.powerFlowView setNeedsDisplay:YES];
    [self refreshPopoverControls];
}

- (void)setPowerFlowAdapter:(double)adapter
                     system:(double)system
                    battery:(double)battery
                 heatPaused:(BOOL)heatPaused
                temperature:(double)temperature {
    NSString *summary = nil;
    BOOL inconsistent = battery > 0.25 &&
        (adapter < battery + 0.5 || system < 0.5);
    if (inconsistent) {
        summary = @"Power readings updating: adapter and battery data disagree";
        [self item:BattItemPowerSystem].attributedTitle = nil;
        [self item:BattItemPowerSystem].title = @"System: unavailable";
    } else if (adapter > 0.1) {
        summary = [NSString stringWithFormat:@"%.1f W adapter  →  %.1f W Mac", adapter, system];
    } else if (battery < -0.1) {
        summary = [NSString stringWithFormat:@"%.1f W battery  →  %.1f W Mac", fabs(battery), system];
    } else {
        summary = [NSString stringWithFormat:@"%.1f W powering the Mac", system];
    }
    [self item:BattItemPowerFlowSummary].title = summary;
    self.powerFlowView.accessibilityLabel = summary;
    if (heatPaused && adapter > 0.1) {
        [self item:BattItemPowerBattery].title = [NSString stringWithFormat:@"Battery held: %.1f°C", temperature];
    }
    self.powerFlowView.adapterWatts = adapter;
    self.powerFlowView.systemWatts = system;
    self.powerFlowView.batteryWatts = battery;
    self.powerFlowView.temperatureCelsius = temperature;
    self.powerFlowView.heatPaused = heatPaused;
    self.powerFlowView.hasTelemetry = YES;
    [self.powerFlowView setNeedsDisplay:YES];
}

- (void)setLimitPercent:(NSInteger)limitPercent {
    self.powerFlowView.limitPercent = limitPercent;
    [self.powerFlowView setNeedsDisplay:YES];
}

- (NSString *)keepAwakeToolPath {
    return [[NSBundle mainBundle] pathForAuxiliaryExecutable:@"KeepAwake"];
}

- (BOOL)isKeepAwakeActive {
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (self.keepAwakeStatusTime == 0 || now - self.keepAwakeStatusTime >= 10) {
        NSNumber *previous = self.keepAwakeStatus;
        [previous retain];
        self.keepAwakeStatusTime = now;
        self.keepAwakeStatus = nil;
        NSString *tool = [self keepAwakeToolPath];
        if (tool != nil) {
            NSTask *task = [[[NSTask alloc] init] autorelease];
            NSPipe *output = [NSPipe pipe];
            task.executableURL = [NSURL fileURLWithPath:tool];
            task.arguments = @[@"--status"];
            task.standardOutput = output;
            task.standardError = [NSFileHandle fileHandleWithNullDevice];
            @try {
                [task launch];
                NSData *data = [output.fileHandleForReading readDataToEndOfFile];
                [task waitUntilExit];
                NSString *value = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
                value = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                if (task.terminationStatus == 0 && ([value isEqualToString:@"on"] || [value isEqualToString:@"off"]))
                    self.keepAwakeStatus = @([value isEqualToString:@"on"]);
            } @catch (NSException *exception) { (void)exception; }
        }
        self.keepAwakeError = self.keepAwakeStatus ? nil : @"Cannot read sleep setting; last display guard state retained";
        if (tool && ![previous isEqual:self.keepAwakeStatus] && (previous || self.keepAwakeStatus))
            WattRecordAwakeEvent(self.keepAwakeError ?: (self.keepAwakeStatus.boolValue ? @"Sleep prevention confirmed on" : @"Sleep prevention confirmed off"));
        [previous release];
    }
    BOOL enabled = self.keepAwakeStatus.boolValue;
    // Preview/test executables have no bundled helper and must not touch hardware.
    if ([self keepAwakeToolPath] != nil)
        WattSyncLidGuard(self,WattKeepLidGuard(self.keepAwakeStatus,self.lidGuard != nil ||
            [NSUserDefaults.standardUserDefaults objectForKey:@"WattNookClosedLidBrightness"] != nil));
    return enabled;
}

- (void)toggleKeepAwake {
    if (self.keepAwakeChanging) return;
    self.keepAwakeStatusTime = 0;
    BOOL active = [self isKeepAwakeActive];
    NSString *tool = [self keepAwakeToolPath];
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:tool]) {
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        alert.messageText = @"Keep Awake helper is missing";
        alert.informativeText = @"Reinstall WattNook to restore its bundled Keep Awake helper.";
        [alert runModal];
        return;
    }
    if (!self.keepAwakeStatus) {
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        alert.messageText = @"Keep Awake status is unavailable";
        alert.informativeText = @"The current sleep setting could not be read. Retry shortly. Your last display guard state is retained.";
        [alert runModal]; return;
    }
    NSTask *task = [[[NSTask alloc] init] autorelease];
    task.executableURL = [NSURL fileURLWithPath:tool];
    if (!active && ![NSUserDefaults.standardUserDefaults boolForKey:@"WattNookKeepAwakeWarningAccepted"]) {
        NSAlert *confirm = [[[NSAlert alloc] init] autorelease];
        confirm.messageText = @"Keep working with the lid closed?";
        confirm.informativeText = @"This disables sleep for the entire Mac, including after WattNook quits. Turn Keep Awake off before carrying your Mac or putting it in a bag. Keep it ventilated, preferably on power. Keep WattNook running for closed-lid brightness handling. Administrator permission is needed unless the narrow sleep-toggle rule is installed. Do not manage this setting in Vorssaint at the same time.";
        [confirm addButtonWithTitle:@"Enable Keep Awake"];
        [confirm addButtonWithTitle:@"Cancel"];
        if ([confirm runModal] != NSAlertFirstButtonReturn) return;
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"WattNookKeepAwakeWarningAccepted"];
    }
    task.arguments = @[active ? @"--disable" : @"--enable"];
    NSPipe *errors = [NSPipe pipe];
    task.standardError = errors;
    @try {
        self.keepAwakeChanging = YES;
        [self refreshPopoverControls];
        task.terminationHandler = ^(NSTask *finished) {
            NSData *data = [errors.fileHandleForReading readDataToEndOfFile];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.keepAwakeChanging = NO;
                self.keepAwakeStatusTime = 0;
                [self refreshPopoverControls];
                if (finished.terminationStatus != 0) {
                    NSString *detail = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
                    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
                    alert.messageText = @"Could not change Keep Awake";
                    alert.informativeText = detail.length ? detail : @"macOS did not confirm the change.";
                    [alert runModal];
                }
            });
        };
        [task launch];
    } @catch (NSException *exception) {
        self.keepAwakeChanging = NO;
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        alert.messageText = @"Could not change Keep Awake";
        alert.informativeText = exception.reason ?: @"Unknown error";
        [alert runModal];
    }
}

- (void)setCustomHeatProtection {
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    alert.messageText = @"Custom Heat Protection";
    alert.informativeText = @"Pause battery charging at this temperature. Charging resumes only below the second temperature.";
    [alert addButtonWithTitle:@"Apply"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *pause = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 80, 24)] autorelease];
    pause.stringValue = @"33";
    NSTextField *resume = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 80, 24)] autorelease];
    resume.stringValue = @"30";
    NSTextField *pauseLabel = [[[NSTextField alloc] initWithFrame:NSZeroRect] autorelease];
    pauseLabel.stringValue = @"Pause at (°C)";
    pauseLabel.editable = NO;
    pauseLabel.bordered = NO;
    pauseLabel.drawsBackground = NO;
    NSTextField *resumeLabel = [[[NSTextField alloc] initWithFrame:NSZeroRect] autorelease];
    resumeLabel.stringValue = @"Resume below (°C)";
    resumeLabel.editable = NO;
    resumeLabel.bordered = NO;
    resumeLabel.drawsBackground = NO;
    NSStackView *accessory = [NSStackView stackViewWithViews:@[
        pauseLabel, pause, resumeLabel, resume
    ]];
    accessory.orientation =NSUserInterfaceLayoutOrientationVertical;
    accessory.alignment = NSLayoutAttributeLeading;
    accessory.spacing = 4;
    alert.accessoryView = accessory;

    if ([alert runModal] != NSAlertFirstButtonReturn) {
        return;
    }
    double pauseAt = pause.doubleValue;
    double resumeAt = resume.doubleValue;
    if (!isfinite(pauseAt) || !isfinite(resumeAt) || pauseAt <= 0 || resumeAt <= 0 || resumeAt >= pauseAt) {
        NSAlert *error = [[[NSAlert alloc] init] autorelease];
        error.messageText = @"Invalid heat protection thresholds";
        error.informativeText = @"Both temperatures must be above 0°C, and resume must be lower than pause.";
        [error runModal];
        return;
    }

    NSTask *task = [[[NSTask alloc] init] autorelease];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/local/bin/batt-thermal"];
    task.arguments = @[
        @"--daemon-socket=/var/run/batt-thermal.sock",
        @"heat-protection", @"set",
        [NSString stringWithFormat:@"%.1f", pauseAt],
        [NSString stringWithFormat:@"%.1f", resumeAt],
    ];
    @try {
        [task launch];
        [task waitUntilExit];
        if (task.terminationStatus != 0) {
            NSAlert *error = [[[NSAlert alloc] init] autorelease];
            error.messageText = @"Could not update heat protection";
            error.informativeText = @"The batt daemon did not accept the thresholds.";
            [error runModal];
        }
    } @catch (NSException *exception) {
        NSAlert *error = [[[NSAlert alloc] init] autorelease];
        error.messageText = @"Could not update heat protection";
        error.informativeText = exception.reason ?: @"Unknown error";
        [error runModal];
    }
}

- (void)setPowerItem:(BattMenuItem)item label:(NSString *)label value:(double)value {
    NSColor *color = NSColor.labelColor;
    char sign = ' ';
    if (![label isEqualToString:@"System"]) {
        if (value > 0) {
            color = NSColor.systemGreenColor;
            sign = '+';
        } else if (value < 0) {
            color = NSColor.systemRedColor;
            sign = '-';
        }
    }

    NSString *labelWithColon = [label stringByAppendingString:@":"];
    NSString *text = [NSString stringWithFormat:@"%-8s %c%7.2fW",
                      labelWithColon.UTF8String, sign, fabs(value)];
    NSMutableAttributedString *attributed = [[[NSMutableAttributedString alloc]
        initWithString:text] autorelease];
    NSRange labelRange = NSMakeRange(0, 9);
    NSRange valueRange = NSMakeRange(9, text.length - 9);
    [attributed addAttribute:NSForegroundColorAttributeName
                       value:NSColor.secondaryLabelColor
                       range:labelRange];
    [attributed addAttribute:NSForegroundColorAttributeName value:color range:valueRange];
    [attributed addAttribute:NSFontAttributeName
                       value:[NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular]
                       range:NSMakeRange(0, text.length)];
    [self item:item].attributedTitle = attributed;
}

@end

void BattBuildMenu(BattMenuController *controller, NSString *version) {
    NSMenu *root = controller.menu;
    NSMenuItem *flowCanvas = [[[NSMenuItem alloc] initWithTitle:@"Power Flow"
                                                         action:nil keyEquivalent:@""] autorelease];
    [controller rememberItem:flowCanvas as:BattItemPowerFlowCanvas];

    NSMenu *limits = AddSubmenu(controller, root, @"Charge Limit", BattItemQuickLimits);
    const NSInteger limitValues[] = {50, 60, 70, 80, 90};
    const BattMenuItem limitItems[] = {
        BattItemLimit50, BattItemLimit60, BattItemLimit70, BattItemLimit80, BattItemLimit90,
    };
    for (NSUInteger index = 0; index < 5; index++) {
        NSInteger limit = limitValues[index];
        NSString *title = [NSString stringWithFormat:@"%ld%%", (long)limit];
        NSString *key = [NSString stringWithFormat:@"%ld", (long)limit];
        [limits addItem:ActionItem(controller, title, key, limitItems[index])];
    }

    NSMenu *disableLimit = AddSubmenu(controller, limits, @"Temporarily Disable Limit",
                                      BattItemDisableLimit);
    NSMenuItem *disableCountdown = DisplayItem(controller, @"",
                                                BattItemDisableLimitCountdown, NO);
    disableCountdown.hidden = YES;
    [disableLimit addItem:disableCountdown];
    [disableLimit addItem:ActionItem(controller, @"Indefinitely", @"d",
                                      BattItemDisableLimitIndefinitely)];
    [disableLimit addItem:[NSMenuItem separatorItem]];
    [disableLimit addItem:ActionItem(controller, @"1 Hour", @"",
                                      BattItemDisableLimit1Hour)];
    [disableLimit addItem:ActionItem(controller, @"2 Hours", @"",
                                      BattItemDisableLimit2Hours)];
    [disableLimit addItem:ActionItem(controller, @"4 Hours", @"",
                                      BattItemDisableLimit4Hours)];
    [disableLimit addItem:ActionItem(controller, @"8 Hours", @"",
                                      BattItemDisableLimit8Hours)];
    [disableLimit addItem:ActionItem(controller, @"12 Hours", @"",
                                      BattItemDisableLimit12Hours)];
    [disableLimit addItem:ActionItem(controller, @"24 Hours", @"",
                                      BattItemDisableLimit24Hours)];
    [disableLimit addItem:ActionItem(controller, @"2 Days", @"",
                                      BattItemDisableLimit2Days)];
    [disableLimit addItem:ActionItem(controller, @"3 Days", @"",
                                      BattItemDisableLimit3Days)];
    [disableLimit addItem:ActionItem(controller, @"7 Days", @"",
                                      BattItemDisableLimit7Days)];

    NSMenu *heat = AddSubmenu(controller, root, @"Heat Protection: Loading...", BattItemHeatProtection);
    [heat addItem:ActionItem(controller, @"Off", @"", BattItemHeatOff)];
    [heat addItem:ActionItem(controller, @"Strict: pause 32°C, resume 29°C", @"", BattItemHeatStrict)];
    [heat addItem:ActionItem(controller, @"Balanced: pause 33°C, resume 30°C", @"", BattItemHeatBalanced)];
    [heat addItem:ActionItem(controller, @"Relaxed: pause 35°C, resume 32°C", @"", BattItemHeatRelaxed)];
    [heat addItem:[NSMenuItem separatorItem]];
    [heat addItem:ActionItem(controller, @"Custom…", @"", BattItemHeatCustom)];
    [root addItem:ActionItem(controller, @"Keep Awake: closed-lid work", @"", BattItemKeepAwake)];

    [root addItem:[NSMenuItem separatorItem]];
    NSMenu *diagnostics = [[[NSMenu alloc] initWithTitle:@"Diagnostics"] autorelease];
    diagnostics.autoenablesItems = NO;
    NSMenuItem *diagnosticsItem = [[[NSMenuItem alloc] initWithTitle:@"Diagnostics"
                                                             action:nil keyEquivalent:@""] autorelease];
    diagnosticsItem.submenu = diagnostics;
    [root addItem:diagnosticsItem];
    NSMenu *power = AddSubmenu(controller, diagnostics, @"Power Details", BattItemPowerFlow);
    [power addItem:DisplayItem(controller, @"Loading power flow...", BattItemPowerFlowSummary, NO)];
    [power addItem:[NSMenuItem separatorItem]];
    [power addItem:DisplayItem(controller, @"Loading...", BattItemState, NO)];
    [power addItem:DisplayItem(controller, @"Loading...", BattItemCurrentLimit, NO)];
    [power addItem:[NSMenuItem separatorItem]];
    [power addItem:DisplayItem(controller, @"", BattItemPowerSystem, YES)];
    [power addItem:DisplayItem(controller, @"", BattItemPowerAdapter, YES)];
    [power addItem:DisplayItem(controller, @"", BattItemPowerBattery, YES)];
    [controller setPowerItem:BattItemPowerSystem label:@"System" value:0];
    [controller setPowerItem:BattItemPowerAdapter label:@"Adapter" value:0];
    [controller setPowerItem:BattItemPowerBattery label:@"Battery" value:0];

    NSMenuItem *cpuApps = [[[NSMenuItem alloc] initWithTitle:@"Top CPU Apps"
                                                    action:nil keyEquivalent:@""] autorelease];
    controller.cpuAppsMenu = [[[NSMenu alloc] initWithTitle:@"Top CPU Apps"] autorelease];
    cpuApps.submenu = controller.cpuAppsMenu;
    [diagnostics addItem:cpuApps];
    NSMenuItem *memoryApps = [[[NSMenuItem alloc] initWithTitle:@"Top RAM Apps"
                                                       action:nil keyEquivalent:@""] autorelease];
    controller.memoryAppsMenu = [[[NSMenu alloc] initWithTitle:@"Top RAM Apps"] autorelease];
    memoryApps.submenu = controller.memoryAppsMenu;
    [diagnostics addItem:memoryApps];
    NSMenuItem *awakeDiagnostics = [[[NSMenuItem alloc] initWithTitle:@"Keep Awake diagnostics…"
        action:@selector(showKeepAwakeDiagnostics:) keyEquivalent:@""] autorelease];
    awakeDiagnostics.target = controller;
    [diagnostics addItem:[NSMenuItem separatorItem]];
    [diagnostics addItem:awakeDiagnostics];

    [root addItem:ActionItem(controller, @"Upgrade Daemon...", @"u", BattItemUpgrade)];
    [root addItem:ActionItem(controller, @"Install Daemon...", @"i", BattItemInstall)];
    NSMenu *advanced = AddSubmenu(controller, root, @"Advanced", BattItemAdvanced);
    NSMenu *magSafe = AddSubmenu(controller, advanced, @"Control MagSafe LED", BattItemMagSafe);
    [magSafe addItem:ActionItem(controller, @"Enable", @"", BattItemMagSafeEnabled)];
    [magSafe addItem:ActionItem(controller, @"Disable", @"", BattItemMagSafeDisabled)];
    [magSafe addItem:ActionItem(controller, @"Always-off", @"", BattItemMagSafeAlwaysOff)];

    [advanced addItem:ActionItem(controller, @"Prevent Idle Sleep when Charging", @"",
                                  BattItemPreventIdleSleep)];
    [advanced addItem:ActionItem(controller, @"Disable Charging before Sleep", @"",
                                  BattItemDisableChargingPreSleep)];
    [advanced addItem:ActionItem(controller,
                                  @"Prevent System Sleep when Charging (Experimental)", @"",
                                  BattItemPreventSystemSleep)];
    NSMenu *forceDischarge = AddSubmenu(controller, advanced, @"Force Discharge...",
                                        BattItemForceDischarge);
    NSMenuItem *forceDischargeCountdown = DisplayItem(controller, @"",
                                                       BattItemForceDischargeCountdown, NO);
    forceDischargeCountdown.hidden = YES;
    [forceDischarge addItem:forceDischargeCountdown];
    [forceDischarge addItem:ActionItem(controller, @"Stop Force Discharge", @"",
                                        BattItemForceDischargeStop)];
    [forceDischarge addItem:ActionItem(controller, @"Indefinitely", @"",
                                        BattItemForceDischargeIndefinitely)];
    [forceDischarge addItem:[NSMenuItem separatorItem]];
    [forceDischarge addItem:ActionItem(controller, @"1 Hour", @"",
                                        BattItemForceDischarge1Hour)];
    [forceDischarge addItem:ActionItem(controller, @"2 Hours", @"",
                                        BattItemForceDischarge2Hours)];
    [forceDischarge addItem:ActionItem(controller, @"4 Hours", @"",
                                        BattItemForceDischarge4Hours)];
    [forceDischarge addItem:ActionItem(controller, @"8 Hours", @"",
                                        BattItemForceDischarge8Hours)];

    NSMenu *calibration = AddSubmenu(controller, advanced,
                                     @"Auto Calibration (Experimental)...",
                                     BattItemAutoCalibration);
    [calibration addItem:DisplayItem(controller, @"Status: Idle",
                                      BattItemCalibrationStatus, NO)];
    [calibration addItem:ActionItem(controller, @"Start", @"", BattItemCalibrationStart)];
    [calibration addItem:ActionItem(controller, @"Pause", @"", BattItemCalibrationPause)];
    [calibration addItem:ActionItem(controller, @"Resume", @"", BattItemCalibrationResume)];
    [calibration addItem:ActionItem(controller, @"Cancel", @"", BattItemCalibrationCancel)];

    [advanced addItem:[NSMenuItem separatorItem]];
    NSString *versionTitle = [@"Version: " stringByAppendingString:version ?: @""];
    [advanced addItem:DisplayItem(controller, versionTitle, BattItemVersion, NO)];
    [advanced addItem:ActionItem(controller, @"Uninstall Daemon...", @"", BattItemUninstall)];

    [root addItem:ActionItem(controller, @"Quit Menubar App", @"q", BattItemQuit)];
}
