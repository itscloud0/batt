# Native dashboard checks

From the repository root, on macOS with Xcode command-line tools:

```sh
clang -mmacosx-version-min=13.0 \
  -framework Cocoa -framework ServiceManagement -framework IOKit -framework QuartzCore \
  tools/power-flow-preview/dashboard.m pkg/gui/*.m \
  -o /tmp/wattnook-dashboard-preview
/tmp/wattnook-dashboard-preview /tmp/wattnook-dashboard-renders
```

The harness uses illustrative app/power values, not the daemon. It renders Battery in seven power states, System sorted by CPU and memory, and an empty System state. It checks tab changes, the keyboard charge-limit callback, rate-counter resets, invalid timing, idle traffic, and Core Animation start/stop (respecting Reduce Motion). It also reads real internal-drive counters through IOKit. It never sends daemon commands or quits another app. A test window briefly opens for the animation check.

`main.m` is the older isolated power-canvas renderer. Link it with `native_power_flow.m`, Cocoa and QuartzCore; do not compile both harness main files into one executable.

AppKit execution needs a normal host session. In a restrictive automation sandbox, compile there but launch the test with narrowly scoped host permission.
