---
name: WattNook
description: Native Mac battery and system monitor
colors:
  graphite-surface: "#1F242E"
  flow-blue: "#3391F5"
  charging-green: "#34C759"
  low-battery-orange: "#FF9F0A"
  primary-text: "#F5F5F7"
  secondary-text: "#A8ABB1"
typography:
  battery:
    fontFamily: "SF Pro, system-ui"
    fontSize: "36pt"
    fontWeight: 600
  metric:
    fontFamily: "SF Pro, system-ui"
    fontSize: "18pt / 22pt"
    fontWeight: 600
  detail:
    fontFamily: "SF Pro, system-ui"
    fontSize: "11pt"
    fontWeight: 500
rounded:
  popover: "12pt"
spacing:
  unit: "4pt"
---

# Design System: WattNook

Consumer CPU percentages use the same total-capacity scale as the CPU headline, with one decimal place. The secondary line shows occupied / available core equivalents (e.g. 2.34 / 10 cores). Raw per-core CPU samples stay unchanged for sampling and sorting; normalization happens only at presentation, including the diagnostic menu.

## Overview

**Creative North Star: “The Mac power instrument.”** One compact menu-bar surface joins AlDente-like battery control with immediately useful system diagnostics. Battery and system each own a visibly separate region. State and meaning lead; ornament does not.

## Colors

The popover uses an accent-tinted graphite native surface. Blue (default), Mint, Violet and Amber palettes are user-selectable; active charging stays green and low battery stays orange. Selected controls darken the accent for readable white text. The UI should not encode a charging state with color alone.

## Typography

Use the system font for native legibility. The battery percentage is 36 pt; system measurements are 14 pt with tabular digits; state and action labels are 11–13 pt. Watt values omit the approximation glyph for a cleaner display; telemetry is still derived and documented as approximate. Temperature is plain text with semantic heat color and no thermometer icon. Battery percentage sits 3 pt closer to its icon.

## Layout

The popover is 360×480 pt with Battery/System tabs. Battery retains the approved A composition: percentage plus unboxed temperature, 220 pt power region, parallel Heat protection/Screen off buttons, three small metrics and an SSD used/free storage bar. Duplicate app rows stay on System only. System follows approved C: three detailed metrics, one readable Swap/process-count row, CPU/Memory/Disk sort controls, six consumer rows and Activity Monitor. Storage/I/O details are not repeated below the headline metrics. Settings replaces the page content without enlarging the popover. A compact layout never removes the meaning of a value to save space. Watt labels occupy their own lanes, away from ribbons and endpoint symbols, with matching weight and size across sources and destinations.

## Elevation & Depth

The graphite surface has a restrained tonal gradient. Translucent buttons share an 8 pt radius and 10 pt icon-to-text gap. The power ribbon has a blue gradient and a travelling highlight driven by Core Animation, only while the Battery view is visible and Reduce Motion is off. App lists remain unboxed.

## Shapes

Energy ribbons enter the flat middle of endpoint tiles through ports no taller than 18 pt. Split/merge uses one continuous silhouette with a 3 pt rounded inner junction, not three adjacent ribbons with a needle-shaped seam. Single-path contours have a shallow waist instead of a pronounced hourglass. A visible traveling highlight conveys left-to-right power flow; the contour does not oscillate. Core Animation runs only on the visible Battery page, respects Reduce Motion and needs no per-frame CPU timer. Widths are decorative, clamped hints, not a proportional Sankey scale. No vertical outline is drawn at the tile seam. The menu-bar battery icon has a dedicated 8 pt gap after text, including when battery percentage is hidden; its percentage retains a separate 10 pt gap from the CPU/RAM/SSD stack.

Use native status-icon states and aspect-fitted SF Symbols. The flow has one source-to-destination path or a clean split/merge with no overlapping translucent strokes. The charge rail has a separate draggable limit marker.

## Components

System headline metrics cycle their own saved units on activation. Captions have no arrow ornament; hover feedback, the Change units tooltip and accessibility labels retain discoverability. The surface stays 360×480 pt. A single 12 pt context row aligns accessible-process count under CPU, swap used under Memory, and free storage under Disk. The three values use existing counters and no extra polling; compact byte units fit their slots without increasing height. Consumer usage has two right-aligned lines (CPU/core equivalents, RSS/RAM percentage, or read/write rates). Compact byte units promote B→KB→MB→GB→TB and beyond; number text fits its slot instead of truncating units. Background processes and WattNook are included without a Quit button.

The charge-limit label is static, left-aligned below the rail and passes pointer events through to the slider. Exact presets remain in Advanced controls. Heat protection and display controls are direct actions. CPU, memory and disk measurements have distinct captions. Each System app has a normal Quit action with confirmation; the list never implies it can force-quit. Settings persists palette and individual CPU/RAM/SSD-space-used/battery-percentage/icon choices. The battery percentage is separated from the metric stack by 10 pt. An empty selection retains the battery icon so the app stays reachable.

## Do's and Don'ts

- Show `Adapter → Mac`, `To battery`, or `Battery → Mac` beside watt readings.
- Label CPU as load, RAM as memory used, disk activity as MB/s; show space used separately.
- Show a reading-updating state when adapter and battery telemetry disagree.
- Never present a derived zero-watt system value as a measured fact.
