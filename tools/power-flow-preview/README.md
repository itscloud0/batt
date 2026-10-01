# Native dashboard checks

From the repository root, on macOS with Xcode command-line tools:

```sh
clang -mmacosx-version-min=13.0 \
  -framework Cocoa -framework ServiceManagement -framework IOKit -framework QuartzCore \
  tools/power-flow-preview/dashboard.m pkg/gui/*.m \
  -o /tmp/wattnook-dashboard-preview
/tmp/wattnook-dashboard-preview /tmp/wattnook-dashboard-renders
```

The harness uses illustrative app/power values, not the daemon. It renders Battery in seven power states, unplug/updating transitions, SSD used/free storage, System sorted by CPU, memory and disk, empty telemetry, settings and all four palettes. It checks tab changes, the keyboard charge-limit callback, saved menu-bar combinations (including the reachable-icon guard), coherent unplug snapshots, rate-counter resets, invalid timing, idle traffic, and Core Animation start/stop (respecting Reduce Motion). It also reads real internal-drive counters through IOKit and samples per-process diagnostics. It never sends daemon commands or quits another app. A test window briefly opens for the animation check.

`main.m` is the older isolated power-canvas renderer. Link it with `native_power_flow.m`, `native_preferences.m`, Cocoa and QuartzCore; do not compile both harness main files into one executable.

AppKit execution needs a normal host session. In a restrictive automation sandbox, compile there but launch the test with narrowly scoped host permission.

System checks additionally cover independently saved CPU/RAM/disk units, compact byte formatting through TB, unit promotion on rounding, unavailable swap, actual host swap sampling, and metric/app-row width assertions for 3 TB. CPU absolute values are core equivalents, not byte counts; app disk rates do not claim device utilization percentages.

Stability checks regress the CPU button's former -1 tag (NSRangeException), perform 300 CPU/Memory/Disk switches, reject invalid sort indices, and assert six consumer rows with a readable Swap line. Pure CPU conversion checks cover Apple Silicon and 1:1 timebases plus reset/zero-duration samples; a 250 ms single-thread busy loop checks live process CPU near one full core. The monitor includes its own PID without a Quit action. This short smoke test is not a long-term leak or energy test.

CPU presentation checks normalize raw per-core usage by the logical processor count (234 → 23.4% on ten cores), while preserving 2.34 occupied core equivalents. Tests cover single/multiple-core hosts, unavailable counts, zero usage and invalid values, and assert both displayed lines in a native consumer row. Sampling/sorting still use raw per-core usage internally.

Context-row checks assert column alignment (processes under CPU, swap under Memory, free storage under Disk), unchanged six-row consumer list and compact free-space values in GB/TB.

Set `WATTNOOK_CHECKS_ONLY=1` to run assertions without generating preview images. Label checks cycle every saved unit mode and assert arrow-free captions with the Change units tooltip preserved.

The harness also checks rail hit-testing beneath the static Limit label at 20% and 80%, the battery-percentage gap and the SSD used setting. For display-wake policy checks without sleeping the real display, compile `tools/dark-work/DarkWork.swift` with `swiftc -Onone` and run the resulting executable with `--self-test`. Assertions must be enabled for this policy check; do not use `-O`. Actual screen wake still requires a manual hardware test.

Dark Work checks cover automation-only wakes retaining the session, physical input ending it, no initial activation-click restoration, key release/zero movement/vendor telemetry rejection, and accepted USB/Bluetooth/built-in FIFO activity. `--input-status` checks permission without requesting it or opening devices. With Input Monitoring permission, `--monitor-probe` opens the physical monitor for ten seconds, then releases it, without arming activity detection or changing the display. Check resource usage during that bounded probe. Hardware wake, repeated ChatGPT wakes, permission revocation and unusual/remapped devices still require manual acceptance.
