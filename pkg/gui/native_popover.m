#import "native_internal.h"

// One AppKit surface: the battery overview and a deeper, sortable System page.
// All frames are points (not image pixels); text never sits on a power ribbon.
static NSTextField *Label(NSView *parent, NSRect frame, NSString *text,
                         CGFloat size, BOOL prominent) {
    NSTextField *label = [NSTextField labelWithString:text];
    label.frame = frame;
    label.font = [NSFont systemFontOfSize:size weight:prominent ?
        NSFontWeightSemibold : NSFontWeightRegular];
    label.textColor = prominent ? NSColor.labelColor :
        [NSColor colorWithCalibratedWhite:0.72 alpha:1];
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    [parent addSubview:label];
    return label;
}

@interface WattButton : NSButton
@property(nonatomic, assign) BOOL selected;
@property(nonatomic, assign) BOOL plain;
@end
@implementation WattButton {
    NSTrackingArea *_tracking;
    BOOL _hover;
}
- (void)dealloc { [_tracking release]; [super dealloc]; }
- (void)updateTrackingAreas {
    if (_tracking) [self removeTrackingArea:_tracking];
    [_tracking release];
    _tracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow |
                NSTrackingInVisibleRect owner:self userInfo:nil];
    [self addTrackingArea:_tracking];
    [super updateTrackingAreas];
}
- (void)mouseEntered:(NSEvent *)event { (void)event; _hover = YES; self.needsDisplay = YES; }
- (void)mouseExited:(NSEvent *)event { (void)event; _hover = NO; self.needsDisplay = YES; }
- (void)setSelected:(BOOL)value {
    _selected = value; self.state = value ? NSControlStateValueOn : NSControlStateValueOff;
    self.needsDisplay = YES;
}
- (void)drawRect:(NSRect)rect {
    (void)rect;
    NSRect surface = NSInsetRect(self.bounds, 0.5, 0.5);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:surface xRadius:8 yRadius:8];
    if (!_plain || _hover || _selected) {
        NSColor *color = _selected ? NSColor.systemBlueColor :
            [NSColor.whiteColor colorWithAlphaComponent:self.highlighted ? 0.19 :
                (_hover ? 0.14 : 0.075)];
        [color setFill]; [path fill];
        [[NSColor.whiteColor colorWithAlphaComponent:0.10] setStroke]; [path stroke];
    }
    if (self.window.firstResponder == self) {
        [NSColor.keyboardFocusIndicatorColor setStroke]; path.lineWidth = 2; [path stroke];
    }
    NSColor *ink = self.enabled ? NSColor.labelColor : NSColor.disabledControlTextColor;
    CGFloat iconWidth = self.image ? 17 : 0;
    NSDictionary *style = @{NSFontAttributeName:self.font,
        NSForegroundColorAttributeName:ink};
    NSSize textSize = [self.title sizeWithAttributes:style];
    CGFloat start = (NSWidth(self.bounds) - textSize.width -
        (iconWidth > 0 && self.title.length > 0 ? iconWidth + 10 : iconWidth)) / 2;
    if (self.image) {
        NSSize intrinsic = self.image.size;
        CGFloat scale = MIN(17 / MAX(1, intrinsic.width), 19 / MAX(1, intrinsic.height));
        NSRect icon = NSMakeRect(start, (NSHeight(self.bounds) - intrinsic.height * scale)/2,
            intrinsic.width * scale, intrinsic.height * scale);
        NSImage *tinted = [[[NSImage alloc] initWithSize:self.image.size] autorelease];
        [tinted lockFocus];
        [self.image drawAtPoint:NSZeroPoint fromRect:NSZeroRect
            operation:NSCompositingOperationSourceOver fraction:1];
        [ink setFill]; NSRectFillUsingOperation(NSMakeRect(0,0,self.image.size.width,self.image.size.height),
            NSCompositingOperationSourceAtop);
        [tinted unlockFocus];
        [tinted drawInRect:icon fromRect:NSZeroRect
            operation:NSCompositingOperationSourceOver fraction:self.enabled ? 1 : 0.4
            respectFlipped:YES hints:nil];
        start += iconWidth + (self.title.length ? 10 : 0);
    }
    [self.title drawAtPoint:NSMakePoint(start, (NSHeight(self.bounds)-textSize.height)/2)
        withAttributes:style];
}
@end

static WattButton *Button(NSView *parent, NSRect frame, NSString *title,
                          NSString *symbol, id target, SEL action) {
    WattButton *button = [[[WattButton alloc] initWithFrame:frame] autorelease];
    button.title = title; button.target = target; button.action = action;
    button.bordered = NO;
    button.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    if (symbol.length) button.image = [NSImage imageWithSystemSymbolName:symbol
        accessibilityDescription:nil];
    button.imagePosition = NSImageLeft;
    button.accessibilityLabel = title.length ? title : @"Settings";
    [parent addSubview:button];
    return button;
}

@interface WattAppRow : NSView
@property(nonatomic, retain) NSDictionary *sample;
@property(nonatomic, assign) BattMenuController *controller;
- (void)update:(NSDictionary *)sample memory:(BOOL)memory;
@end
@implementation WattAppRow {
    NSImageView *_icon;
    NSTextField *_name, *_amount;
    WattButton *_quit;
}
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _icon = [[[NSImageView alloc] initWithFrame:NSMakeRect(0, 4, 26, 26)] autorelease];
        _icon.imageScaling = NSImageScaleProportionallyUpOrDown;
        [self addSubview:_icon];
        _name = Label(self, NSMakeRect(36, 8, 117, 19), @"Sampling…", 12, YES);
        _amount = Label(self, NSMakeRect(156, 8, 98, 19), @"", 11, NO);
        _amount.alignment = NSTextAlignmentRight;
        _amount.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
        _quit = Button(self, NSMakeRect(266, 4, 46, 27), @"Quit", @"", self, @selector(quit:));
        _quit.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
        _quit.toolTip = @"Request a normal Quit after confirmation";
    }
    return self;
}
- (void)dealloc { [_sample release]; [super dealloc]; }
- (void)update:(NSDictionary *)sample memory:(BOOL)memory {
    BOOL changed = ![sample[@"path"] isEqual:self.sample[@"path"]];
    self.sample = sample;
    self.hidden = sample == nil;
    if (!sample) return;
    if (changed) _icon.image = [NSWorkspace.sharedWorkspace iconForFile:sample[@"path"]];
    _name.stringValue = sample[@"name"] ?: @"Application";
    _name.toolTip = _name.stringValue;
    _amount.stringValue = memory ? [NSByteCountFormatter
        stringFromByteCount:[sample[@"memory"] longLongValue]
        countStyle:NSByteCountFormatterCountStyleMemory] :
        [NSString stringWithFormat:@"%.0f%% CPU", [sample[@"cpu"] doubleValue]];
    _amount.toolTip = memory ? @"Resident memory, including helper processes" :
        @"CPU across cores; 100% is one full CPU core";
    _quit.accessibilityLabel = [@"Quit " stringByAppendingString:_name.stringValue];
}
- (void)quit:(id)sender {
    (void)sender;
    if (!self.sample) return;
    NSMenuItem *request = [[[NSMenuItem alloc] initWithTitle:@"Quit"
        action:nil keyEquivalent:@""] autorelease];
    request.representedObject = self.sample;
    [self.controller quitDiagnosedApp:request];
    [self.controller updateAppStats];
    [self.controller refreshPopoverControls];
}
@end

@interface WattDashboard : NSView
@property(nonatomic, assign) BattMenuController *controller;
- (void)refreshCPU:(double)cpu memory:(double)memory;
@end
@implementation WattDashboard {
    NSView *_batteryPage, *_systemPage;
    WattButton *_batteryTab, *_systemTab, *_cpuSort, *_memorySort;
    NSMutableArray *_summary, *_details, *_featured, *_rows;
    NSTextField *_storage, *_read, *_write, *_footer, *_empty, *_overviewEmpty;
    BOOL _system, _sortMemory;
    double _cpu, _memory;
}
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _summary = [[NSMutableArray alloc] init]; _details = [[NSMutableArray alloc] init];
        _featured = [[NSMutableArray alloc] init]; _rows = [[NSMutableArray alloc] init];
    }
    return self;
}
- (void)dealloc {
    [_summary release]; [_details release]; [_featured release]; [_rows release];
    [super dealloc];
}
- (void)drawRect:(NSRect)rect {
    (void)rect;
    NSGradient *surface = [[[NSGradient alloc] initWithStartingColor:
        [NSColor colorWithCalibratedRed:0.15 green:0.18 blue:0.22 alpha:1]
        endingColor:[NSColor colorWithCalibratedRed:0.105 green:0.125 blue:0.16 alpha:1]] autorelease];
    [surface drawInRect:self.bounds angle:90];
}
- (void)line:(NSView *)parent y:(CGFloat)y {
    NSBox *line = [[[NSBox alloc] initWithFrame:NSMakeRect(18, y, 324, 1)] autorelease];
    line.boxType = NSBoxSeparator; [parent addSubview:line];
}
- (void)build {
    Label(self, NSMakeRect(20, 449, 230, 17), @"WattNook", 11, YES);
    WattButton *settings = Button(self, NSMakeRect(318, 440, 26, 28), @"", @"gearshape",
        self.controller, @selector(showMoreMenu:)); settings.plain = YES;
    _batteryTab = Button(self, NSMakeRect(20, 407, 156, 29), @"Battery", @"battery.100percent",
        self, @selector(battery:));
    _systemTab = Button(self, NSMakeRect(184, 407, 156, 29), @"System", @"chart.bar.fill",
        self, @selector(system:)); _batteryTab.selected = YES;
    _batteryPage = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 360, 408)] autorelease];
    _systemPage = [[[NSView alloc] initWithFrame:_batteryPage.frame] autorelease];
    [self addSubview:_batteryPage]; [self addSubview:_systemPage]; _systemPage.hidden = YES;
    BattMenuController *c = self.controller;
    c.powerFlowView.frame = NSMakeRect(0, 188, 360, 220);
    c.powerFlowView.limitTarget = c; c.powerFlowView.limitAction = @selector(commitLimitFromRail:);
    [_batteryPage addSubview:c.powerFlowView];
    c.chargeButton = Button(_batteryPage, NSMakeRect(220, 295, 120, 22),
        @"Limit 80% ›", @"", c, @selector(showChargeLimits:));
    ((WattButton *)c.chargeButton).plain = YES;
    c.chargeButton.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    c.chargeButton.toolTip = @"Drag the marker or choose an exact charge limit";
    c.heatButton = Button(_batteryPage, NSMakeRect(20, 151, 156, 31),
        @"Heat protection ›", @"thermometer.medium", c, @selector(showHeatOptions:));
    c.darkButton = Button(_batteryPage, NSMakeRect(184, 151, 156, 31),
        @"Screen off", @"moon.fill", c, @selector(toggleDarkWorkFromPopover:));
    c.heatButton.font = c.darkButton.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    [self line:_batteryPage y:141];
    WattButton *system = Button(_batteryPage, NSMakeRect(17, 118, 75, 22),
        @"System ›", @"", self, @selector(system:)); system.plain = YES;
    [self line:_batteryPage y:76];
    for (NSInteger i = 0; i < 3; i++) {
        WattButton *metric = Button(_batteryPage, NSMakeRect(20+i*110, 94, 100, 24),
            @"—", @"", self, @selector(metric:));
        metric.plain = YES; metric.tag = i;
        metric.font = [NSFont monospacedDigitSystemFontOfSize:18 weight:NSFontWeightSemibold];
        [_summary addObject:metric];
        Label(_batteryPage, NSMakeRect(23+i*110, 80, 105, 14),
            @[@"CPU load", @"Memory used", @"Disk MB/s"][i], 10, NO);
        WattButton *detail = Button(_systemPage, NSMakeRect(20+i*110, 349, 100, 34),
            @"—", @"", self, @selector(metric:));
        detail.plain = YES; detail.tag = i;
        detail.font = [NSFont monospacedDigitSystemFontOfSize:22 weight:NSFontWeightSemibold];
        [_details addObject:detail];
        Label(_systemPage, NSMakeRect(24+i*110, 328, 100, 16),
            @[@"CPU load", @"Memory used", @"Disk MB/s"][i], 11, NO);
    }
    // Overview is deliberately only two rows; the full list is one click away.
    for (NSInteger i = 0; i < 2; i++) {
        WattAppRow *row = [[[WattAppRow alloc] initWithFrame:NSMakeRect(24, 40-i*34, 312, 34)] autorelease];
        [_batteryPage addSubview:row]; row.controller = c; [_featured addObject:row];
    }
    _overviewEmpty = Label(_batteryPage, NSMakeRect(24, 24, 312, 20),
        @"Collecting app samples…", 11, NO);
    _read = Label(_systemPage, NSMakeRect(24, 303, 150, 17), @"Read —", 11, NO);
    _write = Label(_systemPage, NSMakeRect(184, 303, 155, 17), @"Write —", 11, NO);
    _storage = Label(_systemPage, NSMakeRect(24, 280, 312, 17), @"Storage sampling…", 11, NO);
    [self line:_systemPage y:268];
    _cpuSort = Button(_systemPage, NSMakeRect(20, 229, 156, 29), @"CPU", @"", self, @selector(sort:));
    _memorySort = Button(_systemPage, NSMakeRect(184, 229, 156, 29), @"Memory", @"", self, @selector(sort:));
    _cpuSort.selected = YES; _memorySort.tag = 1;
    for (NSInteger i = 0; i < 5; i++) {
        WattAppRow *row = [[[WattAppRow alloc] initWithFrame:NSMakeRect(24, 190-i*34, 312, 34)] autorelease];
        [_systemPage addSubview:row]; row.controller = c; [_rows addObject:row];
    }
    _empty = Label(_systemPage, NSMakeRect(24, 181, 312, 32), @"Collecting app samples…", 12, NO);
    WattButton *activity = Button(_systemPage, NSMakeRect(20, 22, 320, 28),
        @"Open Activity Monitor ↗", @"waveform.path.ecg", self, @selector(activity:)); activity.plain = YES;
    _footer = Label(_systemPage, NSMakeRect(24, 2, 312, 16), @"", 10, NO);
    _footer.alignment = NSTextAlignmentCenter;
}
- (void)battery:(id)sender { (void)sender; _system = NO; [self selectPage]; }
- (void)system:(id)sender { (void)sender; _system = YES; [self selectPage]; }
- (void)selectPage {
    _batteryPage.hidden = _system; _systemPage.hidden = !_system;
    _batteryTab.selected = !_system; _systemTab.selected = _system;
    self.controller.powerFlowView.flowAnimationEnabled = !_system && self.window.visible;
    [self refreshCPU:_cpu memory:_memory];
}
- (void)metric:(NSButton *)sender {
    if (sender.tag < 2) _sortMemory = sender.tag == 1;
    [self system:sender];
}
- (void)sort:(NSButton *)sender { _sortMemory = sender.tag == 1; [self refreshCPU:_cpu memory:_memory]; }
- (void)activity:(id)sender {
    (void)sender;
    [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:
        @"/System/Applications/Utilities/Activity Monitor.app"]];
}
- (void)refreshCPU:(double)cpu memory:(double)memory {
    _cpu = cpu; _memory = memory;
    BattMenuController *c = self.controller;
    double io = c.diskReadRate < 0 || c.diskWriteRate < 0 ? -1 :
        (c.diskReadRate + c.diskWriteRate)/1000000;
    NSArray *values = @[cpu < 0 ? @"—" : [NSString stringWithFormat:@"%.0f%%",cpu],
        memory < 0 ? @"—" : [NSString stringWithFormat:@"%.0f%%",memory],
        io < 0 ? @"—" : [NSString stringWithFormat:io >= 100 ? @"%.0f" : @"%.1f",io]];
    for (NSInteger i = 0; i < 3; i++) {
        ((NSButton *)_summary[i]).title = values[i]; ((NSButton *)_details[i]).title = values[i];
        ((NSButton *)_summary[i]).needsDisplay = YES; ((NSButton *)_details[i]).needsDisplay = YES;
        NSString *description = [NSString stringWithFormat:@"%@ %@",
            @[@"CPU load", @"Memory used", @"Disk throughput MB/s"][i], values[i]];
        ((NSButton *)_summary[i]).accessibilityLabel = description;
        ((NSButton *)_details[i]).accessibilityLabel = description;
    }
    _read.stringValue = c.diskReadRate < 0 ? @"Read: sampling…" :
        [NSString stringWithFormat:@"Read %.1f MB/s",c.diskReadRate/1000000];
    _write.stringValue = c.diskWriteRate < 0 ? @"Write: sampling…" :
        [NSString stringWithFormat:@"Write %.1f MB/s",c.diskWriteRate/1000000];
    _storage.stringValue = c.diskTotalBytes == 0 ? @"Storage unavailable" :
        [NSString stringWithFormat:@"%.0f%% used · %@ free of %@",c.diskSpacePercent,
            [NSByteCountFormatter stringFromByteCount:c.diskFreeBytes countStyle:NSByteCountFormatterCountStyleFile],
            [NSByteCountFormatter stringFromByteCount:c.diskTotalBytes countStyle:NSByteCountFormatterCountStyleFile]];
    c.chargeButton.title = [NSString stringWithFormat:@"Limit %ld%% ›",(long)c.powerFlowView.displayedLimitPercent];
    c.heatButton.title = @"Heat protection ›";
    c.heatButton.toolTip = [c item:BattItemHeatProtection].title;
    c.darkButton.title = [c isDarkWorkActive] ? @"Restore display" : @"Screen off";
    c.darkButton.accessibilityLabel = c.darkButton.title;
    c.chargeButton.accessibilityLabel = c.chargeButton.title;
    c.chargeButton.enabled = ![c item:BattItemQuickLimits].hidden;
    c.heatButton.enabled = ![c item:BattItemHeatProtection].hidden;
    c.powerFlowView.limitEditable = c.chargeButton.enabled && [c item:BattItemLimit80].enabled;
    _cpuSort.selected = !_sortMemory; _memorySort.selected = _sortMemory;
    NSArray *cpuApps = [c.appStats sortedArrayUsingDescriptors:@[
        [NSSortDescriptor sortDescriptorWithKey:@"cpu" ascending:NO],
        [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES]]];
    NSArray *memoryApps = [c.appStats sortedArrayUsingDescriptors:@[
        [NSSortDescriptor sortDescriptorWithKey:@"memory" ascending:NO],
        [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES]]];
    NSDictionary *cpuApp = cpuApps.firstObject;
    NSDictionary *memoryApp = memoryApps.firstObject;
    if ([memoryApp[@"pid"] isEqual:cpuApp[@"pid"]] && memoryApps.count > 1) memoryApp = memoryApps[1];
    [(WattAppRow *)_featured[0] update:cpuApp memory:NO];
    [(WattAppRow *)_featured[1] update:memoryApp memory:YES];
    _overviewEmpty.hidden = cpuApps.count > 0;
    NSArray *apps = _sortMemory ? memoryApps : cpuApps;
    for (NSInteger i = 0; i < _rows.count; i++)
        [(WattAppRow *)_rows[i] update:i < apps.count ? apps[i] : nil memory:_sortMemory];
    _empty.hidden = apps.count > 0;
    _footer.stringValue = c.powerFlowView.chargePercent < 0 ? @"Battery unavailable" :
        [NSString stringWithFormat:@"Battery %ld%% · %@ · %.1f°C",(long)c.powerFlowView.chargePercent,
            c.powerFlowView.pluggedIn ? @"Plugged in" : @"On battery",c.powerFlowView.temperatureCelsius];
    [c.powerFlowView setNeedsDisplay:YES];
}
@end

void BattBuildPopover(BattMenuController *controller) {
    WattDashboard *content = [[[WattDashboard alloc] initWithFrame:NSMakeRect(0,0,360,480)] autorelease];
    content.controller = controller;
    content.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    [content build];
    NSViewController *viewController = [[[NSViewController alloc] init] autorelease];
    viewController.view = content;
    controller.popover = [[[NSPopover alloc] init] autorelease];
    controller.popover.behavior = NSPopoverBehaviorTransient;
    controller.popover.delegate = controller;
    controller.popover.contentSize = content.frame.size;
    controller.popover.contentViewController = viewController;
}
void BattRefreshPopover(BattMenuController *controller, double cpu, double memory) {
    WattDashboard *view = (WattDashboard *)controller.popover.contentViewController.view;
    [view refreshCPU:cpu memory:memory];
}
