#import <Cocoa/Cocoa.h>
#import <stdint.h>

#include "native.h"

@interface BattPowerFlowView : NSView
@property(nonatomic, assign) double adapterWatts;
@property(nonatomic, assign) double systemWatts;
@property(nonatomic, assign) double batteryWatts;
@property(nonatomic, assign) double temperatureCelsius;
@property(nonatomic, assign) NSInteger chargePercent;
@property(nonatomic, assign) NSInteger limitPercent;
@property(nonatomic, assign) BOOL pluggedIn;
@property(nonatomic, assign) BOOL heatPaused;
@property(nonatomic, assign) BOOL hasTelemetry;
@property(nonatomic, assign) BOOL limitEditable;
@property(nonatomic, assign) id limitTarget;
@property(nonatomic, assign) SEL limitAction;
@property(nonatomic, assign, readonly) NSInteger displayedLimitPercent;
@property(nonatomic, assign) BOOL flowAnimationEnabled;
@end

@interface BattMenuController : NSObject <NSMenuDelegate, NSPopoverDelegate> {
    uint64_t _previousCPUTicks[4];
    BOOL _hasCPUSample;
    NSInteger _statsTickCount;
    double _cpuPercent;
    double _memoryPercent;
    double _diskPercent;
    NSTimeInterval _previousProcessSampleTime;
}
@property(nonatomic, assign) uintptr_t handle;
@property(nonatomic, retain) NSStatusItem *statusItem;
@property(nonatomic, retain) NSImage *batteryIcon;
@property(nonatomic, retain) NSMenu *menu;
@property(nonatomic, retain) NSMutableDictionary<NSNumber *, NSMenuItem *> *items;
@property(nonatomic, retain) NSTimer *timer;
@property(nonatomic, retain) NSTimer *statsTimer;
@property(nonatomic, retain) BattPowerFlowView *powerFlowView;
@property(nonatomic, retain) NSPopover *popover;
@property(nonatomic, retain) NSButton *chargeButton;
@property(nonatomic, retain) NSButton *heatButton;
@property(nonatomic, retain) NSButton *darkButton;
@property(nonatomic, retain) NSButton *statsButton;
@property(nonatomic, retain) NSButton *memoryButton;
@property(nonatomic, retain) NSButton *diskButton;
@property(nonatomic, retain) NSTextField *cpuTopAppLabel;
@property(nonatomic, retain) NSTextField *memoryTopAppLabel;
@property(nonatomic, retain) NSButton *cpuQuitButton;
@property(nonatomic, retain) NSButton *memoryQuitButton;
@property(nonatomic, retain) NSDictionary *cpuFeaturedApp;
@property(nonatomic, retain) NSDictionary *memoryFeaturedApp;
@property(nonatomic, retain) NSMenu *cpuAppsMenu;
@property(nonatomic, retain) NSMenu *memoryAppsMenu;
@property(nonatomic, retain) NSArray<NSDictionary *> *appStats;
@property(nonatomic, retain) NSDictionary<NSNumber *, NSNumber *> *previousProcessCPU;
@property(nonatomic, retain) NSDictionary *previousProcessDisk;
@property(nonatomic, retain) NSDictionary *previousDiskCounters;
@property(nonatomic, assign) NSTimeInterval previousDiskSampleTime;
@property(nonatomic, assign) double diskReadRate;
@property(nonatomic, assign) double diskWriteRate;
@property(nonatomic, assign) double diskSpacePercent;
@property(nonatomic, assign) uint64_t diskTotalBytes;
@property(nonatomic, assign) uint64_t diskFreeBytes;

- (instancetype)initWithHandle:(uintptr_t)handle version:(NSString *)version;
- (NSMenuItem *)item:(BattMenuItem)item;
- (void)rememberItem:(NSMenuItem *)item as:(BattMenuItem)identifier;
- (void)menuAction:(NSMenuItem *)sender;
- (void)noop:(NSMenuItem *)sender;
- (void)setStatusIconInstalled:(BOOL)installed
                       capable:(BOOL)capable
                  needsUpgrade:(BOOL)needsUpgrade;
- (void)setPowerItem:(BattMenuItem)item label:(NSString *)label value:(double)value;
- (void)setPowerFlowAdapter:(double)adapter
                     system:(double)system
                    battery:(double)battery
                 heatPaused:(BOOL)heatPaused
                temperature:(double)temperature;
- (void)setLimitPercent:(NSInteger)limitPercent;
- (void)setLiveStatusCharge:(NSInteger)charge
                   pluggedIn:(BOOL)pluggedIn
                    charging:(BOOL)charging
                 heatPaused:(BOOL)heatPaused;
- (void)updateSystemStats:(NSTimer *)timer;
- (void)refreshStatusImage;
- (void)updateAppStats;
- (void)updateDiagnosticMenus;
- (void)quitDiagnosedApp:(NSMenuItem *)sender;
- (void)toggleDarkWork;
- (void)setCustomHeatProtection;
- (void)refreshPopoverControls;
- (void)commitLimitFromRail:(BattPowerFlowView *)sender;
- (BOOL)isDarkWorkActive;
@end

void BattBuildMenu(BattMenuController *controller, NSString *version);
void BattApplyTooltips(BattMenuController *controller);
void BattBuildPopover(BattMenuController *controller);
void BattRefreshPopover(BattMenuController *controller, double cpu, double memory);
void BattUpdateStorage(BattMenuController *controller);
void BattUpdateBattery(BattMenuController *controller);
void BattApplyBatterySnapshot(BattMenuController *controller, NSDictionary *battery);
NSColor *WattAccentColor(void);
NSColor *WattSurfaceColor(BOOL lighter);
NSArray *WattMenuMetrics(void);
BOOL WattMenuBatteryIcon(void);
double BattCounterRate(uint64_t previous, uint64_t current, double elapsed);
