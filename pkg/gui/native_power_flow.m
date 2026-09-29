#import "native_internal.h"

static void Text(NSString *value, NSRect rect, CGFloat size, NSFontWeight weight,
                 NSColor *color, NSTextAlignment alignment) {
    NSDictionary *style = @{
        NSFontAttributeName: [NSFont systemFontOfSize:size weight:weight],
        NSForegroundColorAttributeName: color,
    };
    NSSize measured = [value sizeWithAttributes:style];
    CGFloat x = NSMinX(rect);
    if (alignment == NSTextAlignmentCenter) x = NSMidX(rect) - measured.width / 2;
    if (alignment == NSTextAlignmentRight) x = NSMaxX(rect) - measured.width;
    [value drawAtPoint:NSMakePoint(x, NSMidY(rect) - measured.height / 2)
      withAttributes:style];
}

static void Symbol(NSString *name, NSRect rect, CGFloat size, NSColor *color) {
    NSImage *source = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
    if (source == nil) return;
    source = [source imageWithSymbolConfiguration:
        [NSImageSymbolConfiguration configurationWithPointSize:size weight:NSFontWeightRegular]];
    NSSize intrinsic = source.size;
    if (intrinsic.width <= 0 || intrinsic.height <= 0) return;
    CGFloat scale = MIN(NSWidth(rect) / intrinsic.width, NSHeight(rect) / intrinsic.height);
    NSSize fitted = NSMakeSize(intrinsic.width * scale, intrinsic.height * scale);
    NSRect target = NSMakeRect(NSMidX(rect) - fitted.width / 2,
                               NSMidY(rect) - fitted.height / 2,
                               fitted.width, fitted.height);
    NSImage *tinted = [[[NSImage alloc] initWithSize:fitted] autorelease];
    [tinted lockFocus];
    [source drawInRect:NSMakeRect(0, 0, fitted.width, fitted.height)
             fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
    [color setFill];
    NSRectFillUsingOperation(NSMakeRect(0, 0, fitted.width, fitted.height),
                             NSCompositingOperationSourceAtop);
    [tinted unlockFocus];
    [tinted drawInRect:target fromRect:NSZeroRect
            operation:NSCompositingOperationSourceOver fraction:1];
}

static void FlowNode(NSString *symbol, NSRect rect, NSColor *symbolColor, BOOL dark) {
    NSColor *surface = dark ? [NSColor.whiteColor colorWithAlphaComponent:0.10] :
        [NSColor.blackColor colorWithAlphaComponent:0.07];
    [surface setFill];
    [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:8 yRadius:8] fill];
    Symbol(symbol, NSInsetRect(rect, 7, 7), 19, symbolColor);
}

static NSColor *FlowColor(void) {
    return [NSColor colorWithCalibratedRed:0.39 green:0.62 blue:0.84 alpha:1];
}

static void Flow(CGFloat x0, CGFloat y0, CGFloat x1, CGFloat y1,
                 CGFloat startWidth, CGFloat endWidth) {
    CGFloat thickness = (startWidth + endWidth) / 2;
    CGFloat span = x1 - x0;
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path moveToPoint:NSMakePoint(x0, y0)];
    [path curveToPoint:NSMakePoint(x1, y1)
         controlPoint1:NSMakePoint(x0 + span * 0.45, y0)
         controlPoint2:NSMakePoint(x1 - span * 0.45, y1)];
    path.lineWidth = thickness;
    path.lineCapStyle = NSLineCapStyleRound;
    [FlowColor() setStroke];
    [path stroke];
}

// A filled ribbon keeps its own width through a split or merge. Unlike
// overlapping round-capped strokes, adjacent ribbons share one clean edge.
static void Ribbon(CGFloat x0, CGFloat top0, CGFloat bottom0,
                   CGFloat x1, CGFloat top1, CGFloat bottom1) {
    CGFloat span = x1 - x0;
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path moveToPoint:NSMakePoint(x0, top0)];
    [path curveToPoint:NSMakePoint(x1, top1)
         controlPoint1:NSMakePoint(x0 + span * 0.45, top0)
         controlPoint2:NSMakePoint(x1 - span * 0.45, top1)];
    [path lineToPoint:NSMakePoint(x1, bottom1)];
    [path curveToPoint:NSMakePoint(x0, bottom0)
         controlPoint1:NSMakePoint(x1 - span * 0.45, bottom1)
         controlPoint2:NSMakePoint(x0 + span * 0.45, bottom0)];
    [path closePath];
    [FlowColor() setFill];
    [path fill];
}

static void RoundCap(CGFloat x, CGFloat center, CGFloat diameter) {
    [FlowColor() setFill];
    [[NSBezierPath bezierPathWithOvalInRect:
        NSMakeRect(x, center - diameter / 2, diameter, diameter)] fill];
}

static CGFloat FlowWidth(double watts) {
    return MIN(16, MAX(7, 4 + sqrt(MAX(0, watts)) * 1.8));
}

static NSString *Watts(double watts) {
    return [NSString stringWithFormat:@"≈%.1f W", MAX(0, watts)];
}

@implementation BattPowerFlowView {
    NSInteger _previewLimitPercent;
    BOOL _limitDragging;
    BOOL _limitMoved;
    NSPoint _limitDragStart;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _chargePercent = -1;
        _limitPercent = 80;
        _previewLimitPercent = 80;
    }
    return self;
}

- (void)setLimitPercent:(NSInteger)limitPercent {
    _limitPercent = MAX(0, MIN(100, limitPercent));
    if (!_limitDragging) _previewLimitPercent = _limitPercent;
    [self setNeedsDisplay:YES];
    [self.window invalidateCursorRectsForView:self];
}

- (NSInteger)displayedLimitPercent {
    return _previewLimitPercent;
}

- (NSRect)railRect {
    return NSMakeRect(20, 131, NSWidth(self.bounds) - 40, 6);
}

- (CGFloat)markerX {
    NSRect rail = [self railRect];
    return NSMinX(rail) + NSWidth(rail) * self.displayedLimitPercent / 100.0;
}

- (NSInteger)limitForPoint:(NSPoint)point {
    NSRect rail = [self railRect];
    double fraction = (point.x - NSMinX(rail)) / NSWidth(rail);
    NSInteger value = (NSInteger)round(fraction * 100.0 / 5.0) * 5;
    // 100% disables charging control; keep that explicit in the existing menu.
    return MAX(20, MIN(95, value));
}

- (void)updatePreviewWithEvent:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    _previewLimitPercent = [self limitForPoint:point];
    [self setNeedsDisplay:YES];
    [self.window invalidateCursorRectsForView:self];
}

- (void)commitPreview {
    if (_previewLimitPercent != _limitPercent) {
        [NSApp sendAction:self.limitAction to:self.limitTarget from:self];
    } else {
        [self setNeedsDisplay:YES];
    }
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (!self.limitEditable || fabs(point.x - [self markerX]) > 16 ||
        fabs(point.y - NSMidY([self railRect])) > 16) {
        [super mouseDown:event];
        return;
    }
    _limitDragging = YES;
    _limitMoved = NO;
    _limitDragStart = point;
    [self.window makeFirstResponder:self];
}

- (void)mouseDragged:(NSEvent *)event {
    if (!_limitDragging) return;
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (fabs(point.x - _limitDragStart.x) < 3 && !_limitMoved) return;
    _limitMoved = YES;
    [self updatePreviewWithEvent:event];
}

- (void)mouseUp:(NSEvent *)event {
    if (!_limitDragging) return;
    if (_limitMoved) [self updatePreviewWithEvent:event];
    _limitDragging = NO;
    if (_limitMoved) [self commitPreview];
}

- (BOOL)acceptsFirstResponder {
    return self.limitEditable;
}

- (void)keyDown:(NSEvent *)event {
    if (self.limitEditable && (event.keyCode == 123 || event.keyCode == 124)) {
        NSInteger direction = event.keyCode == 123 ? -5 : 5;
        _previewLimitPercent = MAX(20, MIN(95, self.displayedLimitPercent + direction));
        [self commitPreview];
        return;
    }
    [super keyDown:event];
}

- (void)resetCursorRects {
    [super resetCursorRects];
    if (self.limitEditable) {
        [self addCursorRect:NSMakeRect([self markerX] - 16, 119, 32, 30)
                    cursor:NSCursor.openHandCursor];
    }
}

- (BOOL)isAccessibilityElement { return self.limitEditable; }
- (NSString *)accessibilityRole { return NSAccessibilitySliderRole; }
- (NSString *)accessibilityLabel { return @"Charge limit"; }
- (id)accessibilityValue { return @(self.displayedLimitPercent); }
- (id)accessibilityMinValue { return @20; }
- (id)accessibilityMaxValue { return @95; }
- (void)accessibilitySetValue:(id)value {
    if (!self.limitEditable || ![value respondsToSelector:@selector(integerValue)]) return;
    _previewLimitPercent = MAX(20, MIN(95,
        (NSInteger)round([value doubleValue] / 5.0) * 5));
    [self commitPreview];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    CGFloat width = NSWidth(self.bounds);
    CGFloat right = width - 20;
    BOOL dark = [[self.effectiveAppearance bestMatchFromAppearancesWithNames:
        @[NSAppearanceNameDarkAqua, NSAppearanceNameAqua]] isEqualToString:NSAppearanceNameDarkAqua];
    NSInteger charge = MAX(0, MIN(100, self.chargePercent));
    NSInteger limit = self.displayedLimitPercent;
    BOOL adapter = self.hasTelemetry && self.pluggedIn && self.adapterWatts > 0.25;
    BOOL charging = self.hasTelemetry && self.batteryWatts > 0.25;
    BOOL discharging = self.hasTelemetry && self.batteryWatts < -0.25;
    BOOL hybrid = adapter && discharging;
    BOOL atLimit = adapter && !charging && !discharging &&
        limit < 100 && self.chargePercent >= limit - 1;
    NSString *state = !self.hasTelemetry ? @"Power data unavailable" :
        (hybrid ? @"AC + battery" :
         (self.heatPaused && self.pluggedIn ? @"Charging paused · heat" :
          (charging ? @"Charging" :
           (atLimit ? @"Charge limit reached" : (adapter ? @"Plugged in" : @"On battery")))));
    NSString *chargeText = self.chargePercent < 0 ? @"—%" :
        [NSString stringWithFormat:@"%ld%%", (long)charge];

    Text(chargeText, NSMakeRect(20, 171, 145, 45), 36, NSFontWeightSemibold,
         NSColor.labelColor, NSTextAlignmentLeft);
    Text(state, NSMakeRect(20, 148, 235, 20), 12, NSFontWeightRegular,
         NSColor.secondaryLabelColor, NSTextAlignmentLeft);
    if (self.temperatureCelsius > 0) {
        Text([NSString stringWithFormat:@"%.1f°C", self.temperatureCelsius],
             NSMakeRect(right - 56, 148, 56, 20), 12, NSFontWeightMedium,
             NSColor.labelColor, NSTextAlignmentRight);
    }

    NSRect rail = [self railRect];
    NSColor *trackColor = dark ? [NSColor.whiteColor colorWithAlphaComponent:0.13] :
        [NSColor.blackColor colorWithAlphaComponent:0.14];
    [trackColor setFill];
    [[NSBezierPath bezierPathWithRoundedRect:rail xRadius:3 yRadius:3] fill];
    if (self.chargePercent >= 0 && charge > 0) {
        NSColor *fillColor = charging ? NSColor.systemGreenColor :
            (charge <= 20 ? NSColor.systemOrangeColor : NSColor.systemBlueColor);
        [fillColor setFill];
        NSRect fill = rail;
        fill.size.width = MAX(6, rail.size.width * charge / 100.0);
        [[NSBezierPath bezierPathWithRoundedRect:fill xRadius:3 yRadius:3] fill];
    }
    CGFloat markerX = [self markerX];
    [NSColor.labelColor setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(markerX - 1.5, 126, 3, 16)
                                     xRadius:2 yRadius:2] fill];
    // A real button, layered by the controller, labels this marker and opens exact limits.
    [[NSColor colorWithCalibratedWhite:dark ? 0.28 : 0.80 alpha:1] setFill];
    NSRectFill(NSMakeRect(14, 104, width - 28, 0.7));

    if (!self.hasTelemetry) {
        Text(@"Power flow unavailable", NSMakeRect(20, 23, width - 40, 40),
             12, NSFontWeightMedium, NSColor.secondaryLabelColor, NSTextAlignmentCenter);
        return;
    }

    // IOKit can briefly report battery charging power above adapter input.
    // Its derived system power is then clamped to zero; don't draw that as fact.
    if (charging && (!self.pluggedIn || self.adapterWatts < self.batteryWatts + 0.5 ||
                     self.systemWatts < 0.5)) {
        Text(@"Power readings updating", NSMakeRect(20, 52, width - 40, 20),
             12, NSFontWeightMedium, NSColor.labelColor, NSTextAlignmentCenter);
        Text(@"Adapter and battery data disagree", NSMakeRect(20, 30, width - 40, 18),
             10, NSFontWeightRegular, NSColor.secondaryLabelColor, NSTextAlignmentCenter);
        return;
    }

    NSColor *muted = NSColor.secondaryLabelColor;
    CGFloat x0 = 67, x1 = width - 67;
    if (adapter && charging) {
        CGFloat split = 128, center = 49;
        CGFloat toBattery = FlowWidth(self.batteryWatts);
        CGFloat toMac = FlowWidth(self.systemWatts);
        CGFloat total = toBattery + toMac;
        CGFloat boundary = center - total / 2 + toMac;
        Ribbon(split, center + total / 2, boundary,
               x1, 70 + toBattery / 2, 70 - toBattery / 2);
        Ribbon(split, boundary, center - total / 2,
               x1, 28 + toMac / 2, 28 - toMac / 2);
        [FlowColor() setFill];
        NSRectFill(NSMakeRect(x0, center - total / 2, split - x0 + 1, total));
        FlowNode(@"powerplug.fill", NSMakeRect(20, 32, 34, 34), muted, dark);
        FlowNode(@"battery.100percent", NSMakeRect(width - 54, 53, 34, 34), muted, dark);
        FlowNode(@"laptopcomputer", NSMakeRect(width - 54, 11, 34, 34), muted, dark);
        Text([NSString stringWithFormat:@"To battery · %@", Watts(self.batteryWatts)],
             NSMakeRect(135, 85, 136, 16), 10.5, NSFontWeightSemibold,
             NSColor.labelColor, NSTextAlignmentRight);
        Text([NSString stringWithFormat:@"To Mac · %@", Watts(self.systemWatts)],
             NSMakeRect(135, 4, 136, 16), 10.5, NSFontWeightSemibold,
             NSColor.labelColor, NSTextAlignmentRight);
        Text([NSString stringWithFormat:@"AC %@", Watts(self.adapterWatts)],
             NSMakeRect(20, 7, 100, 16), 10, NSFontWeightMedium,
             muted, NSTextAlignmentLeft);
    } else if (hybrid) {
        CGFloat join = 215, center = 49;
        CGFloat fromAdapter = FlowWidth(self.adapterWatts);
        CGFloat fromBattery = FlowWidth(-self.batteryWatts);
        CGFloat total = fromAdapter + fromBattery;
        CGFloat boundary = center - total / 2 + fromBattery;
        Ribbon(x0, 70 + fromAdapter / 2, 70 - fromAdapter / 2,
               join, center + total / 2, boundary);
        Ribbon(x0, 28 + fromBattery / 2, 28 - fromBattery / 2,
               join, boundary, center - total / 2);
        [FlowColor() setFill];
        NSRectFill(NSMakeRect(join, center - total / 2, x1 - join, total));
        FlowNode(@"powerplug.fill", NSMakeRect(20, 53, 34, 34), muted, dark);
        FlowNode(@"battery.100percent", NSMakeRect(20, 11, 34, 34), muted, dark);
        FlowNode(@"laptopcomputer", NSMakeRect(width - 54, 32, 34, 34), muted, dark);
        Text([NSString stringWithFormat:@"AC · %@", Watts(self.adapterWatts)],
             NSMakeRect(67, 85, 140, 16), 10.5, NSFontWeightSemibold,
             NSColor.labelColor, NSTextAlignmentLeft);
        Text([NSString stringWithFormat:@"Battery · %@", Watts(-self.batteryWatts)],
             NSMakeRect(67, 4, 140, 16), 10.5, NSFontWeightSemibold,
             NSColor.labelColor, NSTextAlignmentLeft);
        Text([NSString stringWithFormat:@"Mac · %@", Watts(self.systemWatts)],
             NSMakeRect(217, 7, 65, 16), 10, NSFontWeightMedium,
             muted, NSTextAlignmentRight);
    } else {
        BOOL fromBattery = !adapter;
        double watts = fromBattery ? -self.batteryWatts : self.adapterWatts;
        if (watts > 0.25) Flow(x0, 50, x1, 50, FlowWidth(watts), FlowWidth(watts));
        FlowNode(fromBattery ? @"battery.100percent" : @"powerplug.fill",
                 NSMakeRect(20, 33, 34, 34), muted, dark);
        FlowNode(@"laptopcomputer", NSMakeRect(width - 54, 33, 34, 34), muted, dark);
        Text([NSString stringWithFormat:@"%@ → Mac · %@",
              fromBattery ? @"Battery" : @"Adapter", Watts(watts)],
             NSMakeRect(75, 74, width - 150, 19), 11, NSFontWeightSemibold,
             NSColor.labelColor, NSTextAlignmentCenter);
        Text(fromBattery ? @"Battery" : @"Adapter", NSMakeRect(12, 9, 50, 16),
             10, NSFontWeightMedium, muted, NSTextAlignmentCenter);
        Text(@"Mac", NSMakeRect(width - 61, 9, 45, 16),
             10, NSFontWeightMedium, muted, NSTextAlignmentCenter);
        if (adapter && !charging) {
            Text(@"Battery held · 0 W", NSMakeRect(84, 9, width - 168, 17),
                 10, NSFontWeightMedium, muted, NSTextAlignmentCenter);
        }
    }
}

@end
