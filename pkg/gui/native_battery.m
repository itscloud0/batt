#import "native_internal.h"
#import <IOKit/IOKitLib.h>

void BattUpdateBattery(BattMenuController *controller) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault,
        IOServiceMatching("AppleSmartBattery"));
    if (!service) return;
    CFMutableDictionaryRef properties = NULL;
    kern_return_t result = IORegistryEntryCreateCFProperties(service,&properties,kCFAllocatorDefault,0);
    IOObjectRelease(service);
    if (result != KERN_SUCCESS || !properties) return;
    BattApplyBatterySnapshot(controller,(NSDictionary *)properties);
    CFRelease(properties);
}

void BattApplyBatterySnapshot(BattMenuController *controller, NSDictionary *battery) {
    NSNumber *connected = battery[@"ExternalConnected"], *voltage = battery[@"Voltage"];
    NSNumber *current = battery[@"InstantAmperage"] ?: battery[@"Amperage"];
    NSNumber *charge = battery[@"CurrentCapacity"];
    if ([connected isKindOfClass:NSNumber.class] && [voltage isKindOfClass:NSNumber.class] &&
        [current isKindOfClass:NSNumber.class] && [charge isKindOfClass:NSNumber.class]) {
        BOOL plugged = connected.boolValue;
        double watts = voltage.doubleValue * current.longLongValue / 1000000.0;
        NSDictionary *power = battery[@"PowerTelemetryData"];
        double adapter = plugged ? [power[@"SystemPowerIn"] doubleValue]/1000.0 : 0;
        // All three flow values and the connection state come from this one snapshot.
        // Never reuse adapter input after unplugging or invent load from adapter rating.
        if (isfinite(watts) && fabs(watts) < 250 && adapter >= 0 && adapter < 250) {
            [controller setPowerFlowAdapter:adapter system:MAX(0,adapter-watts) battery:watts
                heatPaused:controller.powerFlowView.heatPaused
                temperature:controller.powerFlowView.temperatureCelsius];
            [controller setLiveStatusCharge:charge.integerValue pluggedIn:plugged
                charging:plugged && watts > 0.25 heatPaused:controller.powerFlowView.heatPaused];
        }
    }
}
