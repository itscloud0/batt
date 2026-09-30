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

## Overview

**Creative North Star: “The Mac power instrument.”** One compact menu-bar surface joins AlDente-like battery control with immediately useful system diagnostics. Battery and system each own a visibly separate region. State and meaning lead; ornament does not.

## Colors

The popover uses a graphite native surface. Blue marks power paths and battery level; green marks active charging, orange marks low battery. Secondary labels stay readable against graphite. The UI should not encode a charging state with color alone.

## Typography

Use the system font for native legibility. The battery percentage is 36 pt; system measurements are 14 pt with tabular digits; state and action labels are 11–13 pt. Every watt value includes a source or destination label and an approximation sign when derived.

## Layout

The popover is 360×480 pt with Battery/System tabs. Battery retains the approved A composition: percentage plus temperature badge, 220 pt power region, parallel Heat protection/Screen off buttons, three small metrics and two app-icon rows. System follows approved C: detailed metrics, separate disk read/write and storage values, CPU/Memory sort controls, five app rows and Activity Monitor. A compact layout never removes the meaning of a value to save space. Watt labels occupy their own lanes, away from ribbons and endpoint symbols.

## Elevation & Depth

The graphite surface has a restrained tonal gradient. Translucent buttons share an 8 pt radius and 10 pt icon-to-text gap. The power ribbon has a blue gradient and a travelling highlight driven by Core Animation, only while the Battery view is visible and Reduce Motion is off. App lists remain unboxed.

## Shapes

Use native status-icon states and aspect-fitted SF Symbols. The flow has one source-to-destination path or a clean split/merge with no overlapping translucent strokes. The charge rail has a separate draggable limit marker.

## Components

The exact charge limit remains available from the rail label. Heat protection and display controls are direct actions. CPU, memory and disk measurements have distinct captions. Each featured app has a normal Quit action with confirmation; the list never implies it can force-quit.

## Do's and Don'ts

- Show `Adapter → Mac`, `To battery`, or `Battery → Mac` beside watt readings.
- Label CPU as load, RAM as memory used, disk activity as MB/s; show space used separately.
- Show a reading-updating state when adapter and battery telemetry disagree.
- Never present a derived zero-watt system value as a measured fact.
