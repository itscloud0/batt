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

### Screen off correction (2026-10-01)

Publication requested for this correction: target `fork/thermal-ui`; include code, tests and README, exclude unrelated `docs/menubar-redesign.md`. Local/unpushed wording below records the original installation checkpoint.

Automation-only display wakes no longer end Screen off. An IOHIDManager listens only during the session to keyboard/mouse/trackpad activity from supported physical transports (including this Mac's FIFO devices); unknown/virtual transports and unrelated sensor/vendor reports are ignored. It retains one activity flag, no key content/history, and is released when the watcher exits. Input Monitoring is checked before activation; failures do not intentionally blank the display. Permission revocation ends the session. Resleep attempts are rate-limited to two seconds; session-file checks now run once a second, display checks at 250 ms. This replaces the previous any-wake policy. Existing explicit Restore remains. The UI surfaces the helper's permission error instead of hiding it behind a generic failure.

Debug Swift policy tests showed the old automation-wake regression failing, then passing with the correction. Physical activity filters, initial-click behavior and timeout checks pass. All Go packages, native UI harness and final app packaging passed (existing AppKit category/link-target warnings remain). Ten-second host HID lifecycle probe succeeded: one idle snapshot showed 9,040 KB RSS and 0.0% CPU; this is not a long-run energy/leak test. Sandbox permission checks reported denied while host checks reported granted, so device/resource checks ran with host permission. Build output `/tmp/WattNook-physical-wake-final.app`; previous installed bundle `/tmp/WattNook-before-physical-wake-20261001.app`. Old Screen off session is ended for replacement; user must activate the new session. Charging daemon is untouched. Changes are local, not pushed.

Next acceptance: physical key/trackpad/mouse wake and repeated real ChatGPT wake on the installed app. The actual app may still require its own Input Monitoring approval despite the host probe's permission. No claim of zero wake flashes, keyboard-backlight control, or support for unknown/remapped HID devices. Do not run a real screen-sleep test unattended through computer-use tools.

- Publication scope: user requested pushing the caption and flow refinements to `fork/thermal-ui` (`itscloud0/wattnook`). README and native-check documentation accompany the UI changes. `docs/menubar-redesign.md` is unrelated and excluded. Prior local/unpushed notes below describe their original implementation checkpoints.

- Flow refinement: charging/hybrid branches now form one continuous outline with a rounded 3 pt inner junction; removed the old three-ribbon geometry. Single-source waist is shallower. A stronger 2.2 s traveling Core Animation highlight conveys flow, without oscillating the contour or introducing a frame timer. Existing visible-Battery/Reduce Motion gating remains. Charging/hybrid native renders inspected; native tests check the single closed mask, junction interior/exterior points, pulse duration and animation shutdown. Go GUI tests and packaging passed. Installed `/tmp/WattNook-rounded-flow.app` into the usual Applications path, preserving `/tmp/WattNook-before-rounded-flow-20260930.app`. Charging daemon untouched. Local changes only; next acceptance is the user's live motion/shape judgment, not a static screenshot. No long-run performance claim from this short check.

- Caption cleanup: removed ↔ from every System metric unit mode. Click-to-cycle, saved preferences, hover feedback, tooltip and VoiceOver descriptions remain. Go GUI tests, native unit-cycle assertions and packaging passed; native checks ran with WATTNOOK_CHECKS_ONLY=1, generating no preview images. Installed clean-labels build; backup `/tmp/WattNook-before-clean-labels-20260930.app`. Changes are local/unpushed after the earlier GitHub update. Unrelated screenshot-to-clipboard request is informational: Apple's Control shortcut targets clipboard instead of a file; simultaneous file+clipboard needs separate automation, not configured without user approval.

- Flow-check caveat: one final native run failed the existing host-dependent busy-thread CPU threshold before reaching flow assertions; unchanged rerun passed. Deterministic CPU conversion tests passed. Investigate sampling-test stability separately; do not treat this as proof of long-run app stability.

- Aligned System context row: processes under CPU, Swap under Memory, free storage under Disk. Single-row height and six consumers retained; values reuse existing counters, with no extra polling. Native alignment/GB/TB tests, all Go packages (`go test ./...`), debug Dark Work policy self-tests, packaging and diff checks passed. Installed the aligned-stats build with backup `/tmp/WattNook-before-aligned-stats-20260930.app`. Native System README capture refreshed. User requested publication of accumulated UI/diagnostics/display-wake refinements; target is fork `itscloud0/wattnook`, default branch `thermal-ui`, preserving GPLv2/upstream history. Untracked `docs/menubar-redesign.md` remains outside publication. Next: long-run stability and actual hardware wake validation, then a separate DMG/release task.

- CPU presentation correction: consumer percentages now divide raw per-core CPU by the logical processor count, matching the headline's total-capacity scale. Secondary text is occupied / available core equivalents. Diagnostic menu and tooltips use the same convention; internal sampling and sorting remain unchanged. Native formatter/row tests (234 → 23.4% on ten cores), existing 300-switch regressions, Go GUI tests and packaging passed. This Mac reports 10 logical processors. Installed the CPU-scale build; previous bundle `/tmp/WattNook-before-cpu-scale-20260930.app`. README/Design updated locally, no GitHub push or daemon modification.

- System/stability correction: replaced duplicate I/O/storage lines with one 12 pt Swap/process-count row and six consumer rows. System crash confirmed in unified logs at 08:56–08:57: CPU sort button inherited NSButton tag -1, indexing the three sort keys. Assigned tag 0 and guarded sort/metric/unit inputs and refresh state. Native harness passed 300 tab switches and invalid-index regression. Process CPU previously treated Mach ticks as ns; host-timebase conversion now makes one busy test thread report 92–98%, with PID-start identity checks. Accessible background processes and WattNook itself are ranked; background/self rows cannot Quit. Process scan interval is 2 s open / 6 s closed with autorelease-pool cleanup and timer tolerance. Go GUI tests, native tests and packaging passed. Installed `/tmp/WattNook-stability.app` at the normal app path, previous bundle `/tmp/WattNook-before-stability-20260930.app`. Short closed-popover host sample: 22.9 MB physical footprint (peak 23 MB); this is not a long-term leak test. README and System capture updated. Daemon unchanged; no commit/push. Next: real interaction/long-run stability, then release/DMG work in a separate session.

- Latest correction after rejected short flow shoulders: single-path transitions now span 18% of the ribbon length with matching adjacent cubic tangents. Native Battery rendering checked for smooth contours. The menu-bar icon gets its own 8 pt text gap regardless of percentage visibility; the native harness checks the icon's width contribution and existing percentage spacing. Go tests, expanded native harness and packaging passed. Installed at the usual app path; previous bundle `/tmp/WattNook-before-soft-flow-20260930.app`. Battery README capture refreshed from `/tmp/wattnook-soft-flow-renders/battery.png`. No daemon change or GitHub push.

- Latest visual refinement supersedes the earlier menu-bar SSD-throughput choice: SSD used again shows occupied disk space percentage; read/write activity stays on System. Native harness asserts the SSD storage percentage in the status item's accessibility label. Watt values have no approximation glyph but remain derived, documented estimates; temperature has no icon and the main battery percentage moved 3 pt closer to its symbol. Ribbon ports narrow to at most 18 pt within tile straight edges; single-path ports have smooth 12 pt flares and no seam outline. Checked Battery/Charging/Hybrid renders, all native behavior tests, Go tests and app packaging. Installed new bundle; prior one is `/tmp/WattNook-before-flow-polish-20260930.app`. Native README images updated from `/tmp/wattnook-flow-polish-renders-final/`. Daemon untouched; changes remain uncommitted/unpushed with previous refinements.

- Control fixes: menu-bar SSD used now means internal read+write throughput, not space occupancy; device busy/read/write percentages were not implemented because transfer-time sums are not wall-clock busy time (Apple IOStorageFamily `addToBytesTransferred` accumulates per-request durations). Battery percentage has a 10 pt gap. Limit is a left-aligned static, event-passthrough label; exact presets remain under Advanced. Native hit-testing passed at 20% and 80%, plus the menu-bar spacing check.
- Dark Work watcher no longer filters wake by HID idle reset or requests sleep again. Any observed display wake ends its own session; old watchers are scoped by caffeinate PID. Debug Swift policy self-tests, Go tests, native harness and app packaging passed. Installed at `/Users/iliasorokin/Applications/WattNook.app`; previous bundle `/tmp/WattNook-before-controls-20260930.app`, daemon unchanged. Physical key/trackpad wake of this revision is not yet verified. Native README captures refreshed from `/tmp/wattnook-controls-renders/`. Changes remain uncommitted/unpushed, including prior System-unit refinement; preserve `docs/menubar-redesign.md`.

- System units refinement: independent saved CPU percent/core equivalents, RAM percent/used bytes and disk throughput/space-used percent/used bytes. Current `vm.swapusage` occupancy is sampled with other system counters; unavailable is distinct from zero. App rows pair relative CPU/RAM with absolute cores/RSS, and disk read/write rates use compact byte units. No per-process disk-utilization percentage is invented. Expanded native harness passed, including saved-unit independence, 3 TB headline/app-row width checks and real host swap sampling; final captures are in `/tmp/wattnook-system-units-renders-final/`. App packaging passed and the updated app is installed; the prior bundle is `/tmp/WattNook-before-system-units-20260930.app`. Daemon unchanged. Changes remain uncommitted; no new GitHub publication was requested for this refinement.

- Refinement: temperature is unboxed, source/destination watt labels are equal-weight, Battery shows SSD used/free GB and an occupancy bar instead of duplicate top-app rows. System adds Disk sorting. Settings persists four palettes and independent menu-bar fields.
- Power/connection readings now come from one local AppleSmartBattery snapshot every two seconds and after the daemon status callback. Synthetic unplug checks discard stale adapter input and show battery → Mac; zero/unavailable transition readings use an updating state, not a claimed zero-watt load. A physical unplug cycle still needs user confirmation.
- `go test ./...`, app packaging and the expanded isolated native harness passed. Native captures are in `/tmp/wattnook-refinement-renders-final/`; repository screenshots use illustrative values, not live process data. Per-app disk I/O attribution is best-effort and includes all volumes, unlike the internal-drive summary.
- Installed the refinement at `/Users/iliasorokin/Applications/WattNook.app`; previous bundle retained at `/tmp/WattNook-before-customize-20260930.app`. Restarted only the menu-bar process; the privileged daemon was untouched. README now includes native Battery/System/Settings captures, telemetry definitions, customization and fork provenance.

- `go test ./...` passes; the bundled Swift helper and app package compile.
- The six synthetic power states render in `tools/power-flow-preview/`; charging and hybrid paths have a shared trunk, separate endpoints, and labels outside the ribbons.
- The installed menu-bar app is WattNook. The legacy `batt-thermal` daemon and socket are intentionally unchanged.
- An earlier real display-sleep/wake test cleared the Dark Work state and its idle-sleep assertion. The current watcher ends on any display wake, without HID-reset filtering or forcing the display back to sleep; recheck physical wake after installing this revision.
- User approved A's energy ribbon, parallel actions and app icons, combined with C's separate System detail screen; B was rejected. Implemented this direction in native AppKit, at 360×480 pt. Do not regenerate or switch layouts without a new request.
- Status item ordering uses `BattThermalCombinedStatus` as its `autosaveName`. Public AppKit offers no always-rightmost position guarantee; user Command-drag placement is preserved by macOS. Startup order must not be described as placement control.
- `go test ./...` passes. The isolated dashboard harness verifies counter reset/zero-time handling, tabs, keyboard limit commit, animation start/stop, empty telemetry and seven full-popover power states (including inconsistent readings). Internal-drive counters were verified on this Mac. Final native captures are in `/tmp/wattnook-dashboard-renders-final/`; mock values are illustrative.
- Installed A+C bundle at `/Users/iliasorokin/Applications/WattNook.app`; old bundle retained at `/tmp/WattNook-before-ac-20260930.app`. Daemon, socket and configured charge limit unchanged. Computer-use host timed out twice, so live pointer interaction was not verified; native controls were tested directly by the isolated harness.
