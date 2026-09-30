# WattNook

<!-- impeccable:product-schema 1 -->

## Platform

macOS native (AppKit menu-bar application with a privileged batt daemon).

## Users

MacBook users who want charge controls and system diagnostics available from one menu-bar item. The primary use scene is checking power and resource use while working, including long-running AI tasks.

## Product Purpose

Make battery state, charging behavior, thermal protection, and CPU/memory/storage use understandable and actionable at a glance. The battery and system views have equal priority on the main popover.

## Operating Context

The app is a public GPLv2 fork of `charlie0129/batt`. It runs on Apple Silicon Macs, uses a native status item/popover, and communicates with a local batt daemon. The user wants to switch off the display while the Mac keeps working.

## Capabilities and Constraints

- Adjustable charge limit, including a draggable 20–95% rail and explicit 100%/disable action.
- Temperature-based charging hold, with separate pause and resume thresholds.
- Battery percentage, charging state, temperature, and approximate power-flow estimates. Watt values are derived from IOKit and can be temporarily inconsistent; the UI must not present contradictory readings as physical facts.
- CPU load, physical memory used, internal disk read/write MB/s and storage space used/free with an occupancy bar. Per-app CPU, resident memory and best-effort disk read/write rates (all volumes, aggregated helpers) are available; the app can request a normal Quit after confirmation. Force Quit is not implemented.
- Four saved accent palettes and selectable menu-bar CPU/RAM/SSD/battery percentage/icon combinations. An empty selection preserves the icon for access.
- Bundled Dark Work helper turns the display off while keeping the Mac awake, then automatically ends the session on display wake; there is no separate menu-bar app.
- Keep the single combined menu-bar item and recognizable macOS battery states. Keep advanced controls discoverable without making the primary popover a command dump.

## Brand Commitments

The user likes AlDente Pro's battery-state and power-flow presentation and CleanMyMac's compact menu-bar diagnostics. The old Batt Thermal popover's visual language is rejected. The interface must state what each value measures and where power flows. WattNook is the user-facing name; daemon and CLI keep their current names for compatibility.

## Evidence on Hand

Existing AppKit implementation in `pkg/gui/`; previously generated state mockups in `.lazyweb/design-improve/batt-states-2026-09-27/`; user screenshots in the conversation; live app on the user's Mac. The user approved the implemented A+C direction, then requested the scoped refinements recorded below.

## Product Principles

1. Show the source, destination, and meaning of every watt value.
2. Give battery controls and system diagnostics equal prominence.
3. Make a heavy app identifiable before offering a normal Quit.
4. Show unavailable or inconsistent telemetry honestly.

## Verified handoff (2026-09-30)

- Refinement: temperature is unboxed, source/destination watt labels are equal-weight, Battery shows SSD used/free GB and an occupancy bar instead of duplicate top-app rows. System adds Disk sorting. Settings persists four palettes and independent menu-bar fields.
- Power/connection readings now come from one local AppleSmartBattery snapshot every two seconds and after the daemon status callback. Synthetic unplug checks discard stale adapter input and show battery → Mac; zero/unavailable transition readings use an updating state, not a claimed zero-watt load. A physical unplug cycle still needs user confirmation.
- `go test ./...`, app packaging and the expanded isolated native harness passed. Native captures are in `/tmp/wattnook-refinement-renders-final/`; repository screenshots use illustrative values, not live process data. Per-app disk I/O attribution is best-effort and includes all volumes, unlike the internal-drive summary.
- Installed the refinement at `/Users/iliasorokin/Applications/WattNook.app`; previous bundle retained at `/tmp/WattNook-before-customize-20260930.app`. Restarted only the menu-bar process; the privileged daemon was untouched. README now includes native Battery/System/Settings captures, telemetry definitions, customization and fork provenance.

- `go test ./...` passes; the bundled Swift helper and app package compile.
- The six synthetic power states render in `tools/power-flow-preview/`; charging and hybrid paths have a shared trunk, separate endpoints, and labels outside the ribbons.
- The installed menu-bar app is WattNook. The legacy `batt-thermal` daemon and socket are intentionally unchanged.
- A real display-sleep/wake test cleared the Dark Work state and its idle-sleep assertion. HID-based recognition of physical versus synthetic activity remains best-effort.
- User approved A's energy ribbon, parallel actions and app icons, combined with C's separate System detail screen; B was rejected. Implemented this direction in native AppKit, at 360×480 pt. Do not regenerate or switch layouts without a new request.
- Status item ordering uses `BattThermalCombinedStatus` as its `autosaveName`. Public AppKit offers no always-rightmost position guarantee; user Command-drag placement is preserved by macOS. Startup order must not be described as placement control.
- `go test ./...` passes. The isolated dashboard harness verifies counter reset/zero-time handling, tabs, keyboard limit commit, animation start/stop, empty telemetry and seven full-popover power states (including inconsistent readings). Internal-drive counters were verified on this Mac. Final native captures are in `/tmp/wattnook-dashboard-renders-final/`; mock values are illustrative.
- Installed A+C bundle at `/Users/iliasorokin/Applications/WattNook.app`; old bundle retained at `/tmp/WattNook-before-ac-20260930.app`. Daemon, socket and configured charge limit unchanged. Computer-use host timed out twice, so live pointer interaction was not verified; native controls were tested directly by the isolated harness.
