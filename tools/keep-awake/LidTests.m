#import "../../pkg/gui/native_internal.h"
#include <assert.h>
#include <math.h>

int main(void) {
    @autoreleasepool {
        assert(([WattLidBrightnessPlan(YES,YES,@0.65,nil) isEqual:@{@"action":@"dim", @"level":@0.65}]));
        assert(WattLidBrightnessPlan(YES,YES,@0,@0.65) == nil);
        assert(([WattLidBrightnessPlan(YES,YES,@0.3,@0.65) isEqual:@{@"action":@"dim", @"level":@0.65}]));
        assert(([WattLidBrightnessPlan(YES,NO,@0,@0.65) isEqual:@{@"action":@"restore", @"level":@0.65}]));
        assert(([WattLidBrightnessPlan(NO,YES,@0,@0.65) isEqual:@{@"action":@"restore", @"level":@0.65}]));
        assert([WattLidBrightnessPlan(YES,NO,@0.8,@0.65) isEqual:@{@"action":@"forget"}]);
        assert(WattLidBrightnessPlan(YES,NO,nil,@0.65) == nil);
        assert(WattLidBrightnessPlan(YES,YES,@0,nil) == nil);
        assert(WattLidBrightnessPlan(YES,YES,nil,nil) == nil);
        assert(WattLidBrightnessPlan(YES,YES,@(NAN),nil) == nil);
        assert(WattLidBrightnessPlan(YES,YES,@1.1,nil) == nil);
        assert(WattLidBrightnessPlan(YES,NO,@0,@(NAN)) == nil);
        assert(WattLidBrightnessPlan(NO,NO,@0.5,nil) == nil);
        puts("Lid brightness policy checks passed");
    }
}
