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
- CPU load, physical memory used, and storage space used. Per-app CPU and memory readings are available; the app can request a normal Quit after confirmation. Force Quit is not implemented.
- Bundled Dark Work helper turns the display off while keeping the Mac awake, then automatically ends the session on display wake; there is no separate menu-bar app.
- Keep the single combined menu-bar item and recognizable macOS battery states. Keep advanced controls discoverable without making the primary popover a command dump.

## Brand Commitments

The user likes AlDente Pro's battery-state and power-flow presentation and CleanMyMac's compact menu-bar diagnostics. The old Batt Thermal popover's visual language is rejected. The interface must state what each value measures and where power flows. WattNook is the user-facing name; daemon and CLI keep their current names for compatibility.

## Evidence on Hand

Existing AppKit implementation in `pkg/gui/`; previously generated state mockups in `.lazyweb/design-improve/batt-states-2026-09-27/`; user screenshots in the conversation; live app on the user's Mac. No release-quality visual approval of the current popover.

## Product Principles

1. Show the source, destination, and meaning of every watt value.
2. Give battery controls and system diagnostics equal prominence.
3. Make a heavy app identifiable before offering a normal Quit.
4. Show unavailable or inconsistent telemetry honestly.

## Verified handoff (2026-09-30)

- `go test ./...` passes; the bundled Swift helper and app package compile.
- The six synthetic power states render in `tools/power-flow-preview/`; charging and hybrid paths have a shared trunk, separate endpoints, and labels outside the ribbons.
- The installed menu-bar app is WattNook. The legacy `batt-thermal` daemon and socket are intentionally unchanged.
- A real display-sleep/wake test cleared the Dark Work state and its idle-sleep assertion. HID-based recognition of physical versus synthetic activity remains best-effort.
- Next: review a screenshot of the live popover and iterate on visual fidelity. The offscreen preview does not prove the full installed popover looks right.
