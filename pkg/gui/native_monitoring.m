#import "native_internal.h"
#import <sys/sysctl.h>
#import <math.h>
#import <float.h>

BOOL WattMonitoringEnabled(void) {
    id saved = [NSUserDefaults.standardUserDefaults objectForKey:@"WattNookMonitoringEnabled"];
    return saved == nil || [saved boolValue];
}
BOOL WattHistoryEnabled(void) {
    return WattMonitoringEnabled() && [NSUserDefaults.standardUserDefaults boolForKey:@"WattNookHistoryEnabled"];
}
NSInteger WattMemoryPressureLevel(void) {
    // XNU returns DISPATCH_MEMORYPRESSURE_* flags, not a RAM-used percentage.
    // This sysctl is not a stable public API: unsupported/denied means unknown.
    uint32_t level = 0; size_t size = sizeof(level);
    if (sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, NULL, 0) != 0 || size != sizeof(level)) return 0;
    return level == DISPATCH_MEMORYPRESSURE_NORMAL || level == DISPATCH_MEMORYPRESSURE_WARN ||
        level == DISPATCH_MEMORYPRESSURE_CRITICAL ? level : 0;
}
NSString *WattMemoryPressureLabel(NSInteger level) {
    switch (level) {
        case DISPATCH_MEMORYPRESSURE_NORMAL: return @"Normal";
        case DISPATCH_MEMORYPRESSURE_WARN: return @"Elevated";
        case DISPATCH_MEMORYPRESSURE_CRITICAL: return @"Critical";
        default: return @"Unavailable";
    }
}
static double Reading(double value, double maximum) {
    return isfinite(value) && value >= 0 && value <= maximum ? value : NAN;
}
@implementation WattMetricHistory
- (NSUInteger)count { return _count; }
- (WattMetricSample)sampleAtIndex:(NSUInteger)index {
    if (index >= _count) return (WattMetricSample){NAN,NAN,NAN,NAN,NAN};
    return _samples[(_next + WattHistoryCapacity - _count + index) % WattHistoryCapacity];
}
- (void)append:(WattMetricSample)sample {
    if (!isfinite(sample.time)) return;
    if (_count) {
        double elapsed = sample.time - [self sampleAtIndex:_count-1].time;
        if (elapsed < 0) { _count = 0; _next = 0; }
        else if (elapsed < 10) return;
    }
    sample.cpu = Reading(sample.cpu,100); sample.memory = Reading(sample.memory,100);
    sample.watts = Reading(sample.watts,DBL_MAX); sample.disk = Reading(sample.disk,DBL_MAX);
    _samples[_next] = sample; _next = (_next+1)%WattHistoryCapacity;
    _count = MIN(_count+1,WattHistoryCapacity);
}
@end

static double Value(WattMetricSample sample, NSInteger metric) {
    switch (metric) { case 0:return sample.cpu; case 1:return sample.memory;
        case 2:return sample.watts; default:return sample.disk; }
}
static NSString *ValueLabel(double value, NSInteger metric) {
    if (!isfinite(value)) return @"—";
    if (metric < 2) return [NSString stringWithFormat:@"%.0f%%",value];
    if (metric == 2) return [NSString stringWithFormat:@"%.1f W",value];
    return [WattCompactBytes(value*1000000,NO) stringByAppendingString:@"/s"];
}
@implementation WattHistoryView
- (void)dealloc { [_history release]; [super dealloc]; }
- (BOOL)isAccessibilityElement { return YES; }
- (NSString *)accessibilityRole { return NSAccessibilityGroupRole; }
- (NSString *)accessibilityLabel {
    if (!self.history) return @"History is off. Enable it in Settings.";
    WattMetricSample sample = [self.history sampleAtIndex:self.history.count ? self.history.count-1 : 0];
    double age = NSDate.timeIntervalSinceReferenceDate-sample.time;
    if (!isfinite(age) || age < 0 || age > 30) sample = (WattMetricSample){NAN,NAN,NAN,NAN,NAN};
    return [NSString stringWithFormat:@"Last 15 minutes. CPU %@, memory %@, estimated Mac power %@, disk %@",
        ValueLabel(sample.cpu,0),ValueLabel(sample.memory,1),ValueLabel(sample.watts,2),ValueLabel(sample.disk,3)];
}
- (void)drawRect:(NSRect)dirty {
    (void)dirty;
    NSDictionary *caption = @{NSFontAttributeName:[NSFont systemFontOfSize:11],
        NSForegroundColorAttributeName:NSColor.secondaryLabelColor};
    if (!self.history || !self.history.count) {
        NSString *message = self.history ? @"Collecting history…" : @"Enable history in Settings to begin.";
        [message drawInRect:NSMakeRect(0,self.bounds.size.height/2,312,30) withAttributes:caption]; return;
    }
    NSTimeInterval now = NSDate.timeIntervalSinceReferenceDate;
    WattMetricSample last = [self.history sampleAtIndex:self.history.count-1];
    NSArray *names = @[@"CPU load",@"Memory used",@"Mac power · estimate",@"Disk read + write"];
    for (NSInteger metric=0;metric<4;metric++) {
        CGFloat y = self.bounds.size.height-(metric+1)*80;
        [names[metric] drawAtPoint:NSMakePoint(0,y+58) withAttributes:caption];
        NSString *label = ValueLabel(now >= last.time && now-last.time <= 30 ? Value(last,metric) : NAN,metric);
        NSDictionary *style = @{NSFontAttributeName:[NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightMedium],
            NSForegroundColorAttributeName:NSColor.labelColor};
        [label drawAtPoint:NSMakePoint(NSWidth(self.bounds)-[label sizeWithAttributes:style].width,y+57) withAttributes:style];
        NSRect plot = NSMakeRect(1,y+9,NSWidth(self.bounds)-2,40);
        [[NSColor.separatorColor colorWithAlphaComponent:0.5] setStroke];
        NSBezierPath *baseline = [NSBezierPath bezierPath];
        [baseline moveToPoint:plot.origin]; [baseline lineToPoint:NSMakePoint(NSMaxX(plot),plot.origin.y)]; [baseline stroke];
        double maximum = metric < 2 ? 100 : 1;
        for (NSUInteger i=0;i<self.history.count;i++) {
            WattMetricSample sample = [self.history sampleAtIndex:i]; double value = Value(sample,metric);
            if (sample.time >= now-900 && sample.time <= now && isfinite(value)) maximum = MAX(maximum,value);
        }
        NSBezierPath *line = [NSBezierPath bezierPath]; line.lineWidth = 1.5;
        BOOL connected = NO; double previousTime = 0;
        for (NSUInteger i=0;i<self.history.count;i++) {
            WattMetricSample sample = [self.history sampleAtIndex:i]; double value = Value(sample,metric);
            if (sample.time < now-900 || sample.time > now || !isfinite(value)) { connected = NO; continue; }
            NSPoint point = NSMakePoint(plot.origin.x+plot.size.width*(sample.time-(now-900))/900,
                plot.origin.y+plot.size.height*value/maximum);
            if (connected && sample.time-previousTime <= 30) [line lineToPoint:point];
            else [line moveToPoint:point];
            connected = YES; previousTime = sample.time;
        }
        [WattAccentColor() setStroke]; [line stroke];
    }
}
@end
