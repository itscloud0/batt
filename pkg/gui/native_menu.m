#import "native_internal.h"
#import <mach/mach.h>
#import <sys/mount.h>

static const NSTimeInterval BattMenuUpdateInterval = 10.0;

static NSButton *BattPopoverButton(NSRect frame, NSString *title, NSString *symbol,
                                   id target, SEL action) {
    NSButton *button = [NSButton buttonWithTitle:title target:target action:action];
    button.frame = frame;
    button.bordered = NO;
    button.alignment = NSTextAlignmentLeft;
    button.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil];
    button.image = [image imageWithSymbolConfiguration:
        [NSImageSymbolConfiguration configurationWithPointSize:15 weight:NSFontWeightRegular]];
    button.imagePosition = NSImageLeft;
    button.imageHugsTitle = YES;
    if (title.length > 0) button.title = title;
    return button;
}

@interface BattPopoverBackground : NSView
@end

@implementation BattPopoverBackground
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    BOOL dark = [[self.effectiveAppearance bestMatchFromAppearancesWithNames:
        @[NSAppearanceNameDarkAqua, NSAppearanceNameAqua]] isEqualToString:NSAppearanceNameDarkAqua];
    NSColor *surface = dark
        ? [NSColor colorWithCalibratedRed:0.12 green:0.14 blue:0.18 alpha:1]
        : [NSColor colorWithCalibratedRed:0.97 green:0.98 blue:0.99 alpha:1];
    [surface setFill];
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:12 yRadius:12] fill];
}
@end

@interface BattPopoverDivider : NSView
@end

@implementation BattPopoverDivider
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    BOOL dark = [[self.effectiveAppearance bestMatchFromAppearancesWithNames:
        @[NSAppearanceNameDarkAqua, NSAppearanceNameAqua]] isEqualToString:NSAppearanceNameDarkAqua];
    [[NSColor colorWithCalibratedWhite:dark ? 0.28 : 0.80 alpha:1] setFill];
    NSRectFill(self.bounds);
}
@end

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
        _diskPercent = -1;
        _powerFlowView = [[BattPowerFlowView alloc] initWithFrame:NSMakeRect(0, 0, 340, 188)];

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
        _statsTimer = [[NSTimer scheduledTimerWithTimeInterval:2.0
                                                        target:self
                                                      selector:@selector(updateSystemStats:)
                                                      userInfo:nil
                                                       repeats:YES] retain];
        [self updateSystemStats:nil];
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
        case BattItemDarkWork:
            [self toggleDarkWork];
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
    NSView *content = [[[BattPopoverBackground alloc]
        initWithFrame:NSMakeRect(0, 0, 340, 400)] autorelease];
    content.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    self.powerFlowView.frame = NSMakeRect(0, 212, 340, 188);
    self.powerFlowView.limitTarget = self;
    self.powerFlowView.limitAction = @selector(commitLimitFromRail:);
    [content addSubview:self.powerFlowView];

    // The charge limit is both a draggable marker and a menu of exact values.
    self.chargeButton = BattPopoverButton(NSMakeRect(218, 287, 102, 20),
        @"Limit 80%  ›", @"", self, @selector(showChargeLimits:));
    self.chargeButton.image = nil;
    self.chargeButton.alignment = NSTextAlignmentRight;
    self.chargeButton.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    self.chargeButton.toolTip = @"Drag the marker or click for exact charge limits";
    [content addSubview:self.chargeButton];

    BattPopoverDivider *powerLine = [[[BattPopoverDivider alloc]
        initWithFrame:NSMakeRect(16, 207, 308, 1)] autorelease];
    [content addSubview:powerLine];
    self.heatButton = BattPopoverButton(NSMakeRect(20, 166, 150, 36),
        @"Heat protection", @"thermometer.medium", self, @selector(showHeatOptions:));
    self.darkButton = BattPopoverButton(NSMakeRect(174, 166, 146, 36),
        @"Screen off", @"moon.fill", self, @selector(toggleDarkWorkFromPopover:));
    for (NSButton *button in @[self.heatButton, self.darkButton]) {
        button.bordered = YES;
        button.bezelStyle = NSBezelStyleRounded;
        button.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
        [content addSubview:button];
    }
    BattPopoverDivider *systemLine = [[[BattPopoverDivider alloc]
        initWithFrame:NSMakeRect(16, 159, 308, 1)] autorelease];
    [content addSubview:systemLine];

    NSTextField *systemTitle = [NSTextField labelWithString:@"System"];
    systemTitle.frame = NSMakeRect(20, 134, 100, 19);
    systemTitle.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    [content addSubview:systemTitle];
    NSButton *more = BattPopoverButton(NSMakeRect(296, 129, 28, 28),
        @"", @"gearshape", self, @selector(showMoreMenu:));
    more.toolTip = @"Settings, advanced controls and Quit";
    more.accessibilityLabel = @"More options";
    [content addSubview:more];

    self.statsButton = BattPopoverButton(NSMakeRect(20, 105, 94, 26),
        @"CPU —", @"cpu", self, @selector(showCPUApps:));
    self.memoryButton = BattPopoverButton(NSMakeRect(120, 105, 94, 26),
        @"RAM —", @"memorychip", self, @selector(showMemoryApps:));
    self.diskButton = BattPopoverButton(NSMakeRect(220, 105, 94, 26),
        @"SSD —", @"internaldrive", self, @selector(showDiagnostics:));
    for (NSButton *button in @[self.statsButton, self.memoryButton, self.diskButton]) {
        button.image = nil;
        button.title = @"—";
        button.font = [NSFont monospacedDigitSystemFontOfSize:14 weight:NSFontWeightSemibold];
        [content addSubview:button];
    }
    NSArray<NSString *> *captions = @[@"CPU load", @"Memory used", @"Disk space used"];
    NSArray<NSNumber *> *captionX = @[@20, @120, @220];
    for (NSInteger index = 0; index < captions.count; index++) {
        NSTextField *caption = [NSTextField labelWithString:captions[index]];
        caption.frame = NSMakeRect(captionX[index].doubleValue, 91, 94, 15);
        caption.font = [NSFont systemFontOfSize:10 weight:NSFontWeightRegular];
        caption.textColor = NSColor.secondaryLabelColor;
        [content addSubview:caption];
    }
    self.statsButton.toolTip = @"CPU busy; top CPU apps";
    self.memoryButton.toolTip = @"Physical memory used; top memory apps";
    self.diskButton.toolTip = @"Storage space used; open diagnostics";
    BattPopoverDivider *appsLine = [[[BattPopoverDivider alloc]
        initWithFrame:NSMakeRect(20, 84, 300, 1)] autorelease];
    [content addSubview:appsLine];
    NSTextField *appsTitle = [NSTextField labelWithString:@"Apps using most"];
    appsTitle.frame = NSMakeRect(20, 65, 100, 16);
    appsTitle.font = [NSFont systemFontOfSize:10 weight:NSFontWeightMedium];
    appsTitle.textColor = NSColor.secondaryLabelColor;
    [content addSubview:appsTitle];
    for (NSInteger index = 0; index < 2; index++) {
        CGFloat y = index == 0 ? 35 : 7;
        NSTextField *label = [NSTextField labelWithString:@"Sampling…"];
        label.frame = NSMakeRect(20, y, 250, 23);
        label.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
        label.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [content addSubview:label];
        NSButton *quit = [NSButton buttonWithTitle:@"Quit" target:self
                                            action:@selector(quitFeaturedApp:)];
        quit.frame = NSMakeRect(278, y - 1, 46, 25);
        quit.bezelStyle = NSBezelStyleRounded;
        quit.font = [NSFont systemFontOfSize:10 weight:NSFontWeightMedium];
        quit.tag = index;
        quit.enabled = NO;
        quit.toolTip = @"Request a normal Quit; you will be asked to confirm";
        [content addSubview:quit];
        if (index == 0) {
            self.cpuTopAppLabel = label;
            self.cpuQuitButton = quit;
        } else {
            self.memoryTopAppLabel = label;
            self.memoryQuitButton = quit;
        }
    }

    NSViewController *controller = [[[NSViewController alloc] init] autorelease];
    controller.view = content;
    self.popover = [[[NSPopover alloc] init] autorelease];
    self.popover.behavior = NSPopoverBehaviorTransient;
    self.popover.contentSize = NSMakeSize(340, 400);
    self.popover.contentViewController = controller;
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
    [self refreshPopoverControls];
    [NSApp activateIgnoringOtherApps:YES];
    [self.popover showRelativeToRect:self.statusItem.button.bounds
                             ofView:self.statusItem.button
                      preferredEdge:NSRectEdgeMinY];
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

- (void)toggleDarkWorkFromPopover:(NSButton *)sender {
    (void)sender;
    [self toggleDarkWork];
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
    self.chargeButton.title = [NSString stringWithFormat:@"Limit %ld%%  ›",
        (long)self.powerFlowView.displayedLimitPercent];
    NSString *heat = [self item:BattItemHeatProtection].title ?: @"Loading…";
    NSRange colon = [heat rangeOfString:@": "];
    heat = colon.location == NSNotFound ? heat :
        [heat substringFromIndex:NSMaxRange(colon)];
    if ([heat hasPrefix:@"paused"]) {
        NSString *label = self.powerFlowView.pluggedIn ? @"Paused · " : @"Cooling · ";
        heat = [heat stringByReplacingOccurrencesOfString:@"paused (" withString:label];
        heat = [heat stringByReplacingOccurrencesOfString:@")" withString:@""];
    } else if ([heat hasPrefix:@"on ("]) {
        heat = [heat stringByReplacingOccurrencesOfString:@"on (" withString:@"On · "];
        heat = [heat stringByReplacingOccurrencesOfString:@"°C → " withString:@"/"];
        heat = [heat stringByReplacingOccurrencesOfString:@")" withString:@""];
    } else if ([heat isEqualToString:@"off"]) {
        heat = @"Off";
    }
    self.heatButton.title = [heat hasPrefix:@"Paused"] ? @"Heat: charge paused" :
        ([heat hasPrefix:@"Cooling"] ? @"Heat: cooling" :
         ([heat isEqualToString:@"Off"] ? @"Heat: off" : @"Heat: on"));
    self.heatButton.toolTip = [NSString stringWithFormat:@"Heat protection: %@. Click to change thresholds.", heat];
    self.darkButton.title = [self isDarkWorkActive] ? @"Restore display" : @"Screen off";
    self.darkButton.toolTip = [self isDarkWorkActive]
        ? @"Turn the display back on" : @"Turn the display off while the Mac stays awake";
    self.statsButton.title = [NSString stringWithFormat:@"%@",
        _cpuPercent < 0 ? @"—" : [NSString stringWithFormat:@"%.0f%%", _cpuPercent]];
    self.memoryButton.title = [NSString stringWithFormat:@"%@",
        _memoryPercent < 0 ? @"—" : [NSString stringWithFormat:@"%.0f%%", _memoryPercent]];
    self.diskButton.title = [NSString stringWithFormat:@"%@",
        _diskPercent < 0 ? @"—" : [NSString stringWithFormat:@"%.0f%%", _diskPercent]];
    NSArray<NSDictionary *> *byCPU = [self.appStats sortedArrayUsingComparator:
        ^NSComparisonResult(NSDictionary *first, NSDictionary *second) {
            return [second[@"cpu"] compare:first[@"cpu"]];
        }];
    NSDictionary *cpuApp = byCPU.firstObject;
    if ([cpuApp[@"cpu"] doubleValue] < 0.1) cpuApp = nil;
    NSArray<NSDictionary *> *byMemory = [self.appStats sortedArrayUsingComparator:
        ^NSComparisonResult(NSDictionary *first, NSDictionary *second) {
            return [second[@"memory"] compare:first[@"memory"]];
        }];
    NSDictionary *memoryApp = nil;
    for (NSDictionary *candidate in byMemory) {
        if (![candidate[@"pid"] isEqual:cpuApp[@"pid"]]) {
            memoryApp = candidate;
            break;
        }
    }
    self.cpuFeaturedApp = cpuApp;
    self.memoryFeaturedApp = memoryApp;
    self.cpuTopAppLabel.stringValue = cpuApp == nil ? @"CPU · sampling" :
        [NSString stringWithFormat:@"CPU · %@  %.0f%%", cpuApp[@"name"],
            [cpuApp[@"cpu"] doubleValue]];
    NSString *memoryAmount = memoryApp == nil ? @"" :
        [NSByteCountFormatter stringFromByteCount:[memoryApp[@"memory"] longLongValue]
                                  countStyle:NSByteCountFormatterCountStyleMemory];
    self.memoryTopAppLabel.stringValue = memoryApp == nil ? @"RAM · no app data" :
        [NSString stringWithFormat:@"RAM · %@  %@", memoryApp[@"name"], memoryAmount];
    self.cpuQuitButton.enabled = cpuApp != nil;
    self.memoryQuitButton.enabled = memoryApp != nil;
    self.chargeButton.enabled = ![self item:BattItemQuickLimits].hidden;
    self.heatButton.enabled = ![self item:BattItemHeatProtection].hidden;
    self.powerFlowView.limitEditable = self.chargeButton.enabled &&
        [self item:BattItemLimit80].enabled;
}

- (void)menuDidClose:(NSMenu *)menu {
    (void)menu;
}

- (void)timerTick:(NSTimer *)timer {
    (void)timer;
    battMenuTimerFired(_handle);
}

- (void)updateSystemStats:(NSTimer *)timer {
    (void)timer;
    host_cpu_load_info_data_t cpu;
    mach_msg_type_number_t cpuCount = HOST_CPU_LOAD_INFO_COUNT;
    if (host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO,
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
    }

    vm_statistics64_data_t memory;
    mach_msg_type_number_t memoryCount = HOST_VM_INFO64_COUNT;
    if (host_statistics64(mach_host_self(), HOST_VM_INFO64,
                          (host_info64_t)&memory, &memoryCount) == KERN_SUCCESS) {
        uint64_t total = [NSProcessInfo processInfo].physicalMemory;
        uint64_t available = ((uint64_t)memory.free_count +
                              (uint64_t)memory.inactive_count +
                              (uint64_t)memory.speculative_count) * (uint64_t)vm_page_size;
        if (total > 0)
            _memoryPercent = 100.0 * (1.0 - MIN(available, total) / (double)total);
    }

    if (_statsTickCount++ % 15 == 0) {
        struct statfs volume;
        if (statfs("/", &volume) == 0 && volume.f_blocks > 0) {
            _diskPercent = 100.0 * (1.0 -
                (double)volume.f_bavail / (double)volume.f_blocks);
        }
    }
    [self refreshStatusImage];
    [self updateAppStats];
    [self refreshPopoverControls];
}

- (void)refreshStatusImage {
    if (self.batteryIcon == nil) return;
    NSImage *combined = [[[NSImage alloc] initWithSize:NSMakeSize(81, 24)] autorelease];
    NSDictionary *attributes = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:8.5
                                                              weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: NSColor.whiteColor,
    };
    [combined lockFocus];
    NSArray<NSString *> *labels = @[@"CPU", @"RAM", @"SSD"];
    NSArray<NSString *> *values = @[
        _cpuPercent < 0 ? @"—" : [NSString stringWithFormat:@"%.0f%%", _cpuPercent],
        _memoryPercent < 0 ? @"—" : [NSString stringWithFormat:@"%.0f%%", _memoryPercent],
        _diskPercent < 0 ? @"—" : [NSString stringWithFormat:@"%.0f%%", _diskPercent],
    ];
    for (NSInteger i = 0; i < labels.count; i++) {
        CGFloat y = 16 - i * 8;
        [labels[i] drawAtPoint:NSMakePoint(1, y) withAttributes:attributes];
        [values[i] drawAtPoint:NSMakePoint(26, y) withAttributes:attributes];
    }
    [self.batteryIcon drawInRect:NSMakeRect(54, 5, 25, 14)
                       fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
    [combined unlockFocus];
    combined.template = NO;
    self.statusItem.button.image = combined;
    self.statusItem.button.title = @"";
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
    NSColor *iconColor = !pluggedIn && charge <= 20 ? NSColor.systemRedColor
        : ([NSProcessInfo processInfo].lowPowerModeEnabled
            ? NSColor.systemYellowColor : NSColor.whiteColor);
    [image lockFocus];
    [iconColor setFill];
    NSRectFillUsingOperation(NSMakeRect(0, 0, image.size.width, image.size.height),
                             NSCompositingOperationSourceAtop);
    [image unlockFocus];
    image.template = NO;
    self.batteryIcon = image;
    [self refreshStatusImage];
    self.statusItem.button.contentTintColor = nil;
    NSString *state = heatPaused && pluggedIn ? @"heat protection paused charging" :
        (charging ? @"charging" : (pluggedIn ? @"plugged in, not charging" : @"on battery"));
    self.statusItem.button.toolTip = [NSString stringWithFormat:@"Battery %ld%%, %@", (long)charge, state];
    self.statusItem.button.accessibilityLabel = self.statusItem.button.toolTip;
    self.powerFlowView.chargePercent = charge;
    self.powerFlowView.pluggedIn = pluggedIn;
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

- (NSString *)darkWorkToolPath {
    NSString *bundled = [[NSBundle mainBundle] pathForAuxiliaryExecutable:@"DarkWork"];
    if (bundled != nil && [[NSFileManager defaultManager] isExecutableFileAtPath:bundled]) {
        return bundled;
    }
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Applications/Dark Work.app/Contents/MacOS/DarkWork"];
}

- (BOOL)isDarkWorkActive {
    NSString *state = [NSHomeDirectory() stringByAppendingPathComponent:
        @"Library/Application Support/DarkWork/state.json"];
    return [[NSFileManager defaultManager] fileExistsAtPath:state];
}

- (void)toggleDarkWork {
    BOOL active = [self isDarkWorkActive];
    NSString *tool = [self darkWorkToolPath];
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:tool]) {
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        alert.messageText = @"Dark Work helper is missing";
        alert.informativeText = @"Reinstall Batt Thermal to restore the screen-off helper.";
        [alert runModal];
        return;
    }
    NSTask *task = [[[NSTask alloc] init] autorelease];
    task.executableURL = [NSURL fileURLWithPath:tool];
    task.arguments = @[active ? @"--restore" : @"--activate"];
    @try {
        [task launch];
        [self item:BattItemDarkWork].title = active
            ? @"Dark Work: screen off, Mac awake"
            : @"Dark Work: restore display";
    } @catch (NSException *exception) {
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        alert.messageText = @"Could not toggle Dark Work";
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
    [root addItem:ActionItem(controller, @"Dark Work: screen off, Mac awake", @"", BattItemDarkWork)];

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
