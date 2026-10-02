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

Monitoring checks cover the 90-sample history bound, ten-second throttling, invalid readings and clock rollback; pressure labels; history navigation; and off/on/off lifecycle (timer, history and process counters released). The harness draws the chart without generating artifacts in checks-only mode. Keep Awake tests also assert that unknown status preserves an active display guard and that the local event journal evicts older entries after 64 events. Test executables have no bundled helper and cannot activate the real lid guard. Sleep/wake delivery, overnight Remote access and sustained energy/memory use still require host acceptance.

For a narrow visual review, `WATTNOOK_CAPTURE_PREFIX=monitoring-` (without checks-only) writes just settings and illustrative four-series history renders. Pressure/History controls also have non-overlap assertions. No full desktop screenshots are captured.

The harness also checks rail hit-testing beneath the static Limit label at 20% and 80%, the battery-percentage gap and the SSD used setting. Screen off / Dark Work has been removed. Keep Awake policy checks (without changing sleep settings):

```sh
swiftc -parse-as-library -Onone tools/keep-awake/Policy.swift tools/keep-awake/Tests.swift -o /tmp/wattnook-keep-awake-tests
/tmp/wattnook-keep-awake-tests
clang -framework Cocoa -framework IOKit tools/keep-awake/LidTests.m pkg/gui/native_lid.m -o /tmp/wattnook-lid-tests
/tmp/wattnook-lid-tests
```

These check valid, missing, malformed and duplicate SleepDisabled telemetry, the fixed non-interactive sudo command boundary, saving/restoring brightness, duplicate close handling, unavailable/invalid readings and preserving already-restored brightness. They do not write hardware brightness. The packaged helper's `--status` reads macOS without changing settings or asking for permission. Administrator cancellation, actual closed-lid brightness/CLI continuation and remote desktop availability require manual acceptance; never infer those from policy tests.
